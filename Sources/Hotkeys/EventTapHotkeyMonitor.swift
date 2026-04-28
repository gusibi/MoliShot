import AppKit
import Carbon
import CoreGraphics
import HotKey

final class EventTapHotkeyMonitor {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var combos: [HotkeyAction: KeyCombo] = [:]
    private var onAction: ((HotkeyAction) -> Void)?

    var isRunning: Bool {
        eventTap != nil
    }

    func configure(combos: [HotkeyAction: KeyCombo], onAction: @escaping (HotkeyAction) -> Void) {
        self.combos = combos
        self.onAction = onAction
    }

    @discardableResult
    func start() -> Bool {
        stop()

        let mask = (1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else {
                return Unmanaged.passUnretained(event)
            }
            let monitor = Unmanaged<EventTapHotkeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            return monitor.handleEventTap(type: type, event: event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        runLoopSource = source
        return true
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        runLoopSource = nil
        eventTap = nil
    }

    private func handleEventTap(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        case .keyDown:
            break
        default:
            return Unmanaged.passUnretained(event)
        }

        let keyCode = UInt32(event.getIntegerValueField(.keyboardEventKeycode))
        let modifiers = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
            .intersection(.deviceIndependentFlagsMask)
            .intersection([.command, .option, .control, .shift])
        let combo = KeyCombo(carbonKeyCode: keyCode, carbonModifiers: modifiers.carbonFlags)

        guard let action = combos.first(where: { $0.value == combo })?.key else {
            return Unmanaged.passUnretained(event)
        }

        DispatchQueue.main.async { [onAction] in
            onAction?(action)
        }
        return nil
    }
}

final class CaptureSessionEventTap {
    struct Event {
        let type: CGEventType
        let location: CGPoint
        let modifiers: NSEvent.ModifierFlags
        let deltaX: CGFloat
        let deltaY: CGFloat
    }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var handler: ((Event) -> Void)?

    @discardableResult
    func start(handler: @escaping (Event) -> Void) -> Bool {
        stop()
        self.handler = handler

        let interestedTypes: [CGEventType] = [
            .mouseMoved,
            .leftMouseDown,
            .leftMouseDragged,
            .leftMouseUp,
            .rightMouseDown,
            .rightMouseDragged,
            .rightMouseUp,
            .otherMouseDown,
            .otherMouseDragged,
            .otherMouseUp,
            .scrollWheel,
            .flagsChanged
        ]
        let mask = interestedTypes.reduce(CGEventMask(0)) { partial, type in
            partial | (CGEventMask(1) << type.rawValue)
        }

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else {
                return Unmanaged.passUnretained(event)
            }
            let monitor = Unmanaged<CaptureSessionEventTap>.fromOpaque(userInfo).takeUnretainedValue()
            return monitor.handleEventTap(type: type, event: event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            self.handler = nil
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        runLoopSource = source
        return true
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        runLoopSource = nil
        eventTap = nil
        handler = nil
    }

    private func handleEventTap(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        case .mouseMoved,
             .leftMouseDown,
             .leftMouseDragged,
             .leftMouseUp,
             .rightMouseDown,
             .rightMouseDragged,
             .rightMouseUp,
             .otherMouseDown,
             .otherMouseDragged,
             .otherMouseUp,
             .scrollWheel,
             .flagsChanged:
            break
        default:
            return Unmanaged.passUnretained(event)
        }

        let forwardedEvent = Event(
            type: type,
            location: event.location,
            modifiers: NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
                .intersection(.deviceIndependentFlagsMask),
            deltaX: CGFloat(event.getDoubleValueField(.mouseEventDeltaX)),
            deltaY: CGFloat(event.getDoubleValueField(.mouseEventDeltaY))
        )

        DispatchQueue.main.async { [handler] in
            handler?(forwardedEvent)
        }
        return nil
    }
}

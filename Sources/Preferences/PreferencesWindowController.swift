import AppKit
import SwiftUI
import HotKey

// MARK: - Layout Constants

private enum PreferencesLayout {
    static let windowWidth: CGFloat = 780
    static let windowHeight: CGFloat = 560
    static let minWindowWidth: CGFloat = 600
    static let minWindowHeight: CGFloat = 400
    static let sidebarWidth: CGFloat = 196
    static let detailMaxWidth: CGFloat = 520
}

private enum PreferencesDesign {
    static let primary = NSColor.srgb(hex: 0x5e6ad2)
    static let primaryHover = NSColor.srgb(hex: 0x828fff)
    static let onPrimary = NSColor.srgb(hex: 0xffffff)

    static let canvas = NSColor.adaptive(light: .srgb(hex: 0xffffff), dark: .srgb(hex: 0x010102))
    static let sidebar = NSColor.adaptive(light: .srgb(hex: 0xf5f6f6), dark: .srgb(hex: 0x0f1011))
    static let surface1 = NSColor.adaptive(light: .srgb(hex: 0xf5f6f6), dark: .srgb(hex: 0x0f1011))
    static let surface2 = NSColor.adaptive(light: .srgb(hex: 0xf6f7f7), dark: .srgb(hex: 0x141516))
    static let surface3 = NSColor.adaptive(light: .srgb(hex: 0xffffff), dark: .srgb(hex: 0x18191a))
    static let ink = NSColor.adaptive(light: .srgb(hex: 0x000000), dark: .srgb(hex: 0xf7f8f8))
    static let inkMuted = NSColor.adaptive(light: .srgb(hex: 0x4d5561), dark: .srgb(hex: 0xd0d6e0))
    static let inkSubtle = NSColor.adaptive(light: .srgb(hex: 0x747986), dark: .srgb(hex: 0x8a8f98))
    static let inkTertiary = NSColor.adaptive(light: .srgb(hex: 0x9aa0aa), dark: .srgb(hex: 0x62666d))
    static let hairline = NSColor.adaptive(light: .srgb(hex: 0xe4e6ea), dark: .srgb(hex: 0x23252a))
    static let hairlineStrong = NSColor.adaptive(light: .srgb(hex: 0xd2d6de), dark: .srgb(hex: 0x34343a))
    static let success = NSColor.srgb(hex: 0x27a644)
    static let danger = NSColor.srgb(hex: 0xff453a)

    static func navFill(isSelected: Bool) -> NSColor {
        isSelected ? surface2 : .clear
    }

    static func controlFill(isPressed: Bool) -> NSColor {
        isPressed ? surface3 : surface2
    }
}

// MARK: - Window Controller

final class PreferencesWindowController: NSWindowController {
    private var hostingView: NSHostingView<PreferencesContentView>?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: PreferencesLayout.windowWidth, height: PreferencesLayout.windowHeight),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.text(.preferences)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = PreferencesDesign.canvas
        window.center()
        window.minSize = NSSize(width: PreferencesLayout.minWindowWidth, height: PreferencesLayout.minWindowHeight)
        super.init(window: window)

        let contentView = PreferencesContentView()
        let hosting = NSHostingView(rootView: contentView)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = hosting
        self.hostingView = hosting

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(languageDidChange),
            name: .appLanguageDidChange,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func languageDidChange() {
        // Re-create the hosting view with fresh SwiftUI content
        // SwiftUI will diff and only update changed text
        hostingView?.rootView = PreferencesContentView()
        window?.title = L10n.text(.preferences)
    }
}

// MARK: - Preferences Pane

private enum PreferencesPane: String, CaseIterable {
    case general
    case hotkeys
    case storage

    var title: String {
        switch self {
        case .general: return L10n.text(.general)
        case .hotkeys: return L10n.text(.hotkeys)
        case .storage: return L10n.text(.storage)
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .hotkeys: return "keyboard"
        case .storage: return "folder"
        }
    }
}

// MARK: - Main Content View

struct PreferencesContentView: View {
    @State private var selectedPane: PreferencesPane = .general

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle()
                .fill(Color(nsColor: PreferencesDesign.hairline))
                .frame(width: 1)
            detailArea
        }
        .background(Color(nsColor: PreferencesDesign.canvas))
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: PreferencesDesign.primary))

                    Text("M")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(nsColor: PreferencesDesign.onPrimary))
                }
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)

                Text(L10n.text(.preferences))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(nsColor: PreferencesDesign.ink))
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 20)

            ForEach(PreferencesPane.allCases, id: \.self) { pane in
                sidebarButton(for: pane)
            }

            Spacer()
        }
        .padding(.top, 50)
        .padding(.horizontal, 16)
        .frame(width: PreferencesLayout.sidebarWidth)
        .background(Color(nsColor: PreferencesDesign.sidebar))
    }

    private func sidebarButton(for pane: PreferencesPane) -> some View {
        let isSelected = selectedPane == pane

        return Button {
            selectedPane = pane
        } label: {
            HStack(spacing: 8) {
                Image(systemName: pane.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 16)
                    .accessibilityHidden(true)

                Text(pane.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))

                Spacer(minLength: 0)
            }
            .foregroundStyle(Color(nsColor: isSelected ? PreferencesDesign.ink : PreferencesDesign.inkSubtle))
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 34)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: PreferencesDesign.navFill(isSelected: isSelected)))
            )
            .overlay(
                HStack(spacing: 0) {
                    Capsule()
                        .fill(Color(nsColor: isSelected ? PreferencesDesign.primary : .clear))
                        .frame(width: 2, height: 16)
                    Spacer()
                }
                .padding(.leading, 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(nsColor: isSelected ? PreferencesDesign.hairlineStrong : .clear), lineWidth: 1)
            )
            .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(pane.title)
    }

    // MARK: - Detail Area

    @ViewBuilder
    private var detailArea: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                switch selectedPane {
                case .general:
                    GeneralPane()
                case .hotkeys:
                    HotkeysPane()
                case .storage:
                    StoragePane()
                }
            }
            .frame(maxWidth: PreferencesLayout.detailMaxWidth, alignment: .leading)
            .padding(.top, 34)
            .padding(.horizontal, 32)
            .padding(.bottom, 42)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: PreferencesDesign.canvas))
    }
}

// MARK: - Section Helpers

private struct PaneHeader: View {
    let title: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(nsColor: PreferencesDesign.primary))
                    .accessibilityHidden(true)

                Text(L10n.text(.preferences))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(nsColor: PreferencesDesign.inkSubtle))
            }

            Text(title)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Color(nsColor: PreferencesDesign.ink))
        }
        .padding(.bottom, 22)
    }
}

private struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(Color(nsColor: PreferencesDesign.inkSubtle))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 2)
            .padding(.top, 22)
            .padding(.bottom, 8)
    }
}

private struct SettingsGroup<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .background(Color(nsColor: PreferencesDesign.surface1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(nsColor: PreferencesDesign.hairline), lineWidth: 1)
        )
    }
}

private struct SettingsRow<Control: View>: View {
    let label: String
    @ViewBuilder let control: () -> Control
    let isLast: Bool

    init(label: String, isLast: Bool = false, @ViewBuilder control: @escaping () -> Control) {
        self.label = label
        self.isLast = isLast
        self.control = control
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 16) {
                if label.isEmpty {
                    Spacer(minLength: 0)
                } else {
                    Text(label)
                        .font(.system(size: 13))
                        .foregroundStyle(Color(nsColor: PreferencesDesign.inkMuted))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                control()
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 46)

            if !isLast {
                Rectangle()
                    .fill(Color(nsColor: PreferencesDesign.hairline))
                    .frame(height: 1)
                    .padding(.leading, 16)
            }
        }
    }
}

private struct SettingsMessageRow: View {
    let text: String
    let isLast: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(nsColor: PreferencesDesign.inkTertiary))
                    .accessibilityHidden(true)

                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(nsColor: PreferencesDesign.inkSubtle))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)

            if !isLast {
                Rectangle()
                    .fill(Color(nsColor: PreferencesDesign.hairline))
                    .frame(height: 1)
                    .padding(.leading, 16)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct SettingsStackedRow<Control: View>: View {
    let label: String
    let isLast: Bool
    @ViewBuilder let control: () -> Control

    init(label: String, isLast: Bool = false, @ViewBuilder control: @escaping () -> Control) {
        self.label = label
        self.isLast = isLast
        self.control = control
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text(label)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(nsColor: PreferencesDesign.inkMuted))

                control()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            if !isLast {
                Rectangle()
                    .fill(Color(nsColor: PreferencesDesign.hairline))
                    .frame(height: 1)
                    .padding(.leading, 16)
            }
        }
    }
}

private struct PermissionStatusLabel: View {
    let isGranted: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .accessibilityHidden(true)

            Text(isGranted ? L10n.text(.granted) : L10n.text(.notGranted))
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(statusColor)
        .padding(.horizontal, 9)
        .frame(height: 24)
        .background(
            Capsule()
                .fill(Color(nsColor: PreferencesDesign.surface2))
        )
        .overlay(
            Capsule()
                .stroke(Color(nsColor: PreferencesDesign.hairline), lineWidth: 1)
        )
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .combine)
    }

    private var statusColor: Color {
        if isGranted {
            return Color(nsColor: PreferencesDesign.success)
        }
        return Color(nsColor: PreferencesDesign.danger)
    }
}

private struct PreferencePathValue: View {
    let path: String

    var body: some View {
        Text(path)
            .font(.system(size: 12))
            .foregroundStyle(Color(nsColor: PreferencesDesign.inkSubtle))
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 10)
            .frame(maxWidth: 270, minHeight: 28, alignment: .trailing)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: PreferencesDesign.surface2))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(nsColor: PreferencesDesign.hairline), lineWidth: 1)
            )
            .accessibilityLabel(path)
    }
}

private struct PreferenceActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color(nsColor: PreferencesDesign.inkMuted))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: PreferencesDesign.controlFill(isPressed: configuration.isPressed)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(nsColor: PreferencesDesign.hairlineStrong), lineWidth: 1)
            )
    }
}

private struct PreferenceTextFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color(nsColor: PreferencesDesign.ink))
            .padding(.horizontal, 8)
            .frame(width: 56, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: PreferencesDesign.surface2))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(nsColor: PreferencesDesign.hairlineStrong), lineWidth: 1)
            )
    }
}

// MARK: - General Pane

private struct GeneralPane: View {
    @AppStorage("app.language")
    private var languageRaw: String = AppLanguage.system.rawValue

    @State private var launchesAtLogin = AppSettings.launchesAtLogin
    @State private var hasScreenCapturePermission = Permissions.hasScreenCapturePermission
    @State private var hasAccessibilityPermission = Permissions.hasAccessibilityPermission
    @State private var hotkeyRegistrationMode = HotkeyManager.shared.registrationMode
    @State private var showLaunchError = false
    @State private var launchErrorMessage = ""

    var body: some View {
        PaneHeader(title: L10n.text(.general), symbol: "gearshape")

        SettingsGroup {
            SettingsRow(label: L10n.text(.language)) {
                Picker("", selection: $languageRaw) {
                    ForEach(AppLanguage.allCases, id: \.rawValue) { lang in
                        Text(lang.displayName).tag(lang.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .onChange(of: languageRaw) { _, newValue in
                    if let lang = AppLanguage(rawValue: newValue) {
                        L10n.selectedLanguage = lang
                    }
                }
            }

            SettingsRow(label: L10n.text(.autoStart), isLast: true) {
                Toggle("", isOn: $launchesAtLogin)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .onChange(of: launchesAtLogin) { _, newValue in
                        do {
                            try AppSettings.setLaunchesAtLogin(newValue)
                        } catch {
                            launchesAtLogin = AppSettings.launchesAtLogin
                            launchErrorMessage = error.localizedDescription
                            showLaunchError = true
                        }
                    }
            }
        }

        SectionHeader(title: L10n.text(.screenRecordingPermission))

        SettingsGroup {
            SettingsStackedRow(label: L10n.text(.screenRecordingPermission), isLast: true) {
                HStack(spacing: 12) {
                    PermissionStatusLabel(isGranted: hasScreenCapturePermission)

                    Button(L10n.text(.openScreenRecordingSettings)) {
                        Permissions.openScreenRecordingPrivacySettings()
                    }
                    .buttonStyle(PreferenceActionButtonStyle())
                }
            }
        }

        SectionHeader(title: L10n.text(.accessibilityPermission))

        SettingsGroup {
            SettingsStackedRow(label: L10n.text(.accessibilityPermission)) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        PermissionStatusLabel(isGranted: hasAccessibilityPermission)
                        accessibilityButtons
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        PermissionStatusLabel(isGranted: hasAccessibilityPermission)
                        accessibilityButtons
                    }
                }
            }

            SettingsRow(label: L10n.text(.hotkeyRegistrationMode)) {
                Text(hotkeyModeText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(nsColor: hotkeyRegistrationMode == .eventTap ? PreferencesDesign.success : PreferencesDesign.inkSubtle))
            }

            SettingsMessageRow(text: L10n.text(.accessibilityPermissionHint), isLast: true)
        }

        .onAppear {
            refreshPermissionState()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissionState()
        }
        .onReceive(NotificationCenter.default.publisher(for: .hotkeyRegistrationModeDidChange)) { _ in
            hotkeyRegistrationMode = HotkeyManager.shared.registrationMode
        }
        .alert(L10n.text(.launchAtLoginFailed), isPresented: $showLaunchError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(launchErrorMessage)
        }
    }

    private var accessibilityButtons: some View {
        HStack(spacing: 8) {
            Button(L10n.text(.requestAccessibilityPermission)) {
                _ = Permissions.requestAccessibilityAccessUserInitiated()
            }
            .buttonStyle(PreferenceActionButtonStyle())

            Button(L10n.text(.openAccessibilitySettings)) {
                Permissions.openAccessibilityPrivacySettings()
            }
            .buttonStyle(PreferenceActionButtonStyle())
        }
    }

    private var hotkeyModeText: String {
        switch hotkeyRegistrationMode {
        case .eventTap:
            return L10n.text(.hotkeyRegistrationModeEventTap)
        case .fallbackHotKey:
            return L10n.text(.hotkeyRegistrationModeFallback)
        }
    }

    private func refreshPermissionState() {
        hasScreenCapturePermission = Permissions.hasScreenCapturePermission
        hasAccessibilityPermission = Permissions.hasAccessibilityPermission
        hotkeyRegistrationMode = HotkeyManager.shared.registrationMode
    }
}

// MARK: - Hotkeys Pane

private struct HotkeysPane: View {
    var body: some View {
        PaneHeader(title: L10n.text(.hotkeys), symbol: "keyboard")

        SettingsGroup {
            let actions = HotkeyAction.allCases
            ForEach(Array(actions.enumerated()), id: \.element) { index, action in
                SettingsRow(label: action.title, isLast: index == actions.count - 1) {
                    HotkeyRecorderView(action: action)
                }
            }
        }
    }
}

// MARK: - Hotkey Recorder (NSViewRepresentable wrapping AppKit)

private struct HotkeyRecorderView: NSViewRepresentable {
    let action: HotkeyAction

    func makeNSView(context: Context) -> HotkeyRecorderButton {
        let button = HotkeyRecorderButton(combo: HotkeyManager.shared.combo(for: action))
        button.onBeginRecording = { HotkeyManager.shared.pauseAll() }
        button.onCapture = { combo in
            HotkeyManager.shared.setCombo(combo, for: action)
            HotkeyManager.shared.resumeAll()
        }
        button.onCancelRecording = { HotkeyManager.shared.resumeAll() }
        return button
    }

    func updateNSView(_ nsView: HotkeyRecorderButton, context: Context) {
        // Sync combo from manager (e.g. after reset)
        nsView.setCombo(HotkeyManager.shared.combo(for: action))
    }
}

/// AppKit-based hotkey recorder button with visual recording-state feedback.
/// Uses Carbon key codes for HotKey library compatibility.
private final class HotkeyRecorderButton: NSButton {
    var onBeginRecording: (() -> Void)?
    var onCapture: ((KeyCombo?) -> Void)?
    var onCancelRecording: (() -> Void)?

    private var combo: KeyCombo?
    private var isRecording = false
    private var widthConstraint: NSLayoutConstraint?

    init(combo: KeyCombo?) {
        self.combo = combo
        super.init(frame: .zero)
        bezelStyle = .regularSquare
        isBordered = false
        wantsLayer = true
        applyBaseStyle()

        target = self
        action = #selector(startRecording)

        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 24).isActive = true

        updateTitle()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyBaseStyle()
        if isRecording {
            layer?.borderColor = PreferencesDesign.primary.cgColor
            layer?.borderWidth = 2
        }
        updateTitle()
    }

    private func applyBaseStyle() {
        layer?.cornerRadius = 6
        layer?.backgroundColor = PreferencesDesign.surface2.cgColor
        layer?.borderWidth = 0.5
        layer?.borderColor = PreferencesDesign.hairlineStrong.cgColor
    }

    @objc private func startRecording() {
        if !isRecording {
            onBeginRecording?()
        }
        isRecording = true
        // Visual feedback: accent border highlight
        layer?.borderColor = PreferencesDesign.primary.cgColor
        layer?.borderWidth = 2
        updateTitle()
        window?.makeFirstResponder(self)
    }

    override func resignFirstResponder() -> Bool {
        if isRecording {
            isRecording = false
            resetBorder()
            updateTitle()
            onCancelRecording?()
        }
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        switch event.keyCode {
        case 53: // Escape
            isRecording = false
            resetBorder()
            updateTitle()
            onCancelRecording?()
            return
        case 51, 117: // Delete / Forward Delete
            combo = nil
            isRecording = false
            resetBorder()
            updateTitle()
            onCapture?(nil)
            return
        default:
            break
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let allowedModifiers = modifiers.intersection([.command, .option, .control, .shift])
        guard !allowedModifiers.isEmpty else {
            NSSound.beep()
            return
        }

        let combo = KeyCombo(carbonKeyCode: UInt32(event.keyCode), carbonModifiers: allowedModifiers.carbonFlags)
        self.combo = combo
        isRecording = false
        resetBorder()
        updateTitle()
        onCapture?(combo)
    }

    private func resetBorder() {
        layer?.borderColor = PreferencesDesign.hairlineStrong.cgColor
        layer?.borderWidth = 0.5
    }

    private func updateTitle() {
        let text = isRecording ? L10n.text(.pressShortcut) : (combo?.description ?? L10n.text(.recordShortcut))
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center

        let attributedTitle = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .regular),
            .foregroundColor: isRecording ? PreferencesDesign.primaryHover : PreferencesDesign.inkMuted,
            .paragraphStyle: paragraph,
        ])
        self.attributedTitle = attributedTitle

        let size = attributedTitle.size()
        widthConstraint?.isActive = false
        widthConstraint = widthAnchor.constraint(equalToConstant: max(60, size.width + 16))
        widthConstraint?.isActive = true
    }

    func setCombo(_ combo: KeyCombo?) {
        self.combo = combo
        updateTitle()
    }
}

// MARK: - Storage Pane

private struct StoragePane: View {
    @State private var saveDirectoryPath = AppSettings.saveDirectoryURL.path
    @State private var historyLimit = AppSettings.historyLimit
    @State private var showFileImporter = false

    var body: some View {
        PaneHeader(title: L10n.text(.storage), symbol: "folder")

        SectionHeader(title: L10n.text(.saveDirectory))

        SettingsGroup {
            SettingsRow(label: L10n.text(.saveDirectory)) {
                HStack(spacing: 8) {
                    PreferencePathValue(path: saveDirectoryPath)

                    Button(L10n.text(.choose)) {
                        showFileImporter = true
                    }
                    .buttonStyle(PreferenceActionButtonStyle())
                }
            }

            SettingsRow(label: "", isLast: true) {
                Button(L10n.text(.resetToDesktop)) {
                    AppSettings.clearSaveDirectory()
                    saveDirectoryPath = AppSettings.saveDirectoryURL.path
                }
                .buttonStyle(PreferenceActionButtonStyle())
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                guard url.startAccessingSecurityScopedResource() else { return }
                defer { url.stopAccessingSecurityScopedResource() }
                AppSettings.setSaveDirectory(url)
                saveDirectoryPath = AppSettings.saveDirectoryURL.path
            case .failure:
                break
            }
        }

        SectionHeader(title: L10n.text(.history))

        SettingsGroup {
            SettingsRow(label: L10n.text(.keepRecentScreenshots), isLast: true) {
                HStack(spacing: 8) {
                    TextField("", value: $historyLimit, format: .number)
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.center)
                        .modifier(PreferenceTextFieldStyle())
                        .accessibilityLabel(L10n.text(.keepRecentScreenshots))
                        .onChange(of: historyLimit) { _, newValue in
                            let clamped = AppSettings.clampedHistoryLimit(newValue)
                            if clamped != newValue {
                                historyLimit = clamped
                            }
                            AppSettings.historyLimit = clamped
                            HistoryStore.shared.applyRetentionLimit()
                        }

                    Stepper("", value: $historyLimit, in: AppSettings.minHistoryLimit...AppSettings.maxHistoryLimit)
                        .labelsHidden()
                        .onChange(of: historyLimit) { _, newValue in
                            let clamped = AppSettings.clampedHistoryLimit(newValue)
                            if clamped != newValue {
                                historyLimit = clamped
                            }
                            AppSettings.historyLimit = clamped
                            HistoryStore.shared.applyRetentionLimit()
                        }
                }
            }
        }
    }
}

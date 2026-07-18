import AppKit
import SwiftUI
import HotKey

// MARK: - Window Controller

final class PreferencesWindowController: NSWindowController {
    /// System Settings uses a fixed-width window; we match that. The detail
    /// Form scrolls, so the height stays fixed too.
    private static let windowWidth: CGFloat = 720
    private static let windowHeight: CGFloat = 560

    private var hostingController: NSHostingController<PreferencesContentView>?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Self.windowWidth, height: Self.windowHeight),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.text(.preferences)
        window.titlebarAppearsTransparent = true
        super.init(window: window)

        let hosting = NSHostingController(rootView: PreferencesContentView())
        window.contentViewController = hosting
        window.setContentSize(NSSize(width: Self.windowWidth, height: Self.windowHeight))
        window.center()
        self.hostingController = hosting

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
        // Rebuild the SwiftUI tree; it diffs and only re-renders changed text.
        hostingController?.rootView = PreferencesContentView()
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
    @State private var selectedPane: PreferencesPane? = .general

    var body: some View {
        NavigationSplitView {
            List(PreferencesPane.allCases, id: \.self, selection: $selectedPane) { pane in
                Label(pane.title, systemImage: pane.symbol)
            }
            .navigationSplitViewColumnWidth(196)
        } detail: {
            Form {
                switch selectedPane ?? .general {
                case .general:
                    GeneralPane()
                case .hotkeys:
                    HotkeysPane()
                case .storage:
                    StoragePane()
                }
            }
            .formStyle(.grouped)
            .navigationTitle((selectedPane ?? .general).title)
        }
    }
}

// MARK: - Permission Badge

/// Status expressed with colour + icon; the pill background the old design drew
/// was a redundant extra layer.
private struct PermissionBadge: View {
    let granted: Bool

    var body: some View {
        Label(
            granted ? L10n.text(.granted) : L10n.text(.notGranted),
            systemImage: granted ? "checkmark.circle.fill" : "xmark.circle.fill"
        )
        .foregroundStyle(granted ? Color.green : Color.red)
        .font(.system(size: 12, weight: .medium))
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
        Section {
            Picker(L10n.text(.language), selection: $languageRaw) {
                ForEach(AppLanguage.allCases, id: \.rawValue) { lang in
                    Text(lang.displayName).tag(lang.rawValue)
                }
            }
            .onChange(of: languageRaw) { _, newValue in
                if let lang = AppLanguage(rawValue: newValue) {
                    L10n.selectedLanguage = lang
                }
            }

            Toggle(L10n.text(.autoStart), isOn: $launchesAtLogin)
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
        .alert(L10n.text(.launchAtLoginFailed), isPresented: $showLaunchError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(launchErrorMessage)
        }

        Section {
            LabeledContent(L10n.text(.screenRecording)) {
                HStack(spacing: 8) {
                    PermissionBadge(granted: hasScreenCapturePermission)
                    Button(L10n.text(.openScreenRecordingSettings)) {
                        Permissions.openScreenRecordingPrivacySettings()
                    }
                }
            }

            LabeledContent(L10n.text(.accessibility)) {
                PermissionBadge(granted: hasAccessibilityPermission)
            }

            HStack {
                Spacer()
                Button(L10n.text(.requestAccessibilityPermission)) {
                    _ = Permissions.requestAccessibilityAccessUserInitiated()
                }
                Button(L10n.text(.openAccessibilitySettings)) {
                    Permissions.openAccessibilityPrivacySettings()
                }
            }

            LabeledContent(L10n.text(.hotkeyRegistrationMode)) {
                Text(hotkeyModeText)
                    .foregroundStyle(hotkeyRegistrationMode == .eventTap ? Color.green : Color.secondary)
            }
        } header: {
            Text(L10n.text(.permissions))
        } footer: {
            Text(L10n.text(.accessibilityPermissionHint))
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
        Section {
            ForEach(HotkeyAction.allCases, id: \.self) { action in
                LabeledContent(action.title) {
                    HotkeyRecorderView(action: action)
                }
            }
        }
    }
}

// MARK: - Storage Pane

private struct StoragePane: View {
    @State private var saveDirectoryPath = AppSettings.saveDirectoryURL.path
    @State private var historyLimit = AppSettings.historyLimit
    @State private var saveFormat = AppSettings.saveFormat
    @State private var jpegQuality = AppSettings.jpegQuality
    @State private var showFileImporter = false

    var body: some View {
        Section {
            LabeledContent(L10n.text(.saveDirectory)) {
                HStack(spacing: 8) {
                    Text(saveDirectoryPath)
                        .truncationMode(.middle)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                    Button(L10n.text(.choose)) {
                        showFileImporter = true
                    }
                }
            }

            HStack {
                Spacer()
                Button(L10n.text(.resetToDesktop)) {
                    AppSettings.clearSaveDirectory()
                    saveDirectoryPath = AppSettings.saveDirectoryURL.path
                }
            }
        } header: {
            Text(L10n.text(.saveDirectory))
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

        Section {
            Stepper(value: $historyLimit, in: AppSettings.minHistoryLimit...AppSettings.maxHistoryLimit) {
                LabeledContent(L10n.text(.keepRecentScreenshots)) {
                    Text("\(historyLimit)")
                }
            }
            .onChange(of: historyLimit) { _, newValue in
                applyHistoryLimit(newValue)
            }

            Picker(L10n.text(.saveFormat), selection: $saveFormat) {
                Text(L10n.text(.pngFormat)).tag(AppSettings.SaveFormat.png)
                Text(L10n.text(.jpegFormat)).tag(AppSettings.SaveFormat.jpeg)
            }
            .pickerStyle(.segmented)
            .onChange(of: saveFormat) { _, newValue in
                AppSettings.saveFormat = newValue
            }

            if saveFormat == .jpeg {
                Slider(value: $jpegQuality, in: AppSettings.minJpegQuality...AppSettings.maxJpegQuality) {
                    Text(L10n.text(.jpegQuality))
                } minimumValueLabel: {
                    Text("\(Int((AppSettings.minJpegQuality * 100).rounded()))")
                        .font(.caption)
                } maximumValueLabel: {
                    Text("\(Int((jpegQuality * 100).rounded()))%")
                        .font(.caption)
                        .monospacedDigit()
                }
                .onChange(of: jpegQuality) { _, newValue in
                    AppSettings.jpegQuality = newValue
                }
            }
        } header: {
            Text(L10n.text(.history))
        }
        // Reveal/hide the JPEG quality row without an instant jump.
        .animation(.default, value: saveFormat)
    }

    /// Clamp, persist, and apply the history retention limit. Shared by the
    /// Stepper's onChange so the logic lives in one place.
    private func applyHistoryLimit(_ newValue: Int) {
        let clamped = AppSettings.clampedHistoryLimit(newValue)
        if clamped != newValue {
            historyLimit = clamped
        }
        AppSettings.historyLimit = clamped
        HistoryStore.shared.applyRetentionLimit()
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
/// Uses Carbon key codes for HotKey library compatibility. This is a legitimate
/// self-drawn control — AppKit ships no shortcut recorder.
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
        toolTip = L10n.text(.hotkeyRecorderHint)

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
            layer?.borderColor = MoliDesign.accent.cgColor
            layer?.borderWidth = 2
        }
        updateTitle()
    }

    private func applyBaseStyle() {
        layer?.cornerRadius = 6
        layer?.backgroundColor = MoliDesign.cardElevated.cgColor
        layer?.borderWidth = 0.5
        layer?.borderColor = MoliDesign.hairline.cgColor
    }

    @objc private func startRecording() {
        if !isRecording {
            onBeginRecording?()
        }
        isRecording = true
        // Visual feedback: accent border highlight
        layer?.borderColor = MoliDesign.accent.cgColor
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
        layer?.borderColor = MoliDesign.hairline.cgColor
        layer?.borderWidth = 0.5
    }

    private func updateTitle() {
        let text = isRecording ? L10n.text(.pressShortcut) : (combo?.description ?? L10n.text(.recordShortcut))
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center

        let attributedTitle = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .regular),
            .foregroundColor: isRecording ? MoliDesign.accent : MoliDesign.secondaryText,
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

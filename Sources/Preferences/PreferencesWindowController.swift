import AppKit
import SwiftUI
import HotKey

// MARK: - Layout Constants

private enum PreferencesLayout {
    static let windowWidth: CGFloat = 750
    static let windowHeight: CGFloat = 550
    static let minWindowWidth: CGFloat = 600
    static let minWindowHeight: CGFloat = 400
    static let sidebarWidth: CGFloat = 180
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
            Divider()
            detailArea
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.text(.preferences))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.bottom, 16)

            ForEach(PreferencesPane.allCases, id: \.self) { pane in
                sidebarButton(for: pane)
            }

            Spacer()
        }
        .padding(.top, 48)
        .padding(.horizontal, 16)
        .frame(width: PreferencesLayout.sidebarWidth)
        .background(.regularMaterial)
    }

    private func sidebarButton(for pane: PreferencesPane) -> some View {
        Button {
            selectedPane = pane
        } label: {
            Label(pane.title, systemImage: pane.symbol)
                .font(.system(size: 13, weight: selectedPane == pane ? .semibold : .regular))
                .foregroundStyle(selectedPane == pane ? Color.accentColor : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 30)
                .contentShape(.rect(cornerRadius: 6))
        }
        .buttonStyle(.plain)
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
            .padding(.top, 24)
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
    }
}

// MARK: - Section Helpers

private struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 6)
    }
}

private struct SettingsGroup<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .separatorColor).opacity(0.08), lineWidth: 1)
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
                Text(label)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                Spacer()
                control()
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 40)

            if !isLast {
                Divider()
                    .padding(.leading, 16)
                    .padding(.trailing, 8)
            }
        }
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
        SectionHeader(title: L10n.text(.general))

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
            SettingsRow(label: L10n.text(.screenRecordingPermission), isLast: true) {
                HStack(spacing: 12) {
                    Text(hasScreenCapturePermission ? L10n.text(.granted) : L10n.text(.notGranted))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(hasScreenCapturePermission ? .green : .red)

                    Button(L10n.text(.openScreenRecordingSettings)) {
                        Permissions.openScreenRecordingPrivacySettings()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
            }
        }

        SectionHeader(title: L10n.text(.accessibilityPermission))

        SettingsGroup {
            SettingsRow(label: L10n.text(.accessibilityPermission)) {
                HStack(spacing: 12) {
                    Text(hasAccessibilityPermission ? L10n.text(.granted) : L10n.text(.notGranted))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(hasAccessibilityPermission ? .green : .red)

                    Button(L10n.text(.requestAccessibilityPermission)) {
                        _ = Permissions.requestAccessibilityAccessUserInitiated()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)

                    Button(L10n.text(.openAccessibilitySettings)) {
                        Permissions.openAccessibilityPrivacySettings()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
            }

            SettingsRow(label: L10n.text(.hotkeyRegistrationMode)) {
                Text(hotkeyModeText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(hotkeyRegistrationMode == .eventTap ? .green : .secondary)
            }

            SettingsRow(label: L10n.text(.accessibilityPermissionHint), isLast: true) {
                Text(L10n.text(.accessibilityPermissionHint))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 280, alignment: .trailing)
            }
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
        SectionHeader(title: L10n.text(.hotkeys))

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
        layer?.cornerRadius = 6
        layer?.backgroundColor = NSColor.controlColor.cgColor
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.separatorColor.cgColor

        target = self
        action = #selector(startRecording)

        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 24).isActive = true

        updateTitle()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    @objc private func startRecording() {
        if !isRecording {
            onBeginRecording?()
        }
        isRecording = true
        // Visual feedback: accent border highlight
        layer?.borderColor = NSColor.controlAccentColor.cgColor
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
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.borderWidth = 0.5
    }

    private func updateTitle() {
        let text = isRecording ? L10n.text(.pressShortcut) : (combo?.description ?? L10n.text(.recordShortcut))
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center

        let attributedTitle = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .regular),
            .foregroundColor: isRecording ? NSColor.controlAccentColor : NSColor.secondaryLabelColor,
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
        SectionHeader(title: L10n.text(.saveDirectory))

        SettingsGroup {
            SettingsRow(label: L10n.text(.saveDirectory)) {
                HStack(spacing: 8) {
                    Text(saveDirectoryPath)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 250, alignment: .trailing)

                    Button(L10n.text(.choose)) {
                        showFileImporter = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
            }

            SettingsRow(label: "", isLast: true) {
                Button(L10n.text(.resetToDesktop)) {
                    AppSettings.clearSaveDirectory()
                    saveDirectoryPath = AppSettings.saveDirectoryURL.path
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
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
                        .frame(width: 50)
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

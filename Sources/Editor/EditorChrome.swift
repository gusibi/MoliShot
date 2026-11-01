import AppKit

/// Native materials for the editor's floating controls; the image canvas stays unchanged.
enum EditorChrome {
    static func style(_ button: NSButton, prominent: Bool = false) {
        if #available(macOS 26, *) {
            button.bezelStyle = .glass
            button.borderShape = button.title.isEmpty ? .circle : .capsule
            button.tintProminence = prominent ? .primary : .none
        } else {
            button.bezelStyle = button.title.isEmpty ? .circular : .rounded
        }
        if prominent { button.bezelColor = .controlAccentColor }
    }

    static func install(_ content: NSView, in host: NSView, fallback: NSVisualEffectView.Material) {
        let container: NSView
        if #available(macOS 26, *) {
            let glass = NSGlassEffectContainerView()
            glass.spacing = 0
            glass.contentView = content
            container = glass
        } else {
            let effect = NSVisualEffectView()
            effect.material = fallback
            effect.blendingMode = .withinWindow
            effect.state = .active
            effect.addSubview(content)
            container = effect
        }
        container.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(container)
        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            container.topAnchor.constraint(equalTo: host.topAnchor),
            container.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            content.topAnchor.constraint(equalTo: container.topAnchor),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
    }

    static func styleGroup(_ content: NSView) -> NSView {
        guard #available(macOS 26, *) else { return content }
        let glass = NSGlassEffectView()
        glass.cornerRadius = 20
        glass.contentView = content
        glass.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
            content.topAnchor.constraint(equalTo: glass.topAnchor),
            content.bottomAnchor.constraint(equalTo: glass.bottomAnchor)
        ])
        return glass
    }
}

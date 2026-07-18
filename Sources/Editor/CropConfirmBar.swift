import AppKit

/// A persistent confirm/cancel bar floated over the canvas while the crop modal
/// is active. Unlike a toast, it stays put, so there's always a visible way out
/// of crop mode (wayfinding). The buttons mirror the Return/Esc keyboard paths.
final class CropConfirmBar: NSVisualEffectView {
    private let applyAction: () -> Void
    private let cancelAction: () -> Void

    init(applyAction: @escaping () -> Void, cancelAction: @escaping () -> Void) {
        self.applyAction = applyAction
        self.cancelAction = cancelAction
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true

        let apply = makeButton(symbol: "checkmark", title: L10n.text(.apply),
                               tooltip: "\(L10n.text(.apply))  ⏎", prominent: true,
                               action: #selector(applyTapped))
        let cancel = makeButton(symbol: "xmark", title: L10n.text(.cancel),
                                tooltip: "\(L10n.text(.cancel))  ⎋", prominent: false,
                                action: #selector(cancelTapped))

        let stack = NSStackView(views: [apply, cancel])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    private func makeButton(symbol: String, title: String, tooltip: String, prominent: Bool, action: Selector) -> MoliHoverButton {
        let button = MoliHoverButton()
        button.isProminent = prominent
        button.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold))
        button.imagePosition = .imageLeading
        button.imageHugsTitle = true
        button.title = title
        button.toolTip = tooltip
        button.setAccessibilityLabel(title)
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 84).isActive = true
        button.heightAnchor.constraint(equalToConstant: 30).isActive = true
        button.refreshStyle()  // rebuild the tinted title now that it's set
        return button
    }

    @objc private func applyTapped() { applyAction() }
    @objc private func cancelTapped() { cancelAction() }

    // MARK: - Show / hide

    func animateIn() {
        alphaValue = 0
        if MoliDesign.reduceMotion {
            alphaValue = 1
            return
        }
        layoutSubtreeIfNeeded()
        layer?.animateCenteredScale(from: 0.96, to: 1, duration: 0.18, curve: .easeOut)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            animator().alphaValue = 1
        }
    }

    func animateOut(completion: @escaping () -> Void) {
        if MoliDesign.reduceMotion {
            alphaValue = 0
            completion()
            return
        }
        layer?.animateCenteredScale(from: 1, to: 0.96, duration: 0.18, curve: .easeIn)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            animator().alphaValue = 0
        }, completionHandler: completion)
    }
}

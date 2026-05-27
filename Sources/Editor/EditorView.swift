import AppKit

protocol EditorViewDelegate: AnyObject {
    func editorViewDidChangeSelection(_ view: EditorView)
    func editorViewDidChangeContent(_ view: EditorView)
    func editorViewDidChangeTool(_ view: EditorView)
}

enum EditorUndoResult {
    case cancelledTextEditing
    case cancelledPendingInteraction
    case removedAnnotation
    case nothingToUndo
}

final class EditorView: NSView {

    weak var delegate: EditorViewDelegate?

    var baseImage: NSImage {
        didSet { needsDisplay = true }
    }

    var currentTool: AnnotationTool = .select {
        didSet {
            updateCursor()
            delegate?.editorViewDidChangeTool(self)
        }
    }
    var strokeColor: NSColor = .systemRed
    var strokeWidth: CGFloat = 3
    var fontSize: CGFloat = 20

    private(set) var annotations: [Annotation] = []
    private(set) var selected: Annotation?

    private var inProgress: Annotation?
    private var dragStart: NSPoint?
    private var lastPoint: NSPoint?
    private var numberCounter: Int = 1

    private var cropRect: NSRect?

    init(image: NSImage) {
        self.baseImage = image
        super.init(frame: NSRect(origin: .zero, size: image.size))
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        baseImage.draw(in: bounds, from: .zero, operation: .copy, fraction: 1)
        for ann in annotations {
            ann.draw(in: ctx, base: baseImage)
        }
        if let ip = inProgress {
            ip.draw(in: ctx, base: baseImage)
        }
        if let sel = selected {
            let box = sel.boundingBox.insetBy(dx: -4, dy: -4)
            ctx.setStrokeColor(NSColor.systemBlue.cgColor)
            ctx.setLineDash(phase: 0, lengths: [4, 3])
            ctx.setLineWidth(1)
            ctx.stroke(box)
            ctx.setLineDash(phase: 0, lengths: [])
        }
        if let crop = cropRect {
            ctx.setStrokeColor(NSColor.systemYellow.cgColor)
            ctx.setLineWidth(2)
            ctx.stroke(crop)
        }
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        commitActiveTextEditing()
        let p = convert(event.locationInWindow, from: nil)
        dragStart = p
        lastPoint = p

        switch currentTool {
        case .select:
            selected = annotations.reversed().first { $0.hitTest(p) }
            if event.clickCount == 2, let text = selected as? TextAnnotation {
                beginEditingText(text)
            }
            delegate?.editorViewDidChangeSelection(self)
            needsDisplay = true
        case .arrow, .rectangle, .ellipse, .line, .highlight, .blur, .pixelate, .crop:
            inProgress = makeShape(start: p, end: p)
        case .pen:
            let pen = PenAnnotation(points: [p])
            pen.color = strokeColor
            pen.strokeWidth = strokeWidth
            inProgress = pen
        case .text:
            let t = TextAnnotation(origin: p, text: L10n.text(.text))
            t.color = strokeColor
            t.fontSize = fontSize
            annotations.append(t)
            selected = t
            beginEditingText(t)
            delegate?.editorViewDidChangeContent(self)
            needsDisplay = true
        case .number:
            let n = NumberAnnotation(center: p, number: numberCounter)
            numberCounter += 1
            n.color = strokeColor
            annotations.append(n)
            selected = n
            delegate?.editorViewDidChangeContent(self)
            currentTool = .select
            needsDisplay = true
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        defer { lastPoint = p }

        if currentTool == .select, let sel = selected, let last = lastPoint {
            sel.move(by: NSSize(width: p.x - last.x, height: p.y - last.y))
            delegate?.editorViewDidChangeContent(self)
            needsDisplay = true
            return
        }

        switch currentTool {
        case .pen:
            if let pen = inProgress as? PenAnnotation {
                pen.points.append(p)
                needsDisplay = true
            }
        case .arrow, .rectangle, .ellipse, .line, .highlight, .blur, .pixelate, .crop:
            if let shape = inProgress as? ShapeAnnotation {
                shape.end = p
                needsDisplay = true
            }
        default: break
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            dragStart = nil
            lastPoint = nil
        }

        if currentTool == .crop, let shape = inProgress as? ShapeAnnotation {
            let r = shape.boundingBox
            if r.width > 5 && r.height > 5 {
                cropRect = r
            }
            inProgress = nil
            currentTool = .select
            needsDisplay = true
            return
        }

        if let ip = inProgress {
            if let shape = ip as? ShapeAnnotation {
                if shape.boundingBox.width > 2 && shape.boundingBox.height > 2 {
                    annotations.append(shape)
                }
            } else if let pen = ip as? PenAnnotation, pen.points.count > 1 {
                annotations.append(pen)
            }
            delegate?.editorViewDidChangeContent(self)
            inProgress = nil
            if currentTool != .select && currentTool != .pen {
                currentTool = .select
            }
        }
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117 { // delete / forward delete
            if let sel = selected {
                annotations.removeAll { $0.id == sel.id }
                selected = nil
                delegate?.editorViewDidChangeContent(self)
                delegate?.editorViewDidChangeSelection(self)
                needsDisplay = true
            }
        } else if event.keyCode == 53 { // esc
            cancelCurrentInteraction()
        } else {
            super.keyDown(with: event)
        }
    }

    private func makeShape(start: NSPoint, end: NSPoint) -> Annotation {
        let annotation: ShapeAnnotation
        switch currentTool {
        case .arrow: annotation = ArrowAnnotation(start: start, end: end)
        case .rectangle: annotation = RectAnnotation(start: start, end: end)
        case .ellipse: annotation = EllipseAnnotation(start: start, end: end)
        case .line: annotation = LineAnnotation(start: start, end: end)
        case .highlight: annotation = HighlightAnnotation(start: start, end: end)
        case .blur: annotation = BlurAnnotation(start: start, end: end)
        case .pixelate: annotation = PixelateAnnotation(start: start, end: end)
        case .crop: annotation = RectAnnotation(start: start, end: end)
        default: annotation = RectAnnotation(start: start, end: end)
        }
        annotation.color = strokeColor
        annotation.strokeWidth = strokeWidth
        return annotation
    }

    private func updateCursor() {
        switch currentTool {
        case .select: NSCursor.arrow.set()
        case .text: NSCursor.iBeam.set()
        default: NSCursor.crosshair.set()
        }
    }

    // MARK: - Public actions

    @discardableResult
    func undo() -> EditorUndoResult {
        if editingField != nil {
            cancelCurrentInteraction()
            return .cancelledTextEditing
        }
        if inProgress != nil || cropRect != nil {
            cancelCurrentInteraction()
            return .cancelledPendingInteraction
        }
        guard !annotations.isEmpty else { return .nothingToUndo }
        annotations.removeLast()
        selected = nil
        currentTool = .select
        delegate?.editorViewDidChangeContent(self)
        delegate?.editorViewDidChangeSelection(self)
        needsDisplay = true
        return .removedAnnotation
    }

    @discardableResult
    func clearAll() -> Bool {
        commitActiveTextEditing()
        let hadContent = !annotations.isEmpty || cropRect != nil
        annotations.removeAll()
        selected = nil
        cropRect = nil
        numberCounter = 1
        currentTool = .select
        delegate?.editorViewDidChangeContent(self)
        needsDisplay = true
        return hadContent
    }

    @discardableResult
    func applyCrop() -> Bool {
        commitActiveTextEditing()
        guard let rect = cropRect, let cropped = renderFinalImage().cropped(to: rect) else { return false }
        baseImage = cropped
        frame = NSRect(origin: .zero, size: cropped.size)
        annotations.removeAll()
        selected = nil
        cropRect = nil
        currentTool = .select
        delegate?.editorViewDidChangeContent(self)
        invalidateIntrinsicContentSize()
        needsDisplay = true
        return true
    }

    override var intrinsicContentSize: NSSize { baseImage.size }

    // MARK: - Export

    func renderFinalImage() -> NSImage {
        commitActiveTextEditing()
        guard let cg = baseImage.cgImageRef else { return baseImage }
        let size = baseImage.size

        // 直接从CGImage创建位图表示，确保和原图格式一致
        let rep = NSBitmapImageRep(cgImage: cg)
        rep.size = size

        let previousContext = NSGraphicsContext.current
        guard let graphicsContext = NSGraphicsContext(bitmapImageRep: rep) else { return baseImage }
        // 设置高质量插值和抗锯齿
        graphicsContext.imageInterpolation = NSImageInterpolation.high
        graphicsContext.shouldAntialias = true
        NSGraphicsContext.current = graphicsContext
        defer { NSGraphicsContext.current = previousContext }

        let ctx = graphicsContext.cgContext
        ctx.clear(NSRect(origin: .zero, size: size))
        // 使用高质量绘制
        baseImage.draw(
            in: NSRect(origin: .zero, size: size),
            from: .zero,
            operation: .copy,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSNumber(value: NSImageInterpolation.high.rawValue)]
        )
        for ann in annotations {
            ann.draw(in: ctx, base: baseImage)
        }
        graphicsContext.flushGraphics()

        let out = NSImage(size: size)
        out.addRepresentation(rep)
        return out
    }

    // MARK: - Text editing

    private var editingField: EscapableTextField?

    func commitActiveTextEditing() {
        if let field = editingField {
            commitEditing(field)
        }
    }

    func cancelCurrentInteraction() {
        if let field = editingField {
            cancelEditing(field)
            return
        }

        if inProgress != nil {
            inProgress = nil
            cropRect = nil
            currentTool = .select
            needsDisplay = true
            return
        }

        if cropRect != nil {
            cropRect = nil
            currentTool = .select
            needsDisplay = true
            return
        }

        if selected != nil {
            selected = nil
            delegate?.editorViewDidChangeSelection(self)
            needsDisplay = true
            return
        }

        if currentTool != .select {
            currentTool = .select
            needsDisplay = true
        }
    }

    private func beginEditingText(_ annotation: TextAnnotation) {
        commitActiveTextEditing()
        let box = annotation.boundingBox
        let tf = EscapableTextField(frame: box.insetBy(dx: -4, dy: -4))
        tf.stringValue = annotation.text
        tf.font = NSFont.systemFont(ofSize: annotation.fontSize, weight: .semibold)
        tf.textColor = annotation.color
        tf.backgroundColor = NSColor.adaptive(
            light: NSColor.white.withAlphaComponent(0.15),
            dark: NSColor.black.withAlphaComponent(0.25)
        )
        tf.isBordered = false
        tf.focusRingType = .none
        tf.target = self
        tf.action = #selector(textFieldAction(_:))
        tf.delegate = self
        tf.onEscape = { [weak self, weak tf] in
            guard let self, let tf else { return }
            self.cancelEditing(tf)
        }
        addSubview(tf)
        window?.makeFirstResponder(tf)
        editingField = tf
        objc_setAssociatedObject(tf, &textAnnotationKey, annotation, .OBJC_ASSOCIATION_ASSIGN)
    }

    @objc private func textFieldAction(_ sender: NSTextField) {
        commitEditing(sender)
    }

    private func commitEditing(_ sender: NSTextField) {
        if let ann = objc_getAssociatedObject(sender, &textAnnotationKey) as? TextAnnotation {
            ann.text = sender.stringValue.isEmpty ? L10n.text(.text) : sender.stringValue
        }
        sender.removeFromSuperview()
        editingField = nil
        delegate?.editorViewDidChangeContent(self)
        needsDisplay = true
    }

    private func cancelEditing(_ sender: NSTextField) {
        let shouldRemovePlaceholder =
            sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            sender.stringValue == L10n.text(.text)
        if shouldRemovePlaceholder,
           let ann = objc_getAssociatedObject(sender, &textAnnotationKey) as? TextAnnotation {
            annotations.removeAll { $0.id == ann.id }
            selected = nil
            delegate?.editorViewDidChangeSelection(self)
            delegate?.editorViewDidChangeContent(self)
        }
        sender.removeFromSuperview()
        editingField = nil
        currentTool = .select
        window?.makeFirstResponder(self)
        needsDisplay = true
    }
}

private var textAnnotationKey: UInt8 = 0

extension EditorView: NSTextFieldDelegate {
    func controlTextDidEndEditing(_ obj: Notification) {
        if let tf = obj.object as? NSTextField {
            commitEditing(tf)
            currentTool = .select
        }
    }
}

private final class EscapableTextField: NSTextField {
    var onEscape: (() -> Void)?

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }
}

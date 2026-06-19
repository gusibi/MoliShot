import AppKit

protocol EditorViewDelegate: AnyObject {
    func editorViewDidChangeSelection(_ view: EditorView)
    func editorViewDidChangeContent(_ view: EditorView)
    func editorViewDidChangeTool(_ view: EditorView)
}

enum EditorUndoResult {
    case cancelledTextEditing
    case cancelledPendingInteraction
    case undid
    case redid
    case nothingToUndo
    case nothingToRedo
}

/// Snapshot of editor state for undo/redo. `selectedID` tracks selection
/// across snapshots by identity (stable UUID) rather than index, so undo can
/// re-resolve the selected annotation if it still exists. `numberCounter`
/// is included so undoing a number annotation creation restores the counter.
struct EditorState {
    var annotations: [Annotation]
    var cropRect: NSRect?
    var selectedID: UUID?
    var numberCounter: Int
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
    private var didDragMove = false
    private var pendingTextCreation = false
    private var styleCoalesceID: UUID?

    private var cropRect: NSRect?

    private var history = HistoryStack<EditorState>()

    init(image: NSImage) {
        self.baseImage = image
        super.init(frame: NSRect(origin: .zero, size: image.size))
        wantsLayer = true
        history.push(snapshot())  // baseline state
    }

    // MARK: - History

    private func snapshot() -> EditorState {
        EditorState(annotations: annotations, cropRect: cropRect,
                    selectedID: selected?.id, numberCounter: numberCounter)
    }

    private func restore(_ state: EditorState) {
        annotations = state.annotations
        cropRect = state.cropRect
        numberCounter = state.numberCounter
        if let id = state.selectedID, let ann = annotations.first(where: { $0.id == id }) {
            selected = ann
        } else {
            selected = nil
        }
        delegate?.editorViewDidChangeContent(self)
        delegate?.editorViewDidChangeSelection(self)
        needsDisplay = true
    }

    /// Checkpoint the current state after an atomic operation.
    private func commitHistory() {
        history.push(snapshot())
        styleCoalesceID = nil
    }

    /// Checkpoint a style change, coalescing consecutive changes to the same
    /// annotation (e.g. a continuous slider drag) into a single undo step.
    private func commitStyleChange(_ id: UUID) {
        if styleCoalesceID == id {
            history.replaceCurrent(snapshot())
        } else {
            history.push(snapshot())
            styleCoalesceID = id
        }
    }

    private func writeBack(_ ann: Annotation) {
        if let idx = annotations.firstIndex(where: { $0.id == ann.id }) {
            annotations[idx] = ann
        }
        if selected?.id == ann.id {
            selected = ann
        }
    }

    // MARK: - Style editing (applies to selection, else defaults)

    func setStrokeColor(_ color: NSColor) {
        strokeColor = color
        applyStyleToSelected { $0.color = color }
    }

    func setStrokeWidth(_ width: CGFloat) {
        strokeWidth = width
        applyStyleToSelected { $0.strokeWidth = width }
    }

    func setFontSize(_ size: CGFloat) {
        fontSize = size
        applyStyleToSelected { $0.fontSize = size }
    }

    private func applyStyleToSelected(_ mutate: (inout AnnotationStyle) -> Void) {
        guard var sel = selected else { return }
        var st = sel.style
        mutate(&st)
        sel.style = st
        writeBack(sel)
        commitStyleChange(sel.id)
        delegate?.editorViewDidChangeContent(self)
        needsDisplay = true
    }

    /// Whether the selection is a text annotation (font size has visible effect).
    var selectedIsText: Bool { selected is TextAnnotation }

    /// Current effective style for the controls: the selected annotation's
    /// style, or the default style for new annotations when nothing is selected.
    var effectiveStyle: AnnotationStyle {
        if let sel = selected { return sel.style }
        return AnnotationStyle(color: strokeColor, strokeWidth: strokeWidth, fontSize: fontSize)
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
            let box = sel.bounds.insetBy(dx: -4, dy: -4)
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
            if let id = AnnotationHitTester.hitTest(point: p, annotations: annotations) {
                selected = annotations.first { $0.id == id }
            } else {
                selected = nil
            }
            if event.clickCount == 2, let text = selected as? TextAnnotation {
                beginEditingText(text)
            }
            delegate?.editorViewDidChangeSelection(self)
            needsDisplay = true
        case .arrow, .rectangle, .ellipse, .line, .highlight, .blur, .pixelate, .crop:
            inProgress = makeShape(start: p, end: p)
        case .pen:
            let pen = PenAnnotation(points: [p], style: defaultStyle())
            inProgress = pen
        case .text:
            let t = TextAnnotation(origin: p, text: L10n.text(.text), style: defaultStyle())
            annotations.append(t)
            selected = t
            pendingTextCreation = true
            beginEditingText(t)
            delegate?.editorViewDidChangeContent(self)
            needsDisplay = true
        case .number:
            let n = NumberAnnotation(center: p, number: numberCounter, style: defaultStyle())
            numberCounter += 1
            annotations.append(n)
            selected = n
            commitHistory()
            delegate?.editorViewDidChangeContent(self)
            currentTool = .select
            needsDisplay = true
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        defer { lastPoint = p }

        if currentTool == .select, var sel = selected, let last = lastPoint {
            sel.move(by: NSSize(width: p.x - last.x, height: p.y - last.y))
            selected = sel
            if let idx = annotations.firstIndex(where: { $0.id == sel.id }) {
                annotations[idx] = sel
            }
            didDragMove = true
            delegate?.editorViewDidChangeContent(self)
            needsDisplay = true
            return
        }

        switch currentTool {
        case .pen:
            if var pen = inProgress as? PenAnnotation {
                pen.points.append(p)
                inProgress = pen
                needsDisplay = true
            }
        case .arrow, .rectangle, .ellipse, .line, .highlight, .blur, .pixelate, .crop:
            if var shape = inProgress as? any BoundedShapeAnnotation {
                shape.end = p
                inProgress = shape
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

        if currentTool == .crop, let shape = inProgress as? any BoundedShapeAnnotation {
            let r = shape.bounds
            if r.width > 5 && r.height > 5 {
                cropRect = r
                commitHistory()
            }
            inProgress = nil
            currentTool = .select
            needsDisplay = true
            return
        }

        if let ip = inProgress {
            if let shape = ip as? any BoundedShapeAnnotation {
                if shape.bounds.width > 2 && shape.bounds.height > 2 {
                    annotations.append(shape)
                    commitHistory()
                }
            } else if let pen = ip as? PenAnnotation, pen.points.count > 1 {
                annotations.append(pen)
                commitHistory()
            }
            delegate?.editorViewDidChangeContent(self)
            inProgress = nil
            if currentTool != .select && currentTool != .pen {
                currentTool = .select
            }
        }

        if didDragMove {
            commitHistory()
            didDragMove = false
        }
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117 { // delete / forward delete
            if let sel = selected {
                annotations.removeAll { $0.id == sel.id }
                selected = nil
                commitHistory()
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
        let style = defaultStyle()
        switch currentTool {
        case .arrow: return ArrowAnnotation(start: start, end: end, style: style)
        case .rectangle: return RectAnnotation(start: start, end: end, style: style)
        case .ellipse: return EllipseAnnotation(start: start, end: end, style: style)
        case .line: return LineAnnotation(start: start, end: end, style: style)
        case .highlight: return HighlightAnnotation(start: start, end: end, style: style)
        case .blur: return BlurAnnotation(start: start, end: end, style: style)
        case .pixelate: return PixelateAnnotation(start: start, end: end, style: style)
        case .crop: return RectAnnotation(start: start, end: end, style: style)
        default: return RectAnnotation(start: start, end: end, style: style)
        }
    }

    private func defaultStyle() -> AnnotationStyle {
        AnnotationStyle(color: strokeColor, strokeWidth: strokeWidth, fontSize: fontSize)
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
        if inProgress != nil {
            cancelCurrentInteraction()
            return .cancelledPendingInteraction
        }
        guard let prev = history.undo() else { return .nothingToUndo }
        restore(prev)
        currentTool = .select
        return .undid
    }

    @discardableResult
    func redo() -> EditorUndoResult {
        if editingField != nil { return .nothingToRedo }
        guard let next = history.redo() else { return .nothingToRedo }
        restore(next)
        return .redid
    }

    var canUndo: Bool { history.canUndo || editingField != nil || inProgress != nil }
    var canRedo: Bool { history.canRedo }

    @discardableResult
    func clearAll() -> Bool {
        commitActiveTextEditing()
        let hadContent = !annotations.isEmpty || cropRect != nil
        annotations.removeAll()
        selected = nil
        cropRect = nil
        numberCounter = 1
        currentTool = .select
        commitHistory()
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
        // Crop is a destructive commit (base image changes, not tracked in
        // EditorState). Reset history so undo cannot cross the crop boundary.
        // Non-destructive crop (#11) will restore full undo across crops.
        history.clear()
        history.push(snapshot())
        delegate?.editorViewDidChangeContent(self)
        invalidateIntrinsicContentSize()
        needsDisplay = true
        return true
    }

    override var intrinsicContentSize: NSSize { baseImage.size }

    // MARK: - Export

    func renderFinalImage() -> NSImage {
        commitActiveTextEditing()
        return AnnotationRenderer.render(annotations: annotations, baseImage: baseImage)
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
        let box = annotation.bounds
        let tf = EscapableTextField(frame: box.insetBy(dx: -4, dy: -4))
        tf.stringValue = annotation.text
        tf.font = NSFont.systemFont(ofSize: annotation.style.fontSize, weight: .semibold)
        tf.textColor = annotation.style.color
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
        // Retain the struct copy (boxed) so commit/cancel can read it back;
        // ASSIGN is for weak object references and would not retain a value type.
        objc_setAssociatedObject(tf, &textAnnotationKey, annotation, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    @objc private func textFieldAction(_ sender: NSTextField) {
        commitEditing(sender)
    }

    private func commitEditing(_ sender: NSTextField) {
        if let ann = objc_getAssociatedObject(sender, &textAnnotationKey) as? TextAnnotation {
            var copy = ann
            copy.text = sender.stringValue.isEmpty ? L10n.text(.text) : sender.stringValue
            let changed = pendingTextCreation || copy.text != ann.text
            if let idx = annotations.firstIndex(where: { $0.id == copy.id }) {
                annotations[idx] = copy
            }
            if selected?.id == copy.id {
                selected = copy
            }
            if changed {
                commitHistory()
            }
        }
        pendingTextCreation = false
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
        pendingTextCreation = false
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

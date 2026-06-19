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

    private var resizeHandle: ResizeHandle?
    private var resizeOriginalBounds: CGRect = .zero
    private var resizeStarted = false

    /// Crop editing modal. When true, mouse events draw/adjust `cropRect`;
    /// draw renders a dim mask outside it. When false with `cropRect` set, the
    /// canvas shows the committed (non-destructive) cropped view.
    private(set) var cropMode = false
    private var cropAdjust = CropAdjust.none
    private var cropDragStart: CGPoint?

    /// Which part of the crop rect a drag is adjusting.
    private enum CropAdjust {
        case none, move, drawing
        case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
    }

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
        cropMode = false
        numberCounter = state.numberCounter
        if let id = state.selectedID, let ann = annotations.first(where: { $0.id == id }) {
            selected = ann
        } else {
            selected = nil
        }
        syncFrameToCrop()
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

    func setOpacity(_ opacity: CGFloat) {
        applyStyleToSelected { $0.opacity = max(0, min(1, opacity)) }
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

        if cropMode {
            drawCropModal(ctx)
            return
        }

        // Committed crop: translate so the crop rect's origin maps to (0,0);
        // the view's (shrunk) bounds clips the rest.
        if let crop = cropRect {
            ctx.saveGState()
            ctx.translateBy(x: -crop.origin.x, y: -crop.origin.y)
            baseImage.draw(in: NSRect(origin: .zero, size: baseImage.size),
                           from: .zero, operation: .copy, fraction: 1)
            drawAnnotations(in: ctx)
            drawSelectionOverlay(in: ctx)
            ctx.restoreGState()
            return
        }

        // Full image (no crop).
        baseImage.draw(in: bounds, from: .zero, operation: .copy, fraction: 1)
        drawAnnotations(in: ctx)
        drawSelectionOverlay(in: ctx)
    }

    /// Draw committed + in-progress annotations, each with its own opacity.
    private func drawAnnotations(in ctx: CGContext) {
        for ann in annotations {
            ctx.saveGState()
            ctx.setAlpha(ann.style.opacity)
            ann.draw(in: ctx, base: baseImage)
            ctx.restoreGState()
        }
        if let ip = inProgress {
            ctx.saveGState()
            ctx.setAlpha(ip.style.opacity)
            ip.draw(in: ctx, base: baseImage)
            ctx.restoreGState()
        }
    }

    private func drawSelectionOverlay(in ctx: CGContext) {
        guard let sel = selected else { return }
        let box = sel.bounds.insetBy(dx: -4, dy: -4)
        ctx.setStrokeColor(NSColor.systemBlue.cgColor)
        ctx.setLineDash(phase: 0, lengths: [4, 3])
        ctx.setLineWidth(1)
        ctx.stroke(box)
        ctx.setLineDash(phase: 0, lengths: [])
        drawHandles(for: sel, in: ctx)
    }

    private func drawCropModal(_ ctx: CGContext) {
        baseImage.draw(in: bounds, from: .zero, operation: .copy, fraction: 1)
        for ann in annotations { ann.draw(in: ctx, base: baseImage) }

        if let crop = cropRect {
            // Dim everything outside the crop rect.
            let b = bounds
            ctx.setFillColor(NSColor.black.withAlphaComponent(0.45).cgColor)
            ctx.fill([
                CGRect(x: b.minX, y: b.minY, width: b.width, height: max(0, crop.minY - b.minY)),
                CGRect(x: b.minX, y: crop.maxY, width: b.width, height: max(0, b.maxY - crop.maxY)),
                CGRect(x: b.minX, y: crop.minY, width: max(0, crop.minX - b.minX), height: crop.height),
                CGRect(x: crop.maxX, y: crop.minY, width: max(0, b.maxX - crop.maxX), height: crop.height),
            ])
            // Crop border + handles.
            ctx.setStrokeColor(NSColor.systemYellow.cgColor)
            ctx.setLineWidth(2)
            ctx.stroke(crop)
            let r: CGFloat = 4
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.setStrokeColor(NSColor.systemYellow.cgColor)
            ctx.setLineWidth(1.5)
            for hp in cropHandlePoints(crop) {
                let rect = CGRect(x: hp.x - r, y: hp.y - r, width: r * 2, height: r * 2)
                ctx.fillEllipse(in: rect)
                ctx.strokeEllipse(in: rect)
            }
        }
    }

    private func cropHandlePoints(_ c: CGRect) -> [CGPoint] {
        [
            CGPoint(x: c.minX, y: c.minY), CGPoint(x: c.midX, y: c.minY), CGPoint(x: c.maxX, y: c.minY),
            CGPoint(x: c.maxX, y: c.midY), CGPoint(x: c.maxX, y: c.maxY), CGPoint(x: c.midX, y: c.maxY),
            CGPoint(x: c.minX, y: c.maxY), CGPoint(x: c.minX, y: c.midY),
        ]
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        commitActiveTextEditing()
        let p = convert(event.locationInWindow, from: nil)
        dragStart = p
        lastPoint = p

        if cropMode {
            cropMouseDown(at: p)
            return
        }

        let bp = basePoint(from: p)

        switch currentTool {
        case .select:
            if let sel = selected, let h = sel.handle(at: bp) {
                resizeHandle = h
                resizeOriginalBounds = sel.bounds
                resizeStarted = false
                return
            }
            if let id = AnnotationHitTester.hitTest(point: bp, annotations: annotations) {
                selected = annotations.first { $0.id == id }
            } else {
                selected = nil
            }
            if event.clickCount == 2, let text = selected as? TextAnnotation {
                beginEditingText(text)
            }
            delegate?.editorViewDidChangeSelection(self)
            needsDisplay = true
        case .arrow, .rectangle, .ellipse, .line, .highlight, .blur, .pixelate:
            inProgress = makeShape(start: bp, end: bp)
        case .pen:
            let pen = PenAnnotation(points: [bp], style: defaultStyle())
            inProgress = pen
        case .text:
            let t = TextAnnotation(origin: bp, text: L10n.text(.text), style: defaultStyle())
            annotations.append(t)
            selected = t
            pendingTextCreation = true
            beginEditingText(t)
            delegate?.editorViewDidChangeContent(self)
            needsDisplay = true
        case .number:
            let n = NumberAnnotation(center: bp, number: numberCounter, style: defaultStyle())
            numberCounter += 1
            annotations.append(n)
            selected = n
            commitHistory()
            delegate?.editorViewDidChangeContent(self)
            currentTool = .select
            needsDisplay = true
        case .crop:
            break  // crop is a modal, not a tool; handled via cropMode
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        defer { lastPoint = p }

        if cropMode {
            cropMouseDragged(at: p)
            return
        }

        let bp = basePoint(from: p)

        if currentTool == .select, let handle = resizeHandle, let sel = selected {
            let resized = applyResize(to: sel, handle: handle, to: bp)
            writeBack(resized)
            if !resizeStarted {
                history.push(snapshot())
                resizeStarted = true
            } else {
                history.replaceCurrent(snapshot())
            }
            delegate?.editorViewDidChangeContent(self)
            needsDisplay = true
            return
        }

        if currentTool == .select, var sel = selected, let last = lastPoint {
            let lastBP = basePoint(from: last)
            sel.move(by: NSSize(width: bp.x - lastBP.x, height: bp.y - lastBP.y))
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
                pen.points.append(bp)
                inProgress = pen
                needsDisplay = true
            }
        case .arrow, .rectangle, .ellipse, .line, .highlight, .blur, .pixelate:
            if var shape = inProgress as? any BoundedShapeAnnotation {
                shape.end = bp
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

        if cropMode {
            cropMouseUp()
            return
        }

        if resizeHandle != nil {
            resizeHandle = nil
            resizeStarted = false
            // A click without drag made no history entry and changed nothing;
            // a drag already coalesced its final state into the current snapshot.
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
        if cropMode {
            if event.keyCode == 36 { applyCropModal(); return }   // Return → apply
            if event.keyCode == 53 { cancelCropMode(); return }   // Esc → cancel
            super.keyDown(with: event)
            return
        }
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

    // MARK: - Resize

    private func applyResize(to ann: Annotation, handle: ResizeHandle, to p: CGPoint) -> Annotation {
        switch handle {
        case .startEndpoint:
            if var b = ann as? any BoundedShapeAnnotation { b.start = p; return b }
            return ann
        case .endEndpoint:
            if var b = ann as? any BoundedShapeAnnotation { b.end = p; return b }
            return ann
        default:
            let newBounds = resizedBounds(from: resizeOriginalBounds, handle: handle, to: p)
            return ann.resized(to: newBounds)
        }
    }

    /// Compute the new bbox by moving the dragged handle's edge(s) to `p`,
    /// anchoring the opposite side. Prevents inversion and enforces a 1pt min.
    private func resizedBounds(from original: CGRect, handle: ResizeHandle, to p: CGPoint) -> CGRect {
        var minX = original.minX, maxX = original.maxX, minY = original.minY, maxY = original.maxY
        switch handle {
        case .topLeft, .top, .topRight: maxY = p.y
        case .bottomLeft, .bottom, .bottomRight: minY = p.y
        default: break
        }
        switch handle {
        case .topLeft, .left, .bottomLeft: minX = p.x
        case .topRight, .right, .bottomRight: maxX = p.x
        default: break
        }
        if minX > maxX { Swift.swap(&minX, &maxX) }
        if minY > maxY { Swift.swap(&minY, &maxY) }
        let minSize: CGFloat = 1
        if maxX - minX < minSize { maxX = minX + minSize }
        if maxY - minY < minSize { maxY = minY + minSize }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func drawHandles(for ann: Annotation, in ctx: CGContext) {
        let r: CGFloat = 4
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.setStrokeColor(NSColor.systemBlue.cgColor)
        ctx.setLineWidth(1.5)
        for (_, hp) in ann.handlePoints {
            let rect = CGRect(x: hp.x - r, y: hp.y - r, width: r * 2, height: r * 2)
            ctx.fillEllipse(in: rect)
            ctx.strokeEllipse(in: rect)
        }
    }

    // MARK: - Crop (non-destructive modal)

    /// Size the canvas should occupy: full image while editing crop or when no
    /// crop is committed; the crop rect size once a crop is committed.
    var effectiveSize: NSSize {
        cropMode || cropRect == nil ? baseImage.size : cropRect!.size
    }

    /// Offset from view coordinates to base-image coordinates. Non-zero only
    /// when a crop is committed (the view is shrunk to the crop and translated).
    private var cropOrigin: CGPoint {
        (cropMode || cropRect == nil) ? .zero : cropRect!.origin
    }

    /// Map a view-space point (from mouse events) to base-image coordinates.
    private func basePoint(from viewPoint: NSPoint) -> NSPoint {
        let o = cropOrigin
        return NSPoint(x: viewPoint.x + o.x, y: viewPoint.y + o.y)
    }

    private func syncFrameToCrop() {
        let newSize = effectiveSize
        if !frame.size.equalTo(newSize) {
            frame = NSRect(origin: .zero, size: newSize)
            invalidateIntrinsicContentSize()
        }
    }

    func enterCropMode() {
        commitActiveTextEditing()
        selected = nil
        currentTool = .select
        cropMode = true
        cropRect = nil
        syncFrameToCrop()
        updateCursor()
        delegate?.editorViewDidChangeContent(self)
        needsDisplay = true
    }

    /// Apply the in-progress crop: commit cropRect, exit modal. No-op if no
    /// valid rect was drawn.
    @discardableResult
    func applyCropModal() -> Bool {
        guard cropMode else { return false }
        guard let r = cropRect, r.width > 5, r.height > 5 else {
            cropRect = nil
            cropMode = false
            syncFrameToCrop()
            updateCursor()
            needsDisplay = true
            return false
        }
        // Normalize (origin at min corner).
        cropRect = r
        cropMode = false
        cropAdjust = .none
        cropDragStart = nil
        commitHistory()
        syncFrameToCrop()
        updateCursor()
        delegate?.editorViewDidChangeContent(self)
        needsDisplay = true
        return true
    }

    func cancelCropMode() {
        guard cropMode else { return }
        cropMode = false
        cropRect = nil
        cropAdjust = .none
        cropDragStart = nil
        syncFrameToCrop()
        updateCursor()
        needsDisplay = true
    }

    // MARK: - Crop modal mouse handling

    private func cropMouseDown(at p: CGPoint) {
        cropDragStart = p
        if let crop = cropRect {
            if let h = cropHandle(at: p, in: crop) {
                cropAdjust = h
            } else if crop.contains(p) {
                cropAdjust = .move
            } else {
                // Start a new crop rect from scratch.
                cropRect = rectFrom(a: p, b: p)
                cropAdjust = .drawing
            }
        } else {
            cropRect = rectFrom(a: p, b: p)
            cropAdjust = .drawing
        }
        needsDisplay = true
    }

    private func cropMouseDragged(at p: CGPoint) {
        guard var crop = cropRect, let start = cropDragStart else { return }
        switch cropAdjust {
        case .drawing:
            crop = rectFrom(a: start, b: p)
        case .move:
            crop.origin.x += p.x - start.x
            crop.origin.y += p.y - start.y
            cropDragStart = p
        case .none:
            return
        case .topLeft, .top, .topRight, .right, .bottomRight, .bottom, .bottomLeft, .left:
            crop = adjustCrop(crop, handle: cropAdjust, to: p)
        }
        cropRect = crop
        needsDisplay = true
    }

    private func cropMouseUp() {
        cropAdjust = .none
        cropDragStart = nil
        // Discard a too-small crop rect drawn by accident.
        if let c = cropRect, c.width < 5 || c.height < 5 {
            cropRect = nil
        }
        needsDisplay = true
    }

    private func cropHandle(at p: CGPoint, in c: CGRect) -> CropAdjust? {
        let tol: CGFloat = 8
        let nearL = abs(p.x - c.minX) <= tol
        let nearR = abs(p.x - c.maxX) <= tol
        let nearB = abs(p.y - c.minY) <= tol
        let nearT = abs(p.y - c.maxY) <= tol
        if nearL && nearT { return .topLeft }
        if nearR && nearT { return .topRight }
        if nearR && nearB { return .bottomRight }
        if nearL && nearB { return .bottomLeft }
        if nearT { return .top }
        if nearR { return .right }
        if nearB { return .bottom }
        if nearL { return .left }
        return nil
    }

    private func adjustCrop(_ c: CGRect, handle: CropAdjust, to p: CGPoint) -> CGRect {
        var minX = c.minX, maxX = c.maxX, minY = c.minY, maxY = c.maxY
        switch handle {
        case .topLeft, .top, .topRight: maxY = p.y
        case .bottomLeft, .bottom, .bottomRight: minY = p.y
        default: break
        }
        switch handle {
        case .topLeft, .left, .bottomLeft: minX = p.x
        case .topRight, .right, .bottomRight: maxX = p.x
        default: break
        }
        if minX > maxX { Swift.swap(&minX, &maxX) }
        if minY > maxY { Swift.swap(&minY, &maxY) }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func rectFrom(a: CGPoint, b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
               width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    private func updateCursor() {
        if cropMode {
            NSCursor.crosshair.set()
            return
        }
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

    // MARK: - Z-order

    /// Annotations are drawn in array order, so the last element is on top.
    /// Reordering the array changes stacking. Each op pushes history.
    @discardableResult
    func bringForward() -> Bool { reorder(delta: 1) }

    @discardableResult
    func sendBackward() -> Bool { reorder(delta: -1) }

    @discardableResult
    func bringToFront() -> Bool { reorder(toFront: true) }

    @discardableResult
    func sendToBack() -> Bool { reorder(toFront: false) }

    @discardableResult
    private func reorder(delta: Int) -> Bool {
        guard let sel = selected, let idx = annotations.firstIndex(where: { $0.id == sel.id }) else { return false }
        let target = idx + delta
        guard target >= 0, target < annotations.count else { return false }
        annotations.swapAt(idx, target)
        commitHistory()
        delegate?.editorViewDidChangeContent(self)
        needsDisplay = true
        return true
    }

    @discardableResult
    private func reorder(toFront: Bool) -> Bool {
        guard let sel = selected, let idx = annotations.firstIndex(where: { $0.id == sel.id }) else { return false }
        let ann = annotations.remove(at: idx)
        if toFront { annotations.append(ann) } else { annotations.insert(ann, at: 0) }
        commitHistory()
        delegate?.editorViewDidChangeContent(self)
        needsDisplay = true
        return true
    }

    @discardableResult
    func clearAll() -> Bool {
        commitActiveTextEditing()
        let hadContent = !annotations.isEmpty || cropRect != nil
        annotations.removeAll()
        selected = nil
        cropRect = nil
        cropMode = false
        numberCounter = 1
        currentTool = .select
        commitHistory()
        syncFrameToCrop()
        delegate?.editorViewDidChangeContent(self)
        needsDisplay = true
        return hadContent
    }

    override var intrinsicContentSize: NSSize { effectiveSize }

    // MARK: - Export

    func renderFinalImage() -> NSImage {
        commitActiveTextEditing()
        // While the crop modal is open, export the full image (the in-progress
        // crop is not committed). Once committed, cropRect is applied.
        let crop = cropMode ? nil : cropRect
        return AnnotationRenderer.render(annotations: annotations, cropRect: crop, baseImage: baseImage)
    }

    // MARK: - Text editing

    private var editingField: EscapableTextField?

    func commitActiveTextEditing() {
        if let field = editingField {
            commitEditing(field)
        }
    }

    func cancelCurrentInteraction() {
        if cropMode {
            cancelCropMode()
            return
        }

        if let field = editingField {
            cancelEditing(field)
            return
        }

        if inProgress != nil {
            inProgress = nil
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

import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

enum AnnotationTool: String, CaseIterable {
    case select, arrow, rectangle, ellipse, line, pen, text, number, blur, pixelate, highlight, crop

    var symbol: String {
        switch self {
        case .select: return "arrow.up.left"
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .line: return "line.diagonal"
        case .pen: return "pencil.tip"
        case .text: return "textformat"
        case .number: return "1.circle"
        case .blur: return "drop"
        case .pixelate: return "square.grid.3x3"
        case .highlight: return "highlighter"
        case .crop: return "crop"
        }
    }

    var title: String {
        switch self {
        case .select: return L10n.text(.select)
        case .arrow: return L10n.text(.arrow)
        case .rectangle: return L10n.text(.rectangle)
        case .ellipse: return L10n.text(.ellipse)
        case .line: return L10n.text(.line)
        case .pen: return L10n.text(.pen)
        case .text: return L10n.text(.text)
        case .number: return L10n.text(.number)
        case .blur: return L10n.text(.blur)
        case .pixelate: return L10n.text(.pixelate)
        case .highlight: return L10n.text(.highlight)
        case .crop: return L10n.text(.crop)
        }
    }
}

/// Value-type annotation model. Each annotation carries a stable `id` (UUID)
/// so selection and undo snapshots can track it across history, and a shared
/// `style`. Selection-by-identity replaces the previous reference-semantics
/// mutation; callers copy-out, mutate, and write back by id.
protocol Annotation {
    var id: UUID { get }
    var bounds: CGRect { get }
    var style: AnnotationStyle { get set }
    func hitTest(_ point: CGPoint) -> Bool
    mutating func move(by delta: NSSize)
    func draw(in ctx: CGContext, base: NSImage)
}

/// Annotations defined by two endpoints (drag to create). Unifies the
/// previously class-inherited ShapeAnnotation family with blur/pixelate,
/// which are now standalone structs.
protocol BoundedShapeAnnotation: Annotation {
    var start: NSPoint { get set }
    var end: NSPoint { get set }
}

// MARK: - Shapes

struct RectAnnotation: Annotation, BoundedShapeAnnotation, Codable {
    let id: UUID
    var start: NSPoint
    var end: NSPoint
    var style: AnnotationStyle

    init(id: UUID = UUID(), start: NSPoint, end: NSPoint, style: AnnotationStyle = AnnotationStyle(color: .systemRed)) {
        self.id = id
        self.start = start
        self.end = end
        self.style = style
    }

    var bounds: NSRect {
        NSRect(x: min(start.x, end.x), y: min(start.y, end.y),
               width: abs(end.x - start.x), height: abs(end.y - start.y))
    }

    mutating func move(by delta: NSSize) {
        start = NSPoint(x: start.x + delta.width, y: start.y + delta.height)
        end = NSPoint(x: end.x + delta.width, y: end.y + delta.height)
    }

    func hitTest(_ point: NSPoint) -> Bool {
        bounds.insetBy(dx: -6, dy: -6).contains(point)
    }

    func draw(in ctx: CGContext, base: NSImage) {
        ctx.setStrokeColor(style.color.cgColor)
        ctx.setLineWidth(style.strokeWidth)
        ctx.stroke(bounds)
    }
}

struct EllipseAnnotation: Annotation, BoundedShapeAnnotation, Codable {
    let id: UUID
    var start: NSPoint
    var end: NSPoint
    var style: AnnotationStyle

    init(id: UUID = UUID(), start: NSPoint, end: NSPoint, style: AnnotationStyle = AnnotationStyle(color: .systemRed)) {
        self.id = id; self.start = start; self.end = end; self.style = style
    }

    var bounds: NSRect {
        NSRect(x: min(start.x, end.x), y: min(start.y, end.y),
               width: abs(end.x - start.x), height: abs(end.y - start.y))
    }
    mutating func move(by delta: NSSize) {
        start = NSPoint(x: start.x + delta.width, y: start.y + delta.height)
        end = NSPoint(x: end.x + delta.width, y: end.y + delta.height)
    }
    func hitTest(_ point: NSPoint) -> Bool { bounds.insetBy(dx: -6, dy: -6).contains(point) }
    func draw(in ctx: CGContext, base: NSImage) {
        ctx.setStrokeColor(style.color.cgColor)
        ctx.setLineWidth(style.strokeWidth)
        ctx.strokeEllipse(in: bounds)
    }
}

struct LineAnnotation: Annotation, BoundedShapeAnnotation, Codable {
    let id: UUID
    var start: NSPoint
    var end: NSPoint
    var style: AnnotationStyle

    init(id: UUID = UUID(), start: NSPoint, end: NSPoint, style: AnnotationStyle = AnnotationStyle(color: .systemRed)) {
        self.id = id; self.start = start; self.end = end; self.style = style
    }

    var bounds: NSRect {
        NSRect(x: min(start.x, end.x), y: min(start.y, end.y),
               width: abs(end.x - start.x), height: abs(end.y - start.y))
    }
    mutating func move(by delta: NSSize) {
        start = NSPoint(x: start.x + delta.width, y: start.y + delta.height)
        end = NSPoint(x: end.x + delta.width, y: end.y + delta.height)
    }
    func hitTest(_ point: NSPoint) -> Bool {
        distanceFromPoint(point, toSegment: start, end) <= strokeHitTolerance
    }
    func draw(in ctx: CGContext, base: NSImage) {
        ctx.setStrokeColor(style.color.cgColor)
        ctx.setLineWidth(style.strokeWidth)
        ctx.setLineCap(.round)
        ctx.move(to: start)
        ctx.addLine(to: end)
        ctx.strokePath()
    }
}

struct ArrowAnnotation: Annotation, BoundedShapeAnnotation, Codable {
    let id: UUID
    var start: NSPoint
    var end: NSPoint
    var style: AnnotationStyle

    init(id: UUID = UUID(), start: NSPoint, end: NSPoint, style: AnnotationStyle = AnnotationStyle(color: .systemRed)) {
        self.id = id; self.start = start; self.end = end; self.style = style
    }

    var bounds: NSRect {
        NSRect(x: min(start.x, end.x), y: min(start.y, end.y),
               width: abs(end.x - start.x), height: abs(end.y - start.y))
    }
    mutating func move(by delta: NSSize) {
        start = NSPoint(x: start.x + delta.width, y: start.y + delta.height)
        end = NSPoint(x: end.x + delta.width, y: end.y + delta.height)
    }
    func hitTest(_ point: NSPoint) -> Bool {
        distanceFromPoint(point, toSegment: start, end) <= strokeHitTolerance
    }
    func draw(in ctx: CGContext, base: NSImage) {
        ctx.setStrokeColor(style.color.cgColor)
        ctx.setFillColor(style.color.cgColor)
        ctx.setLineWidth(style.strokeWidth)
        ctx.setLineCap(.round)

        let dx = end.x - start.x
        let dy = end.y - start.y
        let angle = atan2(dy, dx)
        let arrowLen: CGFloat = max(style.strokeWidth * 4, 14)
        let arrowAngle: CGFloat = .pi / 6

        let shaftEnd = NSPoint(
            x: end.x - cos(angle) * arrowLen * 0.6,
            y: end.y - sin(angle) * arrowLen * 0.6
        )
        ctx.move(to: start)
        ctx.addLine(to: shaftEnd)
        ctx.strokePath()

        let p1 = NSPoint(
            x: end.x - cos(angle - arrowAngle) * arrowLen,
            y: end.y - sin(angle - arrowAngle) * arrowLen
        )
        let p2 = NSPoint(
            x: end.x - cos(angle + arrowAngle) * arrowLen,
            y: end.y - sin(angle + arrowAngle) * arrowLen
        )
        ctx.move(to: end)
        ctx.addLine(to: p1)
        ctx.addLine(to: p2)
        ctx.closePath()
        ctx.fillPath()
    }
}

struct HighlightAnnotation: Annotation, BoundedShapeAnnotation, Codable {
    let id: UUID
    var start: NSPoint
    var end: NSPoint
    var style: AnnotationStyle

    init(id: UUID = UUID(), start: NSPoint, end: NSPoint, style: AnnotationStyle = AnnotationStyle(color: .systemRed)) {
        self.id = id; self.start = start; self.end = end; self.style = style
    }

    var bounds: NSRect {
        NSRect(x: min(start.x, end.x), y: min(start.y, end.y),
               width: abs(end.x - start.x), height: abs(end.y - start.y))
    }
    mutating func move(by delta: NSSize) {
        start = NSPoint(x: start.x + delta.width, y: start.y + delta.height)
        end = NSPoint(x: end.x + delta.width, y: end.y + delta.height)
    }
    func hitTest(_ point: NSPoint) -> Bool { bounds.insetBy(dx: -6, dy: -6).contains(point) }
    func draw(in ctx: CGContext, base: NSImage) {
        ctx.setFillColor(style.color.withAlphaComponent(0.4).cgColor)
        ctx.fill(bounds)
    }
}

// MARK: - Pen

struct PenAnnotation: Annotation, Codable {
    let id: UUID
    var points: [NSPoint]
    var style: AnnotationStyle

    init(id: UUID = UUID(), points: [NSPoint] = [], style: AnnotationStyle = AnnotationStyle(color: .systemRed)) {
        self.id = id; self.points = points; self.style = style
    }

    var bounds: NSRect {
        guard let first = points.first else { return .zero }
        var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y
        for p in points {
            minX = min(minX, p.x); minY = min(minY, p.y)
            maxX = max(maxX, p.x); maxY = max(maxY, p.y)
        }
        return NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    mutating func move(by delta: NSSize) {
        points = points.map { NSPoint(x: $0.x + delta.width, y: $0.y + delta.height) }
    }

    func hitTest(_ point: NSPoint) -> Bool {
        guard let first = points.first else { return false }
        if points.count == 1 {
            return hypot(point.x - first.x, point.y - first.y) <= strokeHitTolerance
        }
        for i in 0..<(points.count - 1) {
            if distanceFromPoint(point, toSegment: points[i], points[i + 1]) <= strokeHitTolerance {
                return true
            }
        }
        return false
    }

    func draw(in ctx: CGContext, base: NSImage) {
        guard points.count > 1 else { return }
        ctx.setStrokeColor(style.color.cgColor)
        ctx.setLineWidth(style.strokeWidth)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.move(to: points[0])
        for p in points.dropFirst() { ctx.addLine(to: p) }
        ctx.strokePath()
    }
}

// MARK: - Text

struct TextAnnotation: Annotation, Codable {
    let id: UUID
    var origin: NSPoint
    var text: String
    var style: AnnotationStyle

    init(id: UUID = UUID(), origin: NSPoint, text: String = L10n.text(.text), style: AnnotationStyle = AnnotationStyle(color: .systemRed)) {
        self.id = id; self.origin = origin; self.text = text; self.style = style
    }

    var bounds: NSRect {
        let attrs = attributes()
        let size = (text as NSString).size(withAttributes: attrs)
        return NSRect(origin: origin, size: size)
    }

    mutating func move(by delta: NSSize) {
        origin = NSPoint(x: origin.x + delta.width, y: origin.y + delta.height)
    }

    func hitTest(_ point: NSPoint) -> Bool {
        bounds.insetBy(dx: -4, dy: -4).contains(point)
    }

    func draw(in ctx: CGContext, base: NSImage) {
        let str = NSAttributedString(string: text, attributes: attributes())
        str.draw(at: origin)
    }

    private func attributes() -> [NSAttributedString.Key: Any] {
        return [
            .font: NSFont.systemFont(ofSize: style.fontSize, weight: .semibold),
            .foregroundColor: style.color
        ]
    }
}

// MARK: - Number

struct NumberAnnotation: Annotation, Codable {
    let id: UUID
    var center: NSPoint
    var number: Int
    var radius: CGFloat = 14
    var style: AnnotationStyle

    init(id: UUID = UUID(), center: NSPoint, number: Int, style: AnnotationStyle = AnnotationStyle(color: .systemRed)) {
        self.id = id; self.center = center; self.number = number; self.style = style
    }

    var bounds: NSRect {
        NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }

    mutating func move(by delta: NSSize) {
        center = NSPoint(x: center.x + delta.width, y: center.y + delta.height)
    }

    func hitTest(_ point: NSPoint) -> Bool {
        let dx = point.x - center.x
        let dy = point.y - center.y
        return dx * dx + dy * dy <= (radius + 4) * (radius + 4)
    }

    func draw(in ctx: CGContext, base: NSImage) {
        ctx.setFillColor(style.color.cgColor)
        ctx.fillEllipse(in: bounds)
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(2)
        ctx.strokeEllipse(in: bounds)

        let str = NSAttributedString(string: "\(number)", attributes: [
            .font: NSFont.boldSystemFont(ofSize: radius * 1.1),
            .foregroundColor: NSColor.white
        ])
        let size = str.size()
        str.draw(at: NSPoint(x: center.x - size.width / 2, y: center.y - size.height / 2))
    }
}

// MARK: - Blur / Pixelate

/// Shared CoreImage region-effect drawing for blur/pixelate. Kept as a free
/// helper so the concrete structs stay Codable (no stored closures) while
/// avoiding draw-code duplication.
private enum RegionEffectDrawing {
    static func draw(
        in ctx: CGContext,
        base: NSImage,
        rect: NSRect,
        apply: (CIImage) -> CIImage?
    ) {
        guard let cg = base.cgImageRef else { return }
        guard rect.width > 0, rect.height > 0 else { return }

        let scaleX = CGFloat(cg.width) / base.size.width
        let scaleY = CGFloat(cg.height) / base.size.height
        let source = CGRect(
            x: rect.origin.x * scaleX,
            y: (base.size.height - rect.origin.y - rect.height) * scaleY,
            width: rect.width * scaleX,
            height: rect.height * scaleY
        )
        guard let crop = cg.cropping(to: source) else { return }
        let ci = CIImage(cgImage: crop)
        guard let processed = apply(ci) else { return }
        let context = CIContext()
        guard let out = context.createCGImage(processed, from: processed.extent) else { return }

        ctx.saveGState()
        ctx.draw(out, in: rect)
        ctx.restoreGState()
    }
}

struct BlurAnnotation: Annotation, BoundedShapeAnnotation, Codable {
    let id: UUID
    var start: NSPoint
    var end: NSPoint
    var style: AnnotationStyle

    init(id: UUID = UUID(), start: NSPoint, end: NSPoint, style: AnnotationStyle = AnnotationStyle(color: .systemRed)) {
        self.id = id; self.start = start; self.end = end; self.style = style
    }

    var bounds: NSRect {
        NSRect(x: min(start.x, end.x), y: min(start.y, end.y),
               width: abs(end.x - start.x), height: abs(end.y - start.y))
    }
    mutating func move(by delta: NSSize) {
        start = NSPoint(x: start.x + delta.width, y: start.y + delta.height)
        end = NSPoint(x: end.x + delta.width, y: end.y + delta.height)
    }
    func hitTest(_ point: NSPoint) -> Bool { bounds.insetBy(dx: -6, dy: -6).contains(point) }
    func draw(in ctx: CGContext, base: NSImage) {
        RegionEffectDrawing.draw(in: ctx, base: base, rect: bounds) { ci in
            let f = CIFilter.gaussianBlur()
            f.inputImage = ci.clampedToExtent()
            f.radius = 15
            return f.outputImage?.cropped(to: ci.extent)
        }
    }
}

struct PixelateAnnotation: Annotation, BoundedShapeAnnotation, Codable {
    let id: UUID
    var start: NSPoint
    var end: NSPoint
    var style: AnnotationStyle

    init(id: UUID = UUID(), start: NSPoint, end: NSPoint, style: AnnotationStyle = AnnotationStyle(color: .systemRed)) {
        self.id = id; self.start = start; self.end = end; self.style = style
    }

    var bounds: NSRect {
        NSRect(x: min(start.x, end.x), y: min(start.y, end.y),
               width: abs(end.x - start.x), height: abs(end.y - start.y))
    }
    mutating func move(by delta: NSSize) {
        start = NSPoint(x: start.x + delta.width, y: start.y + delta.height)
        end = NSPoint(x: end.x + delta.width, y: end.y + delta.height)
    }
    func hitTest(_ point: NSPoint) -> Bool { bounds.insetBy(dx: -6, dy: -6).contains(point) }
    func draw(in ctx: CGContext, base: NSImage) {
        RegionEffectDrawing.draw(in: ctx, base: base, rect: bounds) { ci in
            let f = CIFilter.pixellate()
            f.inputImage = ci
            f.scale = 12
            f.center = CGPoint(x: ci.extent.midX, y: ci.extent.midY)
            return f.outputImage?.cropped(to: ci.extent)
        }
    }
}

// MARK: - Stroke hit-testing geometry

/// Tolerance for selecting line/arrow/pen strokes by proximity, in view
/// (logical point) coordinates. 6pt visual; no backingScaleFactor multiplier
/// because view coords are already in points (Retina density is factored out
/// by NSView.convert). Zoom scales both the view and click mapping, so this
/// stays 6 world-points at any zoom — standard behaviour (Preview/Figma).
private let strokeHitTolerance: CGFloat = 6

/// Perpendicular distance from `p` to segment `a`–`b` (clamped to endpoints).
private func distanceFromPoint(_ p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
    let dx = b.x - a.x
    let dy = b.y - a.y
    let len2 = dx * dx + dy * dy
    if len2 == 0 { return hypot(p.x - a.x, p.y - a.y) }
    var t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2
    t = Swift.max(0, Swift.min(1, t))
    let px = a.x + t * dx
    let py = a.y + t * dy
    return hypot(p.x - px, p.y - py)
}

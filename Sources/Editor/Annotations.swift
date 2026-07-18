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

    /// Single-key shortcut for switching to this tool (uppercased for display).
    /// Canonical source for both the toolbar tooltips and the editor's
    /// key-down tool switching — reverse this map, don't maintain a second one.
    /// `crop` is a modal, not a tool, so it has no single-key shortcut.
    var shortcutKey: String? {
        switch self {
        case .select: return "V"
        case .rectangle: return "R"
        case .ellipse: return "O"
        case .line: return "L"
        case .arrow: return "A"
        case .pen: return "P"
        case .text: return "T"
        case .number: return "N"
        case .blur: return "B"
        case .pixelate: return "X"
        case .highlight: return "Y"
        case .crop: return nil
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
    /// Handle positions to draw, paired with their semantic handle.
    var handlePoints: [(ResizeHandle, CGPoint)] { get }
    func hitTest(_ point: CGPoint) -> Bool
    mutating func move(by delta: NSSize)
    /// Returns a copy resized to the given bounds (view coordinates).
    func resized(to newBounds: CGRect) -> any Annotation
    func draw(in ctx: CGContext, base: NSImage)
}

/// Which resize handle is under a point. Bbox handles for shapes/pen/text/
/// number; endpoint handles for line/arrow.
enum ResizeHandle {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
    case startEndpoint, endEndpoint
}

extension Annotation {
    /// Default 8-handle bbox layout. Line/arrow override to expose endpoints.
    var handlePoints: [(ResizeHandle, CGPoint)] {
        let b = bounds
        return [
            (.topLeft, CGPoint(x: b.minX, y: b.maxY)),
            (.top, CGPoint(x: b.midX, y: b.maxY)),
            (.topRight, CGPoint(x: b.maxX, y: b.maxY)),
            (.right, CGPoint(x: b.maxX, y: b.midY)),
            (.bottomRight, CGPoint(x: b.maxX, y: b.minY)),
            (.bottom, CGPoint(x: b.midX, y: b.minY)),
            (.bottomLeft, CGPoint(x: b.minX, y: b.minY)),
            (.left, CGPoint(x: b.minX, y: b.midY)),
        ]
    }

    /// Returns the handle under `point` (within an 8pt radius), if any.
    func handle(at point: CGPoint) -> ResizeHandle? {
        let tol: CGFloat = 8
        for (handle, hp) in handlePoints {
            if hypot(point.x - hp.x, point.y - hp.y) <= tol {
                return handle
            }
        }
        return nil
    }
}

/// Annotations defined by two endpoints (drag to create). Unifies the
/// previously class-inherited ShapeAnnotation family with blur/pixelate,
/// which are now standalone structs.
protocol BoundedShapeAnnotation: Annotation {
    var start: NSPoint { get set }
    var end: NSPoint { get set }
}

extension BoundedShapeAnnotation {
    /// Default bbox resize: map start/end proportionally from old bounds to
    /// new bounds (preserves direction). Line/arrow use endpoint handles, so
    /// this is a fallback for them; shapes/highlight/blur/pixelate use it for
    /// their 8 bbox handles.
    func resized(to newBounds: CGRect) -> any Annotation {
        var copy = self
        let old = bounds
        copy.start = mapPoint(start, from: old, to: newBounds)
        copy.end = mapPoint(end, from: old, to: newBounds)
        return copy
    }
}

// MARK: - Shapes

struct RectAnnotation: Annotation, BoundedShapeAnnotation, Codable {
    var id: UUID
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
        if let fill = style.fillColor {
            ctx.setFillColor(fill.cgColor)
            ctx.fill(bounds)
        }
        ctx.setStrokeColor(style.color.cgColor)
        ctx.setLineWidth(style.strokeWidth)
        ctx.stroke(bounds)
    }
}

struct EllipseAnnotation: Annotation, BoundedShapeAnnotation, Codable {
    var id: UUID
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
        if let fill = style.fillColor {
            ctx.setFillColor(fill.cgColor)
            ctx.fillEllipse(in: bounds)
        }
        ctx.setStrokeColor(style.color.cgColor)
        ctx.setLineWidth(style.strokeWidth)
        ctx.strokeEllipse(in: bounds)
    }
}

struct LineAnnotation: Annotation, BoundedShapeAnnotation, Codable {
    var id: UUID
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
    var handlePoints: [(ResizeHandle, CGPoint)] {
        [(.startEndpoint, start), (.endEndpoint, end)]
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
    var id: UUID
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
    var handlePoints: [(ResizeHandle, CGPoint)] {
        [(.startEndpoint, start), (.endEndpoint, end)]
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
    var id: UUID
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
        // Fill: explicit fillColor if set, else the stroke colour at 40% (legacy highlight).
        let fill = style.fillColor ?? style.color.withAlphaComponent(0.4)
        ctx.setFillColor(fill.cgColor)
        ctx.fill(bounds)
    }
}

// MARK: - Pen

struct PenAnnotation: Annotation, Codable {
    var id: UUID
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

    func resized(to newBounds: CGRect) -> any Annotation {
        var copy = self
        let old = bounds
        copy.points = points.map { mapPoint($0, from: old, to: newBounds) }
        return copy
    }
}

// MARK: - Text

struct TextAnnotation: Annotation, Codable {
    var id: UUID
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

    func resized(to newBounds: CGRect) -> any Annotation {
        var copy = self
        let old = bounds
        copy.origin = newBounds.origin
        if old.height > 0 {
            // Resize = scale font size by height ratio (D14).
            copy.style.fontSize = min(200, max(8, style.fontSize * (newBounds.height / old.height)))
        }
        return copy
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
    var id: UUID
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

    func resized(to newBounds: CGRect) -> any Annotation {
        var copy = self
        copy.center = CGPoint(x: newBounds.midX, y: newBounds.midY)
        copy.radius = max(6, min(newBounds.width, newBounds.height) / 2)
        return copy
    }
}

// MARK: - Blur / Pixelate

/// Shared CoreImage region-effect drawing for blur/pixelate. Kept as a free
/// helper so the concrete structs stay Codable (no stored closures) while
/// avoiding draw-code duplication.
enum RegionEffectDrawing {

    /// One shared CIContext (construction is expensive; reusing it across
    /// draws is the single biggest CoreImage win).
    private static let ciContext = CIContext()

    /// Cache of processed CGImage blobs, keyed by a stable signature of
    /// (annotation id, source-rect-in-pixels, effect parameter). Invalidation
    /// is implicit: when baseImage, bounds, or the effect strength change, the
    /// signature changes and a fresh entry is computed; old entries linger
    /// until the annotation is removed. Bounded to avoid unbounded growth.
    private static var cache: [EffectCacheKey: CGImage] = [:]
    private static let cacheLimit = 32

    private struct EffectCacheKey: Hashable {
        let annotationId: UUID
        let sourceRect: CGRect
        let paramKey: Double
    }

    static func draw(
        in ctx: CGContext,
        base: NSImage,
        rect: NSRect,
        annotationId: UUID,
        paramValue: Double,
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
        let key = EffectCacheKey(annotationId: annotationId, sourceRect: source, paramKey: paramValue)

        let out: CGImage
        if let cached = cache[key] {
            out = cached
        } else {
            guard let crop = cg.cropping(to: source) else { return }
            let ci = CIImage(cgImage: crop)
            guard let processed = apply(ci) else { return }
            guard let rendered = ciContext.createCGImage(processed, from: processed.extent) else { return }
            if cache.count >= cacheLimit {
                cache.remove(at: cache.startIndex)
            }
            cache[key] = rendered
            out = rendered
        }

        ctx.saveGState()
        ctx.draw(out, in: rect)
        ctx.restoreGState()
    }

    /// Drop all cached effect renders (call when the base image changes, e.g.
    /// a new screenshot is loaded or a crop is committed).
    static func invalidateAll() {
        cache.removeAll(keepingCapacity: false)
    }
}

struct BlurAnnotation: Annotation, BoundedShapeAnnotation, Codable {
    var id: UUID
    var start: NSPoint
    var end: NSPoint
    var style: AnnotationStyle
    var radius: CGFloat = 15

    init(id: UUID = UUID(), start: NSPoint, end: NSPoint, style: AnnotationStyle = AnnotationStyle(color: .systemRed), radius: CGFloat = 15) {
        self.id = id; self.start = start; self.end = end; self.style = style; self.radius = radius
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
        let r = radius
        RegionEffectDrawing.draw(in: ctx, base: base, rect: bounds,
                                 annotationId: id, paramValue: Double(r)) { ci in
            let f = CIFilter.gaussianBlur()
            f.inputImage = ci.clampedToExtent()
            f.radius = Float(r)
            return f.outputImage?.cropped(to: ci.extent)
        }
    }
}

struct PixelateAnnotation: Annotation, BoundedShapeAnnotation, Codable {
    var id: UUID
    var start: NSPoint
    var end: NSPoint
    var style: AnnotationStyle
    var pixelSize: CGFloat = 12

    init(id: UUID = UUID(), start: NSPoint, end: NSPoint, style: AnnotationStyle = AnnotationStyle(color: .systemRed), pixelSize: CGFloat = 12) {
        self.id = id; self.start = start; self.end = end; self.style = style; self.pixelSize = pixelSize
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
        let s = pixelSize
        RegionEffectDrawing.draw(in: ctx, base: base, rect: bounds,
                                 annotationId: id, paramValue: Double(s)) { ci in
            let f = CIFilter.pixellate()
            f.inputImage = ci
            f.scale = Float(s)
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

/// Map a point from `oldBounds` to `newBounds` by relative position (affine
/// scale + translate). Used by bbox resize for shapes/pen and as a fallback.
private func mapPoint(_ p: CGPoint, from oldBounds: CGRect, to newBounds: CGRect) -> CGPoint {
    guard oldBounds.width > 0, oldBounds.height > 0 else { return newBounds.origin }
    let relX = (p.x - oldBounds.minX) / oldBounds.width
    let relY = (p.y - oldBounds.minY) / oldBounds.height
    return CGPoint(x: newBounds.minX + relX * newBounds.width,
                   y: newBounds.minY + relY * newBounds.height)
}

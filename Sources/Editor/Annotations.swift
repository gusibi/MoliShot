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

/// Base class for all annotations. Uses reference semantics so the editor can mutate
/// a selected annotation by identity.
class Annotation {
    var id = UUID()
    var color: NSColor = .systemRed
    var strokeWidth: CGFloat = 3

    func draw(in ctx: CGContext, base: NSImage) {}
    func hitTest(_ point: NSPoint) -> Bool { false }
    func move(by delta: NSSize) {}
    var boundingBox: NSRect { .zero }
}

// MARK: - Shapes

class ShapeAnnotation: Annotation {
    var start: NSPoint
    var end: NSPoint

    init(start: NSPoint, end: NSPoint) {
        self.start = start
        self.end = end
    }

    override var boundingBox: NSRect {
        NSRect(x: min(start.x, end.x), y: min(start.y, end.y),
               width: abs(end.x - start.x), height: abs(end.y - start.y))
    }

    override func move(by delta: NSSize) {
        start = NSPoint(x: start.x + delta.width, y: start.y + delta.height)
        end = NSPoint(x: end.x + delta.width, y: end.y + delta.height)
    }

    override func hitTest(_ point: NSPoint) -> Bool {
        boundingBox.insetBy(dx: -6, dy: -6).contains(point)
    }
}

final class RectAnnotation: ShapeAnnotation {
    override func draw(in ctx: CGContext, base: NSImage) {
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(strokeWidth)
        ctx.stroke(boundingBox)
    }
}

final class EllipseAnnotation: ShapeAnnotation {
    override func draw(in ctx: CGContext, base: NSImage) {
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(strokeWidth)
        ctx.strokeEllipse(in: boundingBox)
    }
}

final class LineAnnotation: ShapeAnnotation {
    override func draw(in ctx: CGContext, base: NSImage) {
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(strokeWidth)
        ctx.setLineCap(.round)
        ctx.move(to: start)
        ctx.addLine(to: end)
        ctx.strokePath()
    }
}

final class ArrowAnnotation: ShapeAnnotation {
    override func draw(in ctx: CGContext, base: NSImage) {
        ctx.setStrokeColor(color.cgColor)
        ctx.setFillColor(color.cgColor)
        ctx.setLineWidth(strokeWidth)
        ctx.setLineCap(.round)

        let dx = end.x - start.x
        let dy = end.y - start.y
        let angle = atan2(dy, dx)
        let arrowLen: CGFloat = max(strokeWidth * 4, 14)
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

final class HighlightAnnotation: ShapeAnnotation {
    override func draw(in ctx: CGContext, base: NSImage) {
        ctx.setFillColor(color.withAlphaComponent(0.4).cgColor)
        ctx.fill(boundingBox)
    }
}

// MARK: - Pen

final class PenAnnotation: Annotation {
    var points: [NSPoint]

    init(points: [NSPoint] = []) { self.points = points }

    override var boundingBox: NSRect {
        guard let first = points.first else { return .zero }
        var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y
        for p in points {
            minX = min(minX, p.x); minY = min(minY, p.y)
            maxX = max(maxX, p.x); maxY = max(maxY, p.y)
        }
        return NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    override func move(by delta: NSSize) {
        points = points.map { NSPoint(x: $0.x + delta.width, y: $0.y + delta.height) }
    }

    override func hitTest(_ point: NSPoint) -> Bool {
        boundingBox.insetBy(dx: -6, dy: -6).contains(point)
    }

    override func draw(in ctx: CGContext, base: NSImage) {
        guard points.count > 1 else { return }
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(strokeWidth)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.move(to: points[0])
        for p in points.dropFirst() { ctx.addLine(to: p) }
        ctx.strokePath()
    }
}

// MARK: - Text

final class TextAnnotation: Annotation {
    var origin: NSPoint
    var text: String
    var fontSize: CGFloat = 20

    init(origin: NSPoint, text: String = L10n.text(.text)) {
        self.origin = origin
        self.text = text
    }

    override var boundingBox: NSRect {
        let attrs = attributes()
        let size = (text as NSString).size(withAttributes: attrs)
        return NSRect(origin: origin, size: size)
    }

    override func move(by delta: NSSize) {
        origin = NSPoint(x: origin.x + delta.width, y: origin.y + delta.height)
    }

    override func hitTest(_ point: NSPoint) -> Bool {
        boundingBox.insetBy(dx: -4, dy: -4).contains(point)
    }

    override func draw(in ctx: CGContext, base: NSImage) {
        let attrs = attributes()
        let str = NSAttributedString(string: text, attributes: attrs)
        str.draw(at: origin)
    }

    private func attributes() -> [NSAttributedString.Key: Any] {
        return [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: color
        ]
    }
}

final class NumberAnnotation: Annotation {
    var center: NSPoint
    var number: Int
    var radius: CGFloat = 14

    init(center: NSPoint, number: Int) {
        self.center = center
        self.number = number
    }

    override var boundingBox: NSRect {
        NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }

    override func move(by delta: NSSize) {
        center = NSPoint(x: center.x + delta.width, y: center.y + delta.height)
    }

    override func hitTest(_ point: NSPoint) -> Bool {
        let dx = point.x - center.x
        let dy = point.y - center.y
        return dx * dx + dy * dy <= (radius + 4) * (radius + 4)
    }

    override func draw(in ctx: CGContext, base: NSImage) {
        ctx.setFillColor(color.cgColor)
        ctx.fillEllipse(in: boundingBox)
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(2)
        ctx.strokeEllipse(in: boundingBox)

        let str = NSAttributedString(string: "\(number)", attributes: [
            .font: NSFont.boldSystemFont(ofSize: radius * 1.1),
            .foregroundColor: NSColor.white
        ])
        let size = str.size()
        str.draw(at: NSPoint(x: center.x - size.width / 2, y: center.y - size.height / 2))
    }
}

// MARK: - Blur / Pixelate

class RegionEffectAnnotation: ShapeAnnotation {
    override func draw(in ctx: CGContext, base: NSImage) {
        guard let cg = base.cgImageRef else { return }
        let rect = boundingBox
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
        guard let processed = apply(filter: ci) else { return }
        let context = CIContext()
        guard let out = context.createCGImage(processed, from: processed.extent) else { return }

        ctx.saveGState()
        ctx.draw(out, in: rect)
        ctx.restoreGState()
    }

    func apply(filter ci: CIImage) -> CIImage? { ci }
}

final class BlurAnnotation: RegionEffectAnnotation {
    override func apply(filter ci: CIImage) -> CIImage? {
        let f = CIFilter.gaussianBlur()
        f.inputImage = ci.clampedToExtent()
        f.radius = 15
        return f.outputImage?.cropped(to: ci.extent)
    }
}

final class PixelateAnnotation: RegionEffectAnnotation {
    override func apply(filter ci: CIImage) -> CIImage? {
        let f = CIFilter.pixellate()
        f.inputImage = ci
        f.scale = 12
        f.center = CGPoint(x: ci.extent.midX, y: ci.extent.midY)
        return f.outputImage?.cropped(to: ci.extent)
    }
}

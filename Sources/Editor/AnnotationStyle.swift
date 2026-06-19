import AppKit

/// Shared visual style for annotations.
///
/// `color` is normalised to sRGB on construction so Codable round-trips and
/// equality are well-defined (NSColor is not Codable and its `isEqual` is
/// unreliable across colour spaces). Stroke width applies to shape outlines
/// and pen strokes; font size applies to text and number annotations.
struct AnnotationStyle: Codable, Equatable {
    var color: NSColor
    var strokeWidth: CGFloat
    var fontSize: CGFloat
    var opacity: CGFloat

    init(color: NSColor, strokeWidth: CGFloat = 3, fontSize: CGFloat = 20, opacity: CGFloat = 1) {
        self.color = color.usingColorSpace(.sRGB) ?? color
        self.strokeWidth = strokeWidth
        self.fontSize = fontSize
        self.opacity = max(0, min(1, opacity))
    }

    private enum CodingKeys: String, CodingKey {
        case red, green, blue, alpha, strokeWidth, fontSize, opacity
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let r = try c.decode(Double.self, forKey: .red)
        let g = try c.decode(Double.self, forKey: .green)
        let b = try c.decode(Double.self, forKey: .blue)
        let a = try c.decode(Double.self, forKey: .alpha)
        self.color = NSColor(srgbRed: CGFloat(r), green: CGFloat(g),
                             blue: CGFloat(b), alpha: CGFloat(a))
        self.strokeWidth = try c.decode(CGFloat.self, forKey: .strokeWidth)
        self.fontSize = try c.decode(CGFloat.self, forKey: .fontSize)
        self.opacity = try c.decodeIfPresent(CGFloat.self, forKey: .opacity) ?? 1
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        let srgb = color.usingColorSpace(.sRGB) ?? color
        try c.encode(Double(srgb.redComponent), forKey: .red)
        try c.encode(Double(srgb.greenComponent), forKey: .green)
        try c.encode(Double(srgb.blueComponent), forKey: .blue)
        try c.encode(Double(srgb.alphaComponent), forKey: .alpha)
        try c.encode(strokeWidth, forKey: .strokeWidth)
        try c.encode(fontSize, forKey: .fontSize)
        try c.encode(opacity, forKey: .opacity)
    }

    static func == (lhs: AnnotationStyle, rhs: AnnotationStyle) -> Bool {
        let l = lhs.color.usingColorSpace(.sRGB) ?? lhs.color
        let r = rhs.color.usingColorSpace(.sRGB) ?? rhs.color
        let eps: CGFloat = 1e-4
        return abs(l.redComponent - r.redComponent) < eps
            && abs(l.greenComponent - r.greenComponent) < eps
            && abs(l.blueComponent - r.blueComponent) < eps
            && abs(l.alphaComponent - r.alphaComponent) < eps
            && lhs.strokeWidth == rhs.strokeWidth
            && lhs.fontSize == rhs.fontSize
            && abs(lhs.opacity - rhs.opacity) < eps
    }
}

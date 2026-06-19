import AppKit

/// Pure rendering of the editor canvas to an `NSImage`.
///
/// Draws `baseImage` at its real pixel resolution (preserving the Retina fix
/// from `da56742`) and composites the annotations on top in the base image's
/// coordinate space. The output `NSImage` carries the true pixel `CGImage`
/// with a logical `size` matching `baseImage.size`, so downstream
/// `pngData()` / `cgImageRef` / pin flows all see real pixels.
///
/// `cropRect` (non-destructive clip) and `zoom` (display-only scaling) are
/// introduced when those features land; this prefactor is behaviour-identical
/// to the previous inline `EditorView.renderFinalImage()`.
enum AnnotationRenderer {

    /// Render `annotations` over `baseImage` into a new `NSImage`.
    /// - Parameters:
    ///   - annotations: Annotations to draw, in base-image coordinates.
    ///   - baseImage: The captured screenshot; its `cgImageRef` provides the
    ///     real pixel buffer and its `size` the logical coordinate space.
    /// - Returns: A new `NSImage` sized to `baseImage.size` with real-pixel
    ///   backing. Falls back to `baseImage` unchanged if no `CGImage` is
    ///   available.
    static func render(annotations: [Annotation], baseImage: NSImage) -> NSImage {
        guard let cg = baseImage.cgImageRef else { return baseImage }
        let size = baseImage.size

        let rep = NSBitmapImageRep(cgImage: cg)
        rep.size = size

        let previousContext = NSGraphicsContext.current
        guard let graphicsContext = NSGraphicsContext(bitmapImageRep: rep) else { return baseImage }
        graphicsContext.imageInterpolation = .high
        graphicsContext.shouldAntialias = true
        NSGraphicsContext.current = graphicsContext
        defer { NSGraphicsContext.current = previousContext }

        let ctx = graphicsContext.cgContext
        ctx.clear(NSRect(origin: .zero, size: size))
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

        // Rebuild with size = logical size, cg = rep's real pixels so
        // pngData()/cgImageRef see real pixels (no resample).
        if let repCG = rep.cgImage {
            return NSImage(cgImage: repCG, size: size)
        }
        let out = NSImage(size: size)
        out.addRepresentation(rep)
        return out
    }
}

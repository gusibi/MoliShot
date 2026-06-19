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
    ///   - cropRect: Optional non-destructive crop. When set, the output is
    ///     cropped to this rect (in base-image logical coords); annotations
    ///     outside are clipped, those inside keep their relative position.
    ///     When nil, the full image is rendered.
    ///   - baseImage: The captured screenshot; its `cgImageRef` provides the
    ///     real pixel buffer and its `size` the logical coordinate space.
    /// - Returns: A new `NSImage` with real-pixel backing. Falls back to
    ///   `baseImage` unchanged if no `CGImage` is available.
    static func render(annotations: [Annotation], cropRect: CGRect?, baseImage: NSImage) -> NSImage {
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
            ctx.saveGState()
            ctx.setAlpha(ann.style.opacity)
            ann.draw(in: ctx, base: baseImage)
            ctx.restoreGState()
        }
        graphicsContext.flushGraphics()

        guard let fullCG = rep.cgImage else {
            let out = NSImage(size: size)
            out.addRepresentation(rep)
            return out
        }

        // Non-destructive crop: slice the rendered CGImage to cropRect (in
        // pixels, with y flipped because CGImage origin is top-left while
        // base-image coords are bottom-left / y-up).
        if let crop = cropRect, crop.width > 0, crop.height > 0 {
            let scale = CGFloat(fullCG.width) / size.width
            let cropPixels = CGRect(
                x: crop.minX * scale,
                y: (size.height - crop.maxY) * scale,
                width: crop.width * scale,
                height: crop.height * scale
            )
            if let croppedCG = fullCG.cropping(to: cropPixels) {
                return NSImage(cgImage: croppedCG, size: crop.size)
            }
        }

        return NSImage(cgImage: fullCG, size: size)
    }
}

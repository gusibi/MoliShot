import AppKit
import Foundation

/// Clipboard (de)serialization for annotations.
///
/// Annotations are written to the pasteboard under a custom UTI
/// (`com.eztolab.molishot.annotations`) as a JSON array of
/// `{ "type": <typeName>, "payload": <annotation-codable> }`. Each entry also
/// carries a fresh UUID on decode so pasted annotations never collide with
/// originals. A PNG fallback is written alongside so other apps get an image.
///
/// The container is type-tagged because `Annotation` is a protocol with
/// heterogeneous conforming structs; Swift's Codable cannot auto-encode an
/// `[any Annotation]` without a discriminator.
enum AnnotationClipboard {

    /// UTI for MoliShot annotation payloads on the pasteboard.
    static let uti = "com.eztolab.molishot.annotations"

    private struct Entry: Codable {
        let type: String
        let payload: Data
    }

    /// Encode `annotations` to a JSON `Data` blob.
    static func encode(_ annotations: [Annotation]) -> Data? {
        let encoder = JSONEncoder()
        var entries: [Entry] = []
        for ann in annotations {
            guard let typeName = typeKey(for: ann),
                  let payload = try? encoder.encode(AnnotationBox(ann)) else { return nil }
            entries.append(Entry(type: typeName, payload: payload))
        }
        return try? encoder.encode(entries)
    }

    /// Decode a JSON blob back to annotations, each with a fresh UUID so
    /// pasted copies never collide with originals.
    static func decode(_ data: Data) -> [Annotation] {
        let decoder = JSONDecoder()
        guard let entries = try? decoder.decode([Entry].self, from: data) else { return [] }
        var result: [Annotation] = []
        for entry in entries {
            guard let ann = make(type: entry.type, from: entry.payload, decoder: decoder) else { continue }
            result.append(ann.withNewId())
        }
        return result
    }

    // MARK: - Type registry

    private static func typeKey(for ann: Annotation) -> String? {
        switch ann {
        case is RectAnnotation: return "rect"
        case is EllipseAnnotation: return "ellipse"
        case is LineAnnotation: return "line"
        case is ArrowAnnotation: return "arrow"
        case is HighlightAnnotation: return "highlight"
        case is BlurAnnotation: return "blur"
        case is PixelateAnnotation: return "pixelate"
        case is PenAnnotation: return "pen"
        case is TextAnnotation: return "text"
        case is NumberAnnotation: return "number"
        default: return nil
        }
    }

    private static func make(type: String, from data: Data, decoder: JSONDecoder) -> Annotation? {
        switch type {
        case "rect": return try? decoder.decode(RectAnnotation.self, from: data)
        case "ellipse": return try? decoder.decode(EllipseAnnotation.self, from: data)
        case "line": return try? decoder.decode(LineAnnotation.self, from: data)
        case "arrow": return try? decoder.decode(ArrowAnnotation.self, from: data)
        case "highlight": return try? decoder.decode(HighlightAnnotation.self, from: data)
        case "blur": return try? decoder.decode(BlurAnnotation.self, from: data)
        case "pixelate": return try? decoder.decode(PixelateAnnotation.self, from: data)
        case "pen": return try? decoder.decode(PenAnnotation.self, from: data)
        case "text": return try? decoder.decode(TextAnnotation.self, from: data)
        case "number": return try? decoder.decode(NumberAnnotation.self, from: data)
        default: return nil
        }
    }
}

/// Type-erased wrapper so any `Annotation` (a protocol existential) can be
/// encoded generically: concrete structs are Codable, but `any Annotation`
/// is not. We delegate to the concrete type's encode via a closure captured
/// at construction.
private struct AnnotationBox: Encodable {
    private let _encode: (Encoder) throws -> Void
    init(_ ann: Annotation) {
        _encode = { encoder in
            switch ann {
            case let v as RectAnnotation: try v.encode(to: encoder)
            case let v as EllipseAnnotation: try v.encode(to: encoder)
            case let v as LineAnnotation: try v.encode(to: encoder)
            case let v as ArrowAnnotation: try v.encode(to: encoder)
            case let v as HighlightAnnotation: try v.encode(to: encoder)
            case let v as BlurAnnotation: try v.encode(to: encoder)
            case let v as PixelateAnnotation: try v.encode(to: encoder)
            case let v as PenAnnotation: try v.encode(to: encoder)
            case let v as TextAnnotation: try v.encode(to: encoder)
            case let v as NumberAnnotation: try v.encode(to: encoder)
            default: throw EncodingError.invalidValue(ann, .init(codingPath: [], debugDescription: "unsupported"))
            }
        }
    }
    func encode(to encoder: Encoder) throws { try _encode(encoder) }
}

extension Annotation {
    /// Returns a copy with a fresh UUID (for paste/duplicate).
    func withNewId() -> Annotation {
        switch self {
        case var v as RectAnnotation: v.id = UUID(); return v
        case var v as EllipseAnnotation: v.id = UUID(); return v
        case var v as LineAnnotation: v.id = UUID(); return v
        case var v as ArrowAnnotation: v.id = UUID(); return v
        case var v as HighlightAnnotation: v.id = UUID(); return v
        case var v as BlurAnnotation: v.id = UUID(); return v
        case var v as PixelateAnnotation: v.id = UUID(); return v
        case var v as PenAnnotation: v.id = UUID(); return v
        case var v as TextAnnotation: v.id = UUID(); return v
        case var v as NumberAnnotation: v.id = UUID(); return v
        default: return self
        }
    }
}

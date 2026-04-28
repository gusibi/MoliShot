import AppKit
import Vision

enum OCRServiceError: LocalizedError {
    case unreadableImage
    case recognitionFailed(Error)

    var errorDescription: String? {
        switch self {
        case .unreadableImage:
            return L10n.text(.ocrImageUnavailable)
        case .recognitionFailed(let error):
            return error.localizedDescription
        }
    }
}

final class OCRService {
    static let shared = OCRService()
    private init() {}

    var recognitionLanguages: [String] = ["zh-Hans", "zh-Hant", "en-US", "ja-JP"]

    func recognize(in image: NSImage, completion: @escaping (Result<String, OCRServiceError>) -> Void) {
        guard let cg = image.cgImageRef else {
            completion(.failure(.unreadableImage))
            return
        }
        let request = VNRecognizeTextRequest { request, error in
            if let error = error {
                NSLog("OCR error: \(error)")
                completion(.failure(.recognitionFailed(error)))
                return
            }
            let results = (request.results as? [VNRecognizedTextObservation]) ?? []
            let lines = results.compactMap { $0.topCandidates(1).first?.string }
            completion(.success(lines.joined(separator: "\n")))
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = recognitionLanguages
        if #available(macOS 13.0, *) {
            request.automaticallyDetectsLanguage = true
        }

        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            do { try handler.perform([request]) }
            catch {
                NSLog("OCR perform failed: \(error)")
                completion(.failure(.recognitionFailed(error)))
            }
        }
    }
}

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

    /// Vision 的 accurate 识别器对输入长边有硬上限：实测长边 ≥2984px 时请求会
    /// 立刻返回 0 个结果（不抛错），≤2960px 正常。留出余量取 2800。
    /// 它内部本来就会把输入缩到固定尺寸，所以限制长边不会降低它的精度。
    private static let maxPixelDimension: CGFloat = 2800

    /// 串行队列：预热和识别互不抢 ANE，多开 OCR 窗口时也按顺序执行。
    private let queue = DispatchQueue(label: "com.molishot.ocr", qos: .userInitiated)
    private var didWarmUp = false

    /// 预热识别模型。模型在进程内常驻，磁盘上的编译缓存跨启动复用，所以每个
    /// 进程跑一次就够；这里放在启动后，避免用户按下热键时才等模型加载。
    func warmUp() {
        guard !didWarmUp else { return }
        didWarmUp = true
        scheduleWarmUp(probe: Self.makeProbeImage(), attempt: 1)
    }

    /// - Parameters:
    ///   - onPartial: 快速识别的结果（约 200ms），先给用户看；accurate 完成后
    ///     会通过 `completion` 再覆盖一次。回调在后台队列执行。
    ///   - completion: 最终结果，回调在后台队列执行。
    func recognize(
        in image: NSImage,
        onPartial: ((String) -> Void)? = nil,
        completion: @escaping (Result<String, OCRServiceError>) -> Void
    ) {
        guard let cg = image.cgImageRef else {
            completion(.failure(.unreadableImage))
            return
        }
        let languages = recognitionLanguages
        queue.async {
            let prepared = Self.preparedImage(cg)

            var quickText: String?
            if let onPartial {
                quickText = try? Self.recognizeText(in: prepared, level: .fast, languages: languages)
                if let text = quickText, !text.isEmpty {
                    onPartial(text)
                } else {
                    quickText = nil
                }
            }

            var accurateError: Error?
            do {
                let text = try Self.recognizeText(in: prepared, level: .accurate, languages: languages)
                if !text.isEmpty {
                    completion(.success(text))
                    return
                }
            } catch {
                accurateError = error
                NSLog("OCR accurate failed: \(error)")
            }

            // accurate 不可用（大图、ANE 异常导致 CRImageReaderError）时，
            // 保留已经拿到的快速结果，而不是把错误丢给用户。
            if let quickText {
                completion(.success(quickText))
                return
            }
            if let rescued = try? Self.recognizeText(in: prepared, level: .fast, languages: languages),
               !rescued.isEmpty {
                completion(.success(rescued))
                return
            }
            if let accurateError {
                completion(.failure(.recognitionFailed(accurateError)))
            } else {
                completion(.success(""))
            }
        }
    }

    // MARK: - Vision

    private func scheduleWarmUp(probe: CGImage?, attempt: Int) {
        guard let probe else { return }
        let languages = recognitionLanguages
        queue.async(qos: .utility) { [weak self] in
            do {
                _ = try Self.recognizeText(in: probe, level: .accurate, languages: languages)
            } catch {
                NSLog("OCR warm-up attempt \(attempt) failed: \(error)")
                guard let self, attempt < 2 else { return }
                self.queue.asyncAfter(deadline: .now() + 10) {
                    self.scheduleWarmUp(probe: probe, attempt: attempt + 1)
                }
            }
        }
    }

    private static func recognizeText(
        in image: CGImage,
        level: VNRequestTextRecognitionLevel,
        languages: [String]
    ) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = level
        request.usesLanguageCorrection = true
        request.recognitionLanguages = languages
        request.automaticallyDetectsLanguage = true

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        let observations = request.results ?? []
        return observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    /// 统一重绘成 8bit sRGB 不透明位图并限制长边：
    /// - 绕开 accurate 的尺寸上限（超限时静默返回空结果）；
    /// - 抹平截图可能带来的 16bit / 广色域 / alpha 数据，避免 CRImageReaderError。
    private static func preparedImage(_ image: CGImage) -> CGImage {
        let longest = max(image.width, image.height)
        let scale = longest > Int(maxPixelDimension) ? maxPixelDimension / CGFloat(longest) : 1
        let width = max(1, Int((CGFloat(image.width) * scale).rounded()))
        let height = max(1, Int((CGFloat(image.height) * scale).rounded()))
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            return image
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }

    /// 预热用的小图：必须带文字，否则识别器可能提前短路、不加载模型。
    private static func makeProbeImage() -> CGImage? {
        let width = 320
        let height = 96
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            return nil
        }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        defer { NSGraphicsContext.current = previous }
        let text = NSAttributedString(
            string: "Warm up 预热",
            attributes: [
                .font: NSFont.systemFont(ofSize: 28),
                .foregroundColor: NSColor.black
            ]
        )
        text.draw(at: NSPoint(x: 12, y: 30))
        return context.makeImage()
    }
}

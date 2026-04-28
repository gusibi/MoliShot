import AppKit

enum UploadError: LocalizedError {
    case encodingFailed
    case http(Int, String)
    case network(Error)
    case missingURL

    var errorDescription: String? {
        switch self {
        case .encodingFailed: return "Could not encode image"
        case .http(let code, let body): return "HTTP \(code): \(body)"
        case .network(let e): return e.localizedDescription
        case .missingURL: return "No URL in response"
        }
    }
}

/// Minimal 0x0.st anonymous file upload. Works without an API key.
/// Replace with your own image host as needed.
final class UploadService {
    static let shared = UploadService()
    private init() {}

    var endpoint = URL(string: "https://0x0.st")!

    func upload(image: NSImage, completion: @escaping (Result<URL, UploadError>) -> Void) {
        guard let data = image.pngData() else {
            completion(.failure(.encodingFailed)); return
        }

        let boundary = "----MoliShot\(UUID().uuidString)"
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"screenshot.png\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/png\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("MoliShot/0.1", forHTTPHeaderField: "User-Agent")
        request.httpBody = body

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(.network(error))); return
            }
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            guard let data = data, let text = String(data: data, encoding: .utf8) else {
                completion(.failure(.http(code, ""))); return
            }
            if !(200..<300).contains(code) {
                completion(.failure(.http(code, text))); return
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: trimmed) else {
                completion(.failure(.missingURL)); return
            }
            completion(.success(url))
        }.resume()
    }
}

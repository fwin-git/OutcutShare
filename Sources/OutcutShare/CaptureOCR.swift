import CoreGraphics
import Vision

/// Text recognition for captures (the card's "copy text" chip).
enum CaptureOCR {
    /// Orders Vision line observations into readable text: rows top to
    /// bottom, within a row left to right. Boxes are Vision-normalized
    /// (bottom-left origin); lines whose vertical centers differ by less
    /// than half a line height count as the same row.
    static func joined(_ lines: [(text: String, box: CGRect)]) -> String {
        guard !lines.isEmpty else { return "" }
        let sorted = lines.sorted { a, b in
            let rowTolerance = min(a.box.height, b.box.height) / 2
            if abs(a.box.midY - b.box.midY) < rowTolerance {
                return a.box.minX < b.box.minX
            }
            return a.box.midY > b.box.midY
        }
        var result = ""
        var previous: CGRect?
        for line in sorted {
            if let previous {
                let sameRow = abs(previous.midY - line.box.midY)
                    < min(previous.height, line.box.height) / 2
                result += sameRow ? " " : "\n"
            }
            result += line.text
            previous = line.box
        }
        return result
    }

    /// Recognizes text in the image (accurate, language auto-detection).
    /// Returns "" when nothing is found or recognition fails.
    static func recognizeText(in image: CGImage) async -> String {
        await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true
            let handler = VNImageRequestHandler(cgImage: image)
            guard (try? handler.perform([request])) != nil,
                  let observations = request.results else { return "" }
            let lines = observations.compactMap { observation in
                observation.topCandidates(1).first.map {
                    (text: $0.string, box: observation.boundingBox)
                }
            }
            return joined(lines)
        }.value
    }
}

/// Newest-first list of recent capture file paths for the Recent Captures
/// menu.
enum RecentCaptures {
    static let limit = 7

    static func updated(_ list: [String], adding path: String) -> [String] {
        var result = list.filter { $0 != path }
        result.insert(path, at: 0)
        return Array(result.prefix(limit))
    }

    static func removing(_ list: [String], path: String) -> [String] {
        list.filter { $0 != path }
    }
}

import Foundation

/// File naming for saved captures: `prefix_YYYY-MM-DD_HH-mm.ext`,
/// with a numeric suffix when that minute already has files.
enum CaptureNaming {
    static func fileName(prefix: String, date: Date, ext: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm"
        return "\(prefix)_\(formatter.string(from: date)).\(ext)"
    }

    static func uniqueFileName(prefix: String, date: Date, ext: String,
                               exists: (String) -> Bool) -> String {
        let base = fileName(prefix: prefix, date: date, ext: ext)
        guard exists(base) else { return base }
        let stem = (base as NSString).deletingPathExtension
        var counter = 2
        while exists("\(stem)_\(counter).\(ext)") {
            counter += 1
        }
        return "\(stem)_\(counter).\(ext)"
    }

    /// Resolves a non-colliding URL in the folder (checked on disk).
    static func uniqueURL(in folder: URL, prefix: String, date: Date,
                          ext: String) -> URL {
        folder.appendingPathComponent(uniqueFileName(prefix: prefix, date: date,
                                                     ext: ext) {
            FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path)
        })
    }
}

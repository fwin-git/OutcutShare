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

    /// `clip.mp4` → `clip_trim.mp4` (then `_trim_2`, …) next to the original.
    static func uniqueSibling(of url: URL, suffix: String,
                              exists: (URL) -> Bool) -> URL {
        let folder = url.deletingLastPathComponent()
        let stem = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var candidate = folder.appendingPathComponent("\(stem)\(suffix).\(ext)")
        var counter = 2
        while exists(candidate) {
            candidate = folder.appendingPathComponent("\(stem)\(suffix)_\(counter).\(ext)")
            counter += 1
        }
        return candidate
    }

    static func uniqueSiblingOnDisk(of url: URL, suffix: String) -> URL {
        uniqueSibling(of: url, suffix: suffix) {
            FileManager.default.fileExists(atPath: $0.path)
        }
    }
}

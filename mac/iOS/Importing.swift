// Bringing files into GranthFlow on iPhone and iPad: each is copied into the app's own folder (shown
// in Files as "GranthFlow") and put on the shelf. Used by +, "Open in GranthFlow" and Shortcuts.
import Foundation
import Observation

enum Importing {
    /// Copies files from elsewhere into GranthFlow's folder and shelves them. A file already there
    /// with the same name and bytes is shelved again rather than copied twice.
    @MainActor @discardableResult
    static func add(_ urls: [URL], to library: Library) -> [URL] {
        let folder = URL.documentsDirectory
        var found: [(url: URL, kind: String)] = []
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            var target = url
            if !url.standardizedFileURL.path.hasPrefix(folder.path) {
                target = Self.place(for: url.lastPathComponent, in: folder, matching: url)
                if !FileManager.default.fileExists(atPath: target.path) {
                    do { try FileManager.default.copyItem(at: url, to: target) } catch { continue }
                }
            }
            guard let data = try? Data(contentsOf: target, options: .mappedIfSafe) else { continue }
            found.append((target, Engine.detectKind(of: data, name: target.lastPathComponent)))
        }
        library.add(found)
        return found.map(\.url)
    }

    /// "Book.epub", or "Book 2.epub" and on when a different file already has the name.
    private static func place(for name: String, in folder: URL, matching source: URL) -> URL {
        let stem = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension
        var candidate = folder.appendingPathComponent(name)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path),
              !FileManager.default.contentsEqual(atPath: candidate.path, andPath: source.path) {
            candidate = folder.appendingPathComponent(ext.isEmpty ? "\(stem) \(n)" : "\(stem) \(n).\(ext)")
            n += 1
        }
        return candidate
    }
}

/// A file Shortcuts or Siri asked to open; the shelf opens it and clears the request.
@MainActor @Observable
final class OpenRequest {
    static let shared = OpenRequest()
    var path: String?
}

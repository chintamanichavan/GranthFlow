// Putting files on the shelf without opening them: dropped onto the library, or found in a
// watched folder. Folders are walked for files; hidden files, packages and their insides are skipped.
import Foundation

enum Adding {
    /// A folder dropped by mistake on a whole disk should not fill the library; this is plenty for a real one.
    static let mostFromOneDrop = 500

    /// The files among `urls`, with folders walked for the files inside them.
    static func files(in urls: [URL], limit: Int = mostFromOneDrop) -> [URL] {
        var out: [URL] = []
        let fm = FileManager.default
        for url in urls where out.count < limit {
            var isFolder: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isFolder) else { continue }
            if !isFolder.boolValue || isPackage(url) {
                if !isFolder.boolValue { out.append(url.standardizedFileURL) }
                continue
            }
            let walker = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey],
                                       options: [.skipsHiddenFiles, .skipsPackageDescendants])
            while let item = walker?.nextObject() as? URL, out.count < limit {
                if (try? item.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true { out.append(item.standardizedFileURL) }
            }
        }
        return out
    }

    /// The kind of a file from its first 64 KB: enough for magic bytes, an EPUB's mimetype entry
    /// and a look at whether it is text, without reading a large file whole.
    static func kind(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let head = (try? handle.read(upToCount: 1 << 16)) ?? Data()
        return Engine.detectKind(of: head, name: url.lastPathComponent)
    }

    /// The files among `urls` with their kinds. Reads from disk, so it runs off the main thread.
    static func scan(_ urls: [URL]) -> [(url: URL, kind: String)] {
        files(in: urls).compactMap { url in kind(of: url).map { (url, $0) } }
    }

    private static func isPackage(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isPackageKey]).isPackage) == true
    }
}

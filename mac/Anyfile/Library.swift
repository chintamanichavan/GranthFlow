// What the library remembers: each file opened, when, and where reading stopped. Kept as
// pretty-printed JSON in Application Support so it can be read, diffed or deleted by hand.
import Foundation
import Observation

struct LibraryEntry: Codable, Equatable, Identifiable {
    var path: String
    var kind: String
    var opened: Date
    /// Where reading stopped: a chapter number for EPUB, a page index for PDF.
    var position: Int?
    var total: Int?
    /// Where in that chapter: the first character on screen, so reading resumes at the same
    /// sentence even after the text size or window width changes. Nil means the chapter's start.
    var anchor: Int?
    /// Words from there to the end of the chapter, for "6 min left in chapter".
    var wordsLeft: Int?
    /// How this book is set for reading; nil until the reader changes it.
    var settings: ReadingSettings?

    var id: String { path }
    var url: URL { URL(fileURLWithPath: path) }
    var name: String { url.lastPathComponent }

    /// "Chapter 4 of 135", "Page 3 of 12", "Finished", or nil when there is nothing to say.
    var progressText: String? {
        guard let position, let total, total > 0 else { return nil }
        switch kind {
        case "epub": return position >= total ? "Finished" : "Chapter \(position) of \(total)"
        case "pdf": return position + 1 >= total ? "Finished" : "Page \(position + 1) of \(total)"
        default: return nil
        }
    }

    /// 0...1 through the file, for the progress bar.
    var progress: Double? {
        guard let position, let total, total > 0 else { return nil }
        return kind == "pdf" ? Double(position + 1) / Double(total) : Double(position) / Double(total)
    }

    var isUnfinished: Bool { (progress ?? 1) < 1 }
}

@MainActor @Observable
final class Library {
    /// `--library <path>` points the app at another file, so UI tests do not write into the real library.
    static let shared: Library = {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--library"), i + 1 < args.count { return Library(file: URL(fileURLWithPath: args[i + 1])) }
        return Library(file: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Anyfile/library.json"))
    }()

    private(set) var entries: [LibraryEntry]
    private let file: URL
    /// Kept short so the file stays readable; the oldest are forgotten first.
    static let limit = 200

    init(file: URL) {
        self.file = file
        let data = try? Data(contentsOf: file)
        entries = data.flatMap { try? Self.decoder.decode([LibraryEntry].self, from: $0) } ?? []
    }

    /// Most recent first, leaving out files that have been moved or deleted.
    var recent: [LibraryEntry] {
        entries.filter { FileManager.default.fileExists(atPath: $0.path) }.sorted { $0.opened > $1.opened }
    }

    /// Books and documents part-way through, most recent first.
    var continueReading: [LibraryEntry] { recent.filter { $0.progress != nil && $0.isUnfinished } }

    func entry(for url: URL) -> LibraryEntry? { entries.first { $0.path == url.standardizedFileURL.path } }

    func recordOpened(_ url: URL, kind: String, at date: Date = Date()) {
        let path = url.standardizedFileURL.path
        if let i = entries.firstIndex(where: { $0.path == path }) {
            entries[i].opened = date
            entries[i].kind = kind
        } else {
            entries.append(LibraryEntry(path: path, kind: kind, opened: date))
            if entries.count > Self.limit {
                entries = Array(entries.sorted { $0.opened > $1.opened }.prefix(Self.limit))
            }
        }
        save()
    }

    func recordPosition(_ url: URL, position: Int, total: Int) {
        guard let i = entries.firstIndex(where: { $0.path == url.standardizedFileURL.path }),
              entries[i].position != position || entries[i].total != total else { return }
        if entries[i].position != position {                                // a new chapter starts at its top
            entries[i].anchor = nil
            entries[i].wordsLeft = nil
        }
        entries[i].position = position
        entries[i].total = total
        save()
    }

    /// Records the first character on screen in the chapter being read, and the words after it.
    func recordAnchor(_ url: URL, anchor: Int, wordsLeft: Int? = nil) {
        guard let i = entries.firstIndex(where: { $0.path == url.standardizedFileURL.path }),
              entries[i].anchor != anchor || entries[i].wordsLeft != wordsLeft else { return }
        entries[i].anchor = anchor
        entries[i].wordsLeft = wordsLeft
        save()
    }

    func recordSettings(_ url: URL, _ settings: ReadingSettings) {
        guard let i = entries.firstIndex(where: { $0.path == url.standardizedFileURL.path }), entries[i].settings != settings else { return }
        entries[i].settings = settings
        save()
    }

    func forget(_ entry: LibraryEntry) {
        entries.removeAll { $0.path == entry.path }
        save()
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Self.encoder.encode(entries.sorted { $0.path < $1.path }).write(to: file, options: .atomic)
        } catch {
            NSLog("library not saved: %@", error.localizedDescription)
        }
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

/// What to call a kind of file on the shelf. Programs are told apart from other data by their magic bytes.
enum KindLabel {
    static func label(kind: String, data: Data? = nil) -> String {
        switch kind {
        case "epub": return "Book"
        case "pdf": return "Document"
        case "markdown": return "Note"
        case "text": return "Text"
        default: return data.map(isProgram) == true ? "Program" : "Data"
        }
    }

    /// Mach-O (32/64-bit, either byte order, and universal), ELF, or a Windows PE file.
    static func isProgram(_ data: Data) -> Bool {
        let head = [UInt8](data.prefix(4))
        guard head.count == 4 else { return head.starts(with: [0x4D, 0x5A]) }
        let magics: [[UInt8]] = [[0xCF, 0xFA, 0xED, 0xFE], [0xCE, 0xFA, 0xED, 0xFE], [0xFE, 0xED, 0xFA, 0xCF],
                                 [0xFE, 0xED, 0xFA, 0xCE], [0xCA, 0xFE, 0xBA, 0xBE], [0x7F, 0x45, 0x4C, 0x46]]
        return magics.contains(head) || head.starts(with: [0x4D, 0x5A])
    }
}

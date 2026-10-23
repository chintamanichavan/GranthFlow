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
    /// On the shelf, from a drop or a watched folder, but not opened yet.
    var unopened: Bool?
    /// The reader's own shelves this file is on.
    var shelves: [String]?

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

    private(set) var entries: [LibraryEntry] { didSet { shelf = nil } }
    /// Files found moved or deleted at the last check.
    private(set) var missing: Set<String> = [] { didSet { shelf = nil } }
    /// `recent`, kept until the library changes: the window reads it many times a redraw.
    @ObservationIgnored private var shelf: [LibraryEntry]?
    private let file: URL
    /// Room for a real library, dropped or watched folders included; the oldest are forgotten first.
    nonisolated static let defaultLimit = 5000
    let limit: Int

    init(file: URL, limit: Int = Library.defaultLimit) {
        self.file = file
        self.limit = limit
        let data = try? Data(contentsOf: file)
        entries = data.flatMap { try? Self.decoder.decode([LibraryEntry].self, from: $0) } ?? []
        checkFiles()
    }

    /// Notes which files have been moved or deleted. Run at launch and when the library comes
    /// forward, not on every redraw: with 5000 files that was 50 000 disk checks a redraw.
    func checkFiles() {
        let gone = Set(entries.map(\.path).filter { !FileManager.default.fileExists(atPath: $0) })
        if gone != missing { missing = gone }
    }

    /// Most recent first, leaving out files that have been moved or deleted.
    var recent: [LibraryEntry] {
        if let shelf { return shelf }
        let sorted = entries.filter { !missing.contains($0.path) }.sorted { $0.opened > $1.opened }
        shelf = sorted
        return sorted
    }

    /// Books and documents part-way through, most recent first.
    var continueReading: [LibraryEntry] { recent.filter { $0.progress != nil && $0.isUnfinished } }

    func entry(for url: URL) -> LibraryEntry? { entries.first { $0.path == url.standardizedFileURL.path } }

    func recordOpened(_ url: URL, kind: String, at date: Date = Date()) {
        shelve(url, kind: kind, at: date)
        if let i = entries.firstIndex(where: { $0.path == url.standardizedFileURL.path }) { entries[i].unopened = nil }
        save()
    }

    /// Files found in a watched folder: only ones not on the shelf yet are added, dated by the file
    /// itself so an old folder does not push recent reading down. Ones already there are left alone.
    @discardableResult
    func addFromFolder(_ found: [(url: URL, kind: String)]) -> Int {
        let known = Set(entries.map(\.path))
        let fresh = found.filter { !known.contains($0.url.standardizedFileURL.path) }
        guard !fresh.isEmpty else { return 0 }
        for (url, kind) in fresh {
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
            entries.append(LibraryEntry(path: url.standardizedFileURL.path, kind: kind, opened: date, unopened: true))
        }
        if entries.count > limit { entries = Array(entries.sorted { $0.opened > $1.opened }.prefix(limit)) }
        save()
        return fresh.count
    }

    /// Puts scanned files on the shelf as if just opened; ones already there move to the front.
    /// Saves once at the end, not once per file. Returns how many were new.
    @discardableResult
    func add(_ found: [(url: URL, kind: String)], at date: Date = Date()) -> Int {
        // Files are found by path in a table, and the shelf trimmed once: 500 files took 0.47 s
        // on the main thread when each searched the whole shelf and each trimmed it.
        var index = Dictionary(entries.indices.map { (entries[$0].path, $0) }, uniquingKeysWith: { a, _ in a })
        var added = 0
        for (url, kind) in found {
            let path = url.standardizedFileURL.path
            if let i = index[path] {
                entries[i].opened = date
                entries[i].kind = kind
            } else {
                index[path] = entries.count
                entries.append(LibraryEntry(path: path, kind: kind, opened: date, unopened: true))
                added += 1
            }
        }
        if entries.count > limit { entries = Array(entries.sorted { $0.opened > $1.opened }.prefix(limit)) }
        if !found.isEmpty { save() }
        return added
    }

    private func shelve(_ url: URL, kind: String, at date: Date) {
        let path = url.standardizedFileURL.path
        if let i = entries.firstIndex(where: { $0.path == path }) {
            entries[i].opened = date
            entries[i].kind = kind
        } else {
            entries.append(LibraryEntry(path: path, kind: kind, opened: date))
            if entries.count > limit {
                entries = Array(entries.sorted { $0.opened > $1.opened }.prefix(limit))
            }
        }
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

    /// Changes one file's entry and saves, if it changed.
    func edit(_ url: URL, _ change: (inout LibraryEntry) -> Void) {
        guard let i = entries.firstIndex(where: { $0.path == url.standardizedFileURL.path }) else { return }
        var e = entries[i]
        change(&e)
        guard e != entries[i] else { return }
        entries[i] = e
        save()
    }

    /// Changes every entry and saves once, if any changed.
    func editAll(_ change: (inout LibraryEntry) -> Void) {
        var changed = entries
        for i in changed.indices { change(&changed[i]) }
        guard changed != entries else { return }
        entries = changed
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

// Marks: passages you highlighted, kept apart from the files so marking never changes a file.
// Stored as pretty-printed JSON beside the library.
import Foundation
import Observation

struct Mark: Codable, Equatable, Identifiable {
    var id = UUID()
    var path: String
    var kind: String
    var quote: String
    /// Where it is, the same way Find and Contents say it: a line, a chapter number or a page index.
    var target: Int
    var place: String
    var created = Date()

    var name: String { (path as NSString).lastPathComponent }
}

/// What is selected in a pane right now, ready to become a mark.
struct Selection: Equatable {
    var quote: String
    var target: Int
    var place: String
}

@MainActor @Observable
final class MarkStore {
    /// `--marks <path>` points the app at another file, for UI tests.
    static let shared: MarkStore = {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--marks"), i + 1 < args.count { return MarkStore(file: URL(fileURLWithPath: args[i + 1])) }
        return MarkStore(file: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Anyfile/marks.json"))
    }()

    private(set) var marks: [Mark]
    /// A mark chosen in the library, waiting for its file's window to open and go there.
    var pending: Mark?
    private let file: URL
    /// A mark is a passage, not a chapter; longer selections are cut here.
    static let longest = 1000

    init(file: URL) {
        self.file = file
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        marks = (try? Data(contentsOf: file)).flatMap { try? d.decode([Mark].self, from: $0) } ?? []
    }

    /// Newest first.
    var all: [Mark] { marks.sorted { $0.created > $1.created } }

    func marks(for url: URL) -> [Mark] {
        let path = url.standardizedFileURL.path
        return marks.filter { $0.path == path }.sorted { ($0.target, $0.created) < ($1.target, $1.created) }
    }

    /// Adds a mark for the selection; a selection already marked at the same place is not added twice.
    @discardableResult
    func add(_ selection: Selection, in url: URL, kind: String, at date: Date = Date()) -> Mark? {
        let quote = Self.clean(selection.quote)
        guard !quote.isEmpty else { return nil }
        let path = url.standardizedFileURL.path
        if let same = marks.first(where: { $0.path == path && $0.target == selection.target && $0.quote == quote }) { return same }
        let mark = Mark(path: path, kind: kind, quote: quote, target: selection.target, place: selection.place, created: date)
        marks.append(mark)
        save()
        return mark
    }

    func remove(_ mark: Mark) {
        marks.removeAll { $0.id == mark.id }
        save()
    }

    /// Trimmed, and cut at `longest` characters on a word boundary.
    static func clean(_ quote: String) -> String {
        let q = quote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count > longest else { return q }
        let cut = q.prefix(longest)
        return String(cut[..<(cut.lastIndex(of: " ") ?? cut.endIndex)]) + "…"
    }

    private func save() {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try e.encode(marks.sorted { $0.created < $1.created }).write(to: file, options: .atomic)
        } catch {
            NSLog("marks not saved: %@", error.localizedDescription)
        }
    }
}

// Marks: passages you highlighted, kept apart from the files so marking never changes a file.
// Stored as pretty-printed JSON beside the library.
import AppKit
import Observation

/// The colour a mark is painted in. A reader might use yellow for ideas and pink for quotes.
enum MarkColour: String, Codable, CaseIterable {
    case yellow, pink, green, blue

    var paint: NSColor {
        switch self {
        case .yellow: Theme.mark
        case .pink: NSColor(hex: "#FF9EC4")!
        case .green: NSColor(hex: "#A6E3A1")!
        case .blue: NSColor(hex: "#9CC8FF")!
        }
    }

    var title: String { rawValue.capitalized }
}

/// A passage to paint, and in which colour.
struct Paint: Equatable {
    let quote: String
    let colour: MarkColour
}

struct Mark: Codable, Equatable, Identifiable {
    var id = UUID()
    var path: String
    var kind: String
    var quote: String
    /// Where it is, the same way Find and Contents say it: a line, a chapter number or a page index.
    var target: Int
    var place: String
    var created = Date()
    /// The reader's own words about the passage.
    var note = ""
    var colour = MarkColour.yellow

    var paint: Paint { Paint(quote: quote, colour: colour) }

    var name: String { (path as NSString).lastPathComponent }

    init(id: UUID = UUID(), path: String, kind: String, quote: String, target: Int, place: String, created: Date = Date(),
         note: String = "", colour: MarkColour = .yellow) {
        self.id = id
        self.path = path
        self.kind = kind
        self.quote = quote
        self.target = target
        self.place = place
        self.created = created
        self.note = note
        self.colour = colour
    }

    // Written by hand so marks saved before a field existed still load, with that field's default.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        path = try c.decode(String.self, forKey: .path)
        kind = try c.decode(String.self, forKey: .kind)
        quote = try c.decode(String.self, forKey: .quote)
        target = try c.decode(Int.self, forKey: .target)
        place = try c.decode(String.self, forKey: .place)
        created = try c.decode(Date.self, forKey: .created)
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        colour = try c.decodeIfPresent(MarkColour.self, forKey: .colour) ?? .yellow
    }
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
        let store = MarkStore(file: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Anyfile/marks.json"))
        // Only the reader's own marks go to Spotlight, and never from a test run.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            store.onSave = { SpotlightMarks.reindex($0) }
            SpotlightMarks.reindex(store.marks)
        }
        return store
    }()

    private(set) var marks: [Mark]
    private let file: URL
    /// Called after each save; the reader's own store keeps Spotlight up to date with it.
    @ObservationIgnored var onSave: (([Mark]) -> Void)?
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

    /// Sets a mark's note, trimmed; an empty note removes it.
    func setNote(_ note: String, for mark: Mark) {
        guard let i = marks.firstIndex(where: { $0.id == mark.id }) else { return }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard marks[i].note != trimmed else { return }
        marks[i].note = trimmed
        save()
    }

    func setColour(_ colour: MarkColour, for mark: Mark) {
        guard let i = marks.firstIndex(where: { $0.id == mark.id }), marks[i].colour != colour else { return }
        marks[i].colour = colour
        save()
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
            onSave?(marks)
        } catch {
            NSLog("marks not saved: %@", error.localizedDescription)
        }
    }
}

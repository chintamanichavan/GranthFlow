// What the library shows for each file: its cover, a title, and one line about it.
// Faces are made off the main thread from the file on disk.
import Foundation

struct ShelfFace {
    let art: CoverArt
    let title: String
    let subtitle: String
    let author: String
    /// The book's cloth, so the hero can take the colour of the cover it shows.
    let cloth: String?
}

enum LibrarySection: String, CaseIterable, Identifiable {
    case library, continueReading, finished, marks, books, documents, notes, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .library: "Library"
        case .continueReading: "Continue reading"
        case .finished: "Finished"
        case .marks: "Marks"
        case .books: "Books"
        case .documents: "Documents"
        case .notes: "Notes and text"
        case .other: "Programs and data"
        }
    }

    var symbol: String {
        switch self {
        case .library: "books.vertical"
        case .continueReading: "bookmark"
        case .finished: "checkmark.circle"
        case .marks: "highlighter"
        case .books: "book.closed"
        case .documents: "doc.richtext"
        case .notes: "note.text"
        case .other: "cpu"
        }
    }

    @MainActor func entries(in library: Library) -> [LibraryEntry] {
        switch self {
        case .library: library.recent
        case .continueReading: library.continueReading
        case .finished: library.finished
        case .marks: []                                  // marks are listed by the view, not as files
        case .books: library.recent.filter { $0.kind == "epub" }
        case .documents: library.recent.filter { $0.kind == "pdf" }
        case .notes: library.recent.filter { $0.kind == "markdown" || $0.kind == "text" }
        case .other: library.recent.filter { !["epub", "pdf", "markdown", "text"].contains($0.kind) }
        }
    }
}

enum Shelf {
    /// Reads the file and makes its face; nil when the file cannot be read.
    static func face(for entry: LibraryEntry) -> ShelfFace? {
        guard let data = try? Data(contentsOf: entry.url, options: .mappedIfSafe) else { return nil }
        return face(data: data, entry: entry)
    }

    static func face(data: Data, entry: LibraryEntry) -> ShelfFace {
        let art = Cover.art(for: data, name: entry.name, kind: entry.kind)
        let label = KindLabel.label(kind: entry.kind, data: data)
        var title = entry.name, author = "", cloth: String?
        switch art {
        case let .book(lines, by, clothIndex):
            title = lines.joined(separator: " ")
            author = by
            cloth = Cover.cloths[clothIndex]
        case let .picture(image, bookTitle, by):
            title = bookTitle
            author = by
            cloth = Cover.averageHex(image)
        default:
            break
        }
        let detail = entry.progressText ?? (author.isEmpty ? ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file) : author)
        return ShelfFace(art: art, title: title, subtitle: "\(label) · \(detail)", author: author, cloth: cloth)
    }
}

/// How the shelf is ordered.
enum ShelfOrder: String, CaseIterable, Identifiable {
    case lastOpened, title, author, kind

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lastOpened: "Last Opened"
        case .title: "Title"
        case .author: "Author"
        case .kind: "Kind"
        }
    }

    /// Titles and authors come from the files' faces where they have them, else the file's name.
    /// Files without an author follow those with one. Ties keep the most recently opened first.
    func sorted(_ entries: [LibraryEntry], faces: [String: ShelfFace]) -> [LibraryEntry] {
        func title(_ e: LibraryEntry) -> String { faces[e.path]?.title ?? Cover.stem(e.name) }
        func author(_ e: LibraryEntry) -> String { faces[e.path]?.author ?? "" }
        func before(_ a: String, _ b: String) -> Bool? {
            let order = a.localizedStandardCompare(b)
            return order == .orderedSame ? nil : order == .orderedAscending
        }
        switch self {
        case .lastOpened:
            return entries.sorted { $0.opened > $1.opened }
        case .title:
            return entries.sorted { before(title($0), title($1)) ?? ($0.opened > $1.opened) }
        case .author:
            return entries.sorted { a, b in
                let (x, y) = (author(a), author(b))
                if x.isEmpty != y.isEmpty { return !x.isEmpty }
                return before(x, y) ?? before(title(a), title(b)) ?? (a.opened > b.opened)
            }
        case .kind:
            return entries.sorted { before(KindLabel.label(kind: $0.kind), KindLabel.label(kind: $1.kind)) ?? before(title($0), title($1)) ?? ($0.opened > $1.opened) }
        }
    }
}

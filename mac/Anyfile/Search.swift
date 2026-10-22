// Search every file in the library. Each file is read and prepared once (its text, a book's
// chapters, a parsed PDF, or mapped bytes); after that a search only looks.
import Foundation
import PDFKit

/// A file made ready to search. A class so a PDF document, which is not a value, can be kept.
final class Searchable: @unchecked Sendable {
    enum Body {
        case text(String)
        case book([(chapter: EpubChapter, text: String)])
        case pdf(PDFDocument)
        case bytes(Data)
        case unreadable
    }

    let entry: LibraryEntry
    let body: Body
    /// The file's modification date when it was read; a later date means read it again.
    let modified: Date?

    init(entry: LibraryEntry) {
        self.entry = entry
        modified = Search.modified(entry.url)
        guard let data = try? Data(contentsOf: entry.url, options: .mappedIfSafe) else { body = .unreadable; return }
        switch entry.kind {
        case "text", "markdown": body = .text(String(decoding: data, as: UTF8.self))
        case "epub": body = .book(Find.bookChapters(data, name: entry.name))
        case "pdf": body = PDFDocument(data: data).map(Body.pdf) ?? .unreadable
        default: body = .bytes(data)
        }
    }

    func hits(for query: String) -> [FindHit] {
        switch body {
        case .text(let s): Find.lines(query, in: s, place: { "Line \($0)" })
        case .book(let chapters): Find.chapters(query, in: chapters)
        case .pdf(let doc): Find.pdf(query, in: doc)
        case .bytes(let data): Find.bytes(query, in: data)
        case .unreadable: []
        }
    }
}

struct SearchResult: Identifiable {
    let entry: LibraryEntry
    let hits: [FindHit]
    var id: String { entry.path }
}

enum Search {
    /// Prepares the files, in parallel, reusing what was prepared before unless the file has
    /// changed on disk since. A PDF parse or a book's chapters dominate the time.
    static func prepare(_ entries: [LibraryEntry], reusing old: [Searchable] = []) -> [Searchable] {
        let previous = Dictionary(old.map { ($0.entry.path, $0) }, uniquingKeysWith: { a, _ in a })
        var out = [Searchable?](repeating: nil, count: entries.count)
        out.withUnsafeMutableBufferPointer { slots in
            let slots = slots
            DispatchQueue.concurrentPerform(iterations: entries.count) { i in
                let entry = entries[i]
                if let kept = previous[entry.path], kept.entry.kind == entry.kind, kept.modified == modified(entry.url) {
                    slots[i] = kept
                } else {
                    slots[i] = Searchable(entry: entry)
                }
            }
        }
        return out.compactMap { $0 }
    }

    static func modified(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    /// Files with at least one match, in the order given. Each file's own hit limit still applies.
    static func run(_ query: String, in corpus: [Searchable]) -> [SearchResult] {
        guard !query.isEmpty else { return [] }
        return corpus.compactMap { item in
            let hits = item.hits(for: query)
            return hits.isEmpty ? nil : SearchResult(entry: item.entry, hits: hits)
        }
    }
}

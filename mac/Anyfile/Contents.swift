// What Contents lists for each kind of file. A target is a chapter number (EPUB), a line number
// (Markdown) or a page index (PDF); the pane for that kind knows how to go there.
import Foundation
import PDFKit

struct ContentsEntry: Identifiable, Hashable {
    let id: Int          // position in the list; two entries may share a target
    let title: String
    let level: Int       // 0 for top level
    let target: Int
}

enum Contents {
    static func hasContents(kind: String) -> Bool { ["pdf", "epub", "markdown"].contains(kind) }

    static func entries(for document: AnyfileDocument) -> [ContentsEntry] {
        switch document.kind {
        case "epub":
            let out = Engine.run("chapters", args: [], on: document.data, name: document.name, kind: document.kind).output
            return EpubChapter.parse(out).enumerated().map {
                ContentsEntry(id: $0.offset, title: $0.element.title.isEmpty ? "Chapter \($0.element.number)" : $0.element.title,
                              level: 0, target: $0.element.number)
            }
        case "markdown":
            return parseOutline(Engine.run("outline", args: [], on: document.data, name: document.name, kind: document.kind).output)
        case "pdf":
            return pdf(PDFDocument(data: document.data))
        default:
            return []
        }
    }

    /// Parses the engine's `outline`: "line<TAB>title", the title indented two spaces per level below the first.
    static func parseOutline(_ output: String) -> [ContentsEntry] {
        output.split(separator: "\n").compactMap { line -> (String, Int, Int)? in
            let fields = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            guard fields.count == 2, let number = Int(fields[0]) else { return nil }
            let indent = fields[1].prefix(while: { $0 == " " }).count
            return (String(fields[1].dropFirst(indent)), indent / 2, number)
        }
        .enumerated().map { ContentsEntry(id: $0.offset, title: $0.element.0, level: $0.element.1, target: $0.element.2) }
    }

    /// The PDF's own outline when it has one, otherwise one entry per page.
    static func pdf(_ doc: PDFDocument?) -> [ContentsEntry] {
        guard let doc else { return [] }
        var items: [(String, Int, Int)] = []
        func walk(_ node: PDFOutline, level: Int) {
            for i in 0..<node.numberOfChildren {
                guard let child = node.child(at: i) else { continue }
                if let page = child.destination?.page {
                    items.append((child.label ?? "Untitled", level, doc.index(for: page)))
                }
                walk(child, level: level + 1)
            }
        }
        if let root = doc.outlineRoot { walk(root, level: 0) }
        if items.isEmpty { items = (0..<doc.pageCount).map { ("Page \($0 + 1)", 0, $0) } }
        return items.enumerated().map { ContentsEntry(id: $0.offset, title: $0.element.0, level: $0.element.1, target: $0.element.2) }
    }
}

/// A request to go somewhere. The serial makes choosing the same entry twice a second request,
/// so a pane that was scrolled away from it moves back.
struct Jump: Equatable {
    let target: Int
    let serial: Int
    /// Text to select at the target, when Find made the jump.
    var query: String? = nil

    func next(_ target: Int, query: String? = nil) -> Jump { Jump(target: target, serial: serial + 1, query: query) }
}

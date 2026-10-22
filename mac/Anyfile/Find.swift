// Find inside one file. Every kind answers with the same kind of hit: where it is, a line of
// context, and a target the pane can go to (line, chapter, page index or byte offset).
import Foundation
import PDFKit

struct FindHit: Identifiable, Hashable {
    let id: Int
    let place: String     // "Line 12", "Chapter 3", "Page 4", "0x1a0"
    let snippet: String
    let target: Int
}

enum Find {
    /// Enough to show; more than this and the query is too broad to be useful.
    static let limit = 500

    static func hits(for query: String, in document: AnyfileDocument) -> [FindHit] {
        guard !query.isEmpty else { return [] }
        switch document.kind {
        case "text", "markdown":
            return lines(query, in: document.text, place: { "Line \($0)" })
        case "epub":
            return chapters(query, in: document)
        case "pdf":
            return pdf(query, in: PDFDocument(data: document.data))
        default:
            return bytes(query, in: document.data)
        }
    }

    /// One hit per matching line, case-insensitive. Targets are 1-based line numbers.
    /// Searches the whole text once and counts newlines only up to each match: splitting an 8 MB
    /// file into lines first took 0.59 s when nothing matched.
    static func lines(_ query: String, in text: String, place: (Int) -> String, startingAt firstID: Int = 0) -> [FindHit] {
        let ns = text as NSString
        var hits: [FindHit] = []
        var lineNumber = 1, counted = 0         // newlines counted in ns[0..<counted]
        var from = 0
        while hits.count < limit {
            let r = ns.range(of: query, options: .caseInsensitive, range: NSRange(location: from, length: ns.length - from))
            if r.location == NSNotFound { break }
            for i in counted..<r.location where ns.character(at: i) == 0x0A { lineNumber += 1 }
            counted = r.location
            var lineRange = ns.lineRange(for: NSRange(location: r.location, length: 0))
            if lineRange.length > 0, ns.character(at: NSMaxRange(lineRange) - 1) == 0x0A { lineRange.length -= 1 }
            let line = ns.substring(with: lineRange)
            let inLine = Range(NSRange(location: r.location - lineRange.location, length: r.length), in: line)!
            hits.append(FindHit(id: firstID + hits.count, place: place(lineNumber), snippet: snippet(line, around: inLine), target: lineNumber))
            from = NSMaxRange(lineRange) + 1   // one hit per line: carry on from the next line
            if from >= ns.length { break }
        }
        return hits
    }

    /// Searches each chapter's text as the engine extracts it. Targets are chapter numbers.
    /// One `text` call for the whole book: asking per chapter took 0.6 s for 135 chapters.
    static func chapters(_ query: String, in document: AnyfileDocument) -> [FindHit] {
        let list = EpubChapter.parse(Engine.run("chapters", args: [], on: document.data, name: document.name, kind: "epub").output)
        let texts = splitBook(Engine.run("text", args: [], on: document.data, name: document.name, kind: "epub").output)
        var hits: [FindHit] = []
        for chapter in list {
            guard let text = texts[chapter.number] else { continue }
            let name = chapter.title.isEmpty ? "Chapter \(chapter.number)" : chapter.title
            let found = lines(query, in: text, place: { _ in name }, startingAt: hits.count)
            hits += found.map { FindHit(id: $0.id, place: $0.place, snippet: $0.snippet, target: chapter.number) }
            if hits.count >= limit { return Array(hits.prefix(limit)) }
        }
        return hits
    }

    /// Splits the engine's whole-book `text` output, where each chapter starts with a line
    /// "== N. title ==". Only the next chapter number counts as a header, so a chapter that
    /// happens to contain such a line is not cut in two.
    static func splitBook(_ output: String) -> [Int: String] {
        var texts: [Int: String] = [:]
        var current = 0
        var body: [Substring] = []
        func close() { if current > 0 { texts[current] = body.joined(separator: "\n") } }
        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("== \(current + 1). ") && line.hasSuffix(" ==") {
                close()
                current += 1
                body = []
            } else {
                body.append(line)
            }
        }
        close()
        return texts
    }

    /// PDFKit's own search, so hits match what the page shows. Targets are page indexes.
    static func pdf(_ query: String, in doc: PDFDocument?) -> [FindHit] {
        guard let doc else { return [] }
        return doc.findString(query, withOptions: .caseInsensitive).prefix(limit).enumerated().compactMap { i, selection in
            guard let page = selection.pages.first else { return nil }
            let index = doc.index(for: page)
            let context = selection.copy() as! PDFSelection
            context.extendForLineBoundaries()
            let line = (context.string ?? selection.string ?? query).replacingOccurrences(of: "\n", with: " ")
            let snippet = line.range(of: query, options: .caseInsensitive).map { Self.snippet(line, around: $0) } ?? line
            return FindHit(id: i, place: "Page \(index + 1)", snippet: snippet, target: index)
        }
    }

    /// Searches bytes: hex digits ("7f 45 4c") when the query is only hex, otherwise the UTF-8 text.
    /// Targets are byte offsets.
    static func bytes(_ query: String, in data: Data) -> [FindHit] {
        let needle = hexBytes(query) ?? Array(query.utf8)
        guard !needle.isEmpty, needle.count <= data.count else { return [] }
        var hits: [FindHit] = []
        var from = data.startIndex
        while hits.count < limit, let r = data.range(of: Data(needle), in: from..<data.endIndex) {
            let offset = r.lowerBound - data.startIndex
            let shown = data[r.lowerBound..<min(r.lowerBound + 16, data.endIndex)].map { String(format: "%02x", $0) }.joined(separator: " ")
            hits.append(FindHit(id: hits.count, place: String(format: "0x%llx", offset), snippet: shown, target: offset))
            from = r.lowerBound + 1
        }
        return hits
    }

    /// Bytes written as "7f 45 4c 46" (two or more pairs) or "0x7f454c46"; nil for anything else,
    /// so a word that happens to be hex, like "cafe", is searched as text.
    static func hexBytes(_ query: String) -> [UInt8]? {
        let q = query.trimmingCharacters(in: .whitespaces)
        let digits: Substring
        if q.lowercased().hasPrefix("0x") {
            digits = q.dropFirst(2)
        } else {
            let pairs = q.split(separator: " ")
            guard pairs.count >= 2, pairs.allSatisfy({ $0.count == 2 }) else { return nil }
            digits = Substring(pairs.joined())
        }
        guard !digits.isEmpty, digits.count % 2 == 0, digits.allSatisfy(\.isHexDigit) else { return nil }
        var out: [UInt8] = []
        var i = digits.startIndex
        while i < digits.endIndex {
            let j = digits.index(i, offsetBy: 2)
            out.append(UInt8(digits[i..<j], radix: 16)!)
            i = j
        }
        return out
    }

    /// At most about 90 characters of a line, centred on the match, with ellipses where cut.
    static func snippet(_ line: String, around match: Range<String.Index>) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard line.count > 90 else { return trimmed }
        let start = line.index(match.lowerBound, offsetBy: -40, limitedBy: line.startIndex) ?? line.startIndex
        let end = line.index(match.upperBound, offsetBy: 40, limitedBy: line.endIndex) ?? line.endIndex
        return (start > line.startIndex ? "…" : "") + line[start..<end].trimmingCharacters(in: .whitespaces) + (end < line.endIndex ? "…" : "")
    }
}

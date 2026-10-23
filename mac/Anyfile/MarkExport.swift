// A book's marks as Markdown: the title, then each passage as a quote with the reader's note under
// it, grouped by chapter or page in reading order. Ready to drop into a notes app.
import AppKit
import UniformTypeIdentifiers

enum MarkExport {
    static func markdown(title: String, author: String = "", marks: [Mark], on date: Date = Date()) -> String {
        var out = "# \(title)\n"
        if !author.isEmpty { out += "\n*\(author)*\n" }
        let count = marks.count == 1 ? "1 mark" : "\(marks.count) marks"
        out += "\nExported from GranthFlow on \(date.formatted(date: .long, time: .omitted)) · \(count)\n"
        // Colours only mean something when the reader used more than one.
        let showColour = Set(marks.map(\.colour)).count > 1
        var place: String?
        for mark in marks.sorted(by: { ($0.target, $0.created) < ($1.target, $1.created) }) {
            if mark.place != place {
                place = mark.place
                out += "\n## \(mark.place)\n"
            }
            out += "\n" + quoted(mark.quote) + "\n"
            if showColour { out += "\n*\(mark.colour.title)*\n" }
            if !mark.note.isEmpty { out += "\n\(mark.note)\n" }
        }
        return out
    }

    /// Each line of the passage behind "> ", so a passage of several lines stays one quote.
    static func quoted(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false).map { $0.isEmpty ? ">" : "> \($0)" }.joined(separator: "\n")
    }

    /// The title and author to head the export with: a book's own, otherwise the file's name.
    static func heading(for data: Data, name: String, kind: String) -> (title: String, author: String) {
        guard kind == "epub" else { return (Cover.stem(name), "") }
        let meta = Engine.run("meta", args: [], on: data, name: name, kind: kind).output
        return (Cover.field("title", in: meta) ?? Cover.stem(name), Cover.field("creator", in: meta) ?? "")
    }

    static func suggestedName(for title: String) -> String {
        let safe = title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        return "\(safe) — marks.md"
    }

    /// Asks where to save, then writes the file. Returns false when cancelled or the write failed.
    @MainActor @discardableResult
    static func save(title: String, author: String, marks: [Mark]) -> Bool {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName(for: title)
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do {
            try markdown(title: title, author: author, marks: marks).write(to: url, atomically: true, encoding: .utf8)
            return true
        } catch {
            NSApp.presentError(error)
            return false
        }
    }
}

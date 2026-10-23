// Actions for the Shortcuts app (and through it Siri and Spotlight): open the book being read, get
// marks and notes as Markdown, add files to the library. Each intent is a thin wrapper; the work is
// in ShortcutWork, which tests call directly.
import AppIntents
import AppKit

enum ShortcutWork {
    /// The book or document part-way through, most recently opened first.
    @MainActor static func currentBook(in library: Library) -> LibraryEntry? { library.continueReading.first }

    /// Marks as Markdown, one section per file, newest file first. With `matching`, only files whose
    /// name or book title contains it (ignoring case).
    @MainActor static func marksText(_ store: MarkStore, matching: String? = nil, title: (String) -> (title: String, author: String)) -> String {
        let byFile = Dictionary(grouping: store.marks, by: \.path)
        let query = matching?.trimmingCharacters(in: .whitespaces) ?? ""
        var parts: [(Date, String)] = []
        for (path, marks) in byFile {
            let heading = title(path)
            let name = (path as NSString).lastPathComponent
            if !query.isEmpty, heading.title.range(of: query, options: .caseInsensitive) == nil, name.range(of: query, options: .caseInsensitive) == nil { continue }
            parts.append((marks.map(\.created).max() ?? .distantPast, MarkExport.markdown(title: heading.title, author: heading.author, marks: marks)))
        }
        return parts.sorted { $0.0 > $1.0 }.map(\.1).joined(separator: "\n---\n\n")
    }

    /// A file's title and author, read from the file: a book's own, otherwise its name.
    static func heading(of path: String) -> (title: String, author: String) {
        let url = URL(fileURLWithPath: path)
        guard url.pathExtension.lowercased() == "epub", let data = try? Data(contentsOf: url) else { return (Cover.stem(url.lastPathComponent), "") }
        return MarkExport.heading(for: data, name: url.lastPathComponent, kind: "epub")
    }
}

struct OpenCurrentBook: AppIntent {
    static let title: LocalizedStringResource = "Open My Current Book"
    static let description = IntentDescription("Opens the book or document you are part-way through, at your place.")
    static let openAppWhenRun = true

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let entry = ShortcutWork.currentBook(in: .shared) else { return .result(dialog: "You are not part-way through a book yet.") }
        NSDocumentController.shared.openDocument(withContentsOf: entry.url, display: true) { _, _, _ in }
        return .result(dialog: "Opening \(Cover.stem(entry.name)).")
    }
}

struct GetMarks: AppIntent {
    static let title: LocalizedStringResource = "Get My Marks"
    static let description = IntentDescription("Your marks and notes as Markdown: all of them, or from books whose title contains some text.")

    @Parameter(title: "Book title contains") var matching: String?

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<String> {
        .result(value: ShortcutWork.marksText(.shared, matching: matching, title: ShortcutWork.heading(of:)))
    }
}

struct AddToLibrary: AppIntent {
    static let title: LocalizedStringResource = "Add to GranthFlow Library"
    static let description = IntentDescription("Puts files on the GranthFlow shelf, as dropping them on the library does.")

    @Parameter(title: "Files") var files: [IntentFile]

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<Int> {
        let urls = files.compactMap(\.fileURL)
        let found = await Task.detached { Adding.scan(urls) }.value
        return .result(value: Library.shared.add(found))
    }
}

struct GranthFlowShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: OpenCurrentBook(), phrases: ["Open my current book in \(.applicationName)", "Continue reading in \(.applicationName)"],
                    shortTitle: "Current Book", systemImageName: "book")
        AppShortcut(intent: GetMarks(), phrases: ["Get my marks from \(.applicationName)"], shortTitle: "My Marks", systemImageName: "highlighter")
    }
}

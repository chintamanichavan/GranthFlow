// Marks in Spotlight: each is indexed under its passage, with the note, the file and the place, so a
// search for a word from a highlight or a note finds it; choosing the result opens the file there.
// Spotlight's own preview shows the passage and the note.
import AppKit
import CoreSpotlight
import UniformTypeIdentifiers

enum SpotlightMarks {
    static let domain = "local.granthflow.marks"

    static func item(for mark: Mark) -> CSSearchableItem {
        let a = CSSearchableItemAttributeSet(contentType: .text)
        a.title = mark.quote.count > 80 ? String(mark.quote.prefix(78)) + "…" : mark.quote
        let whereAbouts = "\(mark.name) · \(mark.place)"
        a.contentDescription = mark.note.isEmpty ? whereAbouts : "\(mark.note)\n\(whereAbouts)"
        a.textContent = [mark.quote, mark.note, mark.name].filter { !$0.isEmpty }.joined(separator: "\n")
        a.keywords = ["mark", "highlight", mark.colour.title.lowercased()] + (mark.note.isEmpty ? [] : ["note"])
        a.contentCreationDate = mark.created
        return CSSearchableItem(uniqueIdentifier: mark.id.uuidString, domainIdentifier: domain, attributeSet: a)
    }

    /// Replaces every indexed mark with the marks as they are now. Hundreds of marks index in a moment.
    static func reindex(_ marks: [Mark], in index: CSSearchableIndex = .default()) {
        let items = marks.map(item(for:))
        index.deleteSearchableItems(withDomainIdentifiers: [domain]) { _ in
            index.indexSearchableItems(items) { error in
                if let error { NSLog("marks not indexed for Spotlight: %@", error.localizedDescription) }
            }
        }
    }

    /// The mark a Spotlight result stands for.
    static func mark(for activity: NSUserActivity, in marks: [Mark]) -> Mark? {
        guard activity.activityType == CSSearchableItemActionType,
              let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else { return nil }
        return marks.first { $0.id.uuidString == id }
    }
}

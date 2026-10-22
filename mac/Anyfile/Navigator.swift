// Opening a file at a place, from the library: a mark, or a search result. The request waits
// here until the file's window sees it, whether that window is new or already open.
import AppKit
import Observation

struct GoRequest: Equatable {
    let path: String
    let target: Int
    let query: String
}

@MainActor @Observable
final class Navigator {
    static let shared = Navigator()
    var pending: GoRequest?

    func open(_ url: URL, at target: Int, selecting query: String) {
        pending = GoRequest(path: url.standardizedFileURL.path, target: target, query: query)
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
            if let error { NSApp.presentError(error) }
        }
    }

    /// The request for this file, taken so no other window acts on it.
    func take(for url: URL) -> GoRequest? {
        guard let p = pending, p.path == url.standardizedFileURL.path else { return nil }
        pending = nil
        return p
    }
}

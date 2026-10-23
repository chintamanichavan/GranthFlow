// The reader's own shelves: Reading, Work, Home, whatever they like. A file can sit on several.
// The names, empty shelves included, are kept in UserDefaults; each file's entry lists its shelves.
import Foundation
import Observation

@MainActor @Observable
final class Shelves {
    static let shared = Shelves(library: .shared, defaults: .standard)

    private(set) var names: [String]
    private let library: Library
    private let defaults: UserDefaults
    private static let key = "shelfNames"

    init(library: Library, defaults: UserDefaults) {
        self.library = library
        self.defaults = defaults
        names = defaults.stringArray(forKey: Self.key) ?? []
    }

    /// A shelf's name made usable: trimmed, and not empty or already taken (ignoring case).
    func available(_ name: String, except old: String? = nil) -> String? {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, !names.contains(where: { $0.caseInsensitiveCompare(n) == .orderedSame && $0 != old }) else { return nil }
        return n
    }

    @discardableResult
    func create(_ name: String) -> String? {
        guard let n = available(name) else { return nil }
        names.append(n)
        save()
        return n
    }

    func rename(_ old: String, to new: String) {
        guard let n = available(new, except: old), let i = names.firstIndex(of: old) else { return }
        names[i] = n
        save()
        library.renameShelf(old, to: n)
    }

    func delete(_ name: String) {
        names.removeAll { $0 == name }
        save()
        library.removeShelf(name)
    }

    func files(on name: String) -> [LibraryEntry] { library.recent.filter { $0.shelves?.contains(name) == true } }

    private func save() { defaults.set(names, forKey: Self.key) }
}

extension Library {
    func put(_ url: URL, on shelf: String) {
        edit(url) { e in
            var s = e.shelves ?? []
            if !s.contains(shelf) { s.append(shelf) }
            e.shelves = s
        }
    }

    func take(_ url: URL, off shelf: String) {
        edit(url) { e in
            e.shelves = e.shelves?.filter { $0 != shelf }
            if e.shelves?.isEmpty == true { e.shelves = nil }
        }
    }

    func renameShelf(_ old: String, to new: String) {
        editAll { e in e.shelves = e.shelves?.map { $0 == old ? new : $0 } }
    }

    func removeShelf(_ name: String) {
        editAll { e in
            e.shelves = e.shelves?.filter { $0 != name }
            if e.shelves?.isEmpty == true { e.shelves = nil }
        }
    }
}

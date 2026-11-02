// The shelf: every file in GranthFlow's folder (Documents, shown in Files as "GranthFlow"), most
// recent first, each with the cover the Mac draws for it. Files come in from +, from "Open in
// GranthFlow" in another app, or by being put in the folder with Files. Marks lists every
// passage marked, in any file; one chosen here or in Spotlight opens its file there. The search
// field looks through every file on the shelf.
import CoreSpotlight
import SwiftUI
import UniformTypeIdentifiers

/// A file to open, and the mark in it to go to.
struct Opening: Hashable {
    let path: String
    var goTo: GoTo? = nil

    init(path: String, goTo: GoTo? = nil) {
        self.path = path
        self.goTo = goTo
    }

    init(_ mark: Mark) { self.init(path: mark.path, goTo: GoTo(target: mark.target, quote: mark.quote)) }
}

struct LibraryScreen: View {
    private let library = Library.shared
    private let markStore = MarkStore.shared
    @State private var section = LibrarySection.library
    /// Faces by path and progress, so a cover's line is redrawn when reading moves on.
    @State private var faces: [String: ShelfFace] = [:]
    @State private var importing = false
    @State private var open: [Opening] = []
    @State private var query = ""
    @State private var results: [SearchResult] = []
    /// Every file read once and kept ready, so the next search only looks.
    @State private var corpus: [Searchable] = []
    @Environment(\.scenePhase) private var phase

    var body: some View {
        NavigationStack(path: $open) {
            Group {
                if !query.isEmpty { searchResults } else if section == .marks { marksList } else { shelf }
            }
            .searchable(text: $query, prompt: "Search every file")
            .task(id: query) { await search() }
            .navigationTitle(section.title)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Show", selection: $section) {
                            ForEach(LibrarySection.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityIdentifier("sectionMenu")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { importing = true } label: { Image(systemName: "plus") }
                }
            }
            .navigationDestination(for: Opening.self) { opening in
                ReaderScreen(url: URL(fileURLWithPath: opening.path), goTo: opening.goTo)
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
                if case let .success(urls) = result { add(urls) }
            }
        }
        .onOpenURL { url in
            if let added = add([url]).first { open = [Opening(path: added.path)] }
        }
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            if let mark = SpotlightMarks.mark(for: activity, in: markStore.marks) { open = [Opening(mark)] }
        }
        .onChange(of: phase, initial: true) {
            if phase == .active { scanFolder() }
        }
        .task {
            // `--open <path>`, as on the Mac, so scripts and UI tests can start on a file.
            let args = CommandLine.arguments
            if let i = args.firstIndex(of: "--open"), i + 1 < args.count {
                open = [Opening(path: URL(fileURLWithPath: args[i + 1], relativeTo: .documentsDirectory).standardizedFileURL.path)]
            }
        }
    }

    private var shelf: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120, maximum: 170), spacing: 20, alignment: .top)], spacing: 28) {
                ForEach(section.entries(in: library)) { entry in
                    NavigationLink(value: Opening(path: entry.path)) {
                        ShelfItem(entry: entry, face: faces[key(entry)])
                    }
                    .buttonStyle(.plain)
                    .contextMenu { menu(for: entry) }
                    .task(id: key(entry)) { await loadFace(entry) }
                }
            }
            .padding()
        }
        .overlay {
            if section.entries(in: library).isEmpty {
                ContentUnavailableView("Nothing here yet", systemImage: section.symbol,
                                       description: Text("Add books and documents with +, or put them in the GranthFlow folder in Files."))
            }
        }
    }

    /// Each file with matches, and its matches; choosing one opens the file there.
    private var searchResults: some View {
        List {
            ForEach(results) { result in
                Section(result.entry.name) {
                    ForEach(result.hits) { hit in
                        Button { open = [Opening(path: result.entry.path, goTo: GoTo(target: hit.target, quote: query))] } label: { HitRow(hit: hit) }
                            .accessibilityIdentifier("searchHit.\(result.entry.name).\(hit.id)")
                    }
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if results.isEmpty { ContentUnavailableView.search(text: query) }
        }
    }

    /// Reads the shelf's files the first time, and again only those changed since, then looks.
    private func search() async {
        guard !query.isEmpty else { return results = [] }
        try? await Task.sleep(for: .milliseconds(250))                     // a word typed, not each letter
        guard !Task.isCancelled else { return }
        let q = query, entries = library.recent, old = corpus
        let (ready, found) = await Task.detached(priority: .userInitiated) {
            let ready = Search.prepare(entries, reusing: old)
            return (ready, Search.run(q, in: ready))
        }.value
        guard !Task.isCancelled else { return }
        corpus = ready
        results = found
    }

    /// Every mark, newest first, under the name of its file.
    private var marksList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(markStore.all) { mark in
                    MarkRow(mark: mark, caption: "\(mark.name)  ·  \(mark.place)", choose: { open = [Opening(mark)] },
                            remove: { markStore.remove(mark) }, setNote: { markStore.setNote($0, for: mark) },
                            setColour: { markStore.setColour($0, for: mark) })
                    Divider()
                }
            }
            .padding(.horizontal)
        }
        .overlay {
            if markStore.marks.isEmpty {
                ContentUnavailableView("No marks yet", systemImage: LibrarySection.marks.symbol,
                                       description: Text("Select a passage in any book or document and choose Mark. It will be kept here."))
            }
        }
    }

    private func key(_ entry: LibraryEntry) -> String { entry.path + "|" + (entry.progressText ?? "") }

    private func loadFace(_ entry: LibraryEntry) async {
        let k = key(entry)
        guard faces[k] == nil else { return }
        if let face = await Task.detached(priority: .userInitiated, operation: { Shelf.face(for: entry) }).value {
            faces[k] = face
        }
    }

    @ViewBuilder private func menu(for entry: LibraryEntry) -> some View {
        Button(entry.isFinished ? "Mark as Not Finished" : "Mark as Finished",
               systemImage: entry.isFinished ? "circle" : "checkmark.circle") {
            library.setFinished(entry.url, !entry.isFinished)
        }
        Button("Delete", systemImage: "trash", role: .destructive) {
            try? FileManager.default.removeItem(at: entry.url)
            library.forget(entry)
        }
    }

    /// Copies files from elsewhere into GranthFlow's folder and shelves them. A file already there
    /// with the same name and bytes is shelved again rather than copied twice.
    @discardableResult
    private func add(_ urls: [URL]) -> [URL] {
        let folder = URL.documentsDirectory
        var found: [(url: URL, kind: String)] = []
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            var target = url
            if !url.standardizedFileURL.path.hasPrefix(folder.path) {
                target = Self.place(for: url.lastPathComponent, in: folder, matching: url)
                if !FileManager.default.fileExists(atPath: target.path) {
                    do { try FileManager.default.copyItem(at: url, to: target) } catch { continue }
                }
            }
            guard let data = try? Data(contentsOf: target, options: .mappedIfSafe) else { continue }
            found.append((target, Engine.detectKind(of: data, name: target.lastPathComponent)))
        }
        library.add(found)
        return found.map(\.url)
    }

    /// "Book.epub", or "Book 2.epub" and on when a different file already has the name.
    private static func place(for name: String, in folder: URL, matching source: URL) -> URL {
        let stem = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension
        var candidate = folder.appendingPathComponent(name)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path),
              !FileManager.default.contentsEqual(atPath: candidate.path, andPath: source.path) {
            candidate = folder.appendingPathComponent(ext.isEmpty ? "\(stem) \(n)" : "\(stem) \(n).\(ext)")
            n += 1
        }
        return candidate
    }

    /// Shelves files put in the folder from Files, and notices ones deleted there.
    private func scanFolder() {
        library.checkFiles()
        let known = Set(library.recent.map(\.path))
        guard let walk = FileManager.default.enumerator(at: URL.documentsDirectory, includingPropertiesForKeys: [.isRegularFileKey],
                                                        options: [.skipsHiddenFiles]) else { return }
        var found: [(url: URL, kind: String)] = []
        for case let url as URL in walk {
            let path = url.standardizedFileURL.path
            guard !known.contains(path), (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                  let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { continue }
            found.append((url, Engine.detectKind(of: data, name: url.lastPathComponent)))
        }
        library.addFromFolder(found)
    }
}

private struct ShelfItem: View {
    let entry: LibraryEntry
    let face: ShelfFace?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let face {
                CoverView(art: face.art)
            } else {
                RoundedRectangle(cornerRadius: 3).fill(.quaternary)
                    .aspectRatio(CoverView.base.width / CoverView.base.height, contentMode: .fit)
            }
            if let progress = entry.progress, !entry.isFinished {
                ProgressView(value: progress).tint(Color(platform: Theme.library.accent))
            }
            Text(face?.title ?? entry.name)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
            Text(face?.subtitle ?? " ")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

// The library: every file you have opened, each with its face, and the book you are part-way
// through at the top. One window for every kind of file.
import SwiftUI
import AppKit

/// What the sidebar can show: a built-in section, one of the reader's shelves, or a watched folder.
enum SidebarItem: Hashable {
    case section(LibrarySection)
    case shelf(String)
    case folder(String)
}

struct LibraryView: View {
    @State private var library: Library
    @State private var selected: SidebarItem? = .section(.library)
    private let shelves = Shelves.shared
    @State private var naming: Naming?
    @State private var name = ""
    @State private var faces: [String: ShelfFace] = [:]
    private let markStore = MarkStore.shared
    private let watched = WatchedFolders.shared
    @State private var query = ""
    @State private var results: [SearchResult] = []
    @State private var searched = ""
    @State private var corpus: [Searchable] = []
    @State private var dropping = false

    /// Tests pass their own library; the app uses the shared one.
    @MainActor init(library: Library? = nil) { _library = State(initialValue: library ?? .shared) }

    /// Asking for a shelf's name: a new shelf, or a new name for one.
    private enum Naming: Equatable { case new, rename(String) }

    private var section: LibrarySection? {
        if case let .section(s) = selected ?? .section(.library) { return s }
        return nil
    }

    private var shown: [LibraryEntry] {
        switch selected ?? .section(.library) {
        case let .section(s): s.entries(in: library)
        case let .shelf(name): shelves.files(on: name)
        case let .folder(path): library.recent.filter { WatchedFolders.folder(holding: $0.path, among: [path]) != nil }
        }
    }

    private var nameIsUsable: Bool {
        if case let .rename(old) = naming { return shelves.available(name, except: old) != nil }
        return shelves.available(name) != nil
    }

    private var heading: String {
        switch selected ?? .section(.library) {
        case .section(.library): "Recently opened"
        case let .section(s): s.title
        case let .shelf(name): name
        case let .folder(path): (path as NSString).lastPathComponent
        }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selected) {
                ForEach(LibrarySection.allCases) { s in
                    Label(s.title, systemImage: s.symbol)
                        .badge(s == .marks ? markStore.marks.count : s.entries(in: library).count)
                        .tag(SidebarItem.section(s))
                        .accessibilityIdentifier("section.\(s.rawValue)")
                }
                Section("Shelves") {
                    ForEach(shelves.names, id: \.self) { shelf in
                        Label(shelf, systemImage: "books.vertical")
                            .badge(shelves.files(on: shelf).count)
                            .tag(SidebarItem.shelf(shelf))
                            .dropDestination(for: URL.self) { urls, _ in
                                for url in urls { library.put(url, on: shelf) }
                                return !urls.isEmpty
                            }
                            .contextMenu {
                                Button("Rename…") { name = shelf; naming = .rename(shelf) }
                                Button("Delete Shelf") {
                                    if selected == .shelf(shelf) { selected = .section(.library) }
                                    shelves.delete(shelf)
                                }
                            }
                            .accessibilityIdentifier("shelf-name.\(shelf)")
                    }
                    Button { name = ""; naming = .new } label: { Label("New Shelf", systemImage: "plus") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("newShelf")
                }
                if !watched.paths.isEmpty {
                    Section("Watched folders") {
                        ForEach(watched.paths, id: \.self) { path in
                            Label((path as NSString).lastPathComponent, systemImage: "folder")
                                .badge(watched.count(in: path))
                                .tag(SidebarItem.folder(path))
                                .help(path)
                                .contextMenu {
                                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
                                    Button("Stop Watching") {
                                        if selected == .folder(path) { selected = .section(.library) }
                                        watched.remove(path)
                                    }
                                }
                                .accessibilityIdentifier("watched.\((path as NSString).lastPathComponent)")
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 220)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !query.isEmpty {
                        SearchResults(query: searched, results: results, faces: faces, searching: searched != query) { entry, hit in
                            Navigator.shared.open(entry.url, at: hit.target, selecting: searched)
                        }
                    } else if section == .library, let current = library.continueReading.first {
                        Hero(entry: current, face: faces[current.path]) { open(current) }
                    }
                    if section == .marks {
                        MarksList(marks: markStore.all, open: open(_:), remove: { markStore.remove($0) },
                                  setNote: { markStore.setNote($1, for: $0) }, setColour: { markStore.setColour($1, for: $0) })
                    } else if shown.isEmpty {
                        EmptyShelf(section: section ?? .library, open: openPanel)
                    } else {
                        Text(heading)
                            .font(.title2.weight(.semibold))
                            .padding(.horizontal, 32)
                            .padding(.top, 28)
                            .padding(.bottom, 16)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 128, maximum: 150), spacing: 26, alignment: .top)],
                                  alignment: .leading, spacing: 30) {
                            ForEach(shown) { entry in
                                ShelfItem(entry: entry, face: faces[entry.path], shelves: shelves.names, open: { open(entry) },
                                          forget: { library.forget(entry) },
                                          toggleShelf: { shelf in
                                              if entry.shelves?.contains(shelf) == true { library.take(entry.url, off: shelf) }
                                              else { library.put(entry.url, on: shelf) }
                                          },
                                          newShelf: { name = ""; naming = .new })
                            }
                        }
                        .padding(.horizontal, 32)
                        .padding(.bottom, 40)
                        if section == .library, !markStore.marks.isEmpty {
                            YourMarks(marks: Array(markStore.all.prefix(6)), open: open(_:))
                        }
                    }
                }
            }
            .background(Color(nsColor: Theme.library.window))
            .dropDestination(for: URL.self) { urls, _ in
                Task {
                    let found = await Task.detached(priority: .userInitiated) { Adding.scan(urls) }.value
                    library.add(found)
                }
                return !urls.isEmpty
            } isTargeted: { dropping = $0 }
            .overlay { if dropping { DropHint() } }
            .searchable(text: $query, placement: .toolbar, prompt: "Search every file")
            .task(id: query) { await search() }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: watchPanel) { Label("Watch a Folder", systemImage: "folder.badge.plus") }
                        .help("Watch a folder: its files join the library by themselves")
                        .accessibilityIdentifier("watchFolder")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: openPanel) { Label("Open", systemImage: "plus") }
                        .help("Open a file")
                        .accessibilityIdentifier("libraryOpen")
                }
            }
        }
        .navigationTitle("Library")
        .alert(naming == .new ? "New Shelf" : "Rename Shelf", isPresented: Binding(get: { naming != nil }, set: { if !$0 { naming = nil } })) {
            TextField("Name", text: $name)
            Button(naming == .new ? "Create" : "Rename") {
                switch naming {
                case .new: if let made = shelves.create(name) { selected = .shelf(made) }
                case let .rename(old):
                    let new = shelves.available(name, except: old)            // the cleaned-up name, before it is taken
                    shelves.rename(old, to: name)
                    if selected == .shelf(old), let new { selected = .shelf(new) }
                case nil: break
                }
                naming = nil
            }
            .disabled(!nameIsUsable)
            Button("Cancel", role: .cancel) { naming = nil }
        }
        .frame(minWidth: 760, minHeight: 520)
        .task(id: library.recent.map(\.path)) { await loadFaces() }
        .onAppear { library.checkFiles() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in library.checkFiles() }
    }

    /// Makes faces for files that have none yet, off the main thread, a few at a time.
    private func loadFaces() async {
        let missing = library.recent.filter { faces[$0.path] == nil }
        await withTaskGroup(of: (String, ShelfFace?).self) { group in
            var running = 0
            for entry in missing {
                if running == 4, let (path, face) = await group.next() { faces[path] = face; running -= 1 }
                group.addTask(priority: .utility) { (entry.path, Shelf.face(for: entry)) }
                running += 1
            }
            for await (path, face) in group { faces[path] = face }
        }
    }

    /// Waits for a pause in typing, then searches every file off the main thread. Files are
    /// prepared on the first search and again only when the library's files change.
    private func search() async {
        guard !query.isEmpty else { results = []; searched = ""; return }
        try? await Task.sleep(for: .milliseconds(200))
        guard !Task.isCancelled else { return }
        let entries = library.recent
        let q = query
        let old = corpus
        let prepared = await Task.detached(priority: .userInitiated) { Search.prepare(entries, reusing: old) }.value
        corpus = prepared
        let found = await Task.detached(priority: .userInitiated) { Search.run(q, in: prepared) }.value
        guard !Task.isCancelled else { return }
        results = found
        searched = q
    }

    private func open(_ entry: LibraryEntry) {
        NSDocumentController.shared.openDocument(withContentsOf: entry.url, display: true) { _, _, error in
            if let error { NSApp.presentError(error) }
        }
    }

    private func open(_ mark: Mark) {
        Navigator.shared.open(URL(fileURLWithPath: mark.path), at: mark.target, selecting: mark.quote)
    }

    private func watchPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Watch"
        panel.message = "Files in these folders join your library, now and whenever new ones arrive."
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { watched.add(url) }
    }

    private func openPanel() { NSDocumentController.shared.openDocument(nil) }
}

/// The book or document you are part-way through, in the colour of its cover.
private struct Hero: View {
    let entry: LibraryEntry
    let face: ShelfFace?
    let resume: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 36) {
            Group {
                if let face { CoverView(art: face.art) } else { Color.clear }
            }
            .frame(width: 150, height: 210)
            VStack(alignment: .leading, spacing: 10) {
                Text("CONTINUE READING").font(.caption.weight(.semibold)).kerning(1.2).opacity(0.7)
                Text(face?.title ?? entry.name).font(.system(size: 38, design: .serif)).lineLimit(2)
                if let author = face?.author, !author.isEmpty { Text(author).font(.title3).opacity(0.85) }
                if let progress = entry.progress {
                    ProgressView(value: progress).tint(.white).frame(maxWidth: 260).padding(.top, 8)
                }
                if let text = entry.progressText {
                    Text([text, entry.wordsLeft.map { ReadingTime.phrase(wordsLeft: $0, wordsPerMinute: ReadingClock.shared.speed.wordsPerMinute) }]
                        .compactMap { $0 }.joined(separator: "  ·  "))
                        .font(.callout).opacity(0.7)
                }
                Button(action: resume) {
                    Text("Resume").font(.callout.weight(.semibold)).padding(.horizontal, 22).padding(.vertical, 8)
                        .background(.white, in: Capsule())
                        .foregroundStyle(Color(nsColor: ground))
                }
                .buttonStyle(.plain)
                .padding(.top, 10)
                .accessibilityIdentifier("resume")
            }
            .foregroundStyle(.white)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 34)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: ground))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hero")
    }

    /// The cover's colour, darkened until white text reads on it; deep blue for documents.
    private var ground: NSColor {
        Theme.groundForWhiteText(face?.cloth.flatMap(NSColor.init(hex:)) ?? NSColor(hex: "#16264F")!)
    }
}

private struct ShelfItem: View {
    let entry: LibraryEntry
    let face: ShelfFace?
    let shelves: [String]
    let open: () -> Void
    let forget: () -> Void
    let toggleShelf: (String) -> Void
    let newShelf: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    if let face { CoverView(art: face.art) }
                    else { RoundedRectangle(cornerRadius: 4).fill(Color(nsColor: Theme.library.hairline)) }
                }
                .aspectRatio(CoverView.base.width / CoverView.base.height, contentMode: .fit)
                .frame(maxWidth: .infinity, alignment: .bottomLeading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(face?.title ?? entry.name).font(.callout.weight(.medium)).lineLimit(2)
                        .foregroundStyle(Color(nsColor: Theme.library.label))
                    Text(face?.subtitle ?? KindLabel.label(kind: entry.kind)).font(.caption).lineLimit(1)
                        .foregroundStyle(Color(nsColor: Theme.library.secondary))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(entry.path)
        .draggable(entry.url)                                    // onto a shelf in the sidebar
        .contextMenu {
            Button("Open") { open() }
            Menu("Add to Shelf") {
                ForEach(shelves, id: \.self) { shelf in
                    Button { toggleShelf(shelf) } label: {
                        if entry.shelves?.contains(shelf) == true { Label(shelf, systemImage: "checkmark") } else { Text(shelf) }
                    }
                }
                if !shelves.isEmpty { Divider() }
                Button("New Shelf…", action: newShelf)
            }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([entry.url]) }
            let marks = MarkStore.shared.marks(for: entry.url)
            if !marks.isEmpty {
                Button("Export Marks…") {
                    MarkExport.save(title: face?.title ?? Cover.stem(entry.name), author: face?.author ?? "", marks: marks)
                }
            }
            Divider()
            Button("Remove from Library") { forget() }
        }
        .accessibilityIdentifier("shelf.\(entry.name)")
    }
}

private struct EmptyShelf: View {
    let section: LibrarySection
    let open: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: section.symbol).font(.system(size: 40)).foregroundStyle(.tertiary)
            Text(section == .library ? "Open any file to start your library." : "Nothing here yet.")
                .font(.title3)
                .foregroundStyle(.secondary)
            if section == .library {
                Text("Books, documents, notes and programs all open in one window. Or drop files here.")
                    .foregroundStyle(.tertiary)
                Button("Open a File…", action: open).controlSize(.large).padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 120)
    }
}

/// The newest marks from every file, side by side: a line of a novel beside a line of a report.
private struct YourMarks: View {
    let marks: [Mark]
    let open: (Mark) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your marks").font(.title2.weight(.semibold))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 230, maximum: 320), spacing: 18)], alignment: .leading, spacing: 18) {
                ForEach(marks) { mark in MarkCard(mark: mark) { open(mark) } }
            }
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 40)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("yourMarks")
    }
}

private struct MarkCard: View {
    let mark: Mark
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 1.5).fill(Color(nsColor: mark.colour.paint)).frame(width: 3)
                VStack(alignment: .leading, spacing: 8) {
                    Group {
                        if mark.kind == "binary" { Text(mark.quote).font(.system(size: 12, design: .monospaced)) }
                        else { Text("“\(mark.quote)”").font(.system(size: 14, design: .serif)) }
                    }
                    .lineLimit(3)
                        .foregroundStyle(Color(nsColor: Theme.library.label))
                    Text("\(mark.name)  ·  \(mark.place)").font(.caption).lineLimit(1)
                        .foregroundStyle(Color(nsColor: Theme.library.secondary))
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open \(mark.name) at this passage")
        .accessibilityIdentifier("markCard.\(mark.quote.prefix(24))")
    }
}

/// Every mark, newest first, with the file it is in.
private struct MarksList: View {
    let marks: [Mark]
    let open: (Mark) -> Void
    let remove: (Mark) -> Void
    let setNote: (Mark, String) -> Void
    let setColour: (Mark, MarkColour) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Marks").font(.title2.weight(.semibold)).padding(.bottom, 12)
            if marks.isEmpty {
                Text("Select a passage in any file and press Mark. It will be kept here.")
                    .foregroundStyle(.secondary)
            }
            ForEach(marks) { mark in
                MarkRow(mark: mark, caption: "\(mark.name)  ·  \(mark.place)", choose: { open(mark) }, remove: { remove(mark) },
                        setNote: { setNote(mark, $0) }, setColour: { setColour(mark, $0) })
                Divider()
            }
        }
        .frame(maxWidth: 720, alignment: .leading)
        .padding(32)
    }
}

/// Matches from every file, grouped by file, each group under the file's face.
private struct SearchResults: View {
    let query: String
    let results: [SearchResult]
    let faces: [String: ShelfFace]
    let searching: Bool
    let open: (LibraryEntry, FindHit) -> Void
    /// Enough lines to judge a file by; the file's own Find shows the rest.
    static let shown = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            Text(summary).font(.title2.weight(.semibold))
                .accessibilityIdentifier("searchSummary")
            ForEach(results) { result in
                HStack(alignment: .top, spacing: 18) {
                    Group {
                        if let face = faces[result.entry.path] { CoverView(art: face.art) } else { Color.clear }
                    }
                    .frame(width: 54, height: 76)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(faces[result.entry.path]?.title ?? result.entry.name).font(.headline)
                            Text(count(result.hits.count)).font(.callout).foregroundStyle(.secondary)
                        }
                        ForEach(result.hits.prefix(Self.shown)) { hit in
                            FindRow(hit: hit) { open(result.entry, hit) }
                                .accessibilityIdentifier("searchHit.\(result.entry.name).\(hit.id)")
                        }
                        if result.hits.count > Self.shown {
                            Text("and \(count(result.hits.count - Self.shown)) more — open the file and use Find")
                                .font(.caption).foregroundStyle(.secondary).padding(.leading, 8)
                        }
                    }
                }
            }
        }
        .padding(32)
        .frame(maxWidth: 900, alignment: .leading)
        .opacity(searching ? 0.6 : 1)
    }

    private var summary: String {
        if query.isEmpty { return "Searching…" }
        if results.isEmpty { return "No file contains “\(query)”" }
        let files = results.count == 1 ? "1 file" : "\(results.count) files"
        return "“\(query)” in \(files)"
    }

    private func count(_ n: Int) -> String {
        n >= Find.limit ? "\(Find.limit)+ matches" : (n == 1 ? "1 match" : "\(n) matches")
    }
}

/// Shown while files are dragged over the library.
private struct DropHint: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18).fill(Color.accentColor.opacity(0.08))
            RoundedRectangle(cornerRadius: 18).strokeBorder(Color.accentColor.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
            VStack(spacing: 10) {
                Image(systemName: "tray.and.arrow.down").font(.system(size: 34, weight: .light))
                Text("Drop to add to your library").font(.title3)
                Text("Files, or a folder of them").foregroundStyle(.secondary)
            }
            .foregroundStyle(Color.accentColor)
        }
        .padding(16)
        .allowsHitTesting(false)
        .accessibilityIdentifier("dropHint")
    }
}

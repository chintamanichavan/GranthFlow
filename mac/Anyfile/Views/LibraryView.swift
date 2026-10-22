// The library: every file you have opened, each with its face, and the book you are part-way
// through at the top. One window for every kind of file.
import SwiftUI
import AppKit

struct LibraryView: View {
    @State private var library: Library
    @State private var section: LibrarySection? = .library
    @State private var faces: [String: ShelfFace] = [:]
    private let markStore = MarkStore.shared

    /// Tests pass their own library; the app uses the shared one.
    @MainActor init(library: Library? = nil) { _library = State(initialValue: library ?? .shared) }

    private var shown: [LibraryEntry] { (section ?? .library).entries(in: library) }

    var body: some View {
        NavigationSplitView {
            List(selection: $section) {
                ForEach(LibrarySection.allCases) { s in
                    Label(s.title, systemImage: s.symbol)
                        .badge(s == .marks ? markStore.marks.count : s.entries(in: library).count)
                        .tag(s)
                        .accessibilityIdentifier("section.\(s.rawValue)")
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 220)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if section == .library, let current = library.continueReading.first {
                        Hero(entry: current, face: faces[current.path]) { open(current) }
                    }
                    if section == .marks {
                        MarksList(marks: markStore.all, open: open(_:), remove: { markStore.remove($0) })
                    } else if shown.isEmpty {
                        EmptyShelf(section: section ?? .library, open: openPanel)
                    } else {
                        Text(section == .library ? "Recently opened" : (section ?? .library).title)
                            .font(.title2.weight(.semibold))
                            .padding(.horizontal, 32)
                            .padding(.top, 28)
                            .padding(.bottom, 16)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 128, maximum: 150), spacing: 26, alignment: .top)],
                                  alignment: .leading, spacing: 30) {
                            ForEach(shown) { entry in
                                ShelfItem(entry: entry, face: faces[entry.path], open: { open(entry) },
                                          forget: { library.forget(entry) })
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
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: openPanel) { Label("Open", systemImage: "plus") }
                        .help("Open a file")
                        .accessibilityIdentifier("libraryOpen")
                }
            }
        }
        .navigationTitle("Library")
        .frame(minWidth: 760, minHeight: 520)
        .task(id: library.recent.map(\.path)) { await loadFaces() }
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

    private func open(_ entry: LibraryEntry) {
        NSDocumentController.shared.openDocument(withContentsOf: entry.url, display: true) { _, _, error in
            if let error { NSApp.presentError(error) }
        }
    }

    /// Opens the mark's file; its window goes to the passage when it sees the pending mark.
    private func open(_ mark: Mark) {
        markStore.pending = mark
        NSDocumentController.shared.openDocument(withContentsOf: URL(fileURLWithPath: mark.path), display: true) { _, _, error in
            if let error { NSApp.presentError(error) }
        }
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
                if let text = entry.progressText { Text(text).font(.callout).opacity(0.7) }
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

    /// A book's cloth, darkened a little so white text sits well on it; deep blue for documents.
    private var ground: NSColor {
        let base = face?.cloth.flatMap(NSColor.init(hex:)) ?? NSColor(hex: "#16264F")!
        return base.blended(withFraction: 0.18, of: .black) ?? base
    }
}

private struct ShelfItem: View {
    let entry: LibraryEntry
    let face: ShelfFace?
    let open: () -> Void
    let forget: () -> Void

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
        .contextMenu {
            Button("Open") { open() }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([entry.url]) }
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
                Text("Books, documents, notes and programs all open in one window.")
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
                RoundedRectangle(cornerRadius: 1.5).fill(Color(nsColor: Theme.mark)).frame(width: 3)
                VStack(alignment: .leading, spacing: 8) {
                    Text("“\(mark.quote)”").font(.system(size: 14, design: .serif)).lineLimit(3)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Marks").font(.title2.weight(.semibold)).padding(.bottom, 12)
            if marks.isEmpty {
                Text("Select a passage in any file and press Mark. It will be kept here.")
                    .foregroundStyle(.secondary)
            }
            ForEach(marks) { mark in
                MarkRow(mark: Mark(id: mark.id, path: mark.path, kind: mark.kind, quote: mark.quote, target: mark.target,
                                   place: "\(mark.name)  ·  \(mark.place)", created: mark.created),
                        choose: { open(mark) }, remove: { remove(mark) })
                Divider()
            }
        }
        .frame(maxWidth: 720, alignment: .leading)
        .padding(32)
    }
}

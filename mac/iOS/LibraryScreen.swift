// The shelf: every file in GranthFlow's folder (Documents, shown in Files as "GranthFlow"), most
// recent first, each with the cover the Mac draws for it. Files come in from +, from "Open in
// GranthFlow" in another app, or by being put in the folder with Files.
import SwiftUI
import UniformTypeIdentifiers

struct LibraryScreen: View {
    private let library = Library.shared
    @State private var section = LibrarySection.library
    /// Faces by path and progress, so a cover's line is redrawn when reading moves on.
    @State private var faces: [String: ShelfFace] = [:]
    @State private var importing = false
    @State private var open: [String] = []
    @Environment(\.scenePhase) private var phase

    /// Marks have no screen on iOS yet.
    private static let sections = LibrarySection.allCases.filter { $0 != .marks }

    var body: some View {
        NavigationStack(path: $open) {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120, maximum: 170), spacing: 20, alignment: .top)], spacing: 28) {
                    ForEach(section.entries(in: library)) { entry in
                        NavigationLink(value: entry.path) {
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
            .navigationTitle(section.title)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Show", selection: $section) {
                            ForEach(Self.sections) { Label($0.title, systemImage: $0.symbol).tag($0) }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { importing = true } label: { Image(systemName: "plus") }
                }
            }
            .navigationDestination(for: String.self) { path in
                ReaderScreen(url: URL(fileURLWithPath: path))
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
                if case let .success(urls) = result { add(urls) }
            }
        }
        .onOpenURL { url in
            if let added = add([url]).first { open = [added.path] }
        }
        .onChange(of: phase, initial: true) {
            if phase == .active { scanFolder() }
        }
        .task {
            // `--open <path>`, as on the Mac, so scripts and UI tests can start on a file.
            let args = CommandLine.arguments
            if let i = args.firstIndex(of: "--open"), i + 1 < args.count {
                open = [URL(fileURLWithPath: args[i + 1], relativeTo: .documentsDirectory).standardizedFileURL.path]
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

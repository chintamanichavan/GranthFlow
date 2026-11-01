// A file opened from the shelf: one pane per kind, as ContentView chooses on the Mac. The library
// keeps where reading stopped, and edits to text are written back when the file is left.
import PDFKit
import SwiftUI

struct ReaderScreen: View {
    let url: URL
    @State private var document: AnyfileDocument?
    @State private var edited = false
    @Environment(\.scenePhase) private var phase

    var body: some View {
        Group {
            if let document {
                ReaderView(document: Binding(get: { document }, set: { self.document = $0; edited = true }),
                           start: Library.shared.entry(for: url)?.position) { position, total in
                    Library.shared.recordPosition(url, position: position, total: total)
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle(url.deletingPathExtension().lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard document == nil, let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return }
            let opened = AnyfileDocument(data: data, name: url.lastPathComponent)
            document = opened
            Library.shared.recordOpened(url, kind: opened.kind)
        }
        .onDisappear(perform: save)
        .onChange(of: phase) {
            if phase != .active { save() }
        }
    }

    private func save() {
        guard edited, let document else { return }
        do {
            try document.data.write(to: url, options: .atomic)
            edited = false
        } catch {
            NSLog("not saved: %@", error.localizedDescription)
        }
    }
}

struct ReaderView: View {
    @Binding var document: AnyfileDocument
    /// Where reading stopped: a chapter number for EPUB, a page index for PDF.
    var start: Int?
    var onPlace: (_ position: Int, _ total: Int) -> Void = { _, _ in }

    var body: some View {
        switch document.kind {
        case "epub":
            EpubReader(document: document, start: start, onPlace: onPlace)
        case "pdf":
            PDFReader(data: document.data, start: start, onPlace: onPlace)
        case "text", "markdown":
            TextEditor(text: $document.text)
                .font(.body.monospaced())
                .padding(.horizontal)
        default:
            HexReader(document: document)
        }
    }
}

/// One chapter at a time; the bottom bar turns chapters and lists them all.
struct EpubReader: View {
    let document: AnyfileDocument
    var start: Int?
    var onPlace: (Int, Int) -> Void
    @State private var chapters: [EpubChapter] = []
    @State private var index = 0
    @State private var text = ""

    var body: some View {
        ScrollView {
            Text(text)
                .font(.system(.body, design: .serif))
                .lineSpacing(6)
                .textSelection(.enabled)
                .frame(maxWidth: 680, alignment: .leading)
                .padding()
                .frame(maxWidth: .infinity)
        }
        .id(index)      // a new chapter starts at its top
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                Button { index -= 1 } label: { Image(systemName: "chevron.left") }
                    .disabled(index == 0)
                Spacer()
                Menu(title(at: index)) {
                    ForEach(chapters.indices, id: \.self) { i in
                        Button(title(at: i)) { index = i }
                    }
                }
                Spacer()
                Button { index += 1 } label: { Image(systemName: "chevron.right") }
                    .disabled(index + 1 >= chapters.count)
            }
        }
        .task {
            chapters = EpubChapter.parse(run("chapters").output)
            index = chapters.firstIndex { $0.number == start } ?? 0
        }
        .task(id: chapters.isEmpty ? nil : chapters[index].number) {
            guard !chapters.isEmpty else { return }
            let number = chapters[index].number
            text = run("text", String(number)).output
            onPlace(number, chapters.count)
        }
    }

    private func title(at i: Int) -> String {
        guard chapters.indices.contains(i) else { return "Contents" }
        let c = chapters[i]
        return c.title.isEmpty ? "Chapter \(c.number)" : c.title
    }

    private func run(_ command: String, _ args: String...) -> RunResult {
        Engine.run(command, args: args, on: document.data, name: document.name, kind: document.kind)
    }
}

struct PDFReader: UIViewRepresentable {
    let data: Data
    var start: Int?
    var onPlace: (Int, Int) -> Void

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = PDFDocument(data: data)
        if let start, let page = view.document?.page(at: start) { view.go(to: page) }
        context.coordinator.watch(view)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPlace: onPlace) }

    final class Coordinator {
        let onPlace: (Int, Int) -> Void
        private var token: NSObjectProtocol?

        init(onPlace: @escaping (Int, Int) -> Void) { self.onPlace = onPlace }

        func watch(_ view: PDFView) {
            token = NotificationCenter.default.addObserver(forName: .PDFViewPageChanged, object: view, queue: .main) { [weak self, weak view] _ in
                guard let view, let doc = view.document, let page = view.currentPage else { return }
                self?.onPlace(doc.index(for: page), doc.pageCount)
            }
        }

        deinit { token.map(NotificationCenter.default.removeObserver) }
    }
}

/// Any other file: its bytes, as the engine's `hex` prints them.
struct HexReader: View {
    let document: AnyfileDocument

    var body: some View {
        GeometryReader { geo in
            ScrollView([.vertical, .horizontal]) {
                Text(Engine.run("hex", args: [], on: document.data, name: document.name, kind: document.kind).output)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .padding()
                    .frame(minWidth: geo.size.width, minHeight: geo.size.height, alignment: .topLeading)
            }
        }
    }
}

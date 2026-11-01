// A file opened from the shelf: one pane per kind, as ContentView chooses on the Mac. The library
// keeps where reading stopped and how each book is set, and edits to text are written back when
// the file is left.
import PDFKit
import SwiftUI

struct ReaderScreen: View {
    let url: URL
    @State private var document: AnyfileDocument?
    @State private var edited = false
    @State private var settings: ReadingSettings
    @Environment(\.scenePhase) private var phase

    init(url: URL) {
        self.url = url
        // This book's own settings, else the latest choice made for any book.
        _settings = State(initialValue: Library.shared.entry(for: url)?.settings ?? ReadingDefaults.load())
    }

    var body: some View {
        Group {
            if let document {
                ReaderView(document: Binding(get: { document }, set: { self.document = $0; edited = true }),
                           settings: $settings, start: Library.shared.entry(for: url)?.position) { position, total in
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
        .onChange(of: settings) { _, new in
            ReadingDefaults.save(new)
            Library.shared.recordSettings(url, new)
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
    @Binding var settings: ReadingSettings
    /// Where reading stopped: a chapter number for EPUB, a page index for PDF.
    var start: Int?
    var onPlace: (_ position: Int, _ total: Int) -> Void = { _, _ in }

    var body: some View {
        switch document.kind {
        case "epub":
            EpubReader(document: document, settings: $settings, start: start, onPlace: onPlace)
        case "pdf":
            PDFReader(data: document.data, start: start, onPlace: onPlace)
        case "markdown":
            MarkdownReader(document: $document)
        case "text":
            SourceEditor(text: $document.text)
        default:
            HexReader(document: document)
        }
    }
}

/// One chapter at a time, set as on the Mac. The bottom bar turns chapters and lists them all;
/// Aa sets the type, column and paper for this book.
struct EpubReader: View {
    let document: AnyfileDocument
    @Binding var settings: ReadingSettings
    var start: Int?
    var onPlace: (Int, Int) -> Void
    @State private var chapters: [EpubChapter] = []
    @State private var index = 0
    @State private var language: String?
    @State private var page = NSAttributedString()
    @State private var showSettings = false

    /// What the page is set from; a change to any of it sets the page again.
    private struct Setting: Equatable {
        let chapter: Int
        let settings: ReadingSettings
    }

    var body: some View {
        PaperText(text: page, paper: settings.palette.window, measure: settings.measure, page: index)
            .background(Color(platform: settings.palette.window))
            .toolbarBackground(Color(platform: settings.palette.window), for: .bottomBar)
            .toolbarBackground(.visible, for: .bottomBar)
            .preferredColorScheme(settings.isDark.map { $0 ? .dark : .light })
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showSettings.toggle() } label: { Text("Aa").font(.system(size: 17, design: .serif)) }
                        .accessibilityLabel("Text size, spacing, column and theme")
                        .popover(isPresented: $showSettings) {
                            TypeSettingsPanel(settings: $settings).presentationCompactAdaptation(.popover)
                        }
                }
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
                language = Cover.field("language", in: run("meta").output)
                index = chapters.firstIndex { $0.number == start } ?? 0
            }
            .task(id: chapters.isEmpty ? nil : Setting(chapter: chapters[index].number, settings: settings)) {
                guard !chapters.isEmpty else { return }
                let chapter = chapters[index]
                page = ReadingStyle.chapter(run("text", String(chapter.number)).output, number: chapter.number,
                                            title: chapter.title, language: language, settings: settings)
                onPlace(chapter.number, chapters.count)
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

/// Markdown: edit the source, or read it set as a page, as on the Mac.
struct MarkdownReader: View {
    @Binding var document: AnyfileDocument
    @State private var showPreview = false
    @State private var preview = NSAttributedString()

    var body: some View {
        Group {
            if showPreview {
                PaperText(text: preview, paper: Theme.paper.window)
            } else {
                SourceEditor(text: $document.text)
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Mode", selection: $showPreview) {
                    Text("Edit").tag(false)
                    Text("Preview").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }
        }
        .onChange(of: showPreview, initial: true) {
            if showPreview { preview = MarkdownRenderer.render(document.text) }
        }
    }
}

struct SourceEditor: View {
    @Binding var text: String

    var body: some View {
        TextEditor(text: $text)
            .font(.body.monospaced())
            .padding(.horizontal)
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

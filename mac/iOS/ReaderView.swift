// A file opened from the shelf: one pane per kind, as ContentView chooses on the Mac. The library
// keeps where reading stopped and how each book is set, and edits to text are written back when
// the file is left. A selected passage can be marked from the menu over it; the highlighter lists
// this file's marks and notes. The magnifying glass finds words in the file, and a book or a note
// can be read aloud from the top of the screen or the selection.
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

struct ReaderScreen: View {
    let url: URL
    @State private var document: AnyfileDocument?
    @State private var edited = false
    @State private var settings: ReadingSettings
    /// A mark to go to: one chosen in the library or Spotlight, then in the marks sheet.
    @State private var goTo: GoTo?
    @State private var showMarks = false
    @State private var showFind = false
    @State private var speaker = Speaker()
    @State private var handle = TextViewHandle()
    /// The chapter or page on show, so reading aloud stops when it changes.
    @State private var position: Int?
    private let markStore = MarkStore.shared
    @Environment(\.scenePhase) private var phase

    init(url: URL, goTo: GoTo? = nil) {
        self.url = url
        _goTo = State(initialValue: goTo)
        // This book's own settings, else the latest choice made for any book.
        _settings = State(initialValue: Library.shared.entry(for: url)?.settings ?? ReadingDefaults.load())
    }

    var body: some View {
        Group {
            if let document {
                ReaderView(document: Binding(get: { document }, set: { self.document = $0; edited = true }),
                           settings: $settings, start: Library.shared.entry(for: url)?.position, goTo: goTo,
                           marks: markStore.marks(for: url), onMark: { markStore.add($0, in: url, kind: document.kind) },
                           handle: handle) { position, total in
                    if position != self.position { speaker.stop() }          // reading belongs to the page it started on
                    self.position = position
                    Library.shared.recordPosition(url, position: position, total: total)
                }
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        if ["epub", "markdown"].contains(document.kind) { readAloud(document) }
                        if ["epub", "pdf", "markdown"].contains(document.kind) {
                            Button { showFind = true } label: { Image(systemName: "magnifyingglass") }
                                .accessibilityLabel("Find in this file")
                                .accessibilityIdentifier("findButton")
                        }
                        Button { showMarks = true } label: { Image(systemName: "highlighter") }
                            .accessibilityLabel("Marks and notes")
                            .accessibilityIdentifier("marksButton")
                    }
                }
                .sheet(isPresented: $showFind) {
                    FindSheet(document: document) { hit, query in
                        showFind = false
                        goTo = GoTo(target: hit.target, quote: query, serial: (goTo?.serial ?? 0) + 1)
                    }
                }
                .sheet(isPresented: $showMarks) {
                    MarksSheet(document: document, marks: markStore.marks(for: url)) { mark in
                        showMarks = false
                        goTo = GoTo(target: mark.target, quote: mark.quote, serial: (goTo?.serial ?? 0) + 1)
                    }
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
        .onDisappear {
            speaker.stop()
            save()
        }
        .onChange(of: phase) {
            if phase != .active { save() }
        }
    }

    /// Read Aloud; while reading, Pause or Resume, and Stop.
    @ViewBuilder private func readAloud(_ document: AnyfileDocument) -> some View {
        if speaker.state == .idle {
            Button {
                guard let tv = handle.textView else { return }
                let language = document.kind == "epub"
                    ? Cover.field("language", in: Engine.run("meta", args: [], on: document.data, name: document.name, kind: document.kind).output)
                    : nil
                speaker.speak(tv, from: (tv as? ColumnTextView)?.topCharacter() ?? 0, language: language)
            } label: { Image(systemName: "speaker.wave.2") }
                .accessibilityLabel("Read aloud")
                .accessibilityIdentifier("readAloud")
        } else {
            Button(action: speaker.stop) { Image(systemName: "stop.fill") }
                .accessibilityLabel("Stop reading")
                .accessibilityIdentifier("stopReading")
            Button(action: speaker.pauseOrResume) { Image(systemName: speaker.state == .paused ? "play.fill" : "pause.fill") }
                .accessibilityLabel(speaker.state == .paused ? "Resume reading" : "Pause reading")
                .accessibilityIdentifier("pauseReading")
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
    var goTo: GoTo? = nil
    var marks: [Mark] = []
    var onMark: (Selection) -> Void = { _ in }
    /// Where the page's text view is kept, for reading aloud.
    var handle: TextViewHandle? = nil
    var onPlace: (_ position: Int, _ total: Int) -> Void = { _, _ in }

    var body: some View {
        switch document.kind {
        case "epub":
            EpubReader(document: document, settings: $settings, start: start, goTo: goTo, marks: marks, onMark: onMark, handle: handle,
                       onPlace: onPlace)
        case "pdf":
            PDFReader(data: document.data, start: start, goTo: goTo, marks: marks, onMark: onMark, onPlace: onPlace)
        case "markdown":
            MarkdownReader(document: $document, goTo: goTo, marks: marks, onMark: onMark, handle: handle)
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
    var goTo: GoTo?
    var marks: [Mark]
    var onMark: (Selection) -> Void
    var handle: TextViewHandle?
    var onPlace: (Int, Int) -> Void
    @State private var chapters: [EpubChapter] = []
    @State private var index = 0
    @State private var language: String?
    @State private var page = NSAttributedString()
    /// The chapter whose text is in `page`.
    @State private var pageNumber: Int?
    @State private var showSettings = false

    /// What the page is set from; a change to any of it sets the page again.
    private struct Setting: Equatable {
        let chapter: Int
        let settings: ReadingSettings
    }

    var body: some View {
        PaperText(text: page, paper: settings.palette.window, measure: settings.measure, page: index,
                  paints: marks.filter { $0.target == pageNumber }.map(\.paint),
                  reveal: goTo?.target == pageNumber ? goTo : nil, onMark: mark(_:), handle: handle)
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
                index = chapters.firstIndex { $0.number == (goTo?.target ?? start) } ?? 0
            }
            .onChange(of: goTo) {
                if let i = chapters.firstIndex(where: { $0.number == goTo?.target }) { index = i }
            }
            .task(id: chapters.isEmpty ? nil : Setting(chapter: chapters[index].number, settings: settings)) {
                guard !chapters.isEmpty else { return }
                let chapter = chapters[index]
                page = ReadingStyle.chapter(run("text", String(chapter.number)).output, number: chapter.number,
                                            title: chapter.title, language: language, settings: settings)
                pageNumber = chapter.number
                onPlace(chapter.number, chapters.count)
            }
    }

    private func mark(_ range: NSRange) {
        guard let pageNumber, let chapter = chapters.first(where: { $0.number == pageNumber }) else { return }
        let place = chapter.title.isEmpty ? "Chapter \(chapter.number)" : chapter.title
        onMark(Selection(quote: page.attributedSubstring(from: range).string, target: chapter.number, place: place))
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
    var goTo: GoTo?
    var marks: [Mark]
    var onMark: (Selection) -> Void
    var handle: TextViewHandle?
    @State private var showPreview = false
    @State private var preview = NSAttributedString()

    var body: some View {
        Group {
            if showPreview {
                // A mark or a find is on a line of the source: its passage is looked for from there.
                PaperText(text: preview, paper: Theme.paper.window, paints: marks.map(\.paint), reveal: goTo,
                          revealFrom: goTo.flatMap { MarkdownRenderer.character(forLine: $0.target, in: preview) } ?? 0,
                          onMark: { range in
                              guard let line = MarkdownRenderer.sourceLine(at: range.location, in: preview) else { return }
                              onMark(Selection(quote: preview.attributedSubstring(from: range).string, target: line, place: "Line \(line)"))
                          }, handle: handle)
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
        .onChange(of: goTo, initial: true) {                // marks are made, and shown, in the preview
            if goTo != nil { showPreview = true }
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
    var goTo: GoTo?
    var marks: [Mark]
    var onMark: (Selection) -> Void
    var onPlace: (Int, Int) -> Void

    func makeUIView(context: Context) -> MarkingPDFView {
        let view = MarkingPDFView()
        view.accessibilityIdentifier = "pdfView"
        view.autoScales = true
        view.document = PDFDocument(data: data)
        if let start, let page = view.document?.page(at: start) { view.go(to: page) }
        context.coordinator.watch(view)
        return view
    }

    func updateUIView(_ view: MarkingPDFView, context: Context) {
        view.onMark = { selection in
            guard let doc = view.document, let page = selection.pages.first, let quote = selection.string else { return }
            let index = doc.index(for: page)
            onMark(Selection(quote: quote, target: index, place: "Page \(index + 1)"))
        }
        let shown = context.coordinator
        if marks != shown.marks {
            shown.marks = marks
            view.highlightedSelections = Self.selections(for: marks, in: view.document)
        }
        if goTo != shown.goTo {
            shown.goTo = goTo
            if let goTo, let doc = view.document, let page = doc.page(at: goTo.target) {
                view.go(to: page)
                if let match = doc.findString(goTo.quote, withOptions: .caseInsensitive).first(where: { $0.pages.contains(page) }) {
                    view.setCurrentSelection(match, animate: true)
                    view.go(to: match)
                }
            }
        }
    }

    /// Each mark found on its own page, for PDFView to paint. Nothing is written into the PDF.
    static func selections(for marks: [Mark], in doc: PDFDocument?) -> [PDFSelection] {
        guard let doc else { return [] }
        return marks.compactMap { mark in
            guard let page = doc.page(at: mark.target),
                  let found = doc.findString(mark.quote, withOptions: []).first(where: { $0.pages.contains(page) }) else { return nil }
            found.color = mark.colour.paint
            return found
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onPlace: onPlace) }

    final class Coordinator {
        let onPlace: (Int, Int) -> Void
        var marks: [Mark] = []
        var goTo: GoTo?
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

/// A PDFView whose menu over selected text offers Mark.
final class MarkingPDFView: PDFView {
    var onMark: (PDFSelection) -> Void = { _ in }

    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)
        guard builder.system == .context, let selection = currentSelection, !(selection.string ?? "").isEmpty else { return }
        let mark = UIAction(title: "Mark", image: UIImage(systemName: "highlighter")) { [weak self] _ in self?.onMark(selection) }
        builder.insertSibling(UIMenu(options: .displayInline, children: [mark]), beforeMenu: .standardEdit)
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

/// This file's marks, in reading order: choose one to go to it, colour it, note it or remove it.
/// Export shares them as a Markdown file, as the Mac saves them.
struct MarksSheet: View {
    let document: AnyfileDocument
    let marks: [Mark]
    let choose: (Mark) -> Void
    private let store = MarkStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(marks) { mark in
                        MarkRow(mark: mark, choose: { choose(mark) }, remove: { store.remove(mark) },
                                setNote: { store.setNote($0, for: mark) }, setColour: { store.setColour($0, for: mark) })
                        Divider()
                    }
                }
                .padding(.horizontal)
            }
            .overlay {
                if marks.isEmpty {
                    ContentUnavailableView("Nothing marked yet", systemImage: "highlighter",
                                           description: Text("Select a passage and choose Mark from the menu over it."))
                }
            }
            .navigationTitle("Marks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                if !marks.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        let heading = MarkExport.heading(for: document.data, name: document.name, kind: document.kind)
                        let file = MarksFile(name: MarkExport.suggestedName(for: heading.title),
                                             text: MarkExport.markdown(title: heading.title, author: heading.author, marks: marks))
                        ShareLink(item: file, preview: SharePreview(file.name)) { Image(systemName: "square.and.arrow.up") }
                            .accessibilityLabel("Export marks")
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Exported marks: a Markdown file for Files and other apps, plain text for ones that take only text.
struct MarksFile: Transferable {
    let name: String
    let text: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: UTType("net.daringfireball.markdown") ?? .plainText) { file in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(file.name)
            try file.text.write(to: url, atomically: true, encoding: .utf8)
            return SentTransferredFile(url)
        }
        ProxyRepresentation(exporting: \.text)
    }
}

/// Find in this file: every match, with its place and the line around it. Choosing one goes there.
struct FindSheet: View {
    let document: AnyfileDocument
    let choose: (FindHit, String) -> Void
    @State private var query = ""
    @State private var hits: [FindHit] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(hits) { hit in
                Button { choose(hit, query) } label: { HitRow(hit: hit) }
                    .accessibilityIdentifier("hit.\(hit.id)")
            }
            .listStyle(.plain)
            .overlay {
                if !query.isEmpty, hits.isEmpty { ContentUnavailableView.search(text: query) }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Find in this file")
            .navigationTitle("Find")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task(id: query) {
                try? await Task.sleep(for: .milliseconds(200))              // a word typed, not each letter
                guard !Task.isCancelled else { return }
                let q = query, d = document
                hits = await Task.detached(priority: .userInitiated) { Find.hits(for: q, in: d) }.value
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// A match: the line around it, and where it is.
struct HitRow: View {
    let hit: FindHit

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(hit.snippet).font(.system(size: 15, design: .serif)).lineLimit(2).foregroundStyle(.primary)
            Text(hit.place).font(.caption).foregroundStyle(.secondary)
        }
    }
}

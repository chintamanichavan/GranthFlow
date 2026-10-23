// One window per document: the content pane for its kind, Contents beside it, the action bar below.
import SwiftUI

struct ContentView: View {
    @Binding var document: AnyfileDocument
    /// Where the file lives, so the library can remember it; nil until an untitled file is saved.
    var fileURL: URL?
    @Environment(\.undoManager) private var undoManager
    @State private var active: DocumentAction?
    @State private var entries: [ContentsEntry] = []
    @State private var jump: Jump?
    @State private var chapter: Int?            // EPUB shows one chapter at a time
    @State private var selection: Selection?
    @State private var markStatus = ""
    /// Where reading stopped inside the saved chapter, applied when that chapter first appears.
    @State private var resume: (chapter: Int, anchor: Int)?
    @State private var wordsLeft: Int?
    @State private var chapterTotal = 0
    @State private var settings = ReadingSettings()
    @State private var showSettings = false
    private let markStore = MarkStore.shared

    /// The place reading stopped is restored here, before any pane appears: the EPUB pane picks
    /// chapter 1 when it finds none, and that would be recorded over the saved place.
    init(document: Binding<AnyfileDocument>, fileURL: URL? = nil) {
        _document = document
        self.fileURL = fileURL
        // This book's own settings, else the latest choice made for any book.
        let saved = fileURL.flatMap { Library.shared.entry(for: $0)?.settings }
        _settings = State(initialValue: saved ?? ReadingDefaults.load())
        guard let fileURL, let position = Library.shared.entry(for: fileURL)?.position else { return }
        switch document.wrappedValue.kind {
        case "epub":
            _chapter = State(initialValue: position)
            if let anchor = Library.shared.entry(for: fileURL)?.anchor { _resume = State(initialValue: (position, anchor)) }
        case "pdf": _jump = State(initialValue: Jump(target: position, serial: 1))
        default: break
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            if active == .contents {
                ContentsPanel(entries: entries, current: document.kind == "epub" ? chapter : jump?.target, choose: { go(to: $0) })
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.primary.opacity(0.08)))
                    .padding([.leading, .top, .bottom], 12)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            pane
        }
        .frame(minWidth: 640, minHeight: 480)
        .background(Color(nsColor: ground))
        .modifier(Night(on: !["pdf", "epub", "markdown", "text"].contains(document.kind) || (document.kind == "epub" && settings.isDark == true)))
        .onChange(of: settings) { _, new in
            ReadingDefaults.save(new)
            if let fileURL { Library.shared.recordSettings(fileURL, new) }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 10) {
                if let panel = activePanel {
                    panel
                        .frame(maxWidth: 620)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.primary.opacity(0.08)))
                        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                ActionBar(active: $active, kind: document.kind)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .animation(.snappy(duration: 0.2), value: active)
        }
        .onExitCommand { active = nil }
        .onAppear(perform: remember)
        .onChange(of: active) { _, now in if now == .mark { markSelection() } }
        .onChange(of: Navigator.shared.pending) { followRequest() }
        .onChange(of: fileURL) { remember() }
        .onChange(of: chapter) { _, chapter in
            guard let fileURL, let chapter else { return }
            Library.shared.recordPosition(fileURL, position: chapter, total: chapterCount)
        }
        .onChange(of: active) { _, now in if now == .contents { entries = Contents.entries(for: document) } }
        .onChange(of: document.data) { if active == .contents { entries = Contents.entries(for: document) } }
        .toolbar {
            if document.kind == "epub" {
                ToolbarItem(placement: .primaryAction) {
                    Button { showSettings.toggle() } label: { Text("Aa").font(.system(size: 14, design: .serif)) }
                        .help("Text size, spacing, column and theme")
                        .accessibilityIdentifier("typeSettings")
                        .popover(isPresented: $showSettings, arrowEdge: .bottom) { TypeSettingsPanel(settings: $settings) }
                }
            }
            ToolbarItem(placement: .status) {
                Text(status)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("kindLabel")
            }
        }
    }

    @ViewBuilder private var pane: some View {
        switch document.kind {
        case "pdf": PdfPane(document: document, jump: jump, onPage: { page, count in
            if let fileURL { Library.shared.recordPosition(fileURL, position: page, total: count) }
        }, marks: marks, onSelect: { selection = $0 })
        case "epub": EpubPane(document: document, chapter: $chapter, find: jump,
                              marks: marks.filter { $0.target == chapter }.map(\.quote), onSelect: { selection = $0 },
                              resume: resume?.chapter == chapter ? resume?.anchor : nil,
                              onPlace: reached, settings: settings)
        case "markdown": MarkdownPane(document: $document, jump: jump, marks: marks.map(\.quote), onSelect: { selection = $0 })
        case "text": TextPane(text: $document.text, jump: jump, marks: marks.map(\.quote), onSelect: { selection = $0 })
        default: HexPane(document: document, jump: jump)
        }
    }

    /// What shows behind the bar: paper for things you read, the system's grey around PDF pages,
    /// and the night of a program's cover for bytes.
    private var ground: NSColor {
        switch document.kind {
        case "pdf": .underPageBackgroundColor
        case "epub": settings.palette.window
        case "markdown", "text": Theme.paper.window
        default: Theme.night.window
        }
    }

    private var activePanel: AnyView? {
        switch active {
        case .info:
            AnyView(CommandPanel(title: "Info", commands: CommandRole.infoCommands(for: document.kind),
                                 document: $document, runsImmediately: true, onApply: apply).id("info-\(document.kind)"))
        case .edit:
            AnyView(CommandPanel(title: "Edit", commands: CommandRole.editCommands(for: document.kind),
                                 document: $document, runsImmediately: false, onApply: apply).id("edit-\(document.kind)"))
        case .mark:
            AnyView(MarkPanel(marks: marks, status: markStatus, choose: { go(to: $0.target, query: $0.quote) },
                              remove: { markStore.remove($0) }, setNote: { markStore.setNote($1, for: $0) }))
        case .find:
            AnyView(FindPanel(document: document) { hit, query in go(to: hit.target, query: query) }.id("find-\(document.kind)"))
        default:
            nil
        }
    }

    /// The title bar's line: the chapter and the time left in it for a book, kind and size otherwise.
    private var status: String {
        if document.kind == "epub", let chapter, chapterTotal > 0 {
            let place = "Chapter \(chapter) of \(chapterTotal)"
            guard let wordsLeft else { return place }
            return place + "  ·  " + ReadingTime.phrase(wordsLeft: wordsLeft, wordsPerMinute: ReadingClock.shared.speed.wordsPerMinute)
        }
        return "\(document.kind)  ·  \(ByteCountFormatter.string(fromByteCount: Int64(document.data.count), countStyle: .file))"
    }

    /// A new reading place in a book: remembered, and timed to learn the reader's speed.
    private func reached(_ anchor: Int, _ words: Int) {
        wordsLeft = words
        guard let fileURL, let chapter else { return }
        Library.shared.recordAnchor(fileURL, anchor: anchor, wordsLeft: words)
        ReadingClock.shared.place(book: fileURL.path, chapter: chapter, wordsLeft: words)
    }

    private func remember() {
        if document.kind == "epub", chapterTotal == 0 { chapterTotal = chapterCount }
        if let fileURL { Library.shared.recordOpened(fileURL, kind: document.kind) }
        followRequest()
    }

    private var marks: [Mark] { fileURL.map(markStore.marks(for:)) ?? [] }

    /// Pressing Mark keeps whatever is selected and says so; with nothing selected it says how.
    private func markSelection() {
        guard let fileURL else { markStatus = "Save the file to keep marks"; return }
        guard let selection else { markStatus = MarkHint.text(kind: document.kind); return }
        if let mark = markStore.add(selection, in: fileURL, kind: document.kind) {
            markStatus = "Marked · \(mark.place)"
        }
    }

    /// A mark or search result chosen in the library goes to its place once this window shows that file.
    private func followRequest() {
        guard let fileURL, let request = Navigator.shared.take(for: fileURL) else { return }
        go(to: request.target, query: request.query)
    }

    private var chapterCount: Int {
        EpubChapter.parse(Engine.run("chapters", args: [], on: document.data, name: document.name, kind: document.kind).output).count
    }

    /// Contents passes a target; Find also passes the query, so the pane can select the match.
    private func go(to target: Int, query: String? = nil) {
        if document.kind == "epub" { chapter = target }
        if document.kind != "epub" || query != nil { jump = (jump ?? Jump(target: target, serial: 0)).next(target, query: query) }
    }

    /// Replaces the document bytes with a command's result, with undo.
    private func apply(_ result: RunResult) {
        guard let changed = result.changedData else { return }
        let before = document.data
        document.data = changed
        undoManager?.registerUndo(withTarget: UndoProxy.shared) { _ in
            self.document.data = before
        }
        undoManager?.setActionName("Run \(result.output.split(separator: " ").first ?? "command")")
    }
}

/// NSUndoManager needs an object target; the real state lives in the SwiftUI binding.
final class UndoProxy: NSObject { static let shared = UndoProxy() }

/// Bytes sit on a dark ground in light mode too, so the bar and cards over them go dark with it.
private struct Night: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        if on { content.environment(\.colorScheme, .dark) } else { content }
    }
}

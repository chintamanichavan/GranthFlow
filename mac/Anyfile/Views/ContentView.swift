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

    /// The place reading stopped is restored here, before any pane appears: the EPUB pane picks
    /// chapter 1 when it finds none, and that would be recorded over the saved place.
    init(document: Binding<AnyfileDocument>, fileURL: URL? = nil) {
        _document = document
        self.fileURL = fileURL
        guard let fileURL, let position = Library.shared.entry(for: fileURL)?.position else { return }
        switch document.wrappedValue.kind {
        case "epub": _chapter = State(initialValue: position)
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
        .onChange(of: fileURL) { remember() }
        .onChange(of: chapter) { _, chapter in
            guard let fileURL, let chapter else { return }
            Library.shared.recordPosition(fileURL, position: chapter, total: chapterCount)
        }
        .onChange(of: active) { _, now in if now == .contents { entries = Contents.entries(for: document) } }
        .onChange(of: document.data) { if active == .contents { entries = Contents.entries(for: document) } }
        .toolbar {
            ToolbarItem(placement: .status) {
                Text("\(document.kind)  ·  \(ByteCountFormatter.string(fromByteCount: Int64(document.data.count), countStyle: .file))")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("kindLabel")
            }
        }
    }

    @ViewBuilder private var pane: some View {
        switch document.kind {
        case "pdf": PdfPane(document: document, jump: jump) { page, count in
            if let fileURL { Library.shared.recordPosition(fileURL, position: page, total: count) }
        }
        case "epub": EpubPane(document: document, chapter: $chapter, find: jump)
        case "markdown": MarkdownPane(document: $document, jump: jump)
        case "text": TextPane(text: $document.text, jump: jump)
        default: HexPane(document: document, jump: jump)
        }
    }

    /// What shows behind the bar: paper for things you read, the system's grey around PDF pages.
    private var ground: NSColor {
        document.kind == "pdf" ? .underPageBackgroundColor : Theme.paper.window
    }

    private var activePanel: AnyView? {
        switch active {
        case .info:
            AnyView(CommandPanel(title: "Info", commands: CommandRole.infoCommands(for: document.kind),
                                 document: $document, runsImmediately: true, onApply: apply).id("info-\(document.kind)"))
        case .edit:
            AnyView(CommandPanel(title: "Edit", commands: CommandRole.editCommands(for: document.kind),
                                 document: $document, runsImmediately: false, onApply: apply).id("edit-\(document.kind)"))
        case .find:
            AnyView(FindPanel(document: document) { hit, query in go(to: hit.target, query: query) }.id("find-\(document.kind)"))
        default:
            nil
        }
    }

    private func remember() {
        if let fileURL { Library.shared.recordOpened(fileURL, kind: document.kind) }
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

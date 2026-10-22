// EPUB: one chapter at a time on paper. Contents chooses the chapter; the engine supplies the text.
import SwiftUI
import AppKit

struct EpubChapter: Identifiable, Hashable {
    let number: Int      // 1-based, as the engine's commands expect
    let title: String
    let path: String
    var id: Int { number }

    /// Parses the engine's `chapters` output: one "number<TAB>title<TAB>path" line per chapter.
    static func parse(_ output: String) -> [EpubChapter] {
        output.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard fields.count == 3, let number = Int(fields[0]) else { return nil }
            return EpubChapter(number: number, title: String(fields[1]), path: String(fields[2]))
        }
    }
}

struct EpubPane: View {
    let document: AnyfileDocument
    /// The chapter number on show. Contents sets it; the pane picks the first chapter when it is nil or gone.
    @Binding var chapter: Int?
    /// A Find jump: its query is selected once the chapter's text is on show.
    var find: Jump? = nil
    @State private var text = ""
    @State private var title = ""
    @State private var loaded: Int?                 // the chapter whose text is in `text`
    @State private var titles: [Int: String] = [:]

    var body: some View {
        ReadingText(text: text, number: loaded, title: title, find: find?.target == loaded ? find : nil)
            .frame(minWidth: 320)
            .onAppear { reload() }
            .onChange(of: document.data) { reload() }      // a command changed the book
            .onChange(of: chapter) { loadText() }
    }

    private func reload() {
        let r = Engine.run("chapters", args: [], on: document.data, name: document.name, kind: document.kind)
        let chapters = EpubChapter.parse(r.output)
        titles = Dictionary(chapters.map { ($0.number, $0.title) }, uniquingKeysWith: { a, _ in a })
        if chapters.isEmpty { text = r.errorText.isEmpty ? "(this book lists no chapters)" : r.errorText }
        if chapter == nil || !chapters.contains(where: { $0.number == chapter }) { chapter = chapters.first?.number }
        loadText()
    }

    private func loadText() {
        guard let chapter else { return }
        let r = Engine.run("text", args: [String(chapter)], on: document.data, name: document.name, kind: document.kind)
        text = r.succeeded ? (r.output.isEmpty ? "(no text in this chapter)" : r.output) : r.errorText
        title = titles[chapter] ?? ""
        loaded = chapter
    }
}

/// Read-only chapter text on paper. AppKit, because it stays fast on chapter-sized strings and SwiftUI's Text does not.
struct ReadingText: NSViewRepresentable {
    let text: String
    var number: Int? = nil
    var title: String = ""
    var find: Jump? = nil

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = true
        scroll.backgroundColor = Theme.paper.window
        let tv = PaperTextView()
        tv.minSize = .zero
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.isEditable = false
        tv.isRichText = false
        tv.drawsBackground = true
        tv.backgroundColor = Theme.paper.window
        tv.selectedTextAttributes = [.backgroundColor: Theme.mark.withAlphaComponent(0.55)]
        tv.setAccessibilityIdentifier("epubText")
        scroll.documentView = tv
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let tv = scroll.documentView as! NSTextView
        let shown = [String(number ?? 0), title, text]
        if context.coordinator.shown != shown {
            context.coordinator.shown = shown
            tv.textStorage?.setAttributedString(ReadingStyle.chapter(text, number: number, title: title))
            tv.scrollToBeginningOfDocument(nil)
        }
        // The chapter's text can arrive one update after the jump, so a jump whose query is not
        // in the text yet stays pending instead of being used up.
        if let find, find != context.coordinator.lastFind, let query = find.query {
            let r = (tv.string as NSString).range(of: query, options: .caseInsensitive)
            if r.location != NSNotFound {
                context.coordinator.lastFind = find
                tv.setSelectedRange(r)
                tv.scrollRangeToVisible(r)
                tv.showFindIndicator(for: r)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator {
        var lastFind: Jump?
        var shown: [String] = []
    }
}

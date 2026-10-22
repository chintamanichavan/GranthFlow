// EPUB: one chapter at a time, full width. Contents chooses the chapter; the engine supplies the text.
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
    @State private var loaded: Int?                 // the chapter whose text is in `text`

    var body: some View {
        ReadingText(text: text, find: find?.target == loaded ? find : nil)
            .frame(minWidth: 320)
            .onAppear { reload() }
            .onChange(of: document.data) { reload() }      // a command changed the book
            .onChange(of: chapter) { loadText() }
    }

    private func reload() {
        let r = Engine.run("chapters", args: [], on: document.data, name: document.name, kind: document.kind)
        let chapters = EpubChapter.parse(r.output)
        if chapters.isEmpty { text = r.errorText.isEmpty ? "(this book lists no chapters)" : r.errorText }
        if chapter == nil || !chapters.contains(where: { $0.number == chapter }) { chapter = chapters.first?.number }
        loadText()
    }

    private func loadText() {
        guard let chapter else { return }
        let r = Engine.run("text", args: [String(chapter)], on: document.data, name: document.name, kind: document.kind)
        text = r.succeeded ? (r.output.isEmpty ? "(no text in this chapter)" : r.output) : r.errorText
        loaded = chapter
    }
}

/// Read-only text that stays fast on chapter-sized strings, which SwiftUI's Text does not.
struct ReadingText: NSViewRepresentable {
    let text: String
    var find: Jump? = nil

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let tv = scroll.documentView as! NSTextView
        tv.isEditable = false
        tv.isRichText = false
        tv.font = NSFont(name: "Charter", size: 15) ?? NSFont.systemFont(ofSize: 15)
        tv.textContainerInset = NSSize(width: 24, height: 20)
        tv.setAccessibilityIdentifier("epubText")
        tv.string = text
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let tv = scroll.documentView as! NSTextView
        if tv.string != text {
            tv.string = text
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
    final class Coordinator { var lastFind: Jump? }
}

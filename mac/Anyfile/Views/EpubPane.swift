// EPUB: the chapter list on the left, the selected chapter's text on the right. Both come from the engine.
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
    @State private var chapters: [EpubChapter] = []
    @State private var selection: Int?
    @State private var text = ""

    var body: some View {
        HSplitView {
            List(chapters, selection: $selection) { chapter in
                Text(chapter.title)
                    .lineLimit(2)
                    .help(chapter.path)
            }
            .frame(minWidth: 160, idealWidth: 220, maxWidth: 360)
            .accessibilityIdentifier("epubChapters")
            ReadingText(text: text)
                .frame(minWidth: 320)
        }
        .onAppear { reload() }
        .onChange(of: document.data) { reload() }      // a command changed the book
        .onChange(of: selection) { loadText() }
    }

    private func reload() {
        let r = Engine.run("chapters", args: [], on: document.data, name: document.name, kind: document.kind)
        chapters = EpubChapter.parse(r.output)
        if chapters.isEmpty { text = r.errorText.isEmpty ? "(this book lists no chapters)" : r.errorText }
        if selection == nil || !chapters.contains(where: { $0.number == selection }) { selection = chapters.first?.number }
        loadText()
    }

    private func loadText() {
        guard let selection else { return }
        let r = Engine.run("text", args: [String(selection)], on: document.data, name: document.name, kind: document.kind)
        text = r.succeeded ? (r.output.isEmpty ? "(no text in this chapter)" : r.output) : r.errorText
    }
}

/// Read-only text that stays fast on chapter-sized strings, which SwiftUI's Text does not.
struct ReadingText: NSViewRepresentable {
    let text: String

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
        guard tv.string != text else { return }
        tv.string = text
        tv.scrollToBeginningOfDocument(nil)
    }
}

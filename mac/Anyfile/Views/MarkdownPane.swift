// Markdown: edit the source, or read it set as a page. The preview is an AppKit text view, like a
// book's, so a passage selected in it can be marked; every line of it knows its line in the source.
import SwiftUI
import AppKit

struct MarkdownPane: View {
    @Binding var document: AnyfileDocument
    /// A heading's line number from Contents, followed in both modes.
    var jump: Jump? = nil
    var marks: [Paint] = []
    var onSelect: (Selection?) -> Void = { _ in }
    var handle: TextViewHandle? = nil
    @State private var showPreview = false

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $showPreview) {
                Text("Edit").tag(false)
                Text("Preview").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 180)
            .padding(6)
            .accessibilityIdentifier("markdownMode")
            .onChange(of: showPreview) { onSelect(nil) }               // a selection belongs to the mode it was made in
            Divider()
            if showPreview {
                MarkdownPreview(source: document.text, jump: jump, marks: marks, onSelect: onSelect, handle: handle)
            } else {
                TextPane(text: $document.text, jump: jump, marks: marks, onSelect: onSelect, handle: handle)
            }
        }
    }
}

/// The preview as a page: the reading view's column and paper, selectable, painted with marks.
struct MarkdownPreview: NSViewRepresentable {
    let source: String
    var jump: Jump?
    var marks: [Paint]
    var onSelect: (Selection?) -> Void
    var handle: TextViewHandle? = nil

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = ReadingText.makePage()
        let tv = scroll.documentView as! PaperTextView
        tv.setAccessibilityIdentifier("markdownPreview")
        handle?.textView = tv
        tv.delegate = context.coordinator
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let tv = scroll.documentView as! NSTextView
        context.coordinator.onSelect = onSelect
        if context.coordinator.source != source {
            context.coordinator.source = source
            tv.textStorage?.setAttributedString(MarkdownRenderer.render(source))
            context.coordinator.marks = nil
        }
        if marks != context.coordinator.marks {
            context.coordinator.marks = marks
            Highlights.apply(marks, to: tv)
        }
        if jump != context.coordinator.jump {
            context.coordinator.jump = jump
            if let jump, let storage = tv.textStorage, let c = MarkdownRenderer.character(forLine: jump.target, in: storage) {
                ReadingPlace.scroll(tv, toCharacter: c)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var source: String?
        var marks: [Paint]?
        var jump: Jump?
        var onSelect: (Selection?) -> Void = { _ in }

        func textView(_ view: NSTextView, menu: NSMenu, for event: NSEvent, at charIndex: Int) -> NSMenu? {
            LookUp.addItem(to: menu, in: view, at: charIndex)
        }

        /// A selection in the preview becomes a mark on the source line it starts on.
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView, let storage = tv.textStorage else { return }
            let r = tv.selectedRange()
            let report = onSelect
            guard r.length > 0, let line = MarkdownRenderer.sourceLine(at: r.location, in: storage) else { return Later.report { report(nil) } }
            let selection = Selection(quote: (tv.string as NSString).substring(with: r), target: line, place: "Line \(line)")
            Later.report { report(selection) }
        }
    }
}

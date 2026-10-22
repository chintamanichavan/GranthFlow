// Editable plain text on top of NSTextView; the document bytes follow every keystroke.
import SwiftUI
import AppKit

struct TextPane: NSViewRepresentable {
    @Binding var text: String
    /// A 1-based line to bring into view and select, once per jump.
    var jump: Jump? = nil

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let tv = scroll.documentView as! NSTextView
        tv.isRichText = false
        tv.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.allowsUndo = true
        tv.delegate = context.coordinator
        tv.setAccessibilityIdentifier("textEditor")
        tv.string = text
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let tv = scroll.documentView as! NSTextView
        if tv.string != text {
            let sel = tv.selectedRanges
            tv.string = text
            tv.selectedRanges = sel.filter { ($0.rangeValue.location + $0.rangeValue.length) <= tv.string.utf16.count }
        }
        if jump != context.coordinator.lastJump {
            context.coordinator.lastJump = jump
            if let jump, let range = Self.range(ofLine: jump.target, in: tv.string) {
                tv.setSelectedRange(range)
                tv.scrollRangeToVisible(range)
                tv.window?.makeFirstResponder(tv)           // so typing goes to the place just chosen
            }
        }
    }

    /// The UTF-16 range of a 1-based line, without its newline, or nil past the end.
    static func range(ofLine line: Int, in text: String) -> NSRange? {
        guard line >= 1 else { return nil }
        let ns = text as NSString
        var start = 0, current = 1
        while current < line {
            let next = ns.range(of: "\n", range: NSRange(location: start, length: ns.length - start))
            if next.location == NSNotFound { return nil }
            start = next.location + 1
            current += 1
        }
        let end = ns.range(of: "\n", range: NSRange(location: start, length: ns.length - start))
        return NSRange(location: start, length: (end.location == NSNotFound ? ns.length : end.location) - start)
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var lastJump: Jump?
        init(text: Binding<String>) { self.text = text }
        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            text.wrappedValue = tv.string
        }
    }
}

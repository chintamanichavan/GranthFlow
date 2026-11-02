// A page of set text, as the Mac's PaperTextView shows it: read-only, selectable, a column kept
// to the reader's measure on the reader's paper. Marked passages are painted in their colours, and
// the menu over a selection offers Mark.
import SwiftUI
import UIKit

/// A place to go in a file: a chapter, page or line, and the passage there to show. The serial
/// makes going to the same passage twice a new request.
struct GoTo: Equatable, Hashable {
    let target: Int
    let quote: String
    var serial = 0
}

struct PaperText: UIViewRepresentable {
    let text: NSAttributedString
    let paper: UIColor
    var measure: CGFloat = ReadingStyle.measure
    /// Changes when the text should start again from its top, as for a new chapter. While it stays
    /// the same, new text (other settings, a new mark) keeps the passage that was at the top of the screen.
    var page: Int = 0
    var paints: [Paint] = []
    /// A passage to bring into view and select, once text holding it is shown: its first
    /// occurrence, in any case, from `revealFrom` on.
    var reveal: GoTo? = nil
    var revealFrom = 0
    /// Mark, in the menu over a selection, with the selected range; nil leaves it out.
    var onMark: ((NSRange) -> Void)? = nil
    /// Where the reader keeps this view, to read it aloud.
    var handle: TextViewHandle? = nil

    func makeUIView(context: Context) -> ColumnTextView {
        let tv = ColumnTextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.textContainer.lineFragmentPadding = 0
        tv.dataDetectorTypes = .link
        tv.delegate = context.coordinator
        tv.accessibilityIdentifier = "paperText"
        return tv
    }

    func updateUIView(_ tv: ColumnTextView, context: Context) {
        tv.backgroundColor = paper
        tv.measure = measure
        handle?.textView = tv
        let shown = context.coordinator
        shown.onMark = onMark
        if shown.text !== text || shown.page != page || shown.paints != paints {
            let keep = shown.page == page ? tv.topCharacter() : nil
            tv.attributedText = Highlights.painted(text, with: paints, dark: Self.isDark(paper.resolvedColor(with: tv.traitCollection)))
            tv.layoutIfNeeded()
            if let keep { tv.scroll(toCharacter: keep) } else { tv.setContentOffset(CGPoint(x: 0, y: -tv.adjustedContentInset.top), animated: false) }
            shown.text = text
            shown.page = page
            shown.paints = paints
        }
        if let reveal, reveal != shown.reveal {
            let ns = tv.text as NSString
            let from = min(revealFrom, ns.length)
            let r = ns.range(of: reveal.quote, options: .caseInsensitive, range: NSRange(location: from, length: ns.length - from))
            if r.location != NSNotFound {                    // else the text holding it is not on show yet
                tv.scroll(toCharacter: r.location)
                tv.selectedRange = r
                shown.reveal = reveal
            }
        }
    }

    static func isDark(_ colour: UIColor) -> Bool {
        var brightness: CGFloat = 1
        colour.getHue(nil, saturation: nil, brightness: &brightness, alpha: nil)
        return brightness < 0.4
    }

    func makeCoordinator() -> Shown { Shown() }

    final class Shown: NSObject, UITextViewDelegate {
        var text: NSAttributedString?
        var page = 0
        var paints: [Paint] = []
        var reveal: GoTo?
        var onMark: ((NSRange) -> Void)?

        func textView(_ textView: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
            guard let onMark, range.length > 0 else { return nil }
            let mark = UIAction(title: "Mark", image: UIImage(systemName: "highlighter")) { _ in onMark(range) }
            return UIMenu(children: [mark] + suggestedActions)
        }
    }
}

extension Highlights {
    /// The text with every occurrence of each marked quote given its colour as a background.
    static func painted(_ text: NSAttributedString, with paints: [Paint], dark: Bool) -> NSAttributedString {
        guard paints.contains(where: { !$0.quote.isEmpty }) else { return text }
        let out = NSMutableAttributedString(attributedString: text)
        let ns = out.string as NSString
        let alpha = strength(onDark: dark)
        for paint in paints where !paint.quote.isEmpty {
            for r in ranges(of: paint.quote, in: ns) {
                out.addAttribute(.backgroundColor, value: paint.colour.paint.withAlphaComponent(alpha), range: r)
            }
        }
        return out
    }
}

final class ColumnTextView: UITextView {
    var measure: CGFloat = ReadingStyle.measure {
        didSet { if measure != oldValue { setNeedsLayout() } }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // A phone is narrower than the measure; its margins are kept smaller than the Mac's 32.
        let side = max(20, (bounds.width - measure) / 2)
        let inset = UIEdgeInsets(top: 28, left: side, bottom: 48, right: side)
        if textContainerInset != inset { textContainerInset = inset }
    }

    /// The first character at the top of the screen.
    func topCharacter() -> Int {
        let point = CGPoint(x: textContainerInset.left + 2, y: contentOffset.y + adjustedContentInset.top + 2)
        guard let position = closestPosition(to: point) else { return 0 }
        return offset(from: beginningOfDocument, to: position)
    }

    func scroll(toCharacter character: Int) {
        guard let position = self.position(from: beginningOfDocument, offset: min(character, textStorage.length)) else { return }
        let y = caretRect(for: position).minY - 2 - adjustedContentInset.top
        let bottom = max(-adjustedContentInset.top, contentSize.height - bounds.height + adjustedContentInset.bottom)
        setContentOffset(CGPoint(x: 0, y: min(max(y, -adjustedContentInset.top), bottom)), animated: false)
    }
}

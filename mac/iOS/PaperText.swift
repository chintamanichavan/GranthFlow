// A page of set text, as the Mac's PaperTextView shows it: read-only, selectable, a column kept
// to the reader's measure on the reader's paper.
import SwiftUI
import UIKit

struct PaperText: UIViewRepresentable {
    let text: NSAttributedString
    let paper: UIColor
    var measure: CGFloat = ReadingStyle.measure
    /// Changes when the text should start again from its top, as for a new chapter. While it stays
    /// the same, new text (other settings) keeps the passage that was at the top of the screen.
    var page: Int = 0

    func makeUIView(context: Context) -> ColumnTextView {
        let tv = ColumnTextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.textContainer.lineFragmentPadding = 0
        tv.dataDetectorTypes = .link
        return tv
    }

    func updateUIView(_ tv: ColumnTextView, context: Context) {
        tv.backgroundColor = paper
        tv.measure = measure
        let shown = context.coordinator
        guard shown.text !== text || shown.page != page else { return }
        let keep = shown.page == page ? tv.topCharacter() : nil
        tv.attributedText = text
        tv.layoutIfNeeded()
        if let keep { tv.scroll(toCharacter: keep) } else { tv.setContentOffset(CGPoint(x: 0, y: -tv.adjustedContentInset.top), animated: false) }
        shown.text = text
        shown.page = page
    }

    func makeCoordinator() -> Shown { Shown() }

    final class Shown {
        var text: NSAttributedString?
        var page = 0
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

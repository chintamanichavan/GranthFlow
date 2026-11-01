// How reading text is set: a centred column of serif type on paper, with the chapter's
// number and title above it, as in the design's reading window.
import AppKit

/// Where reading is in a text view, as a character, and back again.
enum ReadingPlace {
    /// The first character at the top of the visible part of the text.
    static func topCharacter(in tv: NSTextView) -> Int {
        guard let lm = tv.layoutManager, let tc = tv.textContainer, tv.textStorage?.length ?? 0 > 0 else { return 0 }
        // A point just inside the top-left of what is visible, in the text container's coordinates.
        let point = NSPoint(x: 2, y: tv.visibleRect.minY - tv.textContainerOrigin.y + 2)
        let glyph = lm.glyphIndex(for: point, in: tc)
        return lm.characterIndexForGlyph(at: glyph)
    }

    /// Scrolls so the line holding `character` is at the top.
    static func scroll(_ tv: NSTextView, toCharacter character: Int) {
        guard let lm = tv.layoutManager else { return }
        let length = tv.textStorage?.length ?? 0
        guard length > 0 else { return }
        let c = min(max(character, 0), length - 1)
        lm.ensureLayout(forCharacterRange: NSRange(location: 0, length: c + 1))
        let glyphs = lm.glyphRange(forCharacterRange: NSRange(location: c, length: 1), actualCharacterRange: nil)
        let line = lm.lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
        tv.scroll(NSPoint(x: 0, y: max(0, line.minY + tv.textContainerOrigin.y - 2)))
    }
}

/// A text view that keeps its column centred and no wider than the reading measure, and turns
/// pages from the keyboard: the arrow keys, or Space, which scrolls and turns once the end is in view.
final class PaperTextView: NSTextView {
    var onTurn: ((Int) -> Void)?
    /// The widest the column grows, from the reader's settings.
    var measure: CGFloat = ReadingStyle.measure {
        didSet { if measure != oldValue { setFrameSize(frame.size) } }
    }

    override func keyDown(with event: NSEvent) {
        let plain = event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
        switch (event.keyCode, plain) {
        case (124, true): onTurn?(1)                                       // →
        case (123, true): onTurn?(-1)                                      // ←
        case (49, true) where Self.atEnd(visibleRect, bounds): onTurn?(1)  // Space at the end of the chapter
        case (49, true): scrollPageDown(nil)                               // Space elsewhere: down a screen, as in Books
        default: super.keyDown(with: event)
        }
    }

    /// True when the bottom of the text is in view.
    static func atEnd(_ visible: NSRect, _ bounds: NSRect) -> Bool { visible.maxY >= bounds.maxY - 2 }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        let inset = ReadingStyle.sideInset(forWidth: newSize.width, measure: measure)
        if textContainerInset.width != inset { textContainerInset = NSSize(width: inset, height: 48) }
    }
}

enum Highlights {
    /// Paints every occurrence of each marked quote in its colour. Temporary attributes, so the
    /// highlight is drawn but never becomes part of the text. On dark paper the colour is laid on
    /// lighter, so the light text over it stays readable.
    static func apply(_ paints: [Paint], to tv: NSTextView) {
        guard let lm = tv.layoutManager else { return }
        let ns = tv.string as NSString
        lm.removeTemporaryAttribute(.backgroundColor, forCharacterRange: NSRange(location: 0, length: ns.length))
        let strength = isDark(tv.backgroundColor) ? 0.38 : 0.7
        for paint in paints where !paint.quote.isEmpty {
            for r in ranges(of: paint.quote, in: ns) {
                lm.addTemporaryAttribute(.backgroundColor, value: paint.colour.paint.withAlphaComponent(strength), forCharacterRange: r)
            }
        }
    }

    static func isDark(_ colour: NSColor) -> Bool { (colour.usingColorSpace(.sRGB)?.brightnessComponent ?? 1) < 0.4 }

    static func ranges(of quote: String, in ns: NSString) -> [NSRange] {
        var out: [NSRange] = []
        var from = 0
        while from < ns.length {
            let r = ns.range(of: quote, options: [], range: NSRange(location: from, length: ns.length - from))
            if r.location == NSNotFound { break }
            out.append(r)
            from = NSMaxRange(r)
        }
        return out
    }

    /// The 1-based line holding a UTF-16 offset.
    static func line(at location: Int, in ns: NSString) -> Int {
        var line = 1
        for i in 0..<min(location, ns.length) where ns.character(at: i) == 0x0A { line += 1 }
        return line
    }
}

/// AppKit reports selection and page changes even when the app made them itself, which happens
/// while SwiftUI is updating a view; writing SwiftUI state then is "modifying state during view
/// update". Reports go through here, so they arrive on the next turn of the run loop instead.
enum Later {
    static func report(_ deliver: @escaping () -> Void) { DispatchQueue.main.async(execute: deliver) }
}

/// Look Up: the system's definition popover for a word or passage. AppKit's text views here do not
/// put it in their right-click menu, so the app adds it, and an Edit menu command with ⌃⌘D.
enum LookUp {
    /// What to look up: the selection, or else the word at a character.
    static func range(in tv: NSTextView, at character: Int) -> NSRange? {
        let sel = tv.selectedRange()
        if sel.length > 0 { return sel }
        let length = (tv.string as NSString).length
        guard character >= 0, character < length else { return nil }
        let word = tv.selectionRange(forProposedRange: NSRange(location: character, length: 0), granularity: .selectByWord)
        let text = (tv.string as NSString).substring(with: word).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return text.isEmpty ? nil : word
    }

    /// Puts "Look Up “word”" at the top of a text view's right-click menu.
    static func addItem(to menu: NSMenu, in tv: NSTextView, at character: Int) -> NSMenu {
        guard let r = range(in: tv, at: character) else { return menu }
        var shown = (tv.string as NSString).substring(with: r).trimmingCharacters(in: .whitespacesAndNewlines)
        if shown.count > 24 { shown = String(shown.prefix(22)) + "…" }
        let item = NSMenuItem(title: "Look Up “\(shown)”", action: #selector(NSTextView.lookUp(_:)), keyEquivalent: "")
        item.representedObject = NSValue(range: r)
        item.target = tv
        menu.insertItem(item, at: 0)
        menu.insertItem(.separator(), at: 1)
        return menu
    }
}

extension NSTextView {
    /// Shows the definition of a range (from a menu item), or else of the selection or the word at the caret.
    @objc func lookUp(_ sender: Any?) {
        let r = ((sender as? NSMenuItem)?.representedObject as? NSValue)?.rangeValue
            ?? LookUp.range(in: self, at: selectedRange().location)
        guard let r, let lm = layoutManager, let storage = textStorage, NSMaxRange(r) <= storage.length else { return }
        let glyphs = lm.glyphRange(forCharacterRange: r, actualCharacterRange: nil)
        let line = lm.lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
        let x = lm.location(forGlyphAt: glyphs.location).x
        let baseline = NSPoint(x: line.minX + x + textContainerOrigin.x,
                               y: line.minY + lm.location(forGlyphAt: glyphs.location).y + textContainerOrigin.y)
        showDefinition(for: storage.attributedSubstring(from: r), at: baseline)
    }
}

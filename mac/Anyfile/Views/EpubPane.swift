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
    var marks: [Paint] = []
    var onSelect: (Selection?) -> Void = { _ in }
    /// Where to resume in the chapter on show: the first character that was on screen.
    var resume: Int? = nil
    /// The reading place: the first character on screen, and the words from there to the chapter's end.
    var onPlace: (Int, Int) -> Void = { _, _ in }
    var settings = ReadingSettings()
    @State private var text = ""
    @State private var title = ""
    @State private var loaded: Int?                 // the chapter whose text is in `text`
    @State private var titles: [Int: String] = [:]
    @State private var language: String?                 // from the book's metadata, for the Devanagari face

    var body: some View {
        ReadingText(text: text, number: loaded, title: title, find: find?.target == loaded ? find : nil, marks: marks,
                    onSelect: { quote in
                        guard let quote, let loaded else { return onSelect(nil) }
                        onSelect(Selection(quote: quote, target: loaded, place: title.isEmpty ? "Chapter \(loaded)" : title))
                    },
                    onTurn: turn(by:), peek: peek(_:), resume: resume, onPlace: onPlace, language: language, settings: settings)
            .frame(minWidth: 320)
            .overlay(alignment: .leading) { TurnArrow(direction: -1, enabled: neighbour(-1) != nil) { turn(by: -1) } }
            .overlay(alignment: .trailing) { TurnArrow(direction: 1, enabled: neighbour(1) != nil) { turn(by: 1) } }
            .onAppear { reload() }
            .onChange(of: document.data) { reload() }      // a command changed the book
            .onChange(of: chapter) { loadText() }
    }

    /// The chapter before or after the one on show, if there is one.
    private func neighbour(_ step: Int) -> Int? { EpubPane.neighbour(of: chapter, step: step, in: Array(titles.keys)) }

    static func neighbour(of chapter: Int?, step: Int, in numbers: [Int]) -> Int? {
        let sorted = numbers.sorted()
        guard let chapter, let i = sorted.firstIndex(of: chapter), sorted.indices.contains(i + step) else { return nil }
        return sorted[i + step]
    }

    private func turn(by step: Int) {
        if let next = neighbour(step) { chapter = next }
    }

    /// The neighbouring chapter's text and title, for a swipe to show before the page is turned.
    private func peek(_ step: Int) -> ReadingText.Page? {
        guard let number = neighbour(step) else { return nil }
        let r = Engine.run("text", args: [String(number)], on: document.data, name: document.name, kind: document.kind)
        guard r.succeeded else { return nil }
        return ReadingText.Page(text: r.output, number: number, title: titles[number] ?? "", language: language, settings: settings)
    }

    private func reload() {
        let r = Engine.run("chapters", args: [], on: document.data, name: document.name, kind: document.kind)
        let chapters = EpubChapter.parse(r.output)
        titles = Dictionary(chapters.map { ($0.number, $0.title) }, uniquingKeysWith: { a, _ in a })
        language = Cover.field("language", in: Engine.run("meta", args: [], on: document.data, name: document.name, kind: document.kind).output)
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
    var marks: [Paint] = []
    var onSelect: (String?) -> Void = { _ in }
    /// Asks for the next (+1) or previous (-1) chapter, from the arrow keys or Space at the end.
    var onTurn: (Int) -> Void = { _ in }
    /// The neighbouring chapter (+1, -1), or nil when there is none that way.
    var peek: (Int) -> Page? = { _ in nil }
    /// A character to bring to the top once, when this chapter's text first appears.
    var resume: Int? = nil
    /// The first character on screen and the words after it, reported once scrolling has rested.
    var onPlace: (Int, Int) -> Void = { _, _ in }
    var language: String? = nil
    var settings = ReadingSettings()

    struct Page {
        let text: String
        let number: Int
        let title: String
        var language: String? = nil
        var settings = ReadingSettings()
    }

    func makeNSView(context: Context) -> PageTurnView {
        let turner = PageTurnView(scroll: Self.makePage())
        (turner.scroll.documentView as? PaperTextView)?.delegate = context.coordinator
        context.coordinator.watchScrolling(turner.scroll)
        return turner
    }

    /// The scroll view and text view a chapter is set in. Also used to draw a neighbouring chapter off-screen.
    static func makePage() -> PageScrollView {
        let scroll = PageScrollView()
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

    /// A neighbouring chapter drawn off-screen at the size of the page on show, top of the chapter in view.
    static func picture(_ page: Page, size: NSSize) -> CGImage? {
        guard size.width > 1, size.height > 1 else { return nil }
        let scroll = makePage()
        scroll.frame = NSRect(origin: .zero, size: size)
        let tv = scroll.documentView as! NSTextView
        tv.frame = NSRect(origin: .zero, size: NSSize(width: size.width, height: size.height))
        dress(scroll, page.settings)
        tv.textStorage?.setAttributedString(ReadingStyle.chapter(page.text, number: page.number, title: page.title,
                                                                 language: page.language, settings: page.settings))
        tv.sizeToFit()
        scroll.layoutSubtreeIfNeeded()
        tv.scrollToBeginningOfDocument(nil)
        guard let rep = scroll.bitmapImageRepForCachingDisplay(in: scroll.bounds) else { return nil }
        scroll.cacheDisplay(in: scroll.bounds, to: rep)
        return rep.cgImage
    }

    /// The page's paper and column, from the reader's settings.
    static func dress(_ scroll: NSScrollView, _ settings: ReadingSettings) {
        let paper = settings.palette.window
        scroll.backgroundColor = paper
        if let tv = scroll.documentView as? PaperTextView {
            tv.backgroundColor = paper
            tv.measure = settings.measure
        }
    }

    func updateNSView(_ turner: PageTurnView, context: Context) {
        let tv = turner.scroll.documentView as! PaperTextView
        Self.dress(turner.scroll, settings)
        turner.paper = settings.palette.window
        tv.onTurn = onTurn
        let peek = self.peek
        turner.preview = { [weak turner] step in
            guard let turner, let page = peek(step) else { return nil }
            return ReadingText.picture(page, size: turner.bounds.size)
        }
        turner.commit = onTurn
        let shown = [String(number ?? 0), title, text, language ?? ""]
        if context.coordinator.shown == shown, context.coordinator.settings != settings {
            // Same chapter, new settings: the lines re-wrap, so keep the sentence at the top where it was.
            let top = ReadingPlace.topCharacter(in: tv)
            tv.textStorage?.setAttributedString(ReadingStyle.chapter(text, number: number, title: title, language: language, settings: settings))
            ReadingPlace.scroll(tv, toCharacter: top)
            context.coordinator.lastMarks = nil
        }
        context.coordinator.settings = settings
        if context.coordinator.shown != shown {
            // A new chapter number is a page turn: picture the old page before the text changes.
            let previous = Int(context.coordinator.shown.first ?? "")
            // A swipe has already pictured and is finishing its own turn, so it is not played twice.
            let turning = previous != nil && previous != 0 && number != nil && previous != number && turner.window != nil && !turner.isBusy
            let old = turning ? turner.snapshot() : nil
            context.coordinator.shown = shown
            tv.textStorage?.setAttributedString(ReadingStyle.chapter(text, number: number, title: title, language: language, settings: settings))
            if let resume, !context.coordinator.resumed, number != nil, !text.isEmpty {
                context.coordinator.resumed = true                    // only the first time this chapter appears
                ReadingPlace.scroll(tv, toCharacter: resume)
                // Again once the window has its final width: lines re-wrap, and the place must stay put.
                DispatchQueue.main.async { [weak tv] in if let tv { ReadingPlace.scroll(tv, toCharacter: resume) } }
            } else {
                tv.scrollToBeginningOfDocument(nil)
            }
            context.coordinator.lastMarks = nil
            if let old, let previous, let number { turner.turn(from: old, forward: number > previous) }
            context.coordinator.reportSoon(tv)                        // a new chapter is a new place
        }
        context.coordinator.onSelect = onSelect
        context.coordinator.onPlace = onPlace
        if marks != context.coordinator.lastMarks {
            context.coordinator.lastMarks = marks
            Highlights.apply(marks, to: tv)
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
    final class Coordinator: NSObject, NSTextViewDelegate {
        var lastFind: Jump?
        var shown: [String] = []
        var lastMarks: [Paint]?
        var onSelect: (String?) -> Void = { _ in }
        var onPlace: (Int, Int) -> Void = { _, _ in }
        var resumed = false
        var settings = ReadingSettings()
        private var pending: DispatchWorkItem?
        private var token: NSObjectProtocol?

        /// Reports the reading place once scrolling has rested, not on every scroll event.
        func watchScrolling(_ scroll: NSScrollView) {
            scroll.contentView.postsBoundsChangedNotifications = true
            token = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scroll.contentView,
                                                           queue: .main) { [weak self, weak scroll] _ in
                guard let self, let tv = scroll?.documentView as? NSTextView else { return }
                self.reportSoon(tv)
            }
        }

        func reportSoon(_ tv: NSTextView) {
            pending?.cancel()
            let work = DispatchWorkItem { [weak self, weak tv] in
                guard let self, let tv else { return }
                let anchor = ReadingPlace.topCharacter(in: tv)
                self.onPlace(anchor, ReadingTime.words(in: tv.string, from: anchor))
            }
            pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
        }

        deinit { if let token { NotificationCenter.default.removeObserver(token) } }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            let r = tv.selectedRange()
            let quote = r.length > 0 ? (tv.string as NSString).substring(with: r) : nil
            let report = onSelect
            Later.report { report(quote) }
        }
    }
}

/// A quiet arrow at the page's edge that shows when the pointer comes near.
private struct TurnArrow: View {
    let direction: Int
    let enabled: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: direction < 0 ? "chevron.left" : "chevron.right")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.secondary)
                .frame(width: 44)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(enabled && hovering ? 1 : 0)
        .animation(.easeOut(duration: 0.18), value: hovering)
        .onHover { hovering = $0 }
        .disabled(!enabled)
        .help(direction < 0 ? "Previous chapter (←)" : "Next chapter (→)")
        .accessibilityLabel(direction < 0 ? "Previous chapter" : "Next chapter")
        .accessibilityIdentifier(direction < 0 ? "previousChapter" : "nextChapter")
    }
}

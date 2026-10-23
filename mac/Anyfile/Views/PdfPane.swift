// PDF: the rendered pages from PDFKit, with the engine's extracted text alongside on request.
import SwiftUI
import PDFKit

struct PdfPane: View {
    let document: AnyfileDocument
    /// A page index from Contents.
    var jump: Jump? = nil
    /// Called with the page index on show and the page count, as the reader moves.
    var onPage: (Int, Int) -> Void = { _, _ in }
    var marks: [Mark] = []
    var onSelect: (Selection?) -> Void = { _ in }
    @State private var showText = false

    var body: some View {
        HSplitView {
            PdfKitView(data: document.data, jump: jump, onPage: onPage, marks: marks, onSelect: onSelect)
                .frame(minWidth: 300)
            if showText {
                ScrollView {
                    Text(extractedText)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .accessibilityIdentifier("pdfText")
                }
                .frame(minWidth: 240)
            }
        }
        .toolbar {
            ToolbarItem {
                Toggle("Extracted text", isOn: $showText)
                    .accessibilityIdentifier("pdfTextToggle")
            }
        }
    }

    private var extractedText: String {
        let r = Engine.run("text", args: [], on: document.data, name: document.name, kind: document.kind)
        return r.output.isEmpty ? (r.errorText.isEmpty ? "(no text)" : r.errorText) : r.output
    }
}

/// Which pages are on show: one at a time, or two side by side like an open book once the window is
/// wide enough. Book layout puts the first page (the cover) alone, then pages in pairs.
enum Spread {
    /// Two pages fit when the window holds two pages at its full height, give or take.
    static func twoUp(view: CGSize, page: CGSize) -> Bool {
        guard page.width > 0, page.height > 0, view.height > 0 else { return false }
        return view.width >= 2 * view.height * page.width / page.height * 0.92 && view.width >= 900
    }

    /// The first page of the spread holding `page`.
    static func start(of page: Int, twoUp: Bool) -> Int {
        guard twoUp, page > 0 else { return page }
        return (page - 1) / 2 * 2 + 1
    }

    /// The page to go to for the next (+1) or previous (-1) page or spread, or nil at either end.
    static func target(from page: Int, step: Int, count: Int, twoUp: Bool) -> Int? {
        let s = start(of: page, twoUp: twoUp)
        let t: Int
        if !twoUp { t = s + step }
        else if step > 0 { t = s == 0 ? 1 : s + 2 }
        else { t = s == 1 ? 0 : s - 2 }
        return (0..<count).contains(t) ? t : nil
    }
}

/// A PDF view that turns pages: the arrow keys play a turn, sideways swipes go to the page turner.
final class PagePDFView: PDFView, SwipeTurning {
    let router = SwipeRouter()
    var onTurn: ((Int) -> Void)?

    override func scrollWheel(with event: NSEvent) {
        if !router.take(event) { super.scrollWheel(with: event) }
    }

    override func keyDown(with event: NSEvent) {
        let plain = event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
        switch (event.keyCode, plain) {
        case (124, true): onTurn?(1)                                       // →
        case (123, true): onTurn?(-1)                                      // ←
        default: super.keyDown(with: event)
        }
    }

    /// One page or two, as the window's shape allows.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        fitSpread()
    }

    func fitSpread() {
        guard let page = document?.page(at: 0) else { return }
        let two = Spread.twoUp(view: bounds.size, page: page.bounds(for: .cropBox).size)
        let mode: PDFDisplayMode = two ? .twoUp : .singlePage
        if displayMode != mode {
            displayMode = mode
            displaysAsBook = true
        }
    }

    var isTwoUp: Bool { displayMode == .twoUp }
    var pageIndex: Int { currentPage.flatMap { document?.index(for: $0) } ?? 0 }

    /// Moves to a page at once, laid out and drawn, so it can be pictured.
    func show(page index: Int) {
        guard let p = document?.page(at: index) else { return }
        go(to: p)
        layoutDocumentView()
        displayIfNeeded()
    }
}

struct PdfKitView: NSViewRepresentable {
    let data: Data
    var jump: Jump? = nil
    var onPage: (Int, Int) -> Void = { _, _ in }
    var marks: [Mark] = []
    var onSelect: (Selection?) -> Void = { _ in }

    func makeNSView(context: Context) -> PageTurnView {
        let v = PagePDFView()
        v.autoScales = true
        v.displayMode = .singlePage
        v.displaysAsBook = true
        v.setAccessibilityIdentifier("pdfView")
        v.document = PDFDocument(data: data)
        context.coordinator.observe(v)
        let turner = PageTurnView(content: v)
        Self.wire(turner, v)
        return turner
    }

    /// Page turns for a PDF: keys picture the page, move, and turn from the picture to the page now on
    /// show; swipes move ahead under the turning picture, and move back if the page settles back.
    static func wire(_ turner: PageTurnView, _ v: PagePDFView) {
        turner.paper = .white
        v.onTurn = { [weak turner, weak v] step in
            guard let turner, let v, !turner.isBusy, let doc = v.document,
                  let target = Spread.target(from: v.pageIndex, step: step, count: doc.pageCount, twoUp: v.isTwoUp),
                  let old = turner.snapshot() else { return }
            v.show(page: target)
            turner.turn(from: old, forward: step > 0)
        }
        var origin: Int?
        turner.preview = { [weak turner, weak v] step in
            guard let turner, let v, let doc = v.document,
                  let target = Spread.target(from: v.pageIndex, step: step, count: doc.pageCount, twoUp: v.isTwoUp) else { return nil }
            origin = v.pageIndex
            v.show(page: target)
            return turner.snapshot()
        }
        turner.cancelled = { [weak v] _ in
            if let back = origin { v?.show(page: back) }
            origin = nil
        }
        turner.commit = { _ in origin = nil }
    }

    func updateNSView(_ turner: PageTurnView, context: Context) {
        let v = turner.content as! PagePDFView
        context.coordinator.onPage = onPage
        context.coordinator.onSelect = onSelect
        if context.coordinator.lastData != data {
            context.coordinator.lastData = data
            let page = v.currentPage.flatMap { v.document?.index(for: $0) } ?? 0
            v.document = PDFDocument(data: data)
            v.fitSpread()
            if let p = v.document?.page(at: min(page, max(0, (v.document?.pageCount ?? 1) - 1))) { v.go(to: p) }
        }
        if marks != context.coordinator.lastMarks || context.coordinator.lastData != context.coordinator.markedData {
            context.coordinator.lastMarks = marks
            context.coordinator.markedData = context.coordinator.lastData
            v.highlightedSelections = Self.selections(for: marks, in: v.document)
        }
        if jump != context.coordinator.lastJump {
            context.coordinator.lastJump = jump
            if let jump, let doc = v.document, let p = doc.page(at: jump.target) {
                v.go(to: p)
                if let query = jump.query,
                   let match = doc.findString(query, withOptions: .caseInsensitive).first(where: { $0.pages.contains(p) }) {
                    v.setCurrentSelection(match, animate: true)
                    v.go(to: match)
                }
            }
        }
    }

    /// Each mark found on its own page, for PDFView to paint. Nothing is written into the PDF.
    static func selections(for marks: [Mark], in doc: PDFDocument?) -> [PDFSelection] {
        guard let doc else { return [] }
        return marks.compactMap { mark in
            guard let page = doc.page(at: mark.target),
                  let found = doc.findString(mark.quote, withOptions: []).first(where: { $0.pages.contains(page) }) else { return nil }
            found.color = mark.colour.paint
            return found
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(lastData: data) }
    final class Coordinator {
        var lastData: Data
        var lastJump: Jump?
        var onPage: (Int, Int) -> Void = { _, _ in }
        var onSelect: (Selection?) -> Void = { _ in }
        var lastMarks: [Mark] = []
        var markedData: Data?
        private var selectionToken: NSObjectProtocol?
        init(lastData: Data) { self.lastData = lastData }

        private var token: NSObjectProtocol?

        func observe(_ v: PDFView) {
            token = NotificationCenter.default.addObserver(forName: .PDFViewPageChanged, object: v, queue: .main) { [weak self, weak v] _ in
                guard let v, let doc = v.document, let page = v.currentPage else { return }
                let (index, count) = (doc.index(for: page), doc.pageCount)
                Later.report { self?.onPage(index, count) }           // go(to:) inside an update posts this
            }
            selectionToken = NotificationCenter.default.addObserver(forName: .PDFViewSelectionChanged, object: v, queue: .main) { [weak self, weak v] _ in
                guard let v, let doc = v.document, let sel = v.currentSelection, let text = sel.string, !text.isEmpty,
                      let page = sel.pages.first else { Later.report { self?.onSelect(nil) }; return }
                let index = doc.index(for: page)
                let selection = Selection(quote: text, target: index, place: "Page \(index + 1)")
                Later.report { self?.onSelect(selection) }
            }
        }

        deinit {
            for t in [token, selectionToken].compactMap({ $0 }) { NotificationCenter.default.removeObserver(t) }
        }
    }
}

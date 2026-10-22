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

struct PdfKitView: NSViewRepresentable {
    let data: Data
    var jump: Jump? = nil
    var onPage: (Int, Int) -> Void = { _, _ in }
    var marks: [Mark] = []
    var onSelect: (Selection?) -> Void = { _ in }

    func makeNSView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.setAccessibilityIdentifier("pdfView")
        v.document = PDFDocument(data: data)
        context.coordinator.observe(v)
        return v
    }

    func updateNSView(_ v: PDFView, context: Context) {
        context.coordinator.onPage = onPage
        context.coordinator.onSelect = onSelect
        if context.coordinator.lastData != data {
            context.coordinator.lastData = data
            let page = v.currentPage.flatMap { v.document?.index(for: $0) } ?? 0
            v.document = PDFDocument(data: data)
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
            found.color = Theme.mark
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
                self?.onPage(doc.index(for: page), doc.pageCount)
            }
            selectionToken = NotificationCenter.default.addObserver(forName: .PDFViewSelectionChanged, object: v, queue: .main) { [weak self, weak v] _ in
                guard let v, let doc = v.document, let sel = v.currentSelection, let text = sel.string, !text.isEmpty,
                      let page = sel.pages.first else { self?.onSelect(nil); return }
                let index = doc.index(for: page)
                self?.onSelect(Selection(quote: text, target: index, place: "Page \(index + 1)"))
            }
        }

        deinit {
            for t in [token, selectionToken].compactMap({ $0 }) { NotificationCenter.default.removeObserver(t) }
        }
    }
}

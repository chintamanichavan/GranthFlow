// PDF: the rendered pages from PDFKit, with the engine's extracted text alongside on request.
import SwiftUI
import PDFKit

struct PdfPane: View {
    let document: AnyfileDocument
    /// A page index from Contents.
    var jump: Jump? = nil
    /// Called with the page index on show and the page count, as the reader moves.
    var onPage: (Int, Int) -> Void = { _, _ in }
    @State private var showText = false

    var body: some View {
        HSplitView {
            PdfKitView(data: document.data, jump: jump, onPage: onPage)
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
        if context.coordinator.lastData != data {
            context.coordinator.lastData = data
            let page = v.currentPage.flatMap { v.document?.index(for: $0) } ?? 0
            v.document = PDFDocument(data: data)
            if let p = v.document?.page(at: min(page, max(0, (v.document?.pageCount ?? 1) - 1))) { v.go(to: p) }
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

    func makeCoordinator() -> Coordinator { Coordinator(lastData: data) }
    final class Coordinator {
        var lastData: Data
        var lastJump: Jump?
        var onPage: (Int, Int) -> Void = { _, _ in }
        init(lastData: Data) { self.lastData = lastData }

        private var token: NSObjectProtocol?

        func observe(_ v: PDFView) {
            token = NotificationCenter.default.addObserver(forName: .PDFViewPageChanged, object: v, queue: .main) { [weak self, weak v] _ in
                guard let v, let doc = v.document, let page = v.currentPage else { return }
                self?.onPage(doc.index(for: page), doc.pageCount)
            }
        }

        deinit { if let token { NotificationCenter.default.removeObserver(token) } }
    }
}

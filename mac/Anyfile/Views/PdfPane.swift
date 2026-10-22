// PDF: the rendered pages from PDFKit, with the engine's extracted text alongside on request.
import SwiftUI
import PDFKit

struct PdfPane: View {
    let document: AnyfileDocument
    @State private var showText = false

    var body: some View {
        HSplitView {
            PdfKitView(data: document.data)
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

    func makeNSView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.setAccessibilityIdentifier("pdfView")
        v.document = PDFDocument(data: data)
        return v
    }

    func updateNSView(_ v: PDFView, context: Context) {
        if context.coordinator.lastData != data {
            context.coordinator.lastData = data
            let page = v.currentPage.flatMap { v.document?.index(for: $0) } ?? 0
            v.document = PDFDocument(data: data)
            if let p = v.document?.page(at: min(page, max(0, (v.document?.pageCount ?? 1) - 1))) { v.go(to: p) }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(lastData: data) }
    final class Coordinator { var lastData: Data; init(lastData: Data) { self.lastData = lastData } }
}

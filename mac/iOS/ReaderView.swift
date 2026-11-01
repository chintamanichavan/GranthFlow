// One pane per kind of file, as ContentView chooses on the Mac.
import PDFKit
import SwiftUI

struct ReaderView: View {
    @Binding var document: AnyfileDocument

    var body: some View {
        switch document.kind {
        case "epub":
            EpubReader(document: document)
        case "pdf":
            PDFReader(data: document.data)
        case "text", "markdown":
            TextEditor(text: $document.text)
                .font(.body.monospaced())
                .padding(.horizontal)
        default:
            HexReader(document: document)
        }
    }
}

/// One chapter at a time; the bottom bar turns chapters and lists them all.
struct EpubReader: View {
    let document: AnyfileDocument
    @State private var chapters: [EpubChapter] = []
    @State private var index = 0
    @State private var text = ""

    var body: some View {
        ScrollView {
            Text(text)
                .font(.system(.body, design: .serif))
                .lineSpacing(6)
                .textSelection(.enabled)
                .frame(maxWidth: 680, alignment: .leading)
                .padding()
                .frame(maxWidth: .infinity)
        }
        .id(index)      // a new chapter starts at its top
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                Button { index -= 1 } label: { Image(systemName: "chevron.left") }
                    .disabled(index == 0)
                Spacer()
                Menu(title(at: index)) {
                    ForEach(chapters.indices, id: \.self) { i in
                        Button(title(at: i)) { index = i }
                    }
                }
                Spacer()
                Button { index += 1 } label: { Image(systemName: "chevron.right") }
                    .disabled(index + 1 >= chapters.count)
            }
        }
        .task {
            chapters = EpubChapter.parse(run("chapters").output)
        }
        .task(id: chapters.isEmpty ? nil : chapters[index].number) {
            guard !chapters.isEmpty else { return }
            text = run("text", String(chapters[index].number)).output
        }
    }

    private func title(at i: Int) -> String {
        guard chapters.indices.contains(i) else { return "Contents" }
        let c = chapters[i]
        return c.title.isEmpty ? "Chapter \(c.number)" : c.title
    }

    private func run(_ command: String, _ args: String...) -> RunResult {
        Engine.run(command, args: args, on: document.data, name: document.name, kind: document.kind)
    }
}

struct PDFReader: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = PDFDocument(data: data)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {}
}

/// Any other file: its bytes, as the engine's `hex` prints them.
struct HexReader: View {
    let document: AnyfileDocument

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            Text(Engine.run("hex", args: [], on: document.data, name: document.name, kind: document.kind).output)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .padding()
        }
    }
}

// Read-only hex view, one page at a time, for files the other panes cannot show.
import SwiftUI

struct HexPane: View {
    let document: AnyfileDocument
    /// A byte offset from Find.
    var jump: Jump? = nil
    @State private var offset: Int = 0
    @State private var jumpText: String = "0"
    private let page = 4096

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("◀ Previous") { move(by: -page) }.disabled(offset == 0)
                Button("Next ▶") { move(by: page) }.disabled(offset + page >= document.data.count)
                Spacer()
                Text("offset").foregroundStyle(.secondary)
                TextField("0x0", text: $jumpText)
                    .frame(width: 110)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit(jumpToTypedOffset)
                    .accessibilityIdentifier("hexOffsetField")
                Text("of \(document.data.count)").foregroundStyle(.secondary).font(.system(.caption, design: .monospaced))
            }
            .padding(8)
            Divider()
            ScrollView {
                Text(dump)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .accessibilityIdentifier("hexText")
            }
        }
        .onChange(of: jump) { _, jump in
            guard let jump else { return }
            offset = Self.rowStart(of: jump.target)
            jumpText = String(format: "0x%llx", offset)
        }
    }

    /// The start of the 16-byte row holding an offset, so the match is on the first row shown.
    static func rowStart(of offset: Int) -> Int { max(0, offset) / 16 * 16 }

    private var dump: String {
        let r = Engine.run("hex", args: [String(offset), String(page)], on: document.data, name: document.name, kind: document.kind)
        return r.output.isEmpty ? "(empty file)" : r.output
    }

    private func move(by delta: Int) {
        offset = max(0, min(offset + delta, max(0, document.data.count - 1)))
        jumpText = String(format: "0x%llx", offset)
    }

    private func jumpToTypedOffset() {
        let s = jumpText.trimmingCharacters(in: .whitespaces)
        let v = s.lowercased().hasPrefix("0x") ? Int(s.dropFirst(2), radix: 16) : Int(s)
        if let v, v >= 0, v < max(1, document.data.count) { offset = v }
    }
}

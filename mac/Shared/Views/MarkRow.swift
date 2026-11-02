// One mark: its colour, the passage and where it is, and the reader's note, which can be added or
// edited in place.
import SwiftUI

struct MarkRow: View {
    let mark: Mark
    /// The line under the quote; the mark's place unless the caller says more, such as the file's name.
    var caption: String? = nil
    let choose: () -> Void
    let remove: () -> Void
    var setNote: (String) -> Void = { _ in }
    var setColour: (MarkColour) -> Void = { _ in }
    @State private var editing = false
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Menu {
                ForEach(MarkColour.allCases, id: \.self) { c in
                    Button { setColour(c) } label: { Label(c.title, systemImage: c == mark.colour ? "checkmark.circle.fill" : "circle.fill") }
                        .accessibilityIdentifier("colour.\(c.rawValue)")
                }
            } label: {
                RoundedRectangle(cornerRadius: 2).fill(Color(platform: mark.colour.paint)).frame(width: 5, height: 34)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Colour: \(mark.colour.title)")
            .accessibilityIdentifier("markColour")
            VStack(alignment: .leading, spacing: 4) {
                Button(action: choose) {
                    VStack(alignment: .leading, spacing: 3) {
                        Group {
                            if mark.kind == "binary" { Text(mark.quote).font(.system(size: 12, design: .monospaced)) }     // bytes, not words
                            else { Text("“\(mark.quote)”").font(.system(size: 14, design: .serif)) }
                        }
                        .lineLimit(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(caption ?? mark.place).font(.caption).foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if editing {
                    TextField("Your note", text: $draft, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...6)
                        .focused($focused)
                        .onSubmit(finish)
                        .onChange(of: focused) { _, now in if !now { finish() } }      // clicking away keeps the note
                        .accessibilityIdentifier("noteField")
                } else if !mark.note.isEmpty {
                    Text(mark.note).font(.callout).italic().foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onTapGesture(count: 2) { begin() }
                        .accessibilityIdentifier("note.\(mark.quote.prefix(24))")
                }
            }
            Button(action: begin) { Image(systemName: mark.note.isEmpty ? "square.and.pencil" : "pencil").foregroundStyle(.secondary) }
                .buttonStyle(.plain)
                .help(mark.note.isEmpty ? "Add a note" : "Edit the note")
                .accessibilityIdentifier("addNote")
            Button(action: remove) { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                .buttonStyle(.plain)
                .help("Remove this mark")
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mark.\(mark.quote.prefix(24))")
    }
}

private extension MarkRow {
    func begin() {
        draft = mark.note
        editing = true
        focused = true
    }

    func finish() {
        guard editing else { return }
        editing = false
        setNote(draft)
    }
}

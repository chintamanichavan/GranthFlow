// The Mark card: pressing Mark keeps the selected passage; the card lists this file's marks.
import SwiftUI

struct MarkPanel: View {
    let marks: [Mark]
    /// One line above the list: what just happened, or what to do to make a mark.
    let status: String
    let choose: (Mark) -> Void
    let remove: (Mark) -> Void
    var setNote: (Mark, String) -> Void = { _, _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Marks").font(.headline)
                Spacer()
                Text(status).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    .accessibilityIdentifier("markStatus")
            }
            if marks.isEmpty {
                Text("Nothing marked in this file yet.").foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(marks) { mark in
                            MarkRow(mark: mark, choose: { choose(mark) }, remove: { remove(mark) }, setNote: { setNote(mark, $0) })
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
        .padding(16)
    }
}

struct MarkRow: View {
    let mark: Mark
    /// The line under the quote; the mark's place unless the caller says more, such as the file's name.
    var caption: String? = nil
    let choose: () -> Void
    let remove: () -> Void
    var setNote: (String) -> Void = { _ in }
    @State private var editing = false
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 1.5).fill(Color(nsColor: Theme.mark)).frame(width: 3)
            VStack(alignment: .leading, spacing: 4) {
                Button(action: choose) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("“\(mark.quote)”").font(.system(size: 14, design: .serif)).lineLimit(3)
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

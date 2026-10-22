// The Find card: type, see every match with its place and a line of context, choose one to go there.
import SwiftUI

struct FindPanel: View {
    let document: AnyfileDocument
    let choose: (FindHit, String) -> Void

    @State private var query = ""
    @State private var hits: [FindHit] = []
    @State private var searched = ""          // the query the hits belong to
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(prompt, text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($focused)
                    .onSubmit { if let first = hits.first { choose(first, searched) } }
                    .accessibilityIdentifier("findField")
                if !searched.isEmpty {
                    Text(countText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("findCount")
                }
            }
            if !hits.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(hits) { hit in
                            FindRow(hit: hit) { choose(hit, searched) }
                                .accessibilityIdentifier("findHit.\(hit.id)")
                        }
                    }
                }
                .frame(maxHeight: 240)
            }
        }
        .padding(16)
        .onAppear { focused = true }
        .task(id: query) {
            // Wait for a pause in typing, then search off the main thread: a 135-chapter book
            // takes about 0.1 s, which would stall typing. Each engine call has its own temp copy.
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            let (q, doc) = (query, document)
            let found = await Task.detached(priority: .userInitiated) { Find.hits(for: q, in: doc) }.value
            guard !Task.isCancelled else { return }
            hits = found
            searched = q
        }
    }

    private var prompt: String {
        document.kind == "binary" ? "Find text, or bytes like 7f 45 4c 46" : "Find in \(document.name)"
    }

    private var countText: String {
        switch hits.count {
        case 0: "No matches"
        case 1: "1 match"
        case Find.limit: "\(Find.limit)+ matches"
        default: "\(hits.count) matches"
        }
    }
}

struct FindRow: View {
    let hit: FindHit
    let choose: () -> Void

    var body: some View {
        Button(action: choose) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(hit.place)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 96, alignment: .leading)
                    .lineLimit(1)
                Text(hit.snippet)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

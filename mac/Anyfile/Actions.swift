// The five actions every window offers, in the same place for every kind of file.
import Foundation

enum DocumentAction: String, CaseIterable, Identifiable {
    case contents, find, edit, mark, info

    var id: String { rawValue }

    var title: String {
        switch self {
        case .contents: "Contents"
        case .find: "Find"
        case .edit: "Edit"
        case .mark: "Mark"
        case .info: "Info"
        }
    }

    var symbol: String {
        switch self {
        case .contents: "list.bullet"
        case .find: "magnifyingglass"
        case .edit: "pencil"
        case .mark: "highlighter"
        case .info: "info.circle"
        }
    }

    /// Why the action is disabled for this kind, or nil when it can be used. Disabled actions stay
    /// visible so the bar never changes shape.
    func unavailableReason(for kind: String) -> String? {
        switch self {
        case .contents: Contents.hasContents(kind: kind) ? nil : "This kind of file has no contents to list"
        case .mark: "\(title) is not built yet"
        case .find, .edit, .info: nil
        }
    }
}

enum CommandRole {
    /// Commands that return new bytes. The engine does not say which these are, so they are listed
    /// here; a unit test fails if the engine gains a command that is in neither list.
    static let changing: Set<String> = [
        "patch", "patch-str", "truncate", "append-bytes",
        "replace", "replace-regex", "append", "insert", "set-line", "delete",
        "replace-section", "add-section",
        "set-meta", "add-page", "add-note", "delete-page",
    ]

    static let reading: Set<String> = [
        "info", "hex", "strings", "help",
        "show", "lines", "grep", "count",
        "render", "outline", "section", "links", "toc",
        "text", "pages", "meta", "object",
        "chapters", "files", "cat",
    ]

    /// Commands behind Edit: the ones that change the file, in the engine's order.
    static func editCommands(for kind: String) -> [CommandInfo] {
        Engine.commands(for: kind).filter { changing.contains($0.name) }
    }

    /// Commands behind Info: the ones that only read, with `info` first.
    static func infoCommands(for kind: String) -> [CommandInfo] {
        let reads = Engine.commands(for: kind).filter { reading.contains($0.name) && $0.name != "help" }
        return reads.filter { $0.name == "info" } + reads.filter { $0.name != "info" }
    }
}

// Swift-side view of the engine: plain values, no Objective-C types leak past this file.
import Foundation

struct CommandInfo: Identifiable, Hashable {
    let name: String
    let usage: String
    let help: String
    var id: String { name }
}

struct RunResult {
    enum Status: Int { case ok = 0, error = 1, badUsage = 2, unknown = 3 }
    let status: Status
    let output: String
    let errorText: String
    let changedData: Data?
    var succeeded: Bool { status == .ok }
}

enum Engine {
    static func detectKind(of data: Data, name: String) -> String {
        AFEngine.detectKind(data, name: name)
    }

    static func commands(for kind: String) -> [CommandInfo] {
        AFEngine.commands(forKind: kind).map { CommandInfo(name: $0.name, usage: $0.usage, help: $0.help) }
    }

    static func run(_ command: String, args: [String], on data: Data, name: String, kind: String) -> RunResult {
        let r = AFEngine.run(command, args: args, data: data, name: name, kind: kind)
        return RunResult(status: RunResult.Status(rawValue: Int(r.status)) ?? .error,
                         output: r.output, errorText: r.errorText, changedData: r.data)
    }

    /// Splits a command line the way a shell would for simple cases: spaces separate arguments,
    /// double or single quotes group them, and a backslash escapes the next character.
    static func splitArguments(_ line: String) -> [String] {
        var args: [String] = []
        var current = ""
        var quote: Character? = nil
        var escaping = false
        var hasToken = false
        for ch in line {
            if escaping { current.append(ch); escaping = false; continue }
            if ch == "\\" && quote != "'" { escaping = true; hasToken = true; continue }
            if let q = quote {
                if ch == q { quote = nil } else { current.append(ch) }
                continue
            }
            if ch == "\"" || ch == "'" { quote = ch; hasToken = true; continue }
            if ch == " " || ch == "\t" {
                if hasToken { args.append(current); current = ""; hasToken = false }
                continue
            }
            current.append(ch); hasToken = true
        }
        if hasToken { args.append(current) }
        return args
    }
}

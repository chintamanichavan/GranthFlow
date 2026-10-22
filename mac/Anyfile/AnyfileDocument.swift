// The document is just bytes plus a name. The engine decides what kind of file it is.
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let markdownText = UTType(importedAs: "net.daringfireball.markdown", conformingTo: .plainText)
}

struct AnyfileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data, .pdf, .epub, .plainText, .markdownText] }
    static var writableContentTypes: [UTType] { [.data, .pdf, .epub, .plainText, .markdownText] }

    var data: Data
    var name: String
    var kind: String

    init(data: Data = Data(), name: String = "Untitled.txt") {
        self.data = data
        self.name = name
        self.kind = Engine.detectKind(of: data, name: name)
    }

    init(configuration: ReadConfiguration) throws {
        guard let contents = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        var name = configuration.file.filename ?? "Untitled"
        if configuration.contentType.conforms(to: .markdownText), name.pathExtension.isEmpty { name += ".md" }
        self.init(data: contents, name: name)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }

    /// Text view of the bytes for editable kinds. Invalid UTF-8 is repaired rather than refused.
    var text: String {
        get { String(decoding: data, as: UTF8.self) }
        set { data = Data(newValue.utf8) }
    }

    var isTextual: Bool { kind == "text" || kind == "markdown" }

    /// Applies a command result. Returns true when the bytes changed.
    @discardableResult
    mutating func apply(_ result: RunResult) -> Bool {
        guard let changed = result.changedData else { return false }
        data = changed
        return true
    }
}

private extension String {
    var pathExtension: String { (self as NSString).pathExtension }
}

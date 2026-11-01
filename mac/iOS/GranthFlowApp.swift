// GranthFlow on iPhone and iPad: the system document browser opens any file, the engine reads it.
import SwiftUI

@main
struct GranthFlowApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: AnyfileDocument()) { file in
            ReaderView(document: file.$document)
        }
    }
}

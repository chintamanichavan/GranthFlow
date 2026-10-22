import SwiftUI

@main
struct AnyfileApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        DocumentGroup(newDocument: AnyfileDocument()) { file in
            ContentView(document: file.$document, fileURL: file.fileURL)
        }
        .commands {
            CommandGroup(replacing: .help) {
                Link("Command reference (README)", destination: URL(fileURLWithPath: Bundle.main.bundlePath))
            }
        }
    }
}

/// Supports `Anyfile --open <path>` so scripts and UI tests can start on a file without the Open panel.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--open"), i + 1 < args.count else { return }
        let url = URL(fileURLWithPath: args[i + 1])
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
            if let error { NSLog("open failed: %@", error.localizedDescription) }
        }
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        !CommandLine.arguments.contains("--open")
    }
}

import SwiftUI

@main
struct AnyfileApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // Listed first so it is the window the app opens with.
        Window("Library", id: "library") {
            LibraryView()
        }
        .defaultSize(width: 1100, height: 760)
        .keyboardShortcut("l", modifiers: [.command, .shift])

        DocumentGroup(newDocument: AnyfileDocument()) { file in
            ContentView(document: file.$document, fileURL: file.fileURL)
        }
        .commands {
            CommandGroup(after: .textEditing) {
                Button("Look Up") { NSApp.sendAction(#selector(NSTextView.lookUp(_:)), to: nil, from: nil) }
                    .keyboardShortcut("d", modifiers: [.control, .command])
            }
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
        // Tests must not sweep the reader's folders into a library: UI tests use one of their own, and
        // unit tests run inside the app itself (a watched Downloads folder would also stall them on a
        // permission prompt).
        let testing = args.contains("--library") || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        if !testing { WatchedFolders.shared.start() }
        guard let i = args.firstIndex(of: "--open"), i + 1 < args.count else { return }
        let url = URL(fileURLWithPath: args[i + 1])
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
            if let error { NSLog("open failed: %@", error.localizedDescription) }
        }
    }

    /// A mark chosen in Spotlight: open its file at the passage.
    func application(_ application: NSApplication, continue activity: NSUserActivity,
                     restorationHandler: @escaping ([any NSUserActivityRestoring]) -> Void) -> Bool {
        guard let mark = SpotlightMarks.mark(for: activity, in: MarkStore.shared.marks) else { return false }
        Navigator.shared.open(URL(fileURLWithPath: mark.path), at: mark.target, selecting: mark.quote)
        return true
    }

    /// The library is the starting window, so no empty document is made at launch.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }
}

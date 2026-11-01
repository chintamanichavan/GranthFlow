// GranthFlow on iPhone and iPad: a shelf of the files in GranthFlow's own folder, the engine reads them.
import SwiftUI

@main
struct GranthFlowApp: App {
    var body: some Scene {
        WindowGroup {
            LibraryScreen()
        }
    }
}

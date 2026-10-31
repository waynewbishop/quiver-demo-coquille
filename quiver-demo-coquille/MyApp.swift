import SwiftUI

@main struct MyApp: App {

    /// Registers the bundled fonts before the first view draws.
    init() {
        AppFonts.register()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands { FileCommands() }
        #if os(macOS)
        .defaultSize(width: 1100, height: 720)
        #endif
    }
}

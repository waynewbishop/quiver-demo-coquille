import SwiftUI

@main struct MyApp: App {

    /// The learner's stats, shared by the editor and, on the Mac, the Corrections window,
    /// so a fix shows in the list as soon as it's made.
    @State private var stats = StatsStore()

    /// Registers the bundled fonts before the first view draws.
    init() {
        AppFonts.register()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(stats: stats)
        }
        .commands { FileCommands() }
        #if os(macOS)
        .defaultSize(width: 1100, height: 720)
        #endif

        #if os(macOS)
        // Listed in the Window menu, so the corrections can stay open beside the editor.
        Window("Corrections", id: "corrections") {
            NavigationStack {
                CorrectionsView(store: stats)
            }
            .tint(.brand)
        }
        .defaultSize(width: 460, height: 560)
        #endif
    }
}

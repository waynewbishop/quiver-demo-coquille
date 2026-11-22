import SwiftUI

@main struct MyApp: App {

    /// The learner's stats, shared by the editor and, on the Mac, the Corrections window,
    /// so a fix shows in the list as soon as it's made.
    @State private var stats = StatsStore() 
    /// Whether the learner has Coquille Pro, asked by the gates and Settings.
    @State private var proStore = ProStore()
    /// The learner's entries, one text file each, in the app's Documents folder.
    @State private var journal = Journal(folderURL: Journal.defaultFolderURL())

    /// Registers the bundled fonts before the first view draws, and clears postcard images
    /// left from earlier launches.
    init() {
        AppFonts.register()
        PostcardRenderer.removeOldExports()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(stats: stats, journal: journal)
                .environment(proStore)
        }
        .commands {
            FileCommands()
            SidebarCommands()
            FontSizeCommands()
            PlaybackCommands()
            #if os(macOS)
            AppearanceCommands()
            AboutCommands()
            WelcomeCommands()
            #endif
        }
        #if os(macOS)
        .defaultSize(width: 1100, height: 720)
        #endif

        #if os(macOS)
        Settings {
            SettingsView(journal: journal)
                .environment(proStore)
                .tint(.brand)
        }

        // Listed in the Window menu, so the corrections can stay open beside the editor.
        Window("Corrections", id: "corrections") {
            NavigationStack {
                ProGate(title: "Your corrections", message: "The history of your corrections is part of Coquille Pro.") {
                    CorrectionsView(store: stats)
                }
            }
            .environment(proStore)
            .tint(.brand)
        }
        .defaultSize(width: 460, height: 560)

        // Opens from Coquille › About Coquille and from Settings.
        Window("About Coquille", id: AboutView.windowID) {
            AboutView()
                .ignoresSafeArea()
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .defaultPosition(.center)

        // Opens by itself at first launch, and again from Help › Welcome to Coquille.
        Window("Welcome to Coquille", id: WelcomeTour.windowID) {
            WelcomeTour()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        #endif
    }
}

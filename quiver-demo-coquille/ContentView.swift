import SwiftUI

/// The app's root view and its custom-URL entry point.
struct ContentView: View {
    let stats: StatsStore
    let journal: Journal
    @State private var pendingRoute: CoquilleRoute?
    @State private var pendingExercise: ExercisePrompt?
    /// Set once the welcome tour has been shown, so it opens by itself only at first launch.
    @AppStorage(WelcomeTour.seenKey) private var hasSeenTour = false
    /// Whether the welcome tour is up, on iPhone and iPad.
    @State private var showsTour = false
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    var body: some View {
        EditorScreen(
            stats: stats,
            journal: journal,
            workspace: Workspace.standard(),
            pendingRoute: $pendingRoute
        )
        .onOpenURL { open($0) }
        .onChange(of: RouteInbox.shared.link, initial: true) {
            guard let link = RouteInbox.shared.link else { return }
            RouteInbox.shared.link = nil
            if let url = URL(string: link) { open(url) }
        }
        .sheet(item: $pendingExercise) { exercise in
            ExerciseStartView(exercise: exercise) { confirmed in
                pendingRoute = .exercise(confirmed)
                pendingExercise = nil
            }
        }
        .environment(\.showWelcomeTour, ShowWelcomeTourAction { showTour() })
        .onAppear {
            if !hasSeenTour { showTour() }
        }
        #if !os(macOS)
        .modifier(TourPresentation(isPresented: $showsTour))
        #endif
    }

    /// Shows the welcome tour: its own window on the Mac, over the editor elsewhere.
    private func showTour() {
        #if os(macOS)
        openWindow(id: WelcomeTour.windowID)
        #else
        showsTour = true
        #endif
    }

    /// Validates a link, asking for confirmation first when it would start an exercise.
    private func open(_ url: URL) {
        guard let route = CoquilleRoute.parse(url) else { return }
        if case .exercise(let exercise) = route {
            pendingExercise = exercise
        } else {
            pendingRoute = route
        }
    }
}

#if !os(macOS)
/// Shows the welcome tour full screen on iPhone, and as a page sheet on iPad.
private struct TourPresentation: ViewModifier {

    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        // The idiom never changes while the app runs, so the editor's identity is stable.
        if UIDevice.current.userInterfaceIdiom == .phone {
            content.fullScreenCover(isPresented: $isPresented) { WelcomeTour() }
        } else {
            content.sheet(isPresented: $isPresented) {
                WelcomeTour()
                    .presentationSizing(.page)
            }
        }
    }
}
#endif

#Preview {
    ContentView(stats: StatsStore(fileURL: nil), journal: Journal(folderURL: .temporaryDirectory.appending(path: "Preview journal")))
}

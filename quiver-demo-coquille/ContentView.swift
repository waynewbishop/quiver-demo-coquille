import SwiftUI

/// The app's root view and its custom-URL entry point.
struct ContentView: View {
    let stats: StatsStore
    let journal: Journal
    @State private var pendingRoute: CoquilleRoute?
    @State private var pendingExercise: ExercisePrompt?

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

#Preview {
    ContentView(stats: StatsStore(fileURL: nil), journal: Journal(folderURL: .temporaryDirectory.appending(path: "Preview journal")))
}

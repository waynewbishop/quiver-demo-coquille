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
        .onOpenURL { url in
            guard let route = CoquilleRoute.parse(url) else { return }
            switch route {
            case .today:
                pendingRoute = route
            case .exercise(let exercise):
                pendingExercise = exercise
            }
        }
        .sheet(item: $pendingExercise) { exercise in
            ExerciseStartView(exercise: exercise) { confirmed in
                pendingRoute = .exercise(confirmed)
                pendingExercise = nil
            }
        }
    }
}

#Preview {
    ContentView(stats: StatsStore(fileURL: nil), journal: Journal(folderURL: .temporaryDirectory.appending(path: "Preview journal")))
}

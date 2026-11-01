import SwiftUI

/// The app's root view.
struct ContentView: View {
    let stats: StatsStore
    let journal: Journal

    var body: some View {
        EditorScreen(stats: stats, journal: journal, workspace: Workspace.standard())
    }
}

#Preview {
    ContentView(stats: StatsStore(fileURL: nil), journal: Journal(folderURL: .temporaryDirectory.appending(path: "Preview journal")))
}

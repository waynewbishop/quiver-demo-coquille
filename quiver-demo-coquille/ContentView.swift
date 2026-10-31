import SwiftUI

/// The app's root view.
struct ContentView: View {
    let stats: StatsStore

    var body: some View {
        EditorScreen(stats: stats)
    }
}

#Preview {
    ContentView(stats: StatsStore(fileURL: nil))
}

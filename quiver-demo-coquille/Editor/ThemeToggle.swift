// Copyright 2026 Wayne W Bishop. All rights reserved.
//
//
// Licensed under the Apache License, Version 2.0 (the "License"); you may not use this
// file except in compliance with the License. You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software distributed under
// the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF
// ANY KIND, either express or implied. See the License for the specific language governing
// permissions and limitations under the License.

import SwiftUI

/// The learner's light or dark choice, as in the Quiver Notebook: the app follows the
/// system until the toggle is used, then remembers the choice between launches.
enum Appearance: String {
    case light
    case dark

    /// The `AppStorage` key holding the choice; absent means follow the system.
    static let storageKey = "appearance"

    /// The color scheme to force, or `nil` to follow the system.
    static func colorScheme(for stored: String?) -> ColorScheme? {
        switch stored.flatMap(Appearance.init(rawValue:)) {
        case .light: .light
        case .dark: .dark
        case nil: nil
        }
    }
}

/// A moon in light mode and a sun in dark mode; clicking switches to the other.
struct ThemeToggle: View {

    @AppStorage(Appearance.storageKey) private var stored: String?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button {
            hideKeyboard()
            stored = (colorScheme == .dark ? Appearance.light : Appearance.dark).rawValue
        } label: {
            Label(label, systemImage: colorScheme == .dark ? "sun.max" : "moon")
                .labelStyle(.iconOnly)
        }
        .help(label)
    }

    /// "Switch to light mode" or "Switch to dark mode".
    private var label: String {
        colorScheme == .dark ? "Switch to light mode" : "Switch to dark mode"
    }
}

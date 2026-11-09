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
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// The learner's appearance choice, remembered between launches.
enum Appearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    /// The `AppStorage` key holding the choice; absent means follow the system.
    static let storageKey = "appearance"

    var id: Self { self }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// The color scheme to force, or `nil` to follow the system.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    /// Applies the choice to the whole app at the platform level.
    ///
    /// `preferredColorScheme(nil)` doesn't reliably undo an earlier light or dark choice,
    /// which left the text editor drawing dark-mode text on a light page. Setting the
    /// platform's own override, or clearing it, also reaches the Settings and
    /// Corrections windows and sheets, which sit outside the editor's view tree.
    @MainActor
    func apply() {
        #if os(macOS)
        NSApplication.shared.appearance = switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
        #else
        let style: UIUserInterfaceStyle = switch self {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows { window.overrideUserInterfaceStyle = style }
        }
        #endif
    }
}

/// A moon in light mode and a sun in dark mode; clicking switches to the other.
struct ThemeToggle: View {

    @AppStorage(Appearance.storageKey) private var appearance = Appearance.system
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button {
            hideKeyboard()
            appearance = colorScheme == .dark ? .light : .dark
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

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

/// The learner's text size, as in the Quiver Notebook: three presets that grow the
/// French and the English, never the toolbar, sidebar or cards around them. The
/// choice is remembered between launches.
enum FontSize: String, CaseIterable, Identifiable {
    case small
    case medium
    case large

    /// The `AppStorage` key holding the choice.
    static let storageKey = "fontSize"

    /// The size a new install starts at, and the one ⌘0 returns to: Small on iPhone,
    /// where the narrow screen fits more of the sentence, and Medium elsewhere.
    static var standard: FontSize {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone ? .small : .medium
        #else
        .medium
        #endif
    }

    var id: Self { self }

    /// The name shown in the Font Size menu.
    var label: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        }
    }

    /// How much this preset scales the `Typography` sizes.
    ///
    /// Text size and line spacing scale together, so each preset keeps the same proportions.
    private var scale: Double {
        switch self {
        case .small: 0.85
        case .medium: 1.0
        case .large: 1.25
        }
    }

    /// The French text size at this preset.
    var frenchSize: Double { Typography.frenchSize * scale }

    /// The French line spacing at this preset.
    var frenchLineSpacing: Double { Typography.frenchLineSpacing * scale }

    /// The English text size at this preset.
    var englishSize: Double { Typography.englishSize * scale }

    /// The English line spacing at this preset.
    var englishLineSpacing: Double { Typography.englishLineSpacing * scale }

    /// The next preset `step` places along, stopping at Small and Large rather than wrapping.
    func stepped(by step: Int) -> FontSize {
        let all = Self.allCases
        let index = all.firstIndex(of: self) ?? 0
        return all[min(max(index + step, 0), all.count - 1)]
    }
}

/// A Font Size submenu for an in-app menu, such as the iPhone's More menu, where
/// there is no menu bar to hold `FontSizeCommands`.
struct FontSizePicker: View {

    @AppStorage(FontSize.storageKey) private var fontSize = FontSize.standard

    var body: some View {
        Picker(selection: $fontSize) {
            ForEach(FontSize.allCases) { size in
                Text(size.label).tag(size)
            }
        } label: {
            Label("Font Size", systemImage: "textformat.size")
        }
        .pickerStyle(.menu)
    }
}

/// The View menu's Font Size submenu: a checkmarked choice of Small, Medium and Large,
/// then ⌘= and ⌘− to step between them and ⌘0 to return to the default size, as in the browser,
/// Xcode and the Quiver Notebook.
struct FontSizeCommands: Commands {

    @AppStorage(FontSize.storageKey) private var fontSize = FontSize.standard

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Menu("Font Size") {
                Picker("Font Size", selection: $fontSize) {
                    ForEach(FontSize.allCases) { size in
                        Text(size.label).tag(size)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()

                Divider()

                Button("Bigger") { fontSize = fontSize.stepped(by: 1) }
                    .keyboardShortcut("=", modifiers: .command)
                    .disabled(fontSize == FontSize.allCases.last)
                Button("Smaller") { fontSize = fontSize.stepped(by: -1) }
                    .keyboardShortcut("-", modifiers: .command)
                    .disabled(fontSize == FontSize.allCases.first)
                Button("Default Size") { fontSize = FontSize.standard }
                    .keyboardShortcut("0", modifiers: .command)
                    .disabled(fontSize == FontSize.standard)
            }
        }
    }
}

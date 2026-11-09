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

import AVFoundation
import SwiftUI
import Translation

/// Coquille's preferences and the state of Apple's separately installed language assets.
struct SettingsView: View {

    @AppStorage(Appearance.storageKey) private var appearance = Appearance.system
    @AppStorage("showsSuggestions") private var showsSuggestions = true
    @AppStorage(SpeechNarrator.voiceStorageKey) private var playbackVoiceID = ""
    @State private var translationStatus: LanguageAvailability.Status?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        #if os(macOS)
        form
            .formStyle(.grouped)
            .frame(width: 480, height: 500)
        #else
        NavigationStack {
            form
                .navigationTitle("Settings")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        #endif
    }

    private var form: some View {
        Form {
            Section("General") {
                Picker("Appearance", selection: $appearance) {
                    ForEach(Appearance.allCases) { appearance in
                        Text(appearance.label).tag(appearance)
                    }
                }
                FontSizePicker()
                Toggle("Show suggestions", isOn: $showsSuggestions)
            }

            Section {
                Picker("French Playback Voice", selection: $playbackVoiceID) {
                    Text("Automatic").tag("")
                    ForEach(frenchVoices, id: \.identifier) { voice in
                        Text("\(voice.name) · \(voice.quality.label)").tag(voice.identifier)
                    }
                }
            } header: {
                Text("Playback")
            } footer: {
                Text("Choose the voice for French playback and the phrasebook. To install more voices, open the system's Accessibility settings, then choose Spoken Content and Voices. Playback voices are separate from translation downloads.")
            }

            Section {
                LabeledContent("French–English Translation", value: translationStatus?.label ?? "Checking…")
            } header: {
                Text("Languages")
            } footer: {
                Text("Translation uses Apple's French–English language pack. To install it, open System Settings, then choose General, Language & Region, and Translation Languages. This is separate from Coquille's bundled French checker.")
            }

            Section("About & Privacy") {
                LabeledContent("Version", value: Self.version)
                Text("Your entries, progress, and translations stay on this device.")
                Text("Word data from [Lexique 3.83](http://www.lexique.org) by Boris New and Christophe Pallier, licensed CC BY-SA 4.0.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            translationStatus = await LanguageAvailability().status(
                from: Locale.Language(identifier: "fr"),
                to: Locale.Language(identifier: "en")
            )
        }
    }

    private var frenchVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language == "fr-FR" }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}

private extension LanguageAvailability.Status {
    var label: String {
        switch self {
        case .installed: "Installed"
        case .supported: "Not Installed"
        case .unsupported: "Unsupported"
        @unknown default: "Unavailable"
        }
    }
}

private extension AVSpeechSynthesisVoiceQuality {
    var label: String {
        switch self {
        case .default: "Default"
        case .enhanced: "Enhanced"
        case .premium: "Premium"
        @unknown default: "System"
        }
    }
}

#Preview {
    SettingsView()
}

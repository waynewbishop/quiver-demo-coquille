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
// TranslationSession isn't Sendable, yet the framework hands one to `.translationTask`,
// and `prepareDownload` uses it once and lets it go.
@preconcurrency import Translation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

extension NotificationCenter {
    /// Fires when the learner comes back to Coquille, perhaps after changing a system setting.
    var appBecameActive: NotificationCenter.Publisher {
        #if os(macOS)
        publisher(for: NSApplication.didBecomeActiveNotification)
        #else
        publisher(for: UIApplication.didBecomeActiveNotification)
        #endif
    }
}

/// Coquille's preferences and the state of Apple's separately installed language assets.
struct SettingsView: View {

    @AppStorage(Appearance.storageKey) private var appearance = Appearance.system
    @AppStorage("showsSuggestions") private var showsSuggestions = true
    @AppStorage(SpeechNarrator.voiceStorageKey) private var playbackVoiceID = ""
    @State private var translationStatus: TranslationPackStatus?
    /// Set when the learner asks to download the pack, which starts the system's prompt.
    @State private var downloadRequest: TranslationSession.Configuration?
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
                if translationStatus?.canDownload == true {
                    Button("Download French…", action: requestDownload)
                }
            } header: {
                Text("Languages")
            } footer: {
                Text("Translation uses Apple's French–English language pack, which is separate from Coquille's bundled French checker.")
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
            forgetMissingVoice()
            translationStatus = await TranslationPack.status()
        }
        .onReceive(NotificationCenter.default.appBecameActive) { _ in
            forgetMissingVoice()
            Task { translationStatus = await TranslationPack.status() }
        }
        .onReceive(NotificationCenter.default.publisher(for: TranslationPack.didChange)) { _ in
            Task { translationStatus = await TranslationPack.status() }
        }
        .translationTask(downloadRequest, action: Self.prepareDownload)
    }

    /// Shows the system's download prompt and announces the outcome. The system reports its
    /// own errors, and declining simply leaves the status unchanged.
    private nonisolated static func prepareDownload(_ session: TranslationSession) async {
        try? await session.prepareTranslation()
        await MainActor.run {
            NotificationCenter.default.post(name: TranslationPack.didChange, object: nil)
        }
    }

    /// Starts the system's download prompt, again if the learner asks a second time.
    private func requestDownload() {
        if downloadRequest == nil {
            downloadRequest = TranslationSession.Configuration(source: TranslationPack.french, target: TranslationPack.english)
        } else {
            downloadRequest?.invalidate()
        }
    }

    /// Goes back to Automatic when the chosen voice has been deleted, so the picker is never blank.
    private func forgetMissingVoice() {
        if !playbackVoiceID.isEmpty, !frenchVoices.contains(where: { $0.identifier == playbackVoiceID }) {
            playbackVoiceID = ""
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

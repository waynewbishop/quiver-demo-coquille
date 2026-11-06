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

/// Starts or stops French voice entry from the editor's SwiftUI toolbar.
struct VoiceEntryButton: View {

    let voice: VoiceEntryModel
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: voice.state == .listening ? "mic.fill" : "mic")
                .labelStyle(.iconOnly)
                .symbolEffect(.pulse, isActive: voice.state == .listening)
        }
        .accessibilityLabel(title)
        .accessibilityValue(voice.state == .listening ? "On" : "Off")
        .help(title)
    }

    private var title: String {
        switch voice.state {
        case .preparing: "Preparing voice entry"
        case .listening: "Stop voice entry"
        case .stopping: "Finishing voice entry"
        default: "Dictate French"
        }
    }
}

/// The current volatile transcription, kept outside the learner's actual document.
struct VoiceInterimView: View {

    let voice: VoiceEntryModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(voice.state == .preparing ? "Préparation…" : "Écoute…", systemImage: "mic.fill")
                .font(.caption.weight(.medium))
            if !voice.interimText.isEmpty {
                Text(voice.interimText)
                    .font(.plexMono(15, relativeTo: .body))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .padding(20)
        .allowsHitTesting(false)
    }
}

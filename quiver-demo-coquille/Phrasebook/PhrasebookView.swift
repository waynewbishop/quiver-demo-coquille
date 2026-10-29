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

/// The phrasebook: phrases by situation, searchable in French or English, each one
/// read aloud on request.
///
/// It stays open beside the editor as a reference. There is no copy or insert: in a
/// paper journal a borrowed phrase is copied out by hand, and the copying is practice,
/// so the learner types the phrase and the linter checks it like any other French.
struct PhrasebookView: View {

    let model: EditorModel

    @State private var query = ""

    private var phrases: [Phrase] { model.phrases }

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(title: "PHRASEBOOK", showsDivider: false)
            searchField
            Divider()
            list
        }
        .onDisappear(perform: model.stopPhrase)
    }

    /// The search box for French or English words.
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search in French or English", text: $query)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button("Clear search", systemImage: "xmark.circle.fill") { query = "" }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    /// Every phrase by situation, or the search results best first.
    @ViewBuilder
    private var list: some View {
        if query.isEmpty {
            List {
                ForEach(Situation.allCases, id: \.self) { situation in
                    let rows = phrases.filter { $0.situation == situation }
                    if !rows.isEmpty {
                        Section(situation.title) {
                            ForEach(rows) { row(for: $0) }
                        }
                    }
                }
            }
            .listStyle(.plain)
        } else {
            let results = PhraseSearch.matches(for: query, in: phrases)
            if results.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                List(results) { row(for: $0) }
                    .listStyle(.plain)
            }
        }
    }

    /// Returns one phrase's row, wired to read it aloud.
    private func row(for phrase: Phrase) -> some View {
        PhraseRow(phrase: phrase, isSpeaking: model.isSpeaking(phrase)) {
            model.togglePhrase(phrase)
        }
    }
}

/// One phrase: the French, its English gloss, a tu or vous tag, the pattern note, and a play button.
struct PhraseRow: View {

    let phrase: Phrase
    let isSpeaking: Bool
    let play: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(Self.french(phrase.french))
                        .font(.plexMono(16, relativeTo: .body))
                    if phrase.register != .either {
                        Text(phrase.register.rawValue)
                            .font(.plexMono(11, relativeTo: .caption2))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .overlay(Capsule().strokeBorder(.secondary.opacity(0.5)))
                            .accessibilityLabel("Say this to someone you call \(phrase.register.rawValue)")
                    }
                }
                Text(phrase.english)
                    .font(.plexSans(14, relativeTo: .subheadline))
                    .foregroundStyle(.secondary)
                if let note = phrase.note {
                    Text(note)
                        .font(.plexSans(13, relativeTo: .footnote))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
            Button(isSpeaking ? "Stop" : "Play", systemImage: isSpeaking ? "stop.fill" : "speaker.wave.2", action: play)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.tint)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityLabel(isSpeaking ? Text("Stop") : Text("Play \(Self.french(phrase.french))"))
        }
        .padding(.vertical, 4)
    }

    /// The phrase marked as French, so VoiceOver reads it with a French voice rather than the interface's.
    private static func french(_ text: String) -> AttributedString {
        var marked = AttributedString(text)
        marked.languageIdentifier = "fr"
        return marked
    }
}

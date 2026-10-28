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

/// The learner's progress: summary cards, weak spots, and tricky words.
struct ProgressSheet: View {

    let stats: LearnerStats
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    summary
                    weakSpots
                    trickyWords
                    footer
                }
                .padding(24)
            }
            .navigationTitle("Your progress")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 380, minHeight: 520)
    }

    /// The four summary cards.
    private var summary: some View {
        let clean = stats.cleanFraction(lastSevenDaysFrom: .now).map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "—"
        return Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                card("Day streak", "\(stats.streak(asOf: .now))")
                card("Sentences checked", "\(stats.sentencesChecked)")
            }
            GridRow {
                card("Clean this week", clean)
                card("Errors fixed", "\(stats.errorsFixed)")
            }
        }
    }

    /// One summary card.
    private func card(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.footnote).foregroundStyle(.secondary)
            Text(value).font(.title.weight(.medium)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    /// Issue kinds ranked by count, as bars scaled to the most frequent.
    @ViewBuilder
    private var weakSpots: some View {
        let spots = stats.weakSpots
        if let top = spots.first?.count {
            section("YOUR WEAK SPOTS") {
                ForEach(spots, id: \.kind) { spot in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(spot.kind.displayName)
                            Spacer()
                            Text("\(spot.count)").fontWeight(.medium).monospacedDigit()
                        }
                        ProgressView(value: Double(spot.count), total: Double(top))
                            .tint(spot.kind == spots.first?.kind ? .red : .secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    /// Nouns the learner has missed more than once.
    @ViewBuilder
    private var trickyWords: some View {
        let words = stats.trickyWords
        if !words.isEmpty {
            section("TRICKY WORDS FOR YOU") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), alignment: .leading)], alignment: .leading, spacing: 8) {
                    ForEach(words, id: \.self) { word in
                        Text(word)
                            .font(.body.monospaced())
                            .foregroundStyle(.tint)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.tint.opacity(0.12), in: Capsule())
                    }
                }
                Text("Nouns you've missed more than once.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Privacy note and the Lexique credit its license requires.
    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Your stats stay on this device.")
            Text("Word data from [Lexique 3.83](http://www.lexique.org) by Boris New and Christophe Pallier, licensed CC BY-SA 4.0.")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    /// A titled section in the house style.
    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.monospaced())
                .tracking(1)
                .foregroundStyle(.secondary)
            content()
        }
    }
}

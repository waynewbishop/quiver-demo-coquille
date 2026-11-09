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

import AppIntents
import SwiftUI
import WidgetKit

/// Reads the widget's size and draws the face on the always-dark surface.
struct CoquilleWidgetView: View {
    let entry: TodaysPromptEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        CoquilleWidgetFace(prompt: entry.prompt, isMedium: family == .systemMedium)
            .containerBackground(for: .widget) { CoquilleWidgetFace.surface }
    }
}

/// The write bar and icon-only shortcuts. Labels live in the accessibility tree, not on the face.
struct CoquilleWidgetFace: View {
    let prompt: WritingPrompt
    let isMedium: Bool
    @Environment(\.widgetRenderingMode) private var renderingMode

    /// The near-black behind everything.
    static let surface = Color(red: 0.098, green: 0.098, blue: 0.09)
    private static let control = Color(red: 0.18, green: 0.18, blue: 0.165)

    /// One round shortcut along the bottom of the widget.
    private struct Action: Identifiable {
        let symbol: String
        let label: String
        let link: String
        var id: String { symbol }
    }

    /// The shortcuts for this size: two on small, four on medium.
    private var actions: [Action] {
        let todayLink = CoquilleRoute.widgetURL(for: prompt)?.absoluteString ?? CoquilleRoute.writeLink
        let shared = [
            Action(symbol: "quote.bubble", label: "Today's prompt", link: todayLink),
            Action(symbol: "book", label: "Phrasebook", link: CoquilleRoute.phrasebookLink),
        ]
        guard isMedium else { return shared }
        return shared + [
            Action(symbol: "list.bullet", label: "Journal", link: CoquilleRoute.journalLink),
            Action(symbol: "checkmark.circle", label: "Corrections", link: CoquilleRoute.correctionsLink),
        ]
    }

    /// Solid charcoal in full color; a translucent white when the system tints the widget.
    private var controlFill: Color {
        renderingMode == .fullColor ? Self.control : .white.opacity(0.16)
    }

    var body: some View {
        VStack(spacing: 0) {
            writeBar
            Spacer(minLength: 6)
            actionRow
            Spacer(minLength: 6).frame(maxHeight: 16)
        }
        .padding(9)
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    /// The main action: back to the current writing, or today's entry on an empty page.
    private var writeBar: some View {
        Button(intent: OpenCoquilleRouteIntent(link: CoquilleRoute.writeLink)) {
            HStack(spacing: 10) {
                Image("CoquilleMark")
                    .resizable()
                    .widgetAccentedRenderingMode(.fullColor)
                    .frame(width: 26, height: 26)
                    .clipShape(RoundedRectangle(cornerRadius: 6.5, style: .continuous))
                Text(isMedium ? "Écrivez en français" : "Écrivez")
                    .font(.plexSans(18, relativeTo: .headline))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 11)
            .frame(height: 50)
            .background(controlFill, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Write in French")
    }

    /// Even spacing across medium; a centered pair on small.
    private var actionRow: some View {
        HStack(spacing: isMedium ? 0 : 12) {
            ForEach(actions) { action in
                if isMedium { Spacer(minLength: 0) }
                shortcut(action)
            }
            if isMedium { Spacer(minLength: 0) }
        }
        .frame(maxWidth: .infinity)
    }

    /// One round button that opens the app at the action's destination.
    private func shortcut(_ action: Action) -> some View {
        Button(intent: OpenCoquilleRouteIntent(link: action.link)) {
            Image(systemName: action.symbol)
                .font(.system(size: 21, weight: .light))
                .widgetAccentable()
                .frame(width: 48, height: 48)
                .background(controlFill, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(action.label)
    }
}

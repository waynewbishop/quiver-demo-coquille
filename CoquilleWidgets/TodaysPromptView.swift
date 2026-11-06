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
import WidgetKit

/// The mockup's small and medium layouts, both entirely English.
struct TodaysPromptView: View {
    let entry: TodaysPromptEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .systemMedium:
                medium
            default:
                small
            }
        }
        .containerBackground(for: .widget) { Color(.systemBackground) }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Today's prompt. \(entry.prompt.text). Write in French in Coquille.")
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 8) {
            header(showsTopic: false)
            Divider()
            Text(entry.prompt.text)
                .font(.plexSans(21, weight: .medium, relativeTo: .headline))
                .lineLimit(4)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
            Spacer(minLength: 0)
            Text("\(entry.prompt.topic) · \(entry.prompt.lesson)")
                .font(.plexSans(12, relativeTo: .caption))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            writingLabel(prominent: false)
        }
        .padding(16)
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 10) {
            header(showsTopic: true)
            Divider()
            HStack(alignment: .bottom, spacing: 16) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(entry.prompt.text)
                        .font(.plexSans(27, weight: .medium, relativeTo: .title2))
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .layoutPriority(1)
                    Text(entry.prompt.lesson)
                        .font(.plexSans(16, relativeTo: .subheadline))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                writingLabel(prominent: true)
            }
            Spacer(minLength: 0)
            Divider()
            Text("One new prompt per day · Available offline")
                .font(.plexSans(12, relativeTo: .caption))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(16)
    }

    private func header(showsTopic: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "calendar")
                .widgetAccentable()
                .foregroundStyle(Color.brand)
            Text("TODAY'S PROMPT")
                .font(.plexMono(11, weight: .medium, relativeTo: .caption))
                .tracking(0.8)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            badge(entry.prompt.level)
            if showsTopic {
                badge(entry.prompt.topic)
            }
        }
    }

    private func badge(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.plexMono(10, weight: .medium, relativeTo: .caption2))
            .widgetAccentable()
            .foregroundStyle(Color.brand)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.brand.opacity(0.09), in: Capsule())
    }

    private func writingLabel(prominent: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "pencil")
            Text("Write in French")
                .font(.plexSans(prominent ? 16 : 14, weight: .medium, relativeTo: .subheadline))
                .lineLimit(1)
            Image(systemName: "arrow.right")
        }
        // The system background reads clearly on the blue in both light and dark appearances.
        .foregroundStyle(prominent ? Color(.systemBackground) : Color.brand)
        .padding(.horizontal, prominent ? 18 : 12)
        .padding(.vertical, prominent ? 14 : 9)
        .frame(maxWidth: prominent ? nil : .infinity)
        .background(prominent ? Color.brand : Color.brand.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .widgetAccentable()
    }
}

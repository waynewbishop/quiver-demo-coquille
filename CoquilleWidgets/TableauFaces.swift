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

/// The postcard palette from the design: cream ground, navy ink and one blue.
enum TableauColor {
    static let ground = Color(red: 0.980, green: 0.976, blue: 0.961)
    static let ink = Color(red: 0.078, green: 0.129, blue: 0.239)
    static let secondary = Color(red: 0.357, green: 0.392, blue: 0.471)
    static let blue = Color(red: 0.145, green: 0.341, blue: 0.839)
    /// The navy behind a photo face's caption and any day without a painting.
    static let shade = Color(red: 0.055, green: 0.078, blue: 0.141)
}

/// The short French words on the face, kept at A1 so the widget is a small reading exercise.
enum TableauWords {
    static let today = "AUJOURD'HUI"
    static let header = "TABLEAU DU JOUR"
    static let tapToWrite = "Touchez pour écrire"
    static let thisWeek = "CETTE SEMAINE"
}

/// Picks the face for the widget's size and makes the whole widget one tap to today's prompt.
struct TableauWidgetView: View {
    let entry: TableauEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        face
            .widgetURL(CoquilleRoute.widgetURL(for: entry.prompt))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
    }

    /// The face for this family.
    @ViewBuilder private var face: some View {
        switch family {
        case .systemMedium:
            MediumFace(entry: entry).containerBackground(TableauColor.ground, for: .widget)
        case .systemLarge:
            LargeFace(entry: entry).containerBackground(TableauColor.ground, for: .widget)
        case .systemExtraLarge:
            ExtraLargeFace(entry: entry).containerBackground(TableauColor.ground, for: .widget)
        #if os(iOS)
        case .accessoryRectangular:
            RectangularFace(entry: entry).containerBackground(for: .widget) { AccessoryWidgetBackground() }
        case .accessoryCircular:
            CircularFace().containerBackground(for: .widget) { AccessoryWidgetBackground() }
        #endif
        default:
            SmallFace(entry: entry).containerBackground(TableauColor.shade, for: .widget)
        }
    }

    /// The prompt, then the painting, as VoiceOver reads it.
    private var accessibilityText: String {
        let prompt = entry.tableau?.french ?? entry.prompt.text
        var parts = [prompt]
        if let tableau = entry.tableau {
            parts.append("Painting: \(tableau.description), \(tableau.title).")
        }
        parts.append("Tap to write.")
        return parts.joined(separator: " ")
    }
}

// MARK: - The painting

/// A painting in full color, or the navy shade for a prompt with no painting yet. It stays
/// in color even on a tinted or clear Home Screen, where the system would otherwise grey it.
struct PaintingView: View {
    let tableau: Tableau?

    var body: some View {
        if let tableau {
            Image(tableau.imageName)
                .resizable()
                .widgetAccentedRenderingMode(.fullColor)
                .scaledToFill()
        } else {
            TableauColor.shade
        }
    }
}

/// The painting filling the space it's given, cropped to fit.
private struct FilledPainting: View {
    let tableau: Tableau?

    var body: some View {
        Color.clear
            .overlay { PaintingView(tableau: tableau) }
            .clipped()
    }
}

// MARK: - Shared pieces

/// A spaced Plex Mono label such as "TABLEAU DU JOUR".
private struct MonoLabel: View {
    let text: String
    var size: Double = 9

    var body: some View {
        Text(text)
            .font(.plexMono(size, relativeTo: .caption2))
            .tracking(size * 0.08)
            .lineLimit(1)
    }
}

/// The painting's French title, in an italic serif like a gallery card.
private struct PaintingTitle: View {
    let title: String
    var size: Double = 16

    var body: some View {
        Text(title)
            .font(.system(size: size, design: .serif).italic())
            .foregroundStyle(TableauColor.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

/// The blue "Touchez pour écrire" that tells the learner a tap starts writing.
private struct TapToWrite: View {
    var size: Double = 12

    var body: some View {
        Text(TableauWords.tapToWrite)
            .font(.plexSans(size, weight: .medium, relativeTo: .caption))
            .foregroundStyle(TableauColor.blue)
            .widgetAccentable()
    }
}

// MARK: - Home Screen and StandBy

/// The painting edge to edge with the prompt over a dark fade. StandBy shows this face too,
/// where the painting fills the nightstand screen.
struct SmallFace: View {
    let entry: TableauEntry

    var body: some View {
        FilledPainting(tableau: entry.tableau)
            .overlay(alignment: .bottomLeading) { caption }
    }

    /// Today's prompt in French over the bottom of the painting.
    private var caption: some View {
        VStack(alignment: .leading, spacing: 3) {
            MonoLabel(text: TableauWords.today).opacity(0.85)
            Text(entry.tableau?.french ?? entry.prompt.text)
                .font(.plexSans(14, weight: .medium, relativeTo: .subheadline))
                .lineLimit(3)
                .minimumScaleFactor(0.85)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .padding(.top, 28)
        .background {
            LinearGradient(colors: [TableauColor.shade.opacity(0.82), TableauColor.shade.opacity(0)],
                           startPoint: .bottom, endPoint: .top)
        }
    }
}

/// The painting on the left and the prompt card on the right, French above the English.
struct MediumFace: View {
    let entry: TableauEntry

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                FilledPainting(tableau: entry.tableau)
                    .frame(width: proxy.size.width * 0.44)
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 5) {
                        MonoLabel(text: TableauWords.header)
                            .foregroundStyle(TableauColor.secondary)
                        Text(entry.tableau?.french ?? entry.prompt.text)
                            .font(.plexSans(16, weight: .medium, relativeTo: .headline))
                            .foregroundStyle(TableauColor.ink)
                            .lineLimit(3)
                            .minimumScaleFactor(0.85)
                        if entry.tableau != nil {
                            Text(entry.prompt.text)
                                .font(.plexSans(12, relativeTo: .caption))
                                .foregroundStyle(TableauColor.secondary)
                                .lineLimit(2)
                        }
                    }
                    Spacer(minLength: 4)
                    TapToWrite()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }
}

/// The painting across the top, the prompt and the painting's title beneath, and this
/// week's paintings along the bottom.
struct LargeFace: View {
    let entry: TableauEntry

    var body: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: 0) {
                FilledPainting(tableau: entry.tableau)
                    .frame(height: proxy.size.height * 0.42)
                VStack(alignment: .leading, spacing: 8) {
                    MonoLabel(text: "\(TableauWords.header) · \(entry.prompt.topic.uppercased())")
                        .foregroundStyle(TableauColor.secondary)
                    Text(entry.tableau?.french ?? entry.prompt.text)
                        .font(.plexSans(17, weight: .medium, relativeTo: .headline))
                        .foregroundStyle(TableauColor.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        TapToWrite()
                        if let tableau = entry.tableau {
                            Text("·")
                                .font(.plexSans(12, relativeTo: .caption))
                                .foregroundStyle(TableauColor.secondary)
                            PaintingTitle(title: tableau.title, size: 15)
                        }
                    }
                    Spacer(minLength: 4)
                    WeekStrip(days: entry.week, columns: 7, thumbnail: CGSize(width: 36, height: 36))
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 14)
            }
        }
    }
}

/// The painting on the left at about half the width, and the prompt with the week beside it.
/// The week wraps into two rows, Monday to Thursday, then Friday to Sunday. iPad and the Mac
/// desktop offer this size.
struct ExtraLargeFace: View {
    let entry: TableauEntry

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                FilledPainting(tableau: entry.tableau)
                    .frame(width: proxy.size.width * 0.53)
                VStack(alignment: .leading, spacing: 5) {
                    MonoLabel(text: "\(TableauWords.header) · \(entry.prompt.topic.uppercased())", size: 10)
                        .foregroundStyle(TableauColor.secondary)
                    Text(entry.tableau?.french ?? entry.prompt.text)
                        .font(.plexSans(17, weight: .medium, relativeTo: .headline))
                        .foregroundStyle(TableauColor.ink)
                        .lineLimit(3)
                        .minimumScaleFactor(0.85)
                    if let tableau = entry.tableau {
                        Text(entry.prompt.text)
                            .font(.plexSans(12, relativeTo: .caption))
                            .foregroundStyle(TableauColor.secondary)
                            .lineLimit(2)
                        PaintingTitle(title: tableau.title, size: 15)
                            .padding(.top, 2)
                    }
                    TapToWrite()
                    Spacer(minLength: 4)
                    WeekStrip(days: entry.week, columns: 4, thumbnail: CGSize(width: 60, height: 44))
                }
                .padding(.horizontal, 17)
                .padding(.top, 15)
                .padding(.bottom, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }
}

/// Monday to Sunday, each day's painting in color with today ringed: a look at the week's
/// prompts. Seven columns fit one row; fewer wrap.
private struct WeekStrip: View {
    let days: [TableauDay]
    let columns: Int
    let thumbnail: CGSize

    /// The days split into rows of `columns`.
    private var rows: [[TableauDay]] {
        stride(from: 0, to: days.count, by: max(columns, 1)).map {
            Array(days[$0..<min($0 + columns, days.count)])
        }
    }

    /// The thumbnail's corner, a little rounder for larger thumbnails.
    private var cornerRadius: Double {
        thumbnail.height >= 40 ? 6 : 8
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            MonoLabel(text: TableauWords.thisWeek)
                .foregroundStyle(TableauColor.secondary)
            VStack(spacing: 7) {
                ForEach(rows, id: \.first?.id) { row in
                    HStack(spacing: 2) {
                        ForEach(row) { day in
                            cell(for: day).frame(maxWidth: .infinity)
                        }
                        // A short last row keeps its days under the columns above.
                        ForEach(row.count..<columns, id: \.self) { _ in
                            Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                        }
                    }
                }
            }
        }
    }

    /// One day's thumbnail and its weekday initial.
    private func cell(for day: TableauDay) -> some View {
        VStack(spacing: 4) {
            PaintingView(tableau: day.tableau)
                .frame(width: thumbnail.width, height: thumbnail.height)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    if day.isToday {
                        RoundedRectangle(cornerRadius: cornerRadius + 1, style: .continuous)
                            .stroke(TableauColor.blue, lineWidth: 2)
                            .padding(-2)
                            .widgetAccentable()
                    }
                }
            Text(day.initial)
                .font(.plexMono(9, relativeTo: .caption2))
                .foregroundStyle(TableauColor.secondary)
        }
    }
}

// MARK: - Lock Screen

#if os(iOS)
/// The prompt in the system's tint. Lock Screen widgets are monochrome, so the painting stays home.
struct RectangularFace: View {
    let entry: TableauEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            MonoLabel(text: "COQUILLE · \(TableauWords.today)", size: 10)
                .opacity(0.8)
            Text(entry.tableau?.french ?? entry.prompt.text)
                .font(.plexSans(15, weight: .medium, relativeTo: .headline))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
    }
}

/// The Écrire mark, one tap from today's prompt.
struct CircularFace: View {
    var body: some View {
        Image(systemName: "pencil.and.scribble")
            .font(.system(size: 22))
    }
}
#endif

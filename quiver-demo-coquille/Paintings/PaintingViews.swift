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

/// `string` marked as French, so VoiceOver reads it with a French voice.
func frenchText(_ string: String) -> AttributedString {
    var text = AttributedString(string)
    text.languageIdentifier = "fr"
    return text
}

extension Font {
    /// The italic of painting titles, theme names and the month: Cormorant Garamond semibold,
    /// a little larger than the system text style, since its letters run small.
    static func paintingTitle(_ style: Font.TextStyle) -> Font {
        switch style {
        case .largeTitle: .cormorant(42, relativeTo: style)
        case .title: .cormorant(34, relativeTo: style)
        case .title2: .cormorant(29, relativeTo: style)
        case .title3: .cormorant(25, relativeTo: style)
        case .subheadline: .cormorant(18, relativeTo: style)
        default: .cormorant(21, relativeTo: style)
        }
    }
}

/// A painting drawn as a postage stamp: a white frame with a dotted, perforated edge,
/// tilted slightly, with the title beneath when there's room.
///
/// Its size is fixed by `width`, and the painting keeps its 4:3 shape, so it never crops
/// or resizes with the window.
struct PaintingStamp: View {
    let tableau: Tableau
    let width: CGFloat
    /// Whether to print the title under the painting; the tiny stamp beside a title doesn't.
    var showsTitle = true
    /// The stamp's tilt in degrees.
    var tilt = 1.5
    /// The title's size in points; in proportion to the stamp's width when `nil`.
    var titleSize: CGFloat?

    /// The frame's margin around the painting, in proportion to the stamp.
    private var margin: CGFloat { max(2, width * 0.05) }

    var body: some View {
        VStack(spacing: 3) {
            Image(tableau.imageName)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: width - 2 * margin, height: (width - 2 * margin) * 3 / 4)
                .clipped()
            if showsTitle {
                Text(frenchText(tableau.title))
                    .font(.cormorant(fixed: titleSize ?? width * 0.135))
                    .foregroundStyle(Color(white: 0.1))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(margin)
        .padding(.bottom, showsTitle ? 1 : 0)
        .frame(width: width)
        .background(.white)
        .overlay {
            Rectangle()
                .strokeBorder(Color(white: 0.8), style: StrokeStyle(lineWidth: 1, dash: [1.5, 2]))
        }
        .shadow(color: .black.opacity(0.14), radius: 3, y: 1)
        .rotationEffect(.degrees(tilt))
    }
}

/// The row under the French header with the entry's painting: its French word on the
/// left and the painting as a stamp in the top-right corner.
///
/// Tapping the stamp calls `replace`, which opens the same picker as Replace Painting…
/// in the menus: File › Painting on the Mac, More on iPhone and iPad.
struct PaintingStampRow: View {
    let tableau: Tableau
    let stampWidth: CGFloat
    /// Opens the painting picker to replace this painting.
    let replace: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("LE MOT DU TABLEAU")
                    .font(.plexMono(12, relativeTo: .caption))
                    .tracking(0.96)
                    .foregroundStyle(Color.brand)
                Text("\(Text(frenchText(tableau.word)).foregroundStyle(Color.brand).fontWeight(.semibold)) · \(tableau.wordEnglish)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 8)
            .accessibilityElement(children: .combine)

            Spacer(minLength: 0)

            Button(action: replace) {
                PaintingStamp(tableau: tableau, width: stampWidth)
                    .padding(4)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Painting: \(frenchText(tableau.title)). \(tableau.description)"))
            .accessibilityHint("Replaces the painting")
            .accessibilityAddTraits([.isImage, .isButton])
            #if os(macOS)
            .help("Replace Painting…")
            #endif
        }
        .padding(.leading, 22)
        .padding(.trailing, 14)
        .padding(.top, 8)
        .padding(.bottom, 2)
    }
}

/// A small 4:3 copy of a painting, for the journal list.
struct PaintingThumbnail: View {
    let tableau: Tableau
    let width: CGFloat

    var body: some View {
        Image(tableau.imageName)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: width, height: width * 3 / 4)
            .clipShape(.rect(cornerRadius: width / 8))
            .accessibilityLabel(Text("Painting: \(frenchText(tableau.title))"))
    }
}

/// The sheet for adding or replacing an entry's painting: "All" and the theme chips,
/// the paintings grouped by theme, and the chosen painting's word at the foot.
///
/// It always opens on All. With a painting already chosen, from replacing one or from
/// the day's prompt, that painting is selected and scrolled into view.
struct PaintingPicker: View {

    /// The painting being replaced, or `nil` when adding one.
    let current: Tableau?
    /// Called with the painting chosen when Add or Replace is clicked.
    let choose: (Tableau) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selection: Tableau?
    /// The theme the list is narrowed to, or `nil` for All.
    @State private var themeID: String?

    /// Opens on `current` when replacing, else on `suggested`, such as the day's prompt painting.
    init(current: Tableau?, suggested: Tableau?, choose: @escaping (Tableau) -> Void) {
        self.current = current
        self.choose = choose
        _selection = State(initialValue: current ?? suggested)
    }

    /// The themes with at least one painting to choose.
    private static var themes: [TableauTheme] {
        let used = Set(TableauCatalog.available.map(\.theme))
        return TableauCatalog.themes.filter { used.contains($0.id) }
    }

    /// The themes shown: every one under All, or just the chosen one.
    private var shownThemes: [TableauTheme] {
        guard let themeID else { return Self.themes }
        return Self.themes.filter { $0.id == themeID }
    }

    /// A theme's paintings, in the catalog's order.
    private func paintings(in theme: TableauTheme) -> [Tableau] {
        TableauCatalog.available.filter { $0.theme == theme.id }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                Text("Optional. It adds a //: tableau line to your entry, which the checker never reads.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 12)

                themeChips
                    .padding(.bottom, 4)

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 22) {
                            ForEach(shownThemes, id: \.id) { theme in
                                section(theme)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                        .padding(.bottom, 16)
                    }
                    .onAppear {
                        if let selection { proxy.scrollTo(selection.id, anchor: .center) }
                    }
                    .onChange(of: themeID) {
                        if let selection, themeID == nil || themeID == selection.theme {
                            proxy.scrollTo(selection.id, anchor: .center)
                        }
                    }
                }

                Divider()
                footer
            }
            .navigationTitle(current == nil ? "Add a painting" : "Replace painting")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(current == nil ? "Add" : "Replace") {
                        if let selection { choose(selection) }
                        dismiss()
                    }
                    .disabled(selection == nil || selection == current)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 640, idealWidth: 720, minHeight: 560, idealHeight: 640)
        #endif
    }

    /// The narrowest a tile gets: three across on iPhone, four or more on the Mac.
    private static var tileWidth: CGFloat {
        #if os(macOS)
        140
        #else
        100
        #endif
    }

    /// A theme's heading, with its French and English names and a count, above its grid.
    private func section(_ theme: TableauTheme) -> some View {
        let tableaux = paintings(in: theme)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(frenchText(theme.french))
                    .font(.paintingTitle(.title3))
                Text(theme.english)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text("\(tableaux.count)")
                    .font(.plexMono(11, relativeTo: .caption2))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("\(tableaux.count) paintings")
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: Self.tileWidth), spacing: 12)], spacing: 14) {
                ForEach(tableaux, id: \.id) { tableau in
                    tile(tableau)
                        .id(tableau.id)
                }
            }
        }
    }

    /// "All" first, then one button per theme; the chosen one is filled.
    private var themeChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", isOn: themeID == nil) { themeID = nil }
                ForEach(Self.themes, id: \.id) { theme in
                    chip(theme.buttonTitle, isOn: theme.id == themeID) { themeID = theme.id }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    /// One theme button.
    private func chip(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.callout.weight(.medium))
                .padding(.horizontal, 14)
                .frame(minHeight: 32)
                .foregroundStyle(isOn ? Color.white : Color.primary)
                .background(isOn ? Color.brand : Color.clear, in: .capsule)
                .overlay(Capsule().strokeBorder(isOn ? Color.clear : Color.secondary.opacity(0.4)))
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    /// A painting and its title; clicking it chooses it, and clicking it again clears the choice.
    private func tile(_ tableau: Tableau) -> some View {
        let isOn = tableau == selection
        return Button {
            selection = isOn ? nil : tableau
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Color.clear
                    .aspectRatio(4 / 3, contentMode: .fit)
                    .overlay {
                        Image(tableau.imageName)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    }
                    .clipShape(.rect(cornerRadius: 9))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9)
                            .strokeBorder(isOn ? Color.brand : Color.secondary.opacity(0.25), lineWidth: isOn ? 3 : 1)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if isOn {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title3)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, Color.brand)
                                .padding(6)
                        }
                    }
                Text(frenchText(tableau.title))
                    .font(.paintingTitle(.subheadline))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(frenchText(tableau.title)), \(frenchText(tableau.word))"))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    /// The chosen painting's title and word, or a hint when nothing is chosen.
    private var footer: some View {
        HStack(spacing: 12) {
            if let selection {
                PaintingThumbnail(tableau: selection, width: 72)
                VStack(alignment: .leading, spacing: 2) {
                    Text(frenchText(selection.title))
                        .font(.paintingTitle(.title3))
                    Text("\(Text(frenchText(selection.word)).foregroundStyle(Color.brand).fontWeight(.medium)) · \(selection.wordEnglish)")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
            } else {
                #if os(macOS)
                Text("Click a painting to see its word.")
                #else
                Text("Tap a painting to see its word.")
                #endif
            }
            Spacer(minLength: 0)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(minHeight: 82)
    }
}

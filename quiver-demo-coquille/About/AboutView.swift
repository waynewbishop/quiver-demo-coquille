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

/// One slide of the About dialog: a widget painting with its prompt in French and English.
///
/// Nothing is retyped here. The painting, its title, style and description come from
/// `TableauCatalog`, and the English from the matching prompt in `fr.prompts.json`.
struct AboutSlide {
    /// The painting, its French title and prompt, its style and its VoiceOver description.
    let tableau: Tableau
    /// The prompt in English.
    let english: String

    /// Every painting that has a prompt, in the catalog's order.
    static let all: [AboutSlide] = TableauCatalog.all.compactMap { tableau in
        PromptCatalog.prompt(withID: tableau.promptID)
            .map { AboutSlide(tableau: tableau, english: $0.text) }
    }

    /// The slide for the prompt that's today's on `date`, the one the widget shows.
    static func index(on date: Date = .now) -> Int {
        let today = PromptCatalog.prompt(on: date)
        return all.firstIndex { $0.tableau.promptID == today.id } ?? 0
    }
}

/// The page shown in the About dialog's panel.
private enum AboutPage {
    case about
    case acknowledgments
    case privacy
}

/// The About dialog: a slideshow of the widget's paintings beside the app's name, version,
/// today's prompt and links to the acknowledgments and privacy pages.
///
/// The Mac shows it in its own fixed-size window, the iPad in a sheet sized to it, and the
/// iPhone in a sheet with the painting above the panel.
struct AboutView: View {

    /// The Mac window's scene identifier, used by the app menu and Settings.
    static let windowID = "about"

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @State private var index = AboutSlide.index()
    @State private var isPaused = false
    @State private var page = AboutPage.about

    #if os(macOS)
    private let isCompact = false
    #else
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var isCompact: Bool { sizeClass == .compact }
    #endif

    private var slide: AboutSlide { AboutSlide.all[index] }

    var body: some View {
        Group {
            if isCompact {
                VStack(spacing: 0) {
                    gallery
                        .frame(height: 340)
                        .overlay(alignment: .topTrailing) {
                            Button("Done") { dismiss() }
                                .buttonStyle(.borderedProminent)
                                .padding(16)
                        }
                    panel
                        .padding(24)
                }
            } else {
                HStack(spacing: 0) {
                    gallery
                        .frame(width: 333)
                    panel
                        .padding(EdgeInsets(top: 32, leading: 27, bottom: 21, trailing: 27))
                }
                .frame(width: 640, height: 400)
            }
        }
        .foregroundStyle(Color("AboutInk"))
        .tint(.brand)
        .background(Color("AboutPanel"))
        .task(id: [isPaused, reduceMotion]) { await rotate() }
    }

    // MARK: Gallery

    /// The paintings stacked on one another, the current one shown, with the caption bar over them.
    private var gallery: some View {
        ZStack(alignment: .bottom) {
            ForEach(AboutSlide.all.indices, id: \.self) { k in
                Color.clear
                    .overlay {
                        Image(AboutSlide.all[k].tableau.imageName)
                            .resizable()
                            .scaledToFill()
                            .animation(reduceMotion ? nil : .linear(duration: 7)) {
                                $0.scaleEffect(k == index && !reduceMotion ? 1.06 : 1)
                            }
                    }
                    .clipped()
                    .animation(.easeInOut(duration: 1.2)) {
                        $0.opacity(k == index ? 1 : 0)
                    }
                    .accessibilityElement()
                    .accessibilityLabel(AboutSlide.all[k].tableau.description)
                    .accessibilityAddTraits(.isImage)
                    .accessibilityHidden(k != index)
            }
            captionBar
        }
        .clipped()
    }

    /// The painting's title, the slide dots and the pause button on a dark scrim.
    private var captionBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Text(french(slide.tableau.title))
                .font(.system(size: isCompact ? 22 : 18, design: .serif).italic())
                .lineLimit(2)
            Spacer(minLength: 8)
            HStack(spacing: isCompact ? 4 : 3) {
                ForEach(AboutSlide.all.indices, id: \.self) { k in
                    Circle()
                        .fill(.white.opacity(k == index ? 1 : 0.4))
                        .frame(width: isCompact ? 5 : 4, height: isCompact ? 5 : 4)
                }
            }
            .padding(.bottom, isCompact ? 20 : 10)
            .accessibilityHidden(true)
            if !reduceMotion {
                Button { isPaused.toggle() } label: {
                    Image(systemName: isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: isCompact ? 15 : 10))
                        .frame(width: isCompact ? 44 : 24, height: isCompact ? 44 : 24)
                        .background(.white.opacity(0.22), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isPaused ? "Play slideshow" : "Pause slideshow")
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .padding(.top, 50)
        .background(
            LinearGradient(colors: [Color(red: 14 / 255, green: 20 / 255, blue: 36 / 255).opacity(0.78), .clear],
                           startPoint: .bottom, endPoint: .top)
        )
    }

    /// Moves to the next painting every six seconds until paused, or not at all with Reduce Motion.
    private func rotate() async {
        guard !isPaused, !reduceMotion else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            index = (index + 1) % AboutSlide.all.count
        }
    }

    // MARK: Panel

    /// The page now shown beside or below the painting.
    @ViewBuilder private var panel: some View {
        switch page {
        case .about: aboutPage
        case .acknowledgments: AcknowledgmentsPage(isCompact: isCompact) { page = .about }
        case .privacy: PrivacyPage(isCompact: isCompact) { page = .about }
        }
    }

    /// The name, version, tagline, today's prompt, links and copyright.
    private var aboutPage: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Coquille")
                .font(.system(size: isCompact ? 34 : 30, weight: .semibold))
            Text("Version \(Bundle.main.versionAndBuild)")
                .font(.system(size: isCompact ? 14 : 12))
                .foregroundStyle(.secondary)
            Text(french("Un compilateur pour votre français."))
                .font(.system(size: isCompact ? 18 : 15, design: .serif).italic())
            Divider()
                .overlay(Color("AboutRule"))
                .padding(.vertical, 14)
            Text(french(slide.tableau.style.uppercased()))
                .font(.system(size: 11, design: .monospaced))
                .tracking(1)
                .foregroundStyle(.secondary)
            Text(french(slide.tableau.french))
                .font(.system(size: isCompact ? 24 : 19, design: .serif).italic())
                .fixedSize(horizontal: false, vertical: true)
            Text(slide.english)
                .font(.system(size: isCompact ? 14 : 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            HStack(spacing: 20) {
                Button("Acknowledgments") { page = .acknowledgments }
                Button("Privacy") { page = .privacy }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .font(.system(size: isCompact ? 16 : 13, weight: .medium))
            Text("© 2026 Wayne W Bishop. All rights reserved.")
                .font(.system(size: isCompact ? 12 : 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// French text tagged so VoiceOver reads it with a French voice.
private func french(_ string: String) -> AttributedString {
    var text = AttributedString(string)
    text.languageIdentifier = "fr"
    return text
}

/// The shared frame of the Acknowledgments and Privacy pages: the back link and title,
/// then the page's text, scrolling when it's longer than the panel.
private struct AboutSubpage<Content: View>: View {
    let title: String
    let isCompact: Bool
    let back: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button("‹ Coquille", action: back)
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .font(.system(size: isCompact ? 16 : 13, weight: .medium))
            Text(title)
                .font(.system(size: isCompact ? 24 : 20, weight: .semibold))
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    content
                }
                .font(.system(size: isCompact ? 15 : 13))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// What Coquille is built on, each with its license.
private struct AcknowledgmentsPage: View {
    let isCompact: Bool
    let back: () -> Void

    var body: some View {
        AboutSubpage(title: "Acknowledgments", isCompact: isCompact, back: back) {
            credit("Quiver.", link: "https://waynewbishop.github.io/quiver", "The machine learning behind spelling suggestions, the part-of-speech layer, the gender of unknown nouns and phrasebook search. Apache License 2.0.")
            credit("Lexique 3.83.", link: "http://www.lexique.org", "The French word list behind spelling, gender and conjugation. By Boris New and Christophe Pallier. CC BY-SA 4.0.")
            credit("Universal Dependencies.", "The French GSD, Rhapsodie and ParisStories treebanks, used to build the part-of-speech models and the verb preposition list. CC BY-SA 4.0.")
            credit("Paintings.", "Made for Coquille, in the style of Monet and Cézanne.")
        }
    }

    /// One credit: its name in bold, linked to its site when it has one, then what it does and its license.
    private func credit(_ name: String, link: String? = nil, _ detail: String) -> some View {
        var title = AttributedString(name)
        title.inlinePresentationIntent = .stronglyEmphasized
        if let link, let url = URL(string: link) {
            title.link = url
        }
        return Text(title + AttributedString(" " + detail))
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Where the learner's writing goes, which is nowhere but this device.
private struct PrivacyPage: View {
    let isCompact: Bool
    let back: () -> Void

    var body: some View {
        AboutSubpage(title: "Privacy", isCompact: isCompact, back: back) {
            Text(french("Votre français reste chez vous."))
                .font(.system(size: isCompact ? 18 : 15, design: .serif).italic())
            Text("Your journal and your stats stay on this device. Coquille doesn't sync them.")
            Text("The checker, Explain, the English translation and French playback all run on the device. Nothing you write is sent to a server.")
            Text("Coquille has no account, no ads and no tracking.")
        }
    }
}

extension Bundle {
    /// The version and build, as in "1.0 (2)".
    var versionAndBuild: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        guard let build = infoDictionary?["CFBundleVersion"] as? String else { return version }
        return "\(version) (\(build))"
    }
}

#if os(macOS)
/// Replaces the standard About Coquille in the app menu with this dialog.
struct AboutCommands: Commands {

    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Coquille") { openWindow(id: AboutView.windowID) }
        }
    }
}
#endif

#Preview {
    AboutView()
}

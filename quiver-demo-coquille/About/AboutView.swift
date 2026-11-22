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

/// The page shown in the About dialog.
private enum AboutPage {
    case about
    case acknowledgments
    case privacy
}

/// The About dialog: a stack of painting stamps over the app's name, tagline, version and
/// links to the acknowledgments and privacy pages.
///
/// The Mac shows it in its own fixed-size window, the iPad in a sheet sized to it, and the
/// iPhone in a full sheet with a Done button.
struct AboutView: View {

    /// The Mac window's scene identifier, used by the app menu and Settings.
    static let windowID = "about"

    @Environment(\.dismiss) private var dismiss
    @State private var page = AboutPage.about
    /// Lives here, not in the stack, so the order survives a visit to Privacy.
    @State private var deck = ShuffleDeck(count: TableauCatalog.available.count)

    #if os(macOS)
    private let isCompact = false
    #else
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var isCompact: Bool { sizeClass == .compact }
    #endif

    var body: some View {
        Group {
            switch page {
            case .about: aboutPage
            case .acknowledgments: AcknowledgmentsPage(isCompact: isCompact) { page = .about }
            case .privacy: PrivacyPage(isCompact: isCompact) { page = .about }
            }
        }
        // Room for the Mac window's controls.
        .padding(.top, isCompact ? 0 : 40)
        .frame(width: isCompact ? nil : 440, height: isCompact ? nil : 620)
        .frame(maxWidth: isCompact ? .infinity : nil, maxHeight: isCompact ? .infinity : nil)
        .foregroundStyle(Color("AboutInk"))
        .tint(.brand)
        .background(Color("AboutPanel"))
        .overlay(alignment: .topTrailing) {
            if isCompact {
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .padding(16)
            }
        }
    }

    /// The stamp stack, then the name, tagline and version, with the links and copyright at the foot.
    private var aboutPage: some View {
        VStack(spacing: 0) {
            StampStack(deck: $deck)
                .frame(height: 300)
            Text("Coquille")
                .font(.system(size: 30, weight: .semibold))
                .padding(.top, 18)
            Text(french("Un compilateur pour votre français."))
                .font(.cormorant(fixed: 21))
                .padding(.top, 6)
            Text("Version \(Bundle.main.versionAndBuild)")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .padding(.top, 8)
            Spacer(minLength: 16)
            HStack(spacing: 22) {
                Button("Acknowledgments") { page = .acknowledgments }
                Button("Privacy") { page = .privacy }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .font(.system(size: isCompact ? 16 : 13, weight: .medium))
            Text("© 2026 Wayne W Bishop. All rights reserved.")
                .font(.cormorant(fixed: isCompact ? 17 : 15, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.top, 6)
        }
        .multilineTextAlignment(.center)
        .padding(EdgeInsets(top: 0, leading: 40, bottom: 22, trailing: 40))
    }
}

/// The paintings as a stack of stamps: the top one lifts away every few seconds to show the next.
private struct StampStack: View {
    @Binding var deck: ShuffleDeck

    /// How long each stamp stays on top.
    private let interval = Duration.seconds(4)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isLifting = false

    private var paintings: [Tableau] { TableauCatalog.available }

    var body: some View {
        ZStack {
            // Only the top three are views, so only three images are ever loaded.
            ForEach(Array(deck.upcoming.prefix(3).enumerated()), id: \.element) { place, index in
                let p = placement(place)
                PaintingStamp(tableau: paintings[index], width: 300, tilt: p.angle, titleSize: 24)
                    .offset(x: p.x, y: p.y)
                    .opacity(p.opacity)
                    .zIndex(Double(3 - place))
                    .transition(.opacity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .task { await run() }
    }

    /// Where a stamp sits: 0 is the top stamp, 1 and 2 peek out beneath it.
    private func placement(_ place: Int) -> (x: CGFloat, y: CGFloat, angle: Double, opacity: Double) {
        if place == 0 && isLifting {
            return reduceMotion ? (0, 0, 1.5, 0) : (30, -90, -9, 0)
        }
        switch place {
        case 0: return (0, 0, 1.5, 1)
        case 1: return (-10, 8, -3, 1)
        default: return (12, 14, 4, 1)
        }
    }

    /// The VoiceOver label naming the top painting, its title tagged French.
    private var label: AttributedString {
        var text = AttributedString("A stack of painting stamps. On top: ")
        text += french(paintings[deck.top].title)
        text += AttributedString(".")
        return text
    }

    /// Lifts the top stamp away every few seconds until the view goes away.
    private func run() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: interval)
            guard !Task.isCancelled else { return }
            let lift = reduceMotion ? 0.4 : 0.7
            withAnimation(.easeInOut(duration: lift)) { isLifting = true }
            try? await Task.sleep(for: .seconds(lift))
            guard !Task.isCancelled else { return }
            // With Reduce Motion the stamps beneath take their places without sliding.
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.7)) {
                deck.advance()
                isLifting = false
            }
        }
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
                .frame(maxWidth: .infinity)
                .padding(.top, 28)
            ScrollView {
                VStack(spacing: 12) {
                    content
                }
                .multilineTextAlignment(.center)
                .font(.cormorant(fixed: isCompact ? 17 : 15, weight: .medium))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(EdgeInsets(top: 10, leading: 36, bottom: 28, trailing: 36))
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
            credit("Cormorant Garamond.", link: "https://github.com/CatharsisFonts/Cormorant", "The italic of painting titles, the calendar and postcards. By Christian Thalmann. SIL Open Font License 1.1.")
            Text(french("Merci."))
                .font(.cormorant(fixed: isCompact ? 24 : 21))
                .padding(.top, 8)
        }
    }

    /// One credit: its name in bold, linked to its site when it has one, then what it does and its license, in the italic of the tagline.
    private func credit(_ name: String, link: String? = nil, _ detail: String) -> some View {
        var title = AttributedString(name)
        title.font = .cormorant(fixed: isCompact ? 17 : 15, weight: .semibold)
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
                .font(.cormorant(fixed: isCompact ? 22 : 18))
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

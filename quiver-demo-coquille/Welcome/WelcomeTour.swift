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

/// One page of the first-run tour: its heading, its explanation, and on the Mac the keys it teaches.
enum TourPage: Int, CaseIterable, Identifiable {
    case welcome
    case mistakes
    case unlock
    case notes
    case phrasebook
    case journal
    case ready

    var id: Int { rawValue }

    /// The page's heading.
    var title: String {
        switch self {
        case .welcome: "Your French, in your own words."
        case .mistakes: "See it first, then fix it yourself."
        case .unlock: "Fix first, then listen."
        case .notes: "Correct isn't always natural."
        case .phrasebook: "Borrow a phrase, make it yours."
        case .journal: "A little French, every day."
        case .ready: "Ready to write."
        }
    }

    /// The page's explanation, worded for taps on iPhone and iPad and clicks on the Mac.
    ///
    /// On iPhone and iPad it's at most three lines, so every page fits without scrolling.
    var body: String {
        switch self {
        case .welcome:
            #if os(macOS)
            return "Write about your day, your plans, or anything on your mind. Mistakes are part of learning, and Coquille helps you understand and correct them yourself."
            #else
            return "Write about your day or anything on your mind. Coquille helps you understand and correct your mistakes yourself."
            #endif
        case .mistakes:
            #if os(macOS)
            return "Coquille underlines mistakes as you write. Click an underline to see the rule, then try correcting the sentence yourself. Errors need fixing; warnings and suggestions are there to help."
            #else
            return "Tap an underline to see the rule, then try correcting it yourself. Errors need fixing; warnings and suggestions help."
            #endif
        case .unlock:
            #if os(macOS)
            return "Fix or ignore your errors to unlock French playback and English translation. It's a chance to learn from each mistake before hearing or reading the answer. Warnings won't keep these features locked."
            #else
            return "Fix or ignore your errors to unlock French playback and English. Warnings won't keep them locked."
            #endif
        case .notes:
            #if os(macOS)
            return "A sentence can be correct but still sound unusual in French. Turn on Show suggestions to see phrases that could sound more natural. Add notes with // that Coquille won't check, or start one with //: natural to ask your reviewer. Share Text sends your writing with its notes."
            #else
            return "Show suggestions marks phrases that could sound more natural. Add notes with // that Coquille won't check."
            #endif
        case .phrasebook:
            #if os(macOS)
            return "Find everyday French phrases with English translations and pronunciation. Search for something useful, then try writing your own version."
            #else
            return "Everyday French phrases with English and pronunciation. Find one you need, then write your own version."
            #endif
        case .journal:
            #if os(macOS)
            return "A short sentence is enough to get started. Click Save to keep it in your journal, then choose File › Painting to add a painting and Share as Postcard to send it. Open Progress to see how far you've come."
            #else
            return "A short sentence is enough to start. Save it to your journal, add a painting, and share it as a postcard."
            #endif
        case .ready:
            #if os(macOS)
            return "Coquille works offline, with no account needed. English translations are optional: download the French-English translation pack if you want them. French voice uses your device's voice settings. Then start today's entry, or try an example to see how Coquille works."
            #else
            return "Works offline, no account needed. English needs the translation pack. Start today's entry or try an example."
            #endif
        }
    }

    /// The Mac keyboard shortcuts this page teaches, as key and description.
    var keys: [(key: String, action: String)] {
        switch self {
        case .mistakes: [("⌘'", "Next issue"), ("⇧⌘'", "Previous issue")]
        case .unlock: [("⌘↵", "Play or pause"), ("⌘.", "Stop"), ("⌥⌘E", "Show or hide English")]
        case .notes: [("⇧⌘E", "Export a Copy…")]
        case .journal: [("⌘N", "New page"), ("⌘S", "Save to your journal")]
        default: []
        }
    }

    /// "3 OF 7".
    var step: String {
        "\(rawValue + 1) OF \(Self.allCases.count)"
    }

    /// The page after this one, or `nil` on the last.
    var next: TourPage? {
        TourPage(rawValue: rawValue + 1)
    }

    /// The page before this one, or `nil` on the first.
    var previous: TourPage? {
        TourPage(rawValue: rawValue - 1)
    }
}

/// Opens the welcome tour again: a full-screen cover on iPhone, a sheet on iPad, its own window on the Mac.
struct ShowWelcomeTourAction {

    private let action: @MainActor () -> Void

    /// Creates the action from what opens the tour.
    init(_ action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    /// Opens the tour.
    @MainActor func callAsFunction() {
        action()
    }
}

extension EnvironmentValues {
    /// Opens the welcome tour again, as ContentView sets it.
    @Entry var showWelcomeTour = ShowWelcomeTourAction {}
}

/// The seven-page tour shown at first launch: a hands-on stage above each page's
/// explanation on iPhone and iPad, and on the Mac one window with the stage beside it.
struct WelcomeTour: View {

    /// Set once the tour has been shown, so it opens by itself only at first launch.
    static let seenKey = "hasSeenWelcomeTour"
    /// The Mac window's scene identifier, used by the Help menu.
    static let windowID = "welcome"

    @AppStorage(Self.seenKey) private var hasSeenTour = false
    @AppStorage(SpeechNarrator.voiceStorageKey) private var playbackVoiceID = ""
    @State private var page = TourPage.welcome
    #if !os(macOS)
    /// The text size, which decides whether a page needs to scroll.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #endif
    /// Reads the tour's sample French aloud, apart from the editor's own narrator.
    @State private var narrator = SpeechNarrator(language: "fr-FR")
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        content
            .tint(.brand)
            .onAppear { hasSeenTour = true }
            .onChange(of: playbackVoiceID, initial: true) { narrator.voiceID = playbackVoiceID }
            .onChange(of: page) { narrator.stop() }
            .onDisappear { narrator.stop() }
    }

    /// The stage for the current page, rebuilt per page so each starts fresh.
    private var stage: some View {
        TourStage(page: page, narrator: narrator)
            .id(page)
    }

    /// The label on the forward button.
    private var nextLabel: String {
        switch page {
        case .welcome: "Show me how"
        case .ready: "Start writing"
        default:
            #if os(macOS)
            "Continue"
            #else
            "Next"
            #endif
        }
    }

    /// Goes to the next page, or closes the tour from the last.
    private func forward() {
        if let next = page.next {
            withAnimation(.snappy(duration: 0.25)) { page = next }
        } else {
            dismiss()
        }
    }

    /// Goes back a page.
    private func back() {
        if let previous = page.previous {
            withAnimation(.snappy(duration: 0.25)) { page = previous }
        }
    }

    /// The page dots, with the current page drawn wide.
    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(TourPage.allCases) { dot in
                Capsule()
                    .fill(dot == page ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                    .frame(width: dot == page ? 22 : 7, height: 7)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Page \(page.rawValue + 1) of \(TourPage.allCases.count)")
    }

    /// "1 OF 7" above the stage or the heading.
    private var stepLabel: some View {
        Text(page.step)
            .font(.plexMono(12, weight: .medium, relativeTo: .caption))
            .tracking(1)
            .foregroundStyle(.secondary)
    }

    #if os(macOS)
    /// The Mac window: the stage on the left, and on the right the heading, explanation,
    /// keys, and Skip, Back and Continue.
    private var content: some View {
        HStack(spacing: 0) {
            stage
                .padding(28)
                .frame(width: 500)
                .frame(maxHeight: .infinity)
                .background(.quaternary.opacity(0.35))
                .overlay(alignment: .trailing) { Divider() }

            VStack(alignment: .leading, spacing: 0) {
                stepLabel
                Text(page.title)
                    .font(.plexSans(28, weight: .medium, relativeTo: .largeTitle))
                    .padding(.top, 10)
                Text(page.body)
                    .font(.plexSans(15, relativeTo: .body))
                    .lineSpacing(4)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)
                if !page.keys.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(page.keys, id: \.key) { key in
                            HStack(spacing: 12) {
                                KeyCap(key.key)
                                Text(key.action)
                                    .font(.plexSans(14, relativeTo: .callout))
                            }
                        }
                    }
                    .padding(.top, 20)
                }
                Spacer(minLength: 16)
                HStack(spacing: 10) {
                    if page.next != nil {
                        Button("Skip tour") { dismiss() }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    dots
                        .padding(.trailing, 8)
                    if page.previous != nil {
                        Button("Back", action: back)
                            .controlSize(.large)
                    }
                    Button(nextLabel, action: forward)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(EdgeInsets(top: 44, leading: 40, bottom: 24, trailing: 40))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: 960, height: 600)
        .background(Color.frenchPaper)
    }
    #else
    /// The iPhone and iPad layout: the step and Skip, the stage, the heading and
    /// explanation, then the dots and Back and Next.
    ///
    /// Every page fits on screen without scrolling. Only at the accessibility text sizes,
    /// where the larger type can't fit, does the page scroll.
    private var content: some View {
        VStack(spacing: 0) {
            HStack {
                stepLabel
                Spacer()
                if page.next != nil {
                    Button("Skip") { dismiss() }
                        .font(.plexSans(15, weight: .medium, relativeTo: .body))
                        .foregroundStyle(.secondary)
                        .frame(minHeight: 44)
                }
            }
            .frame(minHeight: 44)
            .padding(.leading, 24)
            .padding(.trailing, 20)

            if dynamicTypeSize.isAccessibilitySize {
                ScrollView { pageContent }
                    .scrollBounceBehavior(.basedOnSize)
            } else {
                pageContent
                    .frame(maxHeight: .infinity, alignment: .top)
            }

            VStack(spacing: 16) {
                dots
                HStack(spacing: 10) {
                    if page.previous != nil {
                        Button("Back", action: back)
                            .font(.plexSans(17, weight: .medium, relativeTo: .body))
                            .frame(minHeight: 50)
                            .padding(.horizontal, 22)
                    }
                    Button(action: forward) {
                        Text(nextLabel)
                            .font(.plexSans(17, weight: .medium, relativeTo: .body))
                            .frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            .padding(.top, 8)
        }
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .background(Color.frenchPaper.ignoresSafeArea())
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
    }

    /// The stage, then the page's heading and explanation.
    private var pageContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            stage
                .frame(height: 320)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.separator))
                .padding(.horizontal, 20)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 10) {
                Text(page.title)
                    .font(.plexSans(26, weight: .medium, relativeTo: .largeTitle))
                Text(page.body)
                    .font(.plexSans(16, relativeTo: .body))
                    .lineSpacing(3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if page == .mistakes {
                    SeverityLegend()
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 20)
            .padding(.bottom, 12)
        }
    }
    #endif
}

/// The three severity marks under the Mistakes page on iPhone and iPad.
private struct SeverityLegend: View {
    var body: some View {
        HStack(spacing: 16) {
            Label { Text("Error") } icon: {
                Circle().fill(.red).frame(width: 8, height: 8)
            }
            Label { Text("Warning") } icon: {
                RoundedRectangle(cornerRadius: 1).fill(.orange).frame(width: 7, height: 7).rotationEffect(.degrees(45))
            }
            Label { Text("Suggestion") } icon: {
                Circle().strokeBorder(.secondary, lineWidth: 1.5).frame(width: 8, height: 8)
            }
        }
        .labelStyle(TightLabelStyle())
        .font(.plexSans(13, weight: .medium, relativeTo: .footnote))
        .foregroundStyle(.secondary)
    }
}

/// A label with its small mark close beside the text.
private struct TightLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon
            configuration.title
        }
    }
}

/// A key, or a key combination, drawn as a keycap.
struct KeyCap: View {

    let key: String

    /// Creates a keycap showing `key`, such as "⌘↵".
    init(_ key: String) {
        self.key = key
    }

    var body: some View {
        Text(key)
            .font(.plexMono(12, weight: .medium, relativeTo: .caption))
            .padding(.horizontal, 7)
            .frame(minWidth: 56, minHeight: 24)
            .background(.background, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
            .accessibilityLabel(key)
    }
}

#if os(macOS)
/// The Help menu's Welcome to Coquille, which reopens the tour window.
struct WelcomeCommands: Commands {

    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("Welcome to Coquille") { openWindow(id: WelcomeTour.windowID) }
        }
    }
}
#endif

#Preview {
    WelcomeTour()
}

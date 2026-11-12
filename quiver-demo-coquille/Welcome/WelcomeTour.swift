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
        case .journal: "A little every day."
        case .ready: "One download, then write."
        }
    }

    /// The page's explanation, worded for taps on iPhone and iPad and clicks on the Mac.
    var body: String {
        switch self {
        case .welcome:
            return "There's no answer key. Write about your day, mistakes and all. Coquille marks them the way a teacher's red pen would, and the fix stays yours to make."
        case .mistakes:
            #if os(macOS)
            return "You can't fix a mistake you can't see. Click an underline and the card names the rule but holds the answer back, so you get the first try. Looking it up isn't cheating: Show fix is always there."
            #else
            return "You can't fix a mistake you can't see. Tap an underline and the card names the rule but holds the answer back, so you get the first try. Looking it up isn't cheating: Show fix is always there."
            #endif
        case .unlock:
            #if os(macOS)
            return "Hearing your French aloud and reading it in English are the reward for a clean page. The translator would quietly smooth over a mistake, so errors hold back Play in the toolbar and the English pane beside your page. Warnings never do."
            #else
            return "Hearing your French aloud and reading it in English are the reward for a clean page. The translator would quietly smooth over a mistake, so errors hold both back. Warnings never do, and the lock takes you to what's left."
            #endif
        case .notes:
            #if os(macOS)
            return "Coquille catches French that's wrong, not French that's right but stiff. Notes after // are never checked, so mark a sentence //: natural and share the page with your teacher or other French learners. Share and Export a Copy send plain text, notes and markers included."
            #else
            return "Coquille catches French that's wrong, not French that's right but stiff. Notes after // are never checked, so mark a sentence //: natural and share the page with your teacher or other French learners, notes and all."
            #endif
        case .phrasebook:
            #if os(macOS)
            return "The phrasebook opens as a panel beside your page, so you can read a phrase and type it out at the same time. There's no copy button on purpose: typing it is how it sticks, and Coquille checks it like the rest of your French."
            #else
            return "Hundreds of everyday phrases, each with English, a tu or vous tag and a play button. There's no copy button on purpose: typing a phrase out is how it sticks, and Coquille checks it like the rest of your French."
            #endif
        case .journal:
            #if os(macOS)
            return "Your journal sits in the sidebar with a new prompt each day, and a few sentences a day keep the momentum going. Every fix lands in the Corrections window, so you can see what keeps coming back. Entries are plain text files; right-click one to Show in Finder."
            #else
            return "A new prompt each day gets you past the blank page, and a few sentences a day keep the momentum going. Every fix lands in your corrections list, so you can see what keeps coming back. It all stays private, on your devices."
            #endif
        case .ready:
            return "Everything else is built in and works offline, with no account. Keeping a paper notebook too? Type a page in here and Coquille will mark it. You can change these anytime in Settings."
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

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    stage
                        .frame(height: 410)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.separator))
                        .padding(.horizontal, 20)
                        .padding(.top, 6)

                    VStack(alignment: .leading, spacing: 12) {
                        Text(page.title)
                            .font(.plexSans(28, weight: .medium, relativeTo: .largeTitle))
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
                    .padding(.top, 28)
                    .padding(.bottom, 16)
                }
            }
            .scrollBounceBehavior(.basedOnSize)

            VStack(spacing: 20) {
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

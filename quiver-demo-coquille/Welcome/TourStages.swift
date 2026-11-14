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

import AVFoundation
import SwiftUI
// TranslationSession isn't Sendable, yet the framework hands one to `.translationTask`,
// and `prepareDownload` uses it once and lets it go.
@preconcurrency import Translation

/// The hands-on part of a tour page: a scripted sample of the editor the learner can try.
///
/// The samples are scripted rather than linted, so the tour works before the French pack
/// has loaded and always shows the same mistake. The phrasebook search, the read-aloud,
/// Share, Export a Copy and the language download are the real ones.
struct TourStage: View {

    let page: TourPage
    let narrator: SpeechNarrator

    var body: some View {
        switch page {
        case .welcome: WelcomeStage()
        case .mistakes: MistakeStage()
        case .unlock: UnlockStage(narrator: narrator)
        case .notes: NotesStage()
        case .phrasebook: PhrasebookStage(narrator: narrator)
        case .journal: JournalStage()
        case .ready: ReadyStage()
        }
    }
}

// MARK: - Shared pieces

/// The French sentence every stage uses, before and after its fix.
private enum Sample {
    static let corrected = "Nous avons acheté un fromage."
    static let english = "We bought a cheese."

    /// The size of the stage's French: larger on iPhone and iPad, as in the editor.
    static var frenchSize: Double {
        #if os(macOS)
        17
        #else
        19
        #endif
    }

    /// "Tap" on iPhone and iPad, "Click" on the Mac.
    static var press: String {
        #if os(macOS)
        "Click"
        #else
        "Tap"
        #endif
    }
}

/// A small uppercase label at the top of a stage, such as TRY IT or SAMPLE DATA.
private struct StageLabel: View {

    let text: String
    var isMuted = false

    /// Creates a label reading `text`, in the tint or, when muted, in gray.
    init(_ text: String, isMuted: Bool = false) {
        self.text = text
        self.isMuted = isMuted
    }

    var body: some View {
        Text(text)
            .font(.plexMono(11, weight: .medium, relativeTo: .caption2))
            .tracking(2)
            .foregroundStyle(isMuted ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
    }
}

/// A flagged word or phrase, underlined as the editor marks an error, that the learner presses.
private struct FlaggedWord: View {

    let text: String
    let accessibilityText: String
    /// Whether the word is highlighted, as when the play button's lock jumps to it.
    var isLit = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .underline(pattern: .solid, color: .red)
                .padding(.horizontal, 1)
                .background(isLit ? Color.yellow.opacity(0.4) : Color.clear, in: RoundedRectangle(cornerRadius: 3))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText)
    }
}

/// The surface the sample French sits on, like the editor's page.
private struct PaperCard: ViewModifier {

    var cornerRadius = 16.0

    func body(content: Content) -> some View {
        content
            .background(.background, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(.separator))
    }
}

private extension View {
    /// Sets the view on a card like the editor's page.
    func paperCard(cornerRadius: Double = 16) -> some View {
        modifier(PaperCard(cornerRadius: cornerRadius))
    }

    /// Fills the stage with its slightly darker ground, behind the page cards.
    func stageGround() -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.secondary.opacity(0.07))
    }
}

/// A tall blinking caret, where the learner would type next.
private struct Caret: View {

    @State private var isVisible = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Rectangle()
            .fill(.tint)
            .frame(width: 1.5, height: 15)
            .opacity(isVisible ? 1 : 0)
            .accessibilityHidden(true)
            .task {
                guard !reduceMotion else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(500))
                    isVisible.toggle()
                }
            }
    }
}

/// A sample Coquille window on the Mac stages: a title bar with optional controls, then the content.
private struct MiniWindow<Content: View>: View {

    let title: String
    var leading: AnyView?
    var trailing: AnyView?
    var titleBarHeight = 36.0
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text(title)
                    .font(.plexSans(12, weight: .medium, relativeTo: .caption))
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    leading
                    Spacer()
                    trailing
                }
            }
            .padding(.horizontal, 10)
            .frame(height: titleBarHeight)
            .background(.quaternary.opacity(0.5))
            .overlay(alignment: .bottom) { Divider() }

            content
        }
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
        .shadow(color: .black.opacity(0.10), radius: 12, y: 6)
    }
}

/// A sample window's footer, holding the status chip and controls.
private struct MiniFooter<Content: View>: View {

    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 8) { content }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.3))
            .overlay(alignment: .top) { Divider() }
            .controlSize(.small)
    }
}

// MARK: - 1 · Welcome

/// The first page: a sentence whose mistake gets marked as it appears, and the gentle status chip.
private struct WelcomeStage: View {

    @State private var isMarked = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content
            .task {
                guard !reduceMotion else {
                    isMarked = true
                    return
                }
                try? await Task.sleep(for: .milliseconds(700))
                withAnimation(.easeOut(duration: 0.8)) { isMarked = true }
            }
    }

    /// "Nous avons acheté une fromage.", with the mistake underlined once it's marked.
    private var sentence: Text {
        let mistake = Text("une fromage").underline(isMarked, pattern: .solid, color: .red)
        return Text("Nous avons acheté \(mistake).")
    }

    /// The gentle chip, rising into place once the mistake is marked.
    private var chip: some View {
        StatusChip(errors: 1, warnings: 0, isGentle: true)
            .opacity(isMarked ? 1 : 0)
            .offset(y: isMarked ? 0 : 6)
    }

    #if os(macOS)
    private var content: some View {
        MiniWindow(title: "Coquille") {
            sentence
                .font(.plexMono(18, relativeTo: .title3))
                .lineSpacing(8)
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            MiniFooter { chip }
        }
        .frame(height: 300)
    }
    #else
    private var content: some View {
        VStack(spacing: 22) {
            Text("COQUILLE")
                .font(.plexMono(13, weight: .medium, relativeTo: .caption))
                .tracking(3)
                .foregroundStyle(.tint)
            sentence
                .font(.plexMono(21, relativeTo: .title3))
                .lineSpacing(8)
                .padding(.vertical, 22)
                .padding(.horizontal, 22)
                .frame(maxWidth: .infinity, alignment: .leading)
                .paperCard()
            chip
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.secondary.opacity(0.07))
    }
    #endif
}

// MARK: - 2 · Mistakes

/// The hands-on page: open the card, read the rule, then type the fix or ask for it.
private struct MistakeStage: View {

    /// How the learner settled the mistake.
    private enum Outcome {
        case fixedByYou
        case applied
        case ignored

        var title: String {
            switch self {
            case .fixedByYou: "Fixed by you."
            case .applied: "Fix applied."
            case .ignored: "Ignored."
            }
        }

        var message: String {
            switch self {
            case .fixedByYou: "Working it out yourself is what makes it stick. It goes in your corrections list."
            case .applied: "Looking it up isn't cheating. The rule stays on the card for next time."
            case .ignored: "Every card has Ignore, so a wrong flag never holds you up."
            }
        }
    }

    @State private var typed = "une"
    @State private var showsCard = false
    @State private var showsFix = false
    @State private var outcome: Outcome?
    @FocusState private var isTyping: Bool

    var body: some View {
        #if os(macOS)
        VStack(alignment: .leading, spacing: 12) {
            StageLabel("TRY IT")
            sentence
                .padding(.horizontal, 22)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .paperCard(cornerRadius: 10)
            below
        }
        .animation(.snappy(duration: 0.2), value: showsCard)
        .animation(.snappy(duration: 0.2), value: outcome == nil)
        #else
        VStack(alignment: .leading, spacing: 12) {
            StageLabel("TRY IT")
            sentence
                .padding(.horizontal, 16)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .paperCard()
            if outcome == nil && !showsCard {
                Text(prompt)
                    .font(.plexSans(15, relativeTo: .subheadline))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.top, 2)
            }
        }
        .padding(20)
        .stageGround()
        .overlay(alignment: .bottom) {
            Group {
                if outcome != nil {
                    doneCard
                } else if showsCard {
                    issueCard
                        .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
                }
            }
            .padding(14)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .animation(.snappy(duration: 0.2), value: showsCard)
        .animation(.snappy(duration: 0.2), value: outcome == nil)
        #endif
    }

    #if os(macOS)
    /// The prompt, the card, or the outcome, under the sample window.
    @ViewBuilder
    private var below: some View {
        if outcome != nil {
            doneCard
        } else if showsCard {
            issueCard
                .shadow(color: .black.opacity(0.10), radius: 12, y: 6)
        } else {
            Text(prompt)
                .font(.plexSans(14, relativeTo: .subheadline))
                .foregroundStyle(.secondary)
        }
    }
    #endif

    /// What to try, shortened on iPhone and iPad so the stage fits without scrolling.
    private var prompt: String {
        #if os(macOS)
        "Click the underlined word and read the rule. Then try typing the fix in the highlighted box yourself."
        #else
        "Tap the underline, read the rule, then type the fix in the box."
        #endif
    }

    /// The sentence: with a box to retype the article in, or as it was settled.
    @ViewBuilder
    private var sentence: some View {
        Group {
            switch outcome {
            case nil:
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 0) {
                        Text("Nous avons acheté ")
                        fixableArticle
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Nous avons acheté")
                        fixableArticle
                    }
                }
            case .fixedByYou, .applied:
                Text(Sample.corrected)
            case .ignored:
                Text("Nous avons acheté une fromage.")
            }
        }
        .font(.plexMono(Sample.frenchSize, relativeTo: .title3))
        .lineSpacing(8)
    }

    /// The article's box, then the flagged noun that opens the card.
    private var fixableArticle: some View {
        HStack(spacing: 0) {
            TextField("", text: $typed)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                .autocorrectionDisabled()
                #if !os(macOS)
                .textInputAutocapitalization(.never)
                #endif
                .focused($isTyping)
                .frame(width: Sample.frenchSize * 2.3)
                .padding(.vertical, 1)
                .background(isTyping ? Color.brand.opacity(0.12) : Color.red.opacity(0.08),
                            in: UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4))
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(isTyping ? Color.brand : Color.red)
                        .frame(height: 2)
                }
                .accessibilityLabel("Article before fromage")
                .onChange(of: typed) {
                    if typed.trimmingCharacters(in: .whitespaces).lowercased() == "un" {
                        settle(.fixedByYou)
                    }
                }
            Text(" ")
            FlaggedWord(text: "fromage", accessibilityText: "fromage, flagged. Open the card") {
                showsCard = true
            }
            Text(".")
        }
    }

    /// The scripted issue card, laid out as the editor's: the rule first, and the fix on request.
    private var issueCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("GENDER · ERROR")
                    .font(.plexMono(12, relativeTo: .caption))
                    .tracking(1)
                    .foregroundStyle(.red)
                Spacer()
                Button {
                    showsCard = false
                    showsFix = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.semibold))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Close")
            }

            if showsFix {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("une fromage")
                        .strikethrough()
                        .foregroundStyle(.secondary)
                    Image(systemName: "arrow.right")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("becomes")
                    Text("un fromage")
                        .font(.plexMono(16, weight: .medium, relativeTo: .body))
                        .foregroundStyle(.tint)
                }
                .font(.plexMono(16, relativeTo: .body))
                Text("fromage is masculine, so the article is un.")
                    .font(.plexSans(14, relativeTo: .subheadline))
            } else {
                Text("une fromage")
                    .font(.plexMono(16, relativeTo: .body))
                    .underline(pattern: .dot, color: .red)
                Text("fromage is masculine.")
                    .font(.plexSans(14, relativeTo: .subheadline))
            }

            HStack(spacing: 10) {
                Text("Lexique · known noun")
                    .font(.plexSans(12, relativeTo: .caption))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Ignore") { settle(.ignored) }
                    .buttonStyle(.bordered)
                if showsFix {
                    Button("Apply fix") { settle(.applied) }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Show fix") { showsFix = true }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(16)
        .paperCard()
    }

    /// What happened, and Try it again.
    @ViewBuilder
    private var doneCard: some View {
        if let outcome {
            VStack(alignment: .leading, spacing: 4) {
                Text(outcome.title)
                    .font(.plexSans(16, weight: .medium, relativeTo: .headline))
                    .foregroundStyle(outcome == .ignored ? AnyShapeStyle(.secondary) : AnyShapeStyle(.green))
                Text(outcome.message)
                    .font(.plexSans(14, relativeTo: .subheadline))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Try it again", action: reset)
                    .buttonStyle(.borderless)
                    .font(.plexSans(14, weight: .medium, relativeTo: .subheadline))
                    .frame(minHeight: 36)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .paperCard()
        }
    }

    /// Ends the try with `outcome`.
    private func settle(_ outcome: Outcome) {
        isTyping = false
        showsCard = false
        self.outcome = outcome
    }

    /// Puts the mistake back for another try.
    private func reset() {
        typed = "une"
        showsCard = false
        showsFix = false
        outcome = nil
    }
}

// MARK: - 3 · Play and English unlock

/// Errors lock playback and the English; fixing them unlocks both, and Play really reads the French.
private struct UnlockStage: View {

    let narrator: SpeechNarrator

    /// Whether the locked play button has pointed the learner at the error.
    @State private var jumped = false
    @State private var isFixed = false
    /// Whether the Mac sample shows its English pane.
    @State private var showsEnglish = true

    /// Plays, pauses or resumes the corrected sentence.
    private func togglePlay() {
        switch narrator.state {
        case .idle: narrator.speak(Sample.corrected)
        case .speaking: narrator.pause()
        case .paused: narrator.resume()
        }
    }

    /// Puts the error back.
    private func reset() {
        narrator.stop()
        jumped = false
        isFixed = false
    }

    /// The sentence, flagged until it's fixed.
    @ViewBuilder
    private var sentence: some View {
        Group {
            if isFixed {
                Text(Sample.corrected)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 0) {
                        Text("Nous avons acheté ")
                        flagged
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Nous avons acheté")
                        flagged
                    }
                }
            }
        }
        .font(.plexMono(Sample.frenchSize, relativeTo: .title3))
        .lineSpacing(8)
    }

    /// The flagged article and noun, then the full stop.
    private var flagged: some View {
        HStack(spacing: 0) {
            FlaggedWord(text: "une fromage", accessibilityText: "une fromage, flagged. \(Sample.press) to fix", isLit: jumped) {
                withAnimation(.snappy(duration: 0.2)) { isFixed = true }
            }
            Text(".")
        }
    }

    /// The English, or why it's waiting.
    @ViewBuilder
    private var english: some View {
        if isFixed {
            Text(Sample.english)
                .font(.system(size: Sample.frenchSize - 2))
        } else {
            Label {
                #if os(macOS)
                Text("The English appears once the French is correct. Fix 1 error to see it.")
                #else
                Text("Fix 1 error to see the English.")
                #endif
            } icon: {
                Image(systemName: "lock")
            }
            .font(.plexSans(14, relativeTo: .subheadline))
            .foregroundStyle(.secondary)
        }
    }

    #if os(macOS)
    /// What to do next, in the French pane.
    private var hint: String {
        guard isFixed else { return "Play is greyed out in the toolbar. Click the underlined words to fix them." }
        return narrator.state == .speaking ? "Speaking French… Press ⌘. to stop." : "Clean. Play and the English are unlocked. Press ⌘↵ or click Play."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            StageLabel("TRY IT")
            MiniWindow(title: isFixed ? "Le fromage" : "Coquille", leading: AnyView(playControls), trailing: AnyView(Color.clear.frame(width: 62, height: 1))) {
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 8) {
                        sentence
                        Text(hint)
                            .font(.plexSans(12, relativeTo: .caption))
                            .foregroundStyle(.secondary)
                        if isFixed {
                            Button("Try it again", action: reset)
                                .buttonStyle(.borderless)
                                .font(.plexSans(13, weight: .medium, relativeTo: .footnote))
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)

                    if showsEnglish {
                        Divider()

                        VStack(alignment: .leading, spacing: 6) {
                            Text("ENGLISH")
                                .font(.plexMono(10, weight: .medium, relativeTo: .caption2))
                                .tracking(2)
                                .foregroundStyle(.secondary)
                            english
                                .font(.plexSans(12, relativeTo: .caption))
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 18)
                        .frame(width: 170, alignment: .leading)
                        .frame(maxHeight: .infinity)
                        .background(.quaternary.opacity(0.3))
                    }
                }
                .frame(maxHeight: .infinity)
                MiniFooter {
                    StatusChip(errors: isFixed ? 0 : 1, warnings: 0, isGentle: true)
                    Spacer()
                    Toggle("English", isOn: $showsEnglish)
                        .toggleStyle(.switch)
                        .font(.plexSans(12, weight: .medium, relativeTo: .caption))
                }
            }
            .frame(height: 320)
        }
    }

    /// Play and Stop, grouped at the toolbar's leading edge as in Xcode.
    private var playControls: some View {
        HStack(spacing: 2) {
            Button(narrator.state == .speaking ? "Pause" : "Read aloud in French",
                   systemImage: narrator.state == .speaking ? "pause.fill" : "play.fill",
                   action: togglePlay)
                .disabled(!isFixed)
            Button("Stop", systemImage: "stop.fill") { narrator.stop() }
                .disabled(narrator.state == .idle)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .font(.system(size: 11))
        .padding(2)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 7))
    }
    #else
    /// What to do next, above the English.
    private var hint: String {
        if isFixed { return "No errors left, so the English and play button are unlocked." }
        return jumped ? "The lock brought you here. Tap the words to fix them." : "Tap the locked play button below."
    }

    /// The caption beside the play button.
    private var caption: String {
        if !isFixed { return "Fix to\nlisten" }
        return narrator.state == .speaking ? "Speaking\nFrench…" : ""
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                StageLabel("TRY IT")
                sentence
                Text(hint)
                    .font(.plexSans(14, relativeTo: .subheadline))
                    .foregroundStyle(.secondary)
                if isFixed {
                    Button("Try it again", action: reset)
                        .font(.plexSans(14, weight: .medium, relativeTo: .subheadline))
                        .frame(minHeight: 36)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(.background)

            VStack(alignment: .leading, spacing: 6) {
                StageLabel("ENGLISH", isMuted: true)
                english
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
            .background(Color.secondary.opacity(0.07))
            .overlay(alignment: .top) { Divider() }

            HStack(spacing: 10) {
                StatusChip(errors: isFixed ? 0 : 1, warnings: 0, isGentle: true)
                Text("EN")
                    .font(.plexMono(12, weight: .medium, relativeTo: .caption))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(.tint))
                    .accessibilityLabel("English on")
                Spacer()
                Text(caption)
                    .font(.plexSans(12, relativeTo: .caption))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                playButton
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(.background)
            .overlay(alignment: .top) { Divider() }
        }
    }

    /// The play button: locked and pointing at the error until it's fixed, then Play and Pause.
    @ViewBuilder
    private var playButton: some View {
        if isFixed {
            let speaking = narrator.state == .speaking
            Button(action: togglePlay) {
                Image(systemName: speaking ? "pause.fill" : "play.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(.tint))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(speaking ? "Pause" : "Read aloud in French")
        } else {
            Button {
                withAnimation(.snappy(duration: 0.2)) { jumped = true }
            } label: {
                Image(systemName: "lock")
                    .font(.system(size: 17))
                    .foregroundStyle(.secondary)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(Color.secondary.opacity(0.12)))
                    .overlay(Circle().strokeBorder(.secondary, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Play locked. Fix 1 error to play. Goes to the first error.")
        }
    }
    #endif
}

// MARK: - 4 · Notes and sharing

/// Notes that are never checked, review markers to finish, and the real Share, plus Export a
/// Copy on the Mac. On iPhone and iPad, Share covers both, since the share sheet saves to Files.
private struct NotesStage: View {

    @State private var keyword = ""
    @State private var isExporting = false
    /// The exported copy's name, once one has been saved.
    @State private var exportedName: String?

    /// The guide note and today's French date, as a new entry starts.
    private let opening: [String] = EditorModel.guidedEntry(prompts: [], for: .now).text
        .split(separator: "\n")
        .map(String.init)

    /// The sample page as plain text, as Share and Export a Copy send it.
    private var pageText: String {
        var lines = opening + [
            "",
            "Ce matin, je suis allé au marché. // went to the market",
            "//: \(keyword)"
        ]
        #if os(macOS)
        lines.append("J'ai acheté des choses pour manger. /* groceries? */")
        #endif
        return lines.joined(separator: "\n")
    }

    /// The sample page, with its notes in gray as the editor draws them.
    private var page: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(opening.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .foregroundStyle(line.hasPrefix("//") ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
            }
            Spacer().frame(height: 8)
            Text("Ce matin, je suis allé au marché. \(Text("// went to the market").foregroundStyle(.secondary))")
            HStack(spacing: 0) {
                Text("//: ")
                    .foregroundStyle(.secondary)
                if keyword.isEmpty {
                    Caret()
                } else {
                    Text(keyword)
                        .font(.plexMono(Self.textSize, weight: .medium, relativeTo: .callout))
                        .foregroundStyle(.tint)
                }
            }
            #if os(macOS)
            Text("J'ai acheté des choses pour manger. \(Text("/* groceries? */").foregroundStyle(.secondary))")
            #endif
        }
        .font(.plexMono(Self.textSize, relativeTo: .callout))
        .lineSpacing(Self.lineSpacing)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static var textSize: Double {
        #if os(macOS)
        13
        #else
        14
        #endif
    }

    /// The space between the sample's lines, tighter on iPhone and iPad so the stage fits.
    private static var lineSpacing: Double {
        #if os(macOS)
        4
        #else
        2
        #endif
    }

    /// The marker keywords; choosing one finishes the //: line, choosing it again clears it.
    private var keywordBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(Notes.markerKeywords, id: \.self) { word in
                    Group {
                        if word == keyword {
                            Button(word) { keyword = "" }
                                .buttonStyle(.borderedProminent)
                        } else {
                            Button(word) { keyword = word }
                                .buttonStyle(.bordered)
                        }
                    }
                    .font(.plexMono(13, relativeTo: .callout))
                    .accessibilityLabel("Marker: \(word)")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
        .overlay(alignment: .top) { Divider() }
    }

    /// What Share sends, or on the Mac where the exported copy went.
    private var sentNote: String {
        if let exportedName {
            return "Saved as “\(exportedName)”, a copy you can attach anywhere."
        }
        return "Share sends the whole page, notes and markers included."
    }

    private var exportButton: some View {
        Button("Export a Copy…") { isExporting = true }
    }

    private var shareLink: some View {
        ShareLink(item: pageText) {
            Label("Share", systemImage: "square.and.arrow.up")
        }
    }

    var body: some View {
        content
            .fileExporter(
                isPresented: $isExporting,
                document: FrenchTextFile(text: pageText),
                contentType: .plainText,
                defaultFilename: FrenchTextFile.suggestedFilename(for: nil)
            ) { result in
                if case .success(let url) = result {
                    exportedName = url.lastPathComponent
                }
            }
    }

    #if os(macOS)
    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            StageLabel("TRY IT")
            MiniWindow(title: "Coquille", trailing: AnyView(shareLink.labelStyle(.iconOnly).buttonStyle(.borderless))) {
                page
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                keywordBar
                    .controlSize(.small)
            }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(exportedName == nil ? "Click Share in the toolbar to send the whole page, notes and all." : sentNote)
                    .font(.plexSans(13, relativeTo: .footnote))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                exportButton
            }
        }
    }
    #else
    private var content: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                StageLabel("TRY IT")
                page
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(.background)

            keywordBar
                .background(.background)

            VStack(alignment: .leading, spacing: 6) {
                shareLink
                    .buttonStyle(.bordered)
                    .font(.plexSans(14, weight: .medium, relativeTo: .subheadline))
                Text(sentNote)
                    .font(.plexSans(12, relativeTo: .caption))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.07))
            .overlay(alignment: .top) { Divider() }
        }
    }
    #endif
}

// MARK: - 5 · Phrasebook

/// The real phrasebook search over the bundled phrases, each one read aloud on request.
private struct PhrasebookStage: View {

    let narrator: SpeechNarrator

    @State private var phrases: [Phrase] = []
    @State private var query = ""
    @State private var speakingID: String?

    /// The three phrases shown before a search on iPhone and iPad: two greetings and a café phrase.
    private static let featured = ["Bonjour !", "Ça va ?", "Un café, s'il vous plaît."]

    /// Reads the bundled phrasebook, or nothing if it won't load.
    private static func loadPhrases() -> [Phrase] {
        guard let url = Bundle.main.url(forResource: "fr.phrases", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Phrase].self, from: data)) ?? []
    }

    /// The featured phrases, in the phrasebook's order.
    private var featuredPhrases: [Phrase] {
        phrases.filter { Self.featured.contains($0.french) }
    }

    /// Reads a phrase aloud, or stops it if it's already playing.
    private func toggle(_ phrase: Phrase) {
        if speakingID == phrase.id && narrator.isSpeaking {
            narrator.stop()
        } else {
            speakingID = phrase.id
            narrator.speak(phrase.french)
        }
    }

    /// Whether this phrase is being read aloud right now.
    private func isSpeaking(_ phrase: Phrase) -> Bool {
        speakingID == phrase.id && narrator.isSpeaking
    }

    var body: some View {
        content
            .task { phrases = Self.loadPhrases() }
    }

    #if os(macOS)
    /// A sample page beside the phrasebook panel, with a phrase being typed out.
    private var content: some View {
        MiniWindow(title: "Coquille", trailing: AnyView(
            Image(systemName: "book")
                .font(.system(size: 12))
                .foregroundStyle(.tint)
                .frame(width: 24, height: 22)
                .background(Color.brand.opacity(0.15), in: RoundedRectangle(cornerRadius: 5))
                .accessibilityLabel("Phrasebook, open")
        )) {
            HStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text("Au café, j'ai dit : « Je voudrais un th")
                    Caret()
                }
                .font(.plexMono(14, relativeTo: .callout))
                .padding(18)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    TextField("French or English", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .font(.plexSans(12, relativeTo: .caption))
                        .autocorrectionDisabled()
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            if query.isEmpty {
                                Text(Situation.cafe.title)
                                    .font(.plexSans(11, weight: .medium, relativeTo: .caption2))
                                    .foregroundStyle(.secondary)
                                ForEach(phrases.filter { $0.situation == .cafe }.prefix(4)) { compactRow(for: $0) }
                            } else {
                                ForEach(PhraseSearch.matches(for: query, in: phrases).prefix(8)) { compactRow(for: $0) }
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
                .padding(10)
                .frame(width: 210)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(.quaternary.opacity(0.3))
            }
        }
        .frame(height: 330)
    }

    /// One phrase in the panel: the French, its English and tag, the note, and a play button.
    private func compactRow(for phrase: Phrase) -> some View {
        HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(phrase.french)
                    .font(.plexMono(12, weight: .medium, relativeTo: .caption))
                Text(phrase.english + (phrase.register == .either ? "" : " · \(phrase.register.rawValue)"))
                    .font(.plexSans(11, relativeTo: .caption2))
                    .foregroundStyle(.secondary)
                if let note = phrase.note {
                    Text(note)
                        .font(.plexSans(10, relativeTo: .caption2))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
            Button(isSpeaking(phrase) ? "Stop" : "Play \(phrase.french)",
                   systemImage: isSpeaking(phrase) ? "stop.fill" : "speaker.wave.2") { toggle(phrase) }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .font(.system(size: 11))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .paperCard(cornerRadius: 8)
    }
    #else
    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            StageLabel("TRY IT · SEARCH “BONJUR” OR “CAFE”")
                .padding(.horizontal, 14)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("French or English", text: $query)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                if !query.isEmpty {
                    Button("Clear search", systemImage: "xmark.circle.fill") { query = "" }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.plexSans(15, relativeTo: .body))
            .padding(.horizontal, 12)
            .frame(minHeight: 40)
            .paperCard(cornerRadius: 10)
            .padding(.horizontal, 14)

            // Three phrases at most and no notes, so the stage never scrolls.
            VStack(alignment: .leading, spacing: 6) {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    ForEach(featuredPhrases) { card(for: $0) }
                } else {
                    let results = PhraseSearch.matches(for: query, in: phrases).prefix(3)
                    if results.isEmpty {
                        Text("No phrases match.")
                            .font(.plexSans(14, relativeTo: .subheadline))
                            .foregroundStyle(.secondary)
                            .padding(12)
                    }
                    ForEach(Array(results)) { card(for: $0) }
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(.top, 14)
        .stageGround()
    }

    /// One phrase as a card, using the phrasebook's own row without its note.
    private func card(for phrase: Phrase) -> some View {
        PhraseRow(phrase: phrase, isSpeaking: isSpeaking(phrase), showsNote: false) { toggle(phrase) }
            .padding(.leading, 12)
            .padding(.trailing, 4)
            .padding(.vertical, 4)
            .paperCard(cornerRadius: 12)
    }
    #endif
}

// MARK: - 6 · Journal and progress

/// Sample entries, corrections and progress, so the learner sees what builds up over time.
private struct JournalStage: View {

    private struct Entry: Identifiable {
        let title: String
        let date: String
        let iso: String
        let preview: String
        let hasErrors: Bool
        var id: String { iso }
    }

    private struct Correction: Identifiable {
        let was: String
        let now: String
        let sentence: String
        let meta: String
        var id: String { was }
    }

    private static let entries = [
        Entry(title: "Le week-end", date: "10 Nov", iso: "2026-11-10", preview: "Samedi, nous avons fait du vélo.", hasErrors: false),
        Entry(title: "Ma famille", date: "8 Nov", iso: "2026-11-08", preview: "J'ai deux frères et une sœur.", hasErrors: true),
        Entry(title: "Une journée au marché", date: "31 Oct", iso: "2026-10-31", preview: "Ce matin, je suis allé au marché.", hasErrors: false)
    ]

    private static let corrections = [
        Correction(was: "une fromage", now: "un fromage", sentence: "Nous avons acheté une fromage.", meta: "Gender · fixed by you · 10 Nov 2026"),
        Correction(was: "à le", now: "au", sentence: "Je suis allé à le marché.", meta: "Contraction · fixed by you · 8 Nov 2026"),
        Correction(was: "gentile", now: "gentille", sentence: "Ma sœur est très gentile.", meta: "Spelling · applied · 8 Nov 2026"),
        Correction(was: "je suis faim", now: "j'ai faim", sentence: "Ce matin, je suis faim.", meta: "Avoir expression · fixed by you · 31 Oct 2026")
    ]

    #if os(macOS)
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topLeading) {
                MiniWindow(title: "Une journée au marché") {
                    HStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("JOURNAL")
                                .font(.plexSans(10, weight: .medium, relativeTo: .caption2))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.bottom, 4)
                            ForEach(Self.entries) { entry in
                                VStack(alignment: .leading, spacing: 1) {
                                    HStack(spacing: 5) {
                                        Text(entry.title)
                                            .font(.plexSans(12, weight: .medium, relativeTo: .caption))
                                        if entry.hasErrors { errorDot(size: 6) }
                                    }
                                    Text(entry.date)
                                        .font(.plexSans(10, relativeTo: .caption2))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 5)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(entry.iso == "2026-10-31" ? Color.brand.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 6))
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(8)
                        .frame(width: 150)
                        .frame(maxHeight: .infinity)
                        .background(.quaternary.opacity(0.4))

                        Divider()

                        VStack(alignment: .leading, spacing: 2) {
                            Text("// What did you do this morning?")
                                .foregroundStyle(.secondary)
                            Text("Ce matin, je suis allé au marché avec ma sœur.")
                        }
                        .font(.plexMono(12, relativeTo: .caption))
                        .padding(14)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                }
                .frame(width: 430, height: 300)

                MiniWindow(title: "Corrections", titleBarHeight: 28) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Self.corrections.prefix(2).reversed()) { correction in
                            correctionRow(correction, showsSentence: false)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                            Divider()
                        }
                    }
                }
                .frame(width: 250)
                .padding(.leading, 194)
                .padding(.top, 210)
            }
            .frame(height: 360, alignment: .topLeading)
            StageLabel("SAMPLE DATA", isMuted: true)
        }
    }
    #else
    private enum Tab: String, CaseIterable, Identifiable {
        case journal = "Journal"
        case corrections = "Corrections"
        case progress = "Progress"
        var id: String { rawValue }
    }

    @State private var tab = Tab.journal
    /// The highlighted entry, by its date.
    @State private var picked = "2026-11-10"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            StageLabel("SAMPLE DATA")
            Picker("View", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            switch tab {
            case .journal: journal
            case .corrections: correctionsList
            case .progress: progress
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .stageGround()
    }

    /// Today's prompt and the sample entries.
    private var journal: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("TODAY'S PROMPT")
                    .font(.plexMono(11, weight: .medium, relativeTo: .caption2))
                    .tracking(1)
                    .foregroundStyle(.secondary)
                Text("What did you do this morning?")
                    .font(.plexSans(15, weight: .medium, relativeTo: .body))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .paperCard(cornerRadius: 12)

            VStack(spacing: 0) {
                ForEach(Self.entries) { entry in
                    Button { picked = entry.iso } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(entry.title)
                                    .font(.plexSans(14, weight: .medium, relativeTo: .subheadline))
                                if entry.hasErrors { errorDot(size: 7) }
                            }
                            Text("\(entry.date) · \(entry.preview)")
                                .font(.plexSans(12, relativeTo: .caption))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(picked == entry.iso ? Color.brand.opacity(0.12) : Color.clear)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if entry.id != Self.entries.last?.id { Divider() }
                }
            }
            .paperCard(cornerRadius: 12)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    /// The first three sample fixes, each with its sentence.
    private var correctionsList: some View {
        let shown = Self.corrections.prefix(3)
        return VStack(spacing: 0) {
            ForEach(shown) { correction in
                correctionRow(correction, showsSentence: true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if correction.id != shown.last?.id { Divider() }
            }
        }
        .paperCard(cornerRadius: 12)
    }

    /// The sample streak, counts and weak spots.
    private var progress: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible())], spacing: 8) {
                statCard("Day streak", "6")
                statCard("Sentences checked", "84")
                statCard("Clean this week", "71%")
                statCard("Fixed by you", "23 of 31")
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Weak spots")
                    .font(.plexSans(13, weight: .medium, relativeTo: .footnote))
                    .foregroundStyle(.secondary)
                weakSpot("Noun gender", count: 9, of: 9)
                weakSpot("Elision", count: 5, of: 9)
            }
        }
    }

    /// One count in the progress grid.
    private func statCard(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.plexSans(12, relativeTo: .caption))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.plexSans(22, weight: .medium, relativeTo: .title2))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }

    /// One weak spot's bar, scaled against the largest count.
    private func weakSpot(_ name: String, count: Int, of largest: Int) -> some View {
        HStack(spacing: 8) {
            Text(name)
                .frame(width: 92, alignment: .leading)
            Capsule()
                .fill(.tint)
                .frame(width: 150 * Double(count) / Double(largest), height: 8)
            Text("\(count)")
        }
        .font(.plexSans(13, relativeTo: .footnote))
        .accessibilityElement(children: .combine)
    }
    #endif

    /// The small red dot that marks an entry with errors.
    private func errorDot(size: Double) -> some View {
        Circle()
            .fill(.red)
            .frame(width: size, height: size)
            .accessibilityLabel("Has errors")
    }

    /// One fix: what it was, what it became, and optionally the sentence it sat in.
    private func correctionRow(_ correction: Correction, showsSentence: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(correction.was)
                    .strikethrough()
                    .foregroundStyle(.secondary)
                Text("→")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("became")
                Text(correction.now)
                    .fontWeight(.medium)
                    .foregroundStyle(.tint)
            }
            .font(.plexMono(showsSentence ? 14 : 12, relativeTo: .subheadline))
            if showsSentence {
                Text(correction.sentence)
                    .font(.plexSans(12, relativeTo: .caption))
                    .foregroundStyle(.secondary)
            }
            Text(correction.meta)
                .font(.plexSans(showsSentence ? 11 : 10, relativeTo: .caption2))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - 7 · Get ready

/// The one download the English needs, and where to find better French voices.
private struct ReadyStage: View {

    @AppStorage(SpeechNarrator.voiceStorageKey) private var playbackVoiceID = ""
    @State private var status: TranslationPackStatus?
    /// Set when the learner asks to download the pack, which starts the system's prompt.
    @State private var downloadRequest: TranslationSession.Configuration?
    @State private var isDownloading = false

    /// The pack's status, as Settings shows it.
    private var statusLabel: String {
        if isDownloading { return "Downloading…" }
        return status?.label ?? "Checking…"
    }

    /// The chosen French voice's name, or Automatic.
    private var voiceName: String {
        guard !playbackVoiceID.isEmpty,
              let voice = AVSpeechSynthesisVoice(identifier: playbackVoiceID) else { return "Automatic" }
        return voice.name
    }

    /// Where the system keeps its French voices, as each platform's settings name it.
    private static var voicePath: String {
        #if os(macOS)
        "System Settings › Accessibility › Read & Speak, then ⓘ next to System voice"
        #else
        "Settings › Accessibility › Spoken Content › Voices › French"
        #endif
    }

    private var translationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("French translation")
                    .font(.plexSans(Self.headingSize, weight: .medium, relativeTo: .headline))
                Spacer()
                Label {
                    Text(statusLabel)
                } icon: {
                    if status == .installed { Image(systemName: "checkmark") }
                }
                .labelStyle(TrailingIconLabelStyle())
                .font(.plexSans(12, weight: .medium, relativeTo: .caption))
                .foregroundStyle(status == .installed ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
            }
            Text(Self.translationNote)
                .font(.plexSans(13, relativeTo: .footnote))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if status?.canDownload == true || isDownloading {
                Button(isDownloading ? "Downloading…" : "Download French…", action: requestDownload)
                    .buttonStyle(.borderedProminent)
                    .disabled(isDownloading)
            }
        }
    }

    private var voiceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("French voice")
                    .font(.plexSans(Self.headingSize, weight: .medium, relativeTo: .headline))
                Spacer()
                Text(voiceName)
                    .font(.plexSans(12, weight: .medium, relativeTo: .caption))
                    .foregroundStyle(.secondary)
            }
            Text(Self.voiceNote)
                .font(.plexSans(13, relativeTo: .footnote))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(Self.voicePath)
                .font(.plexMono(12, weight: .medium, relativeTo: .caption))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private static var headingSize: Double {
        #if os(macOS)
        13
        #else
        16
        #endif
    }

    /// What the translation pack is for, shortened on iPhone and iPad so the stage fits.
    private static var translationNote: String {
        #if os(macOS)
        "The English pane needs Apple's French–English language pack. It downloads once and works offline after that."
        #else
        "The English needs Apple's French–English pack. It downloads once, then works offline."
        #endif
    }

    /// Where better voices come from, shortened on iPhone and iPad so the stage fits.
    private static var voiceNote: String {
        #if os(macOS)
        "Play uses your device's French voices. The enhanced and premium ones sound much more natural. To add one, open"
        #else
        "For a more natural voice, open"
        #endif
    }

    var body: some View {
        content
            .task { status = await TranslationPack.status() }
            .onReceive(NotificationCenter.default.appBecameActive) { _ in
                Task { status = await TranslationPack.status() }
            }
            .onReceive(NotificationCenter.default.publisher(for: TranslationPack.didChange)) { _ in
                Task {
                    status = await TranslationPack.status()
                    isDownloading = false
                }
            }
            .translationTask(downloadRequest, action: Self.prepareDownload)
    }

    #if os(macOS)
    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            StageLabel("TRY IT")
            MiniWindow(title: "Settings") {
                VStack(alignment: .leading, spacing: 14) {
                    translationSection
                    Divider()
                    voiceSection
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
            }
        }
    }
    #else
    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            StageLabel("TRY IT")
            translationSection
                .padding(12)
                .paperCard(cornerRadius: 14)
            voiceSection
                .padding(12)
                .paperCard(cornerRadius: 14)
        }
        .padding(14)
        .stageGround()
    }
    #endif

    /// Shows the system's download prompt and announces the outcome. The system reports its
    /// own errors, and declining simply leaves the status unchanged.
    private nonisolated static func prepareDownload(_ session: TranslationSession) async {
        try? await session.prepareTranslation()
        await MainActor.run {
            NotificationCenter.default.post(name: TranslationPack.didChange, object: nil)
        }
    }

    /// Starts the system's download prompt, again if the learner asks a second time.
    private func requestDownload() {
        isDownloading = true
        if downloadRequest == nil {
            downloadRequest = TranslationSession.Configuration(source: TranslationPack.french, target: TranslationPack.english)
        } else {
            downloadRequest?.invalidate()
        }
    }
}

/// A label with its icon after the text, as in "Installed ✓".
private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.title
            configuration.icon
        }
    }
}

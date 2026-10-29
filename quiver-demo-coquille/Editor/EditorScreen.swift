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

/// The whole app: one French text editor with live linting, a play button, and an
/// English toggle. On wide windows the English sits beside the French.
struct EditorScreen: View {

    @State private var model = EditorModel()
    @State private var showsIssueList = false
    @State private var showsProgress = false
    @FocusState private var editorIsFocused: Bool
    @AppStorage(Appearance.storageKey) private var appearance: String?

    #if os(macOS)
    /// The story's title from the on-device model, or `nil` to show the app's name.
    @State private var storyTitle: String?
    /// The English pane's share of the window, kept between launches.
    @AppStorage("englishPaneFraction") private var englishFraction = SplitPanes<EmptyView, EmptyView>.defaultFraction
    #endif

    /// Window width at which English moves from below the French to beside it.
    private static let splitWidth = 700.0

    var body: some View {
        layout
            .tint(.brand)
            .preferredColorScheme(Appearance.colorScheme(for: appearance))
            .animation(.snappy(duration: 0.2), value: model.selectedIssueID)
            .task { await model.load() }
            .sheet(isPresented: $showsIssueList) {
                IssueListSheet(model: model) { issue in
                    showsIssueList = false
                    editorIsFocused = true
                    model.select(issue)
                }
                .tint(.brand)
            }
            .sheet(isPresented: $showsProgress) {
                ProgressSheet(stats: model.stats.stats)
                    .tint(.brand)
            }
    }

    #if os(macOS)
    /// The Mac window: French and English side by side with a draggable divider, play
    /// and stop grouped at the toolbar's leading edge as in Xcode, the streak and the
    /// Clear and theme pair at its trailing edge, and status and English in the footer.
    /// Once the French is correct, the title names the story.
    private var layout: some View {
        VStack(spacing: 0) {
            SplitPanes(showsTrailing: model.isEnglishOn, trailingFraction: $englishFraction) {
                frenchPane
            } trailing: {
                EnglishPane(model: model, showsHeaderBar: true)
            }

            MacBottomBar(model: model, showsIssueList: $showsIssueList)
        }
        .navigationTitle(storyTitle ?? "Coquille")
        .task(id: titleSource) { await retitle() }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                MacPlayButton(model: model)
                MacStopButton(model: model)
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    showsProgress = true
                } label: {
                    Label("\(model.stats.stats.streak(asOf: .now)) day streak", systemImage: "chart.bar.xaxis")
                        .labelStyle(.titleAndIcon)
                }
                .help("Your progress")
            }

            ToolbarSpacer(.fixed, placement: .primaryAction)

            ToolbarItemGroup(placement: .primaryAction) {
                Button("Clear", action: model.clear)
                    .keyboardShortcut("k", modifiers: .command)
                    .help("Clear text (⌘K)")
                    .disabled(!model.hasText)

                ThemeToggle()
            }
        }
    }

    /// The text to title: the French once it's linted with no errors, otherwise `nil`.
    private var titleSource: String? {
        model.isLintCurrent && !model.isLocked && model.hasText ? model.plainText : nil
    }

    /// Names the story after a pause in typing; an empty editor goes back to the app's name.
    private func retitle() async {
        guard let text = titleSource else {
            if !model.hasText { storyTitle = nil }
            return
        }
        try? await Task.sleep(for: .seconds(2))
        guard !Task.isCancelled, let title = await StoryTitler.title(for: text), !Task.isCancelled else { return }
        storyTitle = title
    }

    /// The French pane: its header, the editor, and the open issue's card floating over it.
    private var frenchPane: some View {
        VStack(spacing: 0) {
            PaneHeader(title: "FRANÇAIS", showsDivider: true)
            editor
        }
        .overlay(alignment: .bottom) {
            if let issue = model.selectedIssue {
                IssueCard(issue: issue, model: model)
                    .id(issue.id)
                    .frame(maxWidth: 440)
                    .padding(20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
    #else
    /// The iPhone and iPad layout: a top bar, the editor with English below or beside
    /// it, the open issue's card, and the bottom bar.
    private var layout: some View {
        GeometryReader { geometry in
            let isWide = geometry.size.width >= Self.splitWidth
            VStack(spacing: 0) {
                TopBar(model: model, showsIssueList: $showsIssueList, showsProgress: $showsProgress)

                if isWide {
                    HStack(spacing: 0) {
                        editor
                        if model.isEnglishOn {
                            Divider()
                            EnglishPane(model: model, showsHeaderBar: true)
                                .frame(width: geometry.size.width * 0.4)
                        }
                    }
                } else {
                    VStack(spacing: 0) {
                        editor
                        if model.isEnglishOn {
                            Divider()
                            EnglishPane(model: model, showsHeaderBar: false)
                                .frame(maxHeight: geometry.size.height * 0.3)
                        }
                    }
                }

                if let issue = model.selectedIssue {
                    IssueCard(issue: issue, model: model)
                        .id(issue.id)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                        .frame(maxWidth: 560)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                BottomBar(model: model, jumpToFirstError: jumpToFirstError)
            }
        }
    }
    #endif

    /// Focuses the editor and opens the first error, for the locked play button on iPhone and iPad.
    private func jumpToFirstError() {
        editorIsFocused = true
        model.jumpToFirstError()
    }

    /// The French editor, with a placeholder when it is empty.
    private var editor: some View {
        TextEditor(text: $model.text, selection: $model.selection)
            .font(.plexMono(Typography.frenchSize, relativeTo: .title3))
            .lineSpacing(Typography.frenchLineSpacing)
            .scrollContentBackground(.hidden)
            // The learner's own mistakes are the point: never let the keyboard fix them.
            .autocorrectionDisabled()
            .focused($editorIsFocused)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .overlay(alignment: .topLeading) {
                if !model.hasText {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(model.loadFailure ?? "Écrivez en français…")
                            .font(.plexMono(Typography.frenchSize, relativeTo: .title3))
                            .foregroundStyle(.tertiary)
                            .allowsHitTesting(false)
                        if model.loadFailure == nil {
                            Button("Try an example", systemImage: "text.badge.checkmark", action: model.loadExample)
                                .buttonStyle(.bordered)
                        }
                    }
                    .padding(.horizontal, 25)
                    .padding(.vertical, 20)
                }
            }
            .onChange(of: model.text) { model.textDidChange() }
            .onChange(of: model.selection) { model.selectionDidChange() }
            .onChange(of: model.narrator.spokenRange) { model.spokenWordDidChange() }
            .onChange(of: model.narrator.state) { model.spokenWordDidChange() }
    }
}

/// A pane's small uppercase label, such as "FRANÇAIS" or "ENGLISH · ON-DEVICE".
struct PaneHeader: View {

    let title: String
    /// Whether to draw a rule under the header, as in the side-by-side layout.
    let showsDivider: Bool

    var body: some View {
        Text(title)
            .font(.plexMono(12, relativeTo: .caption))
            .tracking(1)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            .overlay(alignment: .bottom) { if showsDivider { Divider() } }
    }
}

#Preview {
    EditorScreen()
}

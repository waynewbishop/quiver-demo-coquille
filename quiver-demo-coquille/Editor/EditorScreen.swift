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
import UniformTypeIdentifiers

/// The whole app: one French text editor with live linting, a play button, and an
/// English toggle. On wide windows the English sits beside the French.
struct EditorScreen: View {

    @State private var model: EditorModel
    @State private var showsIssueList = false
    @State private var showsImporter = false
    @State private var showsExporter = false
    /// New Entry or Open… waiting on the learner's answer before replacing text in the editor.
    @State private var pendingReplace: FileRequest?
    @State private var fileProblem: FileProblem?
    /// A command chosen in the File menu, handled and cleared by this window.
    @State private var fileRequest: FileRequest?
    /// The story's title from the on-device model, or `nil` to show the app's name.
    /// Only the Mac window titles stories, so on iPhone and iPad it stays `nil`.
    @State private var storyTitle: String?
    @State private var showsProgress = false
    @State private var showsPhrasebook = false
    @FocusState private var editorIsFocused: Bool
    @AppStorage(Appearance.storageKey) private var appearance: String?
    /// The Show suggestions setting, kept between launches and mirrored into the model.
    @AppStorage("showsSuggestions") private var showsSuggestions = true

    #if os(macOS)
    /// The English pane's share of the window, kept between launches.
    @AppStorage("englishPaneFraction") private var englishFraction = SplitPanes<EmptyView, EmptyView>.defaultFraction
    #endif

    /// Window width at which English moves from below the French to beside it.
    private static let splitWidth = 700.0

    /// Creates the editor around the app's one stats store, which the Corrections window reads too.
    init(stats: StatsStore) {
        _model = State(initialValue: EditorModel(stats: stats, draftURL: EditorModel.defaultDraftURL()))
    }

    var body: some View {
        screen
            .fileImporter(isPresented: $showsImporter, allowedContentTypes: [.plainText], onCompletion: openPicked)
            .fileExporter(
                isPresented: $showsExporter,
                document: FrenchTextFile(text: model.plainText),
                contentType: .plainText,
                defaultFilename: FrenchTextFile.suggestedFilename(for: storyTitle),
                onCompletion: savedPicked
            )
            .confirmationDialog("Replace the text in the editor?", isPresented: confirmsReplace, titleVisibility: .visible, presenting: pendingReplace) { request in
                Button(request == .newEntry ? "New Entry" : "Open…") { replace(with: request) }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("Save first to keep it.")
            }
            .alert(fileProblem?.title ?? "", isPresented: showsFileProblem, presenting: fileProblem) { _ in
                Button("OK", role: .cancel) {}
            } message: { problem in
                Text(problem.message)
            }
            // The File menu's commands ask this window through `fileRequest`.
            .focusedSceneValue(\.fileRequest, $fileRequest)
            .focusedSceneValue(\.canSaveFile, model.hasText)
            .onChange(of: fileRequest) {
                switch fileRequest {
                case .newEntry: newEntry()
                case .open: openFile()
                case .save: saveFile()
                case .saveAs: saveFileAs()
                case nil: return
                }
                fileRequest = nil
            }
    }

    /// The layout with its sheets, the phrasebook panel, and the model's setup.
    private var screen: some View {
        layout
            .tint(.brand)
            .preferredColorScheme(Appearance.colorScheme(for: appearance))
            .animation(.snappy(duration: 0.2), value: model.selectedIssueID)
            .task { await model.load() }
            .onChange(of: showsSuggestions, initial: true) { model.showsSuggestions = showsSuggestions }
            .onChange(of: model.showsSuggestions) { showsSuggestions = model.showsSuggestions }
            .sheet(isPresented: $showsIssueList) {
                IssueListSheet(model: model) { issue in
                    showsIssueList = false
                    editorIsFocused = true
                    model.select(issue)
                }
                .tint(.brand)
            }
            .sheet(isPresented: $showsProgress) {
                ProgressSheet(store: model.stats)
                    .tint(.brand)
            }
            // A side panel on the Mac and iPad; on iPhone a half-height sheet the editor stays usable under.
            .inspector(isPresented: $showsPhrasebook) {
                PhrasebookView(model: model)
                    .tint(.brand)
                    .inspectorColumnWidth(min: 280, ideal: 360, max: 520)
                    .presentationDetents([.medium, .large])
                    .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            }
    }

    // MARK: - New Entry, Open and Save

    /// A failed Open or Save, shown as an alert.
    private struct FileProblem {
        let title: String
        let message: String
    }

    /// Starts a new entry, first asking whether to replace text that's in the editor.
    private func newEntry() {
        if model.hasText {
            pendingReplace = .newEntry
        } else {
            replace(with: .newEntry)
        }
    }

    /// Starts Open…, first asking whether to replace text that's in the editor.
    private func openFile() {
        if model.hasText {
            pendingReplace = .open
        } else {
            replace(with: .open)
        }
    }

    /// Carries out New Entry or Open… once the editor's text may be replaced.
    private func replace(with request: FileRequest) {
        switch request {
        case .newEntry:
            // The last story's title doesn't name a new one, even as a suggested file name.
            storyTitle = nil
            model.newEntry()
            editorIsFocused = true
        case .open:
            showsImporter = true
        case .save, .saveAs:
            return
        }
    }

    /// Writes back to the file the text came from or last went to, or starts Save As…
    /// for new text. A file that can no longer be written also falls back to Save As….
    private func saveFile() {
        guard let url = model.fileURL else {
            showsExporter = true
            return
        }
        do {
            try FrenchTextFile.write(model.plainText, to: url)
        } catch {
            showsExporter = true
        }
    }

    /// Starts Save As….
    private func saveFileAs() {
        showsExporter = true
    }

    /// Loads the file picked in Open…, or reports why it couldn't be read.
    private func openPicked(_ result: Result<URL, any Error>) {
        do {
            let url = try result.get()
            model.open(try FrenchTextFile.text(at: url), from: url)
            storyTitle = nil
        } catch {
            fileProblem = FileProblem(title: "The file couldn't be opened", message: error.localizedDescription)
        }
    }

    /// Remembers where Save As… wrote, or reports why it failed.
    private func savedPicked(_ result: Result<URL, any Error>) {
        switch result {
        case .success(let url):
            model.didSave(to: url)
        case .failure(let error):
            // Canceling the save panel isn't a problem to report.
            if (error as? CocoaError)?.code != .userCancelled {
                fileProblem = FileProblem(title: "The file couldn't be saved", message: error.localizedDescription)
            }
        }
    }

    /// Whether the replace question is showing; dismissing it clears the pending command.
    private var confirmsReplace: Binding<Bool> {
        Binding(get: { pendingReplace != nil }, set: { if !$0 { pendingReplace = nil } })
    }

    /// Whether the file alert is showing; dismissing it clears the problem.
    private var showsFileProblem: Binding<Bool> {
        Binding(get: { fileProblem != nil }, set: { if !$0 { fileProblem = nil } })
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
                Button("Phrasebook", systemImage: "book") {
                    showsPhrasebook.toggle()
                }
                .help("Phrasebook")
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
                TopBar(model: model, showsIssueList: $showsIssueList, showsProgress: $showsProgress, showsPhrasebook: $showsPhrasebook, newEntry: newEntry, openFile: openFile, saveFile: saveFile, saveFileAs: saveFileAs)

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

    /// The placeholder's top offset, matching where the editor draws its first line.
    ///
    /// The editor is padded 12 points; UITextView adds an 8-point top inset, NSTextView adds none.
    private var placeholderTopInset: CGFloat {
        #if os(macOS)
        12
        #else
        20
        #endif
    }

    /// The French editor, with a placeholder when it is empty.
    private var editor: some View {
        TextEditor(text: $model.text, selection: $model.selection)
            .font(.plexMono(Typography.frenchSize, relativeTo: .title3))
            .lineSpacing(Typography.frenchLineSpacing)
            .scrollContentBackground(.hidden)
            // The learner's own mistakes are the point: never let the keyboard fix them.
            .autocorrectionDisabled()
            // Pasted text keeps only Coquille's own styling, never the source's fonts or colors.
            .attributedTextFormattingDefinition(EditorAttributes.self)
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
                    .padding(.vertical, placeholderTopInset)
                }
            }
            .onChange(of: model.text) { model.textDidChange() }
            .onChange(of: model.selection) { model.selectionDidChange() }
            .onChange(of: model.narrator.spokenRange) { model.spokenWordDidChange() }
            .onChange(of: model.narrator.state) { model.spokenWordDidChange() }
    }
}

/// The only attributes the French editor accepts: the issue underlines and the highlights.
struct EditorAttributes: AttributeScope {
    let underlineStyle: AttributeScopes.SwiftUIAttributes.UnderlineStyleAttribute
    let backgroundColor: AttributeScopes.SwiftUIAttributes.BackgroundColorAttribute
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
    EditorScreen(stats: StatsStore(fileURL: nil))
}

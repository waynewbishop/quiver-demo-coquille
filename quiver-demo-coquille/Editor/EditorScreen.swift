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
/// English toggle, beside the journal's saved entries. On wide windows the English
/// sits beside the French.
///
/// Saving is always the learner's choice, as in the Notebook and Xcode: writing is
/// kept between launches but never becomes an entry unless saved, and leaving work
/// that isn't saved asks Save, Don't Save or Cancel. Don't Save lets it go.
struct EditorScreen: View {

    let journal: Journal
    @State private var model: EditorModel
    /// A validated link waiting for initial restoration or a save decision.
    @Binding private var pendingRoute: CoquilleRoute?
    @State private var showsIssueList = false
    @State private var showsImporter = false
    /// The text and name of a copy being exported, while the save panel is up.
    @State private var exporting: ExportItem?
    /// The entries list as a sheet, on iPhone and iPad.
    @State private var showsEntries = false
    @State private var fileProblem: FileProblem?
    /// A command chosen in the File menu, handled and cleared by this window.
    @State private var fileRequest: FileRequest?
    /// Where the learner asked to go while there's work that isn't saved, awaiting Save or Don't Save.
    @State private var pendingMove: Move?
    /// The title sheet for saving new writing, and what to do once it's saved.
    @State private var naming: Naming?
    /// The entry waiting on the learner's confirmation before it's deleted.
    @State private var pendingDelete: URL?
    /// The entry whose name is being edited in the list.
    @State private var renaming: URL?
    /// The story's title from the on-device model, or `nil` until there is one. It
    /// names unsaved writing in the window and fills in the title when it's saved.
    @State private var storyTitle: String?
    @State private var showsProgress = false
    @State private var showsPhrasebook = false
    @State private var showsSettings = false
    @State private var showsCorrections = false
    @FocusState private var editorIsFocused: Bool
    @Environment(\.scenePhase) private var scenePhase
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif
    @AppStorage(Appearance.storageKey) private var appearance = Appearance.system
    #if !os(macOS)
    /// Compact on iPhone, where the editor gets a navigation bar instead of the top bar.
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// Compact in iPhone landscape, where height is what runs short.
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    /// Whether the editor uses the iPhone layout: on every iPhone, including the larger
    /// ones that report a regular width in landscape, and in narrow iPad windows.
    private var usesPhoneLayout: Bool {
        horizontalSizeClass == .compact || UIDevice.current.userInterfaceIdiom == .phone
    }

    /// Whether the iPhone is in landscape, with the English and the issue card beside the French.
    private var isLandscapePhone: Bool {
        usesPhoneLayout && verticalSizeClass == .compact
    }
    #endif
    /// The Show suggestions setting, kept between launches and mirrored into the model.
    @AppStorage("showsSuggestions") private var showsSuggestions = true
    /// The learner's text size, from the View menu.
    @AppStorage(FontSize.storageKey) private var fontSize = FontSize.standard
    /// The installed French playback voice, shared by the editor and phrasebook.
    @AppStorage(SpeechNarrator.voiceStorageKey) private var playbackVoiceID = ""

    #if os(macOS)
    /// The English pane's share of the window, kept between launches.
    @AppStorage("englishPaneFraction") private var englishFraction = SplitPanes<EmptyView, EmptyView>.defaultFraction
    /// Whether the journal sidebar is showing. It starts closed, so the writing comes first.
    @State private var columns = NavigationSplitViewVisibility.detailOnly
    #endif

    /// Window width at which English moves from below the French to beside it.
    private static let splitWidth = 700.0

    /// Creates the editor around the app's one stats store, which the Corrections window
    /// reads too, the journal of saved entries, and the workspace that keeps unsaved work.
    init(
        stats: StatsStore,
        journal: Journal,
        workspace: Workspace?,
        pendingRoute: Binding<CoquilleRoute?> = .constant(nil)
    ) {
        self.journal = journal
        _model = State(initialValue: EditorModel(stats: stats, journal: journal, workspace: workspace))
        _pendingRoute = pendingRoute
    }

    var body: some View {
        root
            .fileImporter(isPresented: $showsImporter, allowedContentTypes: [.plainText], onCompletion: imported)
            .fileExporter(
                isPresented: showsExporter,
                document: FrenchTextFile(text: exporting?.text ?? ""),
                contentType: .plainText,
                defaultFilename: exporting?.name,
                onCompletion: exported
            )
            #if os(macOS)
            .confirmationDialog(saveQuestion, isPresented: asksToSave, titleVisibility: .visible, presenting: pendingMove) { move in
                Button("Save") { save(then: move) }
                Button("Don't Save", role: .destructive) { carryOut(move) }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("Your changes will be lost if you don't save them.")
            }
            #else
            // An alert, since the question can come from a menu or the journal sheet,
            // where a confirmation dialog floats as a popover without its Cancel button.
            .alert(saveQuestion, isPresented: asksToSave, presenting: pendingMove) { move in
                Button("Save") { save(then: move) }
                Button("Don't Save", role: .destructive) { carryOut(move) }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("Your changes will be lost if you don't save them.")
            }
            #endif
            .alert(deleteQuestion, isPresented: confirmsDelete, presenting: pendingDelete) { url in
                Button("Delete", role: .destructive) { delete(url) }
                Button("Cancel", role: .cancel) {}
            } message: { url in
                Text(url == model.fileURL
                     ? "Its text stays in the editor, unsaved, so you can save it again. This can't be undone."
                     : "It will be removed from your journal. This can't be undone.")
            }
            .alert(fileProblem?.title ?? "", isPresented: showsFileProblem, presenting: fileProblem) { _ in
                Button("OK", role: .cancel) {}
            } message: { problem in
                Text(problem.message)
            }
            .sheet(item: $naming) { naming in
                SaveEntrySheet(
                    suggestedTitle: model.exerciseTitle ?? storyTitle ?? "",
                    proposedName: model.proposedName(title:),
                    isNewEntry: naming.asNewEntry
                ) { title in
                    finishSaving(naming, title: title)
                }
                .tint(.brand)
            }
            // The File menu's commands ask this window through `fileRequest`.
            .focusedSceneValue(\.fileRequest, $fileRequest)
            .focusedSceneValue(\.editorModel, model)
            .focusedSceneValue(\.fileMenuState, FileMenuState(
                canSave: model.canSave,
                canExport: model.hasText,
                hasOpenEntry: model.fileURL != nil
            ))
            .onChange(of: fileRequest) {
                if let fileRequest { handle(fileRequest) }
                fileRequest = nil
            }
            // A title the model gave other writing doesn't name this writing.
            .onChange(of: model.document) {
                storyTitle = nil
            }
            // Writing that isn't saved is kept before the app can be quit.
            .onChange(of: scenePhase) {
                if scenePhase != .active { model.saveNow() }
                if scenePhase == .active { journal.refresh() }
            }
            // A language pack installed elsewhere, or from Settings, can fill in the English.
            .onReceive(NotificationCenter.default.appBecameActive) { _ in model.recheckEnglish() }
            .onReceive(NotificationCenter.default.publisher(for: TranslationPack.didChange)) { _ in model.recheckEnglish() }
    }

    /// On the Mac, the journal sidebar beside the editor; elsewhere the editor alone,
    /// with the journal in a sheet.
    @ViewBuilder
    private var root: some View {
        #if os(macOS)
        NavigationSplitView(columnVisibility: $columns) {
            entriesList
                .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 360)
                .tint(.brand)
                // The Journal button below replaces the system's sidebar button, so the Mac
                // shows the same list icon as the iPhone and iPad.
                .toolbar(removing: .sidebarToggle)
        } detail: {
            screen
        }
        #else
        screen
            .sheet(isPresented: $showsEntries) {
                NavigationStack {
                    entriesList
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showsEntries = false }
                            }
                        }
                }
                .tint(.brand)
            }
        #endif
    }

    /// The saved entries, whose every action goes through this window.
    private var entriesList: some View {
        EntriesList(journal: journal, model: model, renaming: $renaming, perform: perform)
    }

    /// The layout with its sheets, the phrasebook panel, and the model's setup.
    private var screen: some View {
        layout
            .tint(.brand)
            .onChange(of: appearance, initial: true) { appearance.apply() }
            .animation(.snappy(duration: 0.2), value: model.selectedIssueID)
            .task {
                await model.load()
                consumePendingRoute()
            }
            .onChange(of: pendingRoute) { consumePendingRoute() }
            .onChange(of: showsSuggestions, initial: true) { model.showsSuggestions = showsSuggestions }
            .onChange(of: model.showsSuggestions) { showsSuggestions = model.showsSuggestions }
            .onChange(of: playbackVoiceID, initial: true) { model.setPlaybackVoice(playbackVoiceID) }
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
            #if !os(macOS)
            .sheet(isPresented: $showsSettings) {
                SettingsView()
                    .tint(.brand)
            }
            .sheet(isPresented: $showsCorrections) {
                NavigationStack {
                    CorrectionsView(store: model.stats)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showsCorrections = false }
                            }
                        }
                }
                .tint(.brand)
            }
            #endif
            .modifier(PhrasebookPresentation(isPresented: $showsPhrasebook, model: model))
    }

    // MARK: - Saving and moving between writing

    /// A failed file action, shown as an alert.
    private struct FileProblem {
        let title: String
        let message: String
    }

    /// A copy to export: its text and suggested name.
    private struct ExportItem {
        let text: String
        let name: String
    }

    /// Other writing the learner asked for, which replaces what's open.
    private enum Move: Equatable {
        case open(URL)
        case new
        case todaysEntry
        case prompt(WritingPrompt)
        case exercise(ExercisePrompt)
        case importFile
        case example
    }

    /// A save that needs a title first, and where to go once it's done.
    private struct Naming: Identifiable {
        let id = UUID()
        /// Whether this is Save as New Entry, which keeps any open entry as it was.
        let asNewEntry: Bool
        let then: Move?
    }

    /// Carries out a File menu command.
    private func handle(_ request: FileRequest) {
        switch request {
        case .new: move(.new)
        case .importFile: move(.importFile)
        case .save: save(then: nil)
        case .saveAsNewEntry: naming = Naming(asNewEntry: true, then: nil)
        case .renameEntry: startRenaming()
        case .duplicateEntry: if let url = model.fileURL { duplicate(url) }
        case .deleteEntry: pendingDelete = model.fileURL
        case .export: export(model.plainText, named: exportName)
        }
    }

    /// Carries out something asked for in the journal list.
    private func perform(_ action: EntryAction) {
        switch action {
        case .open(let url): move(.open(url))
        case .rename(let url, let title):
            attempt("The entry couldn't be renamed") { try model.renameEntry(url, to: title) }
        case .duplicate(let url): duplicate(url)
        case .delete(let url): pendingDelete = url
        case .export(let url):
            attempt("The entry couldn't be read") {
                export(try FrenchTextFile.text(at: url), named: url.deletingPathExtension().lastPathComponent)
            }
        }
    }

    /// Applies a link only after workspace restoration; a later arrival waits for that task.
    private func consumePendingRoute() {
        guard model.hasFinishedLoading, let route = pendingRoute else { return }
        pendingRoute = nil
        switch route {
        case .today(let prompt): move(.prompt(prompt))
        case .exercise(let exercise): move(.exercise(exercise))
        case .write:
            // Never a save question on the way to writing: carry on, or start today's entry.
            if model.hasText { editorIsFocused = true } else { move(.todaysEntry) }
        case .phrasebook:
            showsPhrasebook = true
        case .journal:
            #if os(macOS)
            columns = .all
            #else
            showsEntries = true
            #endif
        case .corrections:
            #if os(macOS)
            openWindow(id: "corrections")
            #else
            showsCorrections = true
            #endif
        }
    }

    /// Goes to other writing, first asking Save or Don't Save when there's work that isn't saved.
    private func move(_ move: Move) {
        if case .open(let url) = move, url == model.fileURL { return }
        if model.needsSaveDecision {
            pendingMove = move
        } else {
            carryOut(move)
        }
    }

    /// Goes to other writing once the work that wasn't saved is saved or let go.
    private func carryOut(_ move: Move) {
        switch move {
        case .open(let url):
            attempt("The entry couldn't be opened") { try model.openEntry(url) }
        case .new:
            model.startNew()
            showsEntries = false
            editorIsFocused = true
        case .todaysEntry:
            model.newEntry()
            editorIsFocused = true
        case .prompt(let prompt):
            model.newEntry(for: prompt)
            storyTitle = nil
            showsEntries = false
            editorIsFocused = true
        case .exercise(let exercise):
            model.newEntry(for: exercise)
            storyTitle = nil
            showsEntries = false
            editorIsFocused = true
        case .importFile:
            showsImporter = true
        case .example:
            editorIsFocused = false
            model.loadExample()
        }
        if case .open = move { showsEntries = false }
    }

    /// Saves the writing, asking for a title first when it isn't an entry yet, then goes on to `move`.
    private func save(then move: Move?) {
        guard model.canSave else {
            if let move { carryOut(move) }
            return
        }
        if model.saveNeedsTitle {
            naming = Naming(asNewEntry: false, then: move)
            return
        }
        attempt("The entry couldn't be saved") {
            try model.save()
            if let move { carryOut(move) }
        }
    }

    /// Saves with the title the learner chose in the sheet, then goes on.
    private func finishSaving(_ naming: Naming, title: String) {
        self.naming = nil
        attempt("The entry couldn't be saved") {
            if naming.asNewEntry {
                try model.saveAsNewEntry(title: title)
            } else {
                try model.save(title: title)
            }
            if let move = naming.then { carryOut(move) }
        }
    }

    /// Edits the open entry's name in the list, showing the list if it's hidden.
    private func startRenaming() {
        guard let url = model.fileURL else { return }
        #if os(macOS)
        columns = .all
        #else
        showsEntries = true
        #endif
        renaming = url
    }

    /// Copies an entry and puts the copy's name up for editing.
    private func duplicate(_ url: URL) {
        attempt("The entry couldn't be duplicated") {
            if let copy = try model.duplicateEntry(url) { renaming = copy }
        }
    }

    /// Deletes an entry the learner confirmed.
    private func delete(_ url: URL) {
        attempt("The entry couldn't be deleted") { try model.deleteEntry(url) }
    }

    /// Starts Export a Copy… for `text`.
    private func export(_ text: String, named name: String) {
        exporting = ExportItem(text: text, name: name)
    }

    /// The open writing's name for an exported copy: the entry's own, or the story's title.
    private var exportName: String {
        model.fileURL?.deletingPathExtension().lastPathComponent ?? FrenchTextFile.suggestedFilename(for: model.exerciseTitle ?? storyTitle)
    }

    /// Copies the file picked in Import… into the journal as a new entry and opens it,
    /// or reports why it couldn't be read.
    private func imported(_ result: Result<URL, any Error>) {
        attempt("The file couldn't be imported") {
            let url = try result.get()
            let contents = try FrenchTextFile.text(at: url)
            let entry = try journal.importEntry(text: contents, originalName: url.deletingPathExtension().lastPathComponent)
            try model.openEntry(entry)
        }
    }

    /// Reports an export that failed.
    private func exported(_ result: Result<URL, any Error>) {
        exporting = nil
        // Canceling the save panel isn't a problem to report.
        if case .failure(let error) = result, (error as? CocoaError)?.code != .userCancelled {
            fileProblem = FileProblem(title: "The copy couldn't be saved", message: error.localizedDescription)
        }
    }

    /// Runs a file action, showing an alert titled `title` if it fails.
    private func attempt(_ title: String, _ action: () throws -> Void) {
        do {
            try action()
        } catch {
            fileProblem = FileProblem(title: title, message: error.localizedDescription)
        }
    }

    /// The open writing's name, as the window and the save question show it.
    private var documentName: String {
        switch model.document {
        case .unsaved: model.exerciseTitle ?? storyTitle ?? "Untitled"
        case .entry(let url): Journal.title(of: url) ?? url.deletingPathExtension().lastPathComponent
        }
    }

    /// The window's second line: whether the writing is saved, and where it lives.
    private var documentStatus: String {
        switch model.document {
        case .unsaved: model.needsSaveDecision ? "Not saved" : ""
        case .entry: model.isEdited ? "Edited" : ""
        }
    }

    /// "Do you want to save the changes to “Une journée au marché”?"
    private var saveQuestion: String {
        "Do you want to save the changes to “\(documentName)”?"
    }

    /// "Delete “Une journée au marché”?"
    private var deleteQuestion: String {
        let name = pendingDelete.map { Journal.title(of: $0) ?? $0.deletingPathExtension().lastPathComponent } ?? ""
        return "Delete “\(name)”?"
    }

    /// The Save, Save as New Entry and Export items, for the Français header's menus.
    @ViewBuilder
    private var saveMenuItems: some View {
        Button("Save", systemImage: "square.and.arrow.down") { save(then: nil) }
            .disabled(!model.canSave)
        Button("Save as New Entry…", systemImage: "plus.square.on.square") { naming = Naming(asNewEntry: true, then: nil) }
            .disabled(!model.canSave)
        Divider()
        Button("Export a Copy…", systemImage: "square.and.arrow.up") { export(model.plainText, named: exportName) }
            .disabled(!model.hasText)
    }

    #if os(macOS)
    /// The French text's right-click menu: Cut, Copy and Paste, then Save.
    ///
    /// The edit commands go to the text view itself, as the Edit menu's do, so they keep
    /// undo and paste only Coquille's own styling.
    @ViewBuilder
    private var editorMenuItems: some View {
        Button("Cut") { NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil) }
            .disabled(!model.hasSelection)
        Button("Copy") { NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil) }
            .disabled(!model.hasSelection)
        Button("Paste") { NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil) }
        Divider()
        Button("Save") { save(then: nil) }
            .disabled(!model.canSave)
    }
    #endif

    /// Whether the save question is showing; dismissing it clears the pending move.
    private var asksToSave: Binding<Bool> {
        Binding(get: { pendingMove != nil }, set: { if !$0 { pendingMove = nil } })
    }

    /// Whether the delete question is showing; dismissing it clears the pending entry.
    private var confirmsDelete: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }

    /// Whether the save panel for a copy is showing.
    private var showsExporter: Binding<Bool> {
        Binding(get: { exporting != nil }, set: { if !$0 { exporting = nil } })
    }

    /// Whether the file alert is showing; dismissing it clears the problem.
    private var showsFileProblem: Binding<Bool> {
        Binding(get: { fileProblem != nil }, set: { if !$0 { fileProblem = nil } })
    }

    #if os(macOS)
    /// Whether the journal sidebar is open, for the toolbar's Journal button.
    private var showsJournalSidebar: Binding<Bool> {
        Binding {
            columns != .detailOnly
        } set: { isShowing in
            withAnimation {
                columns = isShowing ? .all : .detailOnly
            }
        }
    }

    /// The Mac window: French and English side by side with a draggable divider, play
    /// and stop grouped at the toolbar's leading edge as in Xcode, New beside the phrasebook,
    /// the streak, and the theme toggle at its trailing edge, and status and English in the footer.
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
        .navigationTitle(documentName)
        .navigationSubtitle(documentStatus)
        .task(id: titleSource) { await retitle() }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                PanelToggle(title: "Journal", systemImage: "list.bullet", isOn: showsJournalSidebar)
                    .help(columns == .detailOnly ? "Show the journal" : "Hide the journal")
            }

            ToolbarItemGroup(placement: .navigation) {
                MacPlayButton(model: model)
                MacStopButton(model: model)
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button("New", systemImage: "square.and.pencil") { move(.new) }
                    .labelStyle(.iconOnly)
                    .help("Start a blank page (⌘N)")
                    .disabled(!model.hasText && model.fileURL == nil)

                PanelToggle(title: "Phrasebook", systemImage: "book", isOn: $showsPhrasebook)
                    .help("Phrasebook")
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    showsProgress = true
                } label: {
                    Label("Progress", systemImage: "chart.bar.xaxis")
                        .labelStyle(.iconOnly)
                }
                .help("Your progress")
            }

            ToolbarItem(placement: .primaryAction) {
                ShareLink(item: model.plainText)
                    .labelStyle(.iconOnly)
                    .help("Export this entry to another app")
                    .disabled(!model.hasText)
            }

            ToolbarSpacer(.fixed, placement: .primaryAction)

            ToolbarItem(placement: .primaryAction) {
                ThemeToggle()
            }
        }
    }

    /// The French pane: its header, the editor, and the open issue's card floating over it.
    private var frenchPane: some View {
        VStack(spacing: 0) {
            PaneHeader(title: "FRANÇAIS", showsDivider: true)
                .background(Color.frenchPaper)
                .overlay(alignment: .trailing) {
                    Menu {
                        saveMenuItems
                    } label: {
                        Text(model.isEdited || model.fileURL == nil ? "Save" : "Saved")
                    } primaryAction: {
                        save(then: nil)
                    }
                    .menuStyle(.button)
                    .buttonStyle(.borderless)
                    .fixedSize()
                    .disabled(!model.canSave)
                    .help("Save to your journal (⌘S)")
                    .padding(.trailing, 16)
                }
                .contextMenu { saveMenuItems }
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
    /// The navigation-bar layout on iPhone, and the top-bar layout on iPad.
    @ViewBuilder
    private var layout: some View {
        if usesPhoneLayout {
            compactLayout
        } else {
            regularLayout
        }
    }

    /// The iPhone layout: the journal, phrasebook and More menu in a navigation bar
    /// titled with the story's name, the editor with English below it, the open issue's
    /// card, and status, English and play along the bottom.
    private var compactLayout: some View {
        NavigationStack {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    if isLandscapePhone {
                        landscapePanes(width: geometry.size.width)
                    } else {
                        portraitPanes(height: geometry.size.height)
                    }

                    CompactBottomBar(
                        model: model,
                        showsIssueList: $showsIssueList,
                        isEditing: editorIsFocused,
                        isShort: isLandscapePhone,
                        dismissKeyboard: { editorIsFocused = false },
                        jumpToFirstError: jumpToFirstError
                    )
                }
            }
            .navigationTitle(documentName)
            .navigationSubtitle(documentStatus)
            .navigationBarTitleDisplayMode(.inline)
            // In landscape the keyboard leaves room for only a line or two, so the
            // navigation bar steps aside while typing; hiding the keyboard brings it back.
            .toolbarVisibility(isLandscapePhone && editorIsFocused ? .hidden : .automatic, for: .navigationBar)
            .animation(.snappy(duration: 0.2), value: editorIsFocused)
            .toolbar {
                CompactToolbar(model: model, showsProgress: $showsProgress, showsPhrasebook: $showsPhrasebook, showsEntries: $showsEntries, showsSettings: $showsSettings, perform: handle)
            }
            // Going back to the French brings the keyboard up, so the phrasebook sheet
            // steps down rather than sharing the screen with it.
            .onChange(of: editorIsFocused) {
                if editorIsFocused { showsPhrasebook = false }
            }
            .task(id: titleSource) { await retitle() }
        }
    }

    /// iPhone portrait: the French, the English below it, then the open issue's card.
    @ViewBuilder
    private func portraitPanes(height: CGFloat) -> some View {
        editor
        if model.isEnglishOn {
            Divider()
            EnglishPane(model: model, showsHeaderBar: false)
                .frame(maxHeight: height * 0.3)
        }

        if let issue = model.selectedIssue {
            IssueCard(issue: issue, model: model)
                .id(issue.id)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    /// iPhone landscape: the French on the left, and on the right the open issue's card,
    /// or the English when no card is open, so neither ever covers the text.
    private func landscapePanes(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            editor
            if let issue = model.selectedIssue {
                ScrollView {
                    IssueCard(issue: issue, model: model)
                        .id(issue.id)
                        .padding(12)
                }
                .frame(width: min(460, width * 0.5))
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else if model.isEnglishOn {
                Divider()
                EnglishPane(model: model, showsHeaderBar: true)
                    .frame(width: width * 0.4)
            }
        }
    }

    /// The iPad layout: a top bar, the editor with English below or beside it, the
    /// open issue's card, and the bottom bar.
    private var regularLayout: some View {
        GeometryReader { geometry in
            let isWide = geometry.size.width >= Self.splitWidth
            VStack(spacing: 0) {
                TopBar(model: model, showsIssueList: $showsIssueList, showsProgress: $showsProgress, showsPhrasebook: $showsPhrasebook, showsEntries: $showsEntries, showsSettings: $showsSettings, perform: handle)

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

    /// The text to title: the French, without the notes, once it's linted with no errors, otherwise `nil`.
    private var titleSource: String? {
        model.isLintCurrent && !model.isLocked && model.hasFrench ? Notes.removed(model.plainText) : nil
    }

    /// Names the story after a pause in typing; an editor with no French goes back to the app's name.
    private func retitle() async {
        guard model.exerciseTitle == nil else { return }
        guard let text = titleSource else {
            if !model.hasFrench { storyTitle = nil }
            return
        }
        try? await Task.sleep(for: .seconds(2))
        guard !Task.isCancelled, let title = await StoryTitler.title(for: text), !Task.isCancelled else { return }
        storyTitle = title
    }

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

    /// The French editor, with an optional exercise hint and an empty-text placeholder.
    private var editor: some View {
        VStack(spacing: 0) {
            if let hint = model.exerciseHint {
                ExerciseHintView(hint: hint)
                    .id(hint)
                Divider()
            }
            textEditor
            MarkerKeywordBar(model: model)
        }
        // A slight cream in light mode; the color is clear in dark mode.
        .background(Color.frenchPaper)
    }

    /// The text editor itself, including its placeholder and editing commands.
    private var textEditor: some View {
        TextEditor(text: $model.text, selection: $model.selection)
            .font(.plexMono(fontSize.frenchSize, relativeTo: .title3))
            .lineSpacing(fontSize.frenchLineSpacing)
            // The text view keeps the font its existing text was drawn in, so a new size
            // would only reach text typed afterwards. Rebuilding the editor redraws all of it;
            // the text and selection live in the model, so neither is lost.
            .id(fontSize)
            .scrollContentBackground(.hidden)
            // The learner's own mistakes are the point: never let the keyboard fix them,
            // nor Writing Tools' Proofread or Rewrite, whose fixes would never be the learner's.
            .autocorrectionDisabled()
            .writingToolsBehavior(.disabled)
            #if os(macOS)
            // The right-click menu holds only Cut, Copy, Paste and Save. iPhone and iPad
            // keep the system's edit menu, since a context menu there would take over the
            // long press that selects text.
            .contextMenu { editorMenuItems }
            #endif
            // Pasted text keeps only Coquille's own styling, never the source's fonts; a
            // pasted color lasts only until the next edit, which recolors every note.
            .attributedTextFormattingDefinition(EditorAttributes.self)
            .focused($editorIsFocused)
            // ⇧↵ plays, as it runs code in the Quiver Notebook, and never adds a line.
            .onKeyPress(.return, phases: .down) { press in
                guard press.modifiers == .shift else { return .ignored }
                playFromKeyboard()
                return .handled
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .overlay(alignment: .topLeading) {
                if !model.hasText {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(model.loadFailure ?? "Écrivez en français…")
                            .font(.plexMono(fontSize.frenchSize, relativeTo: .title3))
                            .foregroundStyle(.tertiary)
                            .allowsHitTesting(false)
                        if model.loadFailure == nil {
                            starterButtons
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

extension EditorScreen {

    /// Plays, pauses or resumes for ⇧↵; on the Mac it beeps when errors keep the French from playing.
    fileprivate func playFromKeyboard() {
        let wasIdle = model.narrator.state == .idle
        model.togglePlay()
        #if os(macOS)
        if wasIdle && model.narrator.state == .idle { NSSound.beep() }
        #endif
    }

    /// Start today's entry and Try an example, side by side, or stacked at one width on iPhone.
    @ViewBuilder
    fileprivate var starterButtons: some View {
        #if os(macOS)
        sideBySideStarterButtons
        #else
        // Stacked in iPhone portrait; landscape has the width for a row.
        if usesPhoneLayout && !isLandscapePhone {
            VStack(alignment: .leading, spacing: 10) {
                Button { move(.todaysEntry) } label: {
                    Label("Start today's entry", systemImage: "calendar")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button { move(.example) } label: {
                    Label("Try an example", systemImage: "text.badge.checkmark")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(.bordered)
            // Both buttons take the wider one's width.
            .fixedSize(horizontal: true, vertical: false)
        } else {
            sideBySideStarterButtons
        }
        #endif
    }

    /// The two starter buttons in a row, as on the Mac and iPad.
    private var sideBySideStarterButtons: some View {
        HStack(spacing: 12) {
            Button("Start today's entry", systemImage: "calendar") { move(.todaysEntry) }
            Button("Try an example", systemImage: "text.badge.checkmark") { move(.example) }
        }
        .buttonStyle(.bordered)
    }
}

/// Shows the phrasebook: a side panel on the Mac and iPad, and on iPhone a half-height
/// sheet the editor stays usable under.
///
/// iPhone always gets the sheet. An inspector there reopens on its own when a Pro Max
/// launches in landscape, where it's a column rather than a sheet, even while closed.
private struct PhrasebookPresentation: ViewModifier {

    @Binding var isPresented: Bool
    let model: EditorModel

    func body(content: Content) -> some View {
        #if os(macOS)
        inspector(on: content)
        #else
        // The idiom never changes while the app runs, so the editor's identity is stable.
        if UIDevice.current.userInterfaceIdiom == .phone {
            content.sheet(isPresented: $isPresented) { phrasebook }
        } else {
            inspector(on: content)
        }
        #endif
    }

    /// The phrasebook as an inspector.
    private func inspector(on content: Content) -> some View {
        content.inspector(isPresented: $isPresented) {
            phrasebook
                .inspectorColumnWidth(min: 280, ideal: 360, max: 520)
        }
    }

    /// The phrasebook with its sheet sizes, which only apply where it's a sheet.
    private var phrasebook: some View {
        PhrasebookView(model: model)
            .tint(.brand)
            .presentationDetents([.medium, .large])
            .presentationBackgroundInteraction(.enabled(upThrough: .medium))
    }
}

/// The only attributes the French editor accepts: the issue underlines, the highlights,
/// and the colors of the learner's notes and review markers.
struct EditorAttributes: AttributeScope {
    let underlineStyle: AttributeScopes.SwiftUIAttributes.UnderlineStyleAttribute
    let backgroundColor: AttributeScopes.SwiftUIAttributes.BackgroundColorAttribute
    let foregroundColor: AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute
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
    EditorScreen(stats: StatsStore(fileURL: nil), journal: Journal(folderURL: .temporaryDirectory.appending(path: "Preview journal")), workspace: nil)
}

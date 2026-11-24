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

/// Something the learner asked the entries list to do. The editor carries it out, so
/// opening other writing first asks Save or Don't Save when the open entry has changes.
enum EntryAction: Equatable {
    case open(URL)
    case rename(URL, String)
    case duplicate(URL)
    case delete(URL)
    case export(URL)
}

/// The journal's saved entries, newest first, like the index at the front of a paper
/// journal, or the Notebook's list of examples.
///
/// Entries only change when the learner acts, from a row's right-click menu or the
/// File menu. It's the Mac window's sidebar, and a sheet on iPhone and iPad.
struct EntriesList: View {

    let journal: Journal
    let model: EditorModel
    /// The entry whose rename dialog is showing, if any.
    @Binding var renaming: URL?
    let perform: (EntryAction) -> Void
    /// Whether the journal shows the month as a calendar of paintings, kept between launches.
    @AppStorage("journalShowsCalendar") private var showsCalendar = false
    /// Set when the learner asks to restore a backup from the empty journal.
    @State private var showsRestorePicker = false
    #if !os(macOS)
    @AppStorage(JournalArchive.lastBackupKey) private var lastBackup = 0.0
    @State private var showsBackUp = false
    #endif

    var body: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $showsCalendar) {
                Label("List view", systemImage: "list.bullet").tag(false)
                Label("Calendar view", systemImage: "calendar").tag(true)
            }
            .pickerStyle(.segmented)
            .labelStyle(.iconOnly)
            .fixedSize()
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            if showsCalendar {
                MonthMosaicView(journal: journal) { perform(.open($0)) }
            } else {
                list
            }
        }
        .navigationTitle("Journal")
        .onAppear { journal.refresh() }
        .journalRestore(journal, isPicking: $showsRestorePicker)
        #if !os(macOS)
        // The journal is itself a sheet here, so its rename dialog opens from inside it.
        .renameSheet($renaming, journal: journal, perform: perform)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { dataMenu }
        }
        .sheet(isPresented: $showsBackUp) {
            BackUpSheet(journal: journal)
                .tint(.brand)
        }
        #endif
    }

    #if !os(macOS)
    /// A quiet shortcut to the same backup and restore actions as Settings, with when the
    /// journal was last backed up.
    private var dataMenu: some View {
        Menu {
            Button("Back Up Journal…", systemImage: "archivebox") { showsBackUp = true }
            Button("Restore from Backup…", systemImage: "arrow.down.doc") { showsRestorePicker = true }
            Section {
                Text("Last backup saved: \(lastBackupDescription(lastBackup))")
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel("Journal data")
    }
    #endif

    /// The entries, newest first, with their right-click menus.
    private var list: some View {
        List(selection: selection) {
            if journal.isUnavailable {
                Label("Coquille can't read the journal folder right now.", systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .selectionDisabled()
            } else if journal.entries.isEmpty {
                Text("Entries you save will appear here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .selectionDisabled()
                // Where someone on a replacement phone, or after reinstalling, looks first.
                Button("Restore from Backup…") { showsRestorePicker = true }
                    .selectionDisabled()
                Text("Starting on a new device, or reinstalled Coquille? Choose a backup to bring your entries back.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .selectionDisabled()
            }
            let showsThumbnailSpace = journal.entries.contains { $0.tableau != nil }
            ForEach(journal.entries) { entry in
                EntryRow(
                    entry: entry,
                    model: model,
                    isOpen: model.fileURL == entry.url,
                    showsThumbnailSpace: showsThumbnailSpace
                )
                .tag(entry.url)
                .swipeActions {
                    Button("Delete", role: .destructive) { perform(.delete(entry.url)) }
                }
            }
        }
        .contextMenu(forSelectionType: URL.self) { urls in
            if let url = urls.first, urls.count == 1 {
                menu(for: url)
            }
        } primaryAction: { urls in
            if let url = urls.first { perform(.open(url)) }
        }
    }

    /// The open entry, selected in the list. Choosing another asks the editor to open it,
    /// which may first ask about unsaved work, so the selection only moves once it has.
    private var selection: Binding<URL?> {
        Binding {
            model.fileURL
        } set: { url in
            if let url, url != model.fileURL { perform(.open(url)) }
        }
    }

    /// A row's right-click menu.
    @ViewBuilder
    private func menu(for url: URL) -> some View {
        Button("Open") { perform(.open(url)) }
        Divider()
        Button("Rename…") { renaming = url }
        Button("Duplicate") { perform(.duplicate(url)) }
        Button("Export a Copy…") { perform(.export(url)) }
        #if os(macOS)
        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        #endif
        Divider()
        Button("Delete…", role: .destructive) { perform(.delete(url)) }
    }
}

/// One saved entry: its title, date and opening line, a red dot while it has errors,
/// and "Edited" while it's open with unsaved changes.
private struct EntryRow: View {

    let entry: Journal.Entry
    let model: EditorModel
    let isOpen: Bool
    /// Whether rows without a painting keep a blank space where one would be, so titles
    /// line up once any entry in the journal has a painting.
    let showsThumbnailSpace: Bool
    /// Whether the entry's French has errors, or `nil` until it's been checked.
    @State private var hasErrors: Bool?

    /// The thumbnail's width: smaller in the Mac sidebar than in the iPhone and iPad list.
    private static var thumbnailWidth: CGFloat {
        #if os(macOS)
        48
        #else
        64
        #endif
    }

    var body: some View {
        HStack(spacing: 10) {
            if let tableau = entry.tableau {
                PaintingThumbnail(tableau: tableau, width: Self.thumbnailWidth)
            } else if showsThumbnailSpace {
                Color.clear
                    .frame(width: Self.thumbnailWidth, height: Self.thumbnailWidth * 3 / 4)
                    .accessibilityHidden(true)
            }
            details
        }
    }

    /// The title, date, opening line and error dot.
    private var details: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title ?? "Untitled")
                    .fontWeight(.medium)
                    .foregroundStyle(entry.title == nil ? .secondary : .primary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                    if isOpen && model.isEdited {
                        Text("· Edited")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if !entry.preview.isEmpty {
                    Text(entry.preview)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if hasErrors == true {
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
                    .accessibilityLabel("Has errors")
            }
        }
        .padding(.vertical, 2)
        // Checked when the row first shows, once the French pack loads, and whenever its text changes.
        .task(id: "\(model.isReady)|\(entry.text)") {
            hasErrors = model.hasErrors(in: entry.text)
        }
    }
}

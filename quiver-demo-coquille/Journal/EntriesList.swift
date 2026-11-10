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
    /// The entry whose name is being edited in place, if any.
    @Binding var renaming: URL?
    let perform: (EntryAction) -> Void

    var body: some View {
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
            }
            ForEach(journal.entries) { entry in
                EntryRow(
                    entry: entry,
                    model: model,
                    isOpen: model.fileURL == entry.url,
                    renaming: $renaming,
                    commitRename: { perform(.rename(entry.url, $0)) }
                )
                .tag(entry.url)
                .swipeActions {
                    Button("Delete", role: .destructive) { perform(.delete(entry.url)) }
                    Button("Duplicate") { perform(.duplicate(entry.url)) }
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
        .navigationTitle("Journal")
        .onAppear { journal.refresh() }
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
/// "Edited" while it's open with unsaved changes, and a text field while it's renamed.
private struct EntryRow: View {

    let entry: Journal.Entry
    let model: EditorModel
    let isOpen: Bool
    @Binding var renaming: URL?
    let commitRename: (String) -> Void
    /// Whether the entry's French has errors, or `nil` until it's been checked.
    @State private var hasErrors: Bool?
    @State private var draftTitle = ""
    @FocusState private var titleIsFocused: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                if renaming == entry.url {
                    TextField("Title", text: $draftTitle)
                        .focused($titleIsFocused)
                        .onSubmit(finishRename)
                        .onAppear {
                            draftTitle = entry.title ?? ""
                            titleIsFocused = true
                        }
                        #if os(macOS)
                        .onExitCommand { renaming = nil }
                        #endif
                        .onChange(of: titleIsFocused) {
                            if !titleIsFocused { finishRename() }
                        }
                } else {
                    Text(entry.title ?? "Untitled")
                        .fontWeight(.medium)
                        .foregroundStyle(entry.title == nil ? .secondary : .primary)
                        .lineLimit(1)
                }
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

    /// Commits the new title once, whether by Return or by clicking away.
    private func finishRename() {
        guard renaming == entry.url else { return }
        renaming = nil
        if draftTitle != (entry.title ?? "") { commitRename(draftTitle) }
    }
}

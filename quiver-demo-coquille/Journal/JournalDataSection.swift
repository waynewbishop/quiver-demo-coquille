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

/// The Settings section for keeping the journal safe: when it was last backed up, and the
/// ways to back it up and bring it back.
///
/// A backup is a ZIP file the learner saves wherever they choose, so a copy can live
/// outside Coquille and survive deleting the app or losing the device.
struct JournalDataSection: View {

    let journal: Journal
    @AppStorage(JournalArchive.lastBackupKey) private var lastBackup = 0.0
    @State private var showsBackUp = false
    @State private var showsRestorePicker = false

    var body: some View {
        Section {
            LabeledContent("Last backup saved", value: lastBackupText)
            Button("Back Up Journal…") { showsBackUp = true }
            Button("Restore from Backup…") { showsRestorePicker = true }
            #if os(macOS)
            Button("Show Journal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([journal.folderURL])
            }
            #endif
        } header: {
            Text("Journal Data")
        } footer: {
            Text("A backup is a ZIP file you save yourself. Keep one outside Coquille so it survives deleting the app.")
        }
        .sheet(isPresented: $showsBackUp) {
            BackUpSheet(journal: journal)
                .tint(.brand)
        }
        .journalRestore(journal, isPicking: $showsRestorePicker)
    }

    /// The date of the last saved backup, or "Never".
    private var lastBackupText: String {
        guard lastBackup > 0 else { return "Never" }
        return Date(timeIntervalSince1970: lastBackup).formatted(date: .abbreviated, time: .omitted)
    }
}

/// A backup, as a file the learner can save.
struct BackupDocument: FileDocument {

    static let readableContentTypes: [UTType] = [.zip]
    static let writableContentTypes: [UTType] = [.zip]

    var data: Data

    /// Wraps a finished backup for saving.
    init(data: Data) {
        self.data = data
    }

    /// Reads a backup file's bytes.
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    /// Writes the backup as it is.
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// Says what a backup holds, then hands it to the system's save panel or Files.
///
/// The backup is built when the sheet opens, so the entry count shown is what will be saved.
struct BackUpSheet: View {

    let journal: Journal
    @AppStorage(JournalArchive.lastBackupKey) private var lastBackup = 0.0
    @Environment(\.dismiss) private var dismiss
    @State private var backup: JournalArchive.Backup?
    @State private var failure: String?
    @State private var saveFailure: String?
    @State private var showsExporter = false

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: failure == nil ? "archivebox" : "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundStyle(.tint)
                .frame(width: 56, height: 56)
                .background(.tint.opacity(0.12), in: Circle())
                .accessibilityHidden(true)
                .padding(.top, 24)

            Text(failure == nil ? "Back up your journal" : "Can't back up yet")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .padding(.top, 16)

            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 10)

            if let unreadable = backup?.unreadable, !unreadable.isEmpty {
                Text("\(entriesText(unreadable.count)) couldn't be read and won't be in this backup: \(nameList(unreadable)).")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)
            }

            if let saveFailure {
                Text(saveFailure)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)
            }

            VStack(spacing: 10) {
                if failure == nil {
                    Button { showsExporter = true } label: {
                        Text("Choose Where to Save…").frame(maxWidth: .infinity, minHeight: 34)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(backup == nil)
                }

                Button(failure == nil ? "Cancel" : "Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .controlSize(.large)
            .padding(.top, 24)

            if failure == nil {
                Text("The file holds your private writing. Save it somewhere outside Coquille, like iCloud Drive, so it survives deleting the app.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 12)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .frame(minWidth: 340)
        .presentationDetents([.medium])
        .task { await prepare() }
        .fileExporter(
            isPresented: $showsExporter,
            document: BackupDocument(data: backup?.data ?? Data()),
            contentType: .zip,
            defaultFilename: backup?.suggestedName ?? "CoquilleJournal"
        ) { result in
            switch result {
            case .success:
                lastBackup = Date.now.timeIntervalSince1970
                dismiss()
            case .failure(let error):
                if (error as? CocoaError)?.code != .userCancelled {
                    saveFailure = error.localizedDescription
                }
            }
        }
    }

    /// What the sheet says under its title.
    private var message: String {
        if let failure { return failure }
        guard let backup else { return "Getting your entries ready…" }
        return "Saves your \(entriesText(backup.entryCount)) as a ZIP of plain text files. Unsaved drafts and your progress stats aren't included."
    }

    /// Reads the journal folder and packs the backup.
    private func prepare() async {
        let folder = journal.folderURL
        let result = await Task.detached { Result { try JournalArchive.makeBackup(of: folder) } }.value
        switch result {
        case .success(let made): backup = made
        case .failure(let error): failure = error.localizedDescription
        }
    }
}

/// "1 entry" or "5 entries".
func entriesText(_ count: Int) -> String {
    count == 1 ? "1 entry" : "\(count) entries"
}

/// Up to five names in a sentence, then how many more there are.
func nameList(_ names: [String]) -> String {
    let shown = names.prefix(5).joined(separator: ", ")
    return names.count > 5 ? "\(shown), and \(names.count - 5) more" : shown
}

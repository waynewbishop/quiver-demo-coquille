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

extension View {

    /// Adds the restore flow: picking a backup, previewing what it would do, restoring, and
    /// reporting the result. Setting `isPicking` to `true` starts it.
    ///
    /// Both Settings and the empty journal use it, so restoring behaves the same from either.
    func journalRestore(_ journal: Journal, isPicking: Binding<Bool>) -> some View {
        modifier(RestoreFlow(journal: journal, isPicking: isPicking))
    }
}

/// Where the restore flow is: showing what a backup would do, or what restoring did.
private enum RestoreStep: Identifiable {
    case preview(JournalArchive.Plan)
    case result(JournalArchive.Summary)

    var id: UUID {
        switch self {
        case .preview(let plan): plan.id
        case .result(let summary): summary.id
        }
    }
}

/// The restore flow behind `journalRestore(_:isPicking:)`.
///
/// Nothing is written until the learner confirms the preview. The same sheet then shows
/// the result, so two sheets are never up at once.
private struct RestoreFlow: ViewModifier {

    let journal: Journal
    @Binding var isPicking: Bool
    @State private var step: RestoreStep?
    @State private var failure: String?
    @State private var isWorking = false

    func body(content: Content) -> some View {
        content
            .fileImporter(isPresented: $isPicking, allowedContentTypes: [.zip]) { result in
                open(result)
            }
            .sheet(item: $step) { step in
                switch step {
                case .preview(let plan):
                    RestorePreview(plan: plan, restore: { restore(plan) }, cancel: { self.step = nil })
                        .tint(.brand)
                case .result(let summary):
                    RestoreResult(summary: summary, done: { self.step = nil })
                        .tint(.brand)
                }
            }
            .overlay {
                if isWorking {
                    ProgressView()
                        .controlSize(.large)
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
            }
            .alert("This backup couldn't be restored", isPresented: showsFailure) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(failure ?? "")
            }
    }

    private var showsFailure: Binding<Bool> {
        Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
    }

    /// Reads the backup the learner picked and shows what restoring it would do.
    private func open(_ result: Result<URL, any Error>) {
        switch result {
        case .failure(let error):
            if (error as? CocoaError)?.code != .userCancelled {
                failure = error.localizedDescription
            }
        case .success(let url):
            let folder = journal.folderURL
            isWorking = true
            // Reading and unpacking can take a while for a large journal, so it happens off
            // the main thread and the interface stays responsive.
            Task {
                let outcome = await Task.detached { () -> Result<JournalArchive.Plan, any Error> in
                    let isAccessing = url.startAccessingSecurityScopedResource()
                    defer {
                        if isAccessing { url.stopAccessingSecurityScopedResource() }
                    }
                    return Result {
                        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                        // The archive's own headers add a little to the files it holds.
                        guard size <= ZipArchive.maximumArchiveSize else { throw JournalArchive.Failure.tooLarge }
                        let data = try CoordinatedFile.read(url) { try Data(contentsOf: $0) }
                        return try JournalArchive.plan(restoring: data, into: folder)
                    }
                }.value
                isWorking = false
                switch outcome {
                case .success(let plan): step = .preview(plan)
                case .failure(let error): failure = error.localizedDescription
                }
            }
        }
    }

    /// Writes the plan into the journal and shows the result.
    private func restore(_ plan: JournalArchive.Plan) {
        let folder = journal.folderURL
        isWorking = true
        Task {
            let summary = await Task.detached { JournalArchive.restore(plan, into: folder) }.value
            isWorking = false
            journal.refresh()
            step = .result(summary)
        }
    }
}

/// What restoring a backup would add, skip and keep, before anything is written.
private struct RestorePreview: View {

    let plan: JournalArchive.Plan
    let restore: () -> Void
    let cancel: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Entries to add", value: "\(plan.toAdd)")
                    LabeledContent("Already here", value: "\(plan.alreadyHere)")
                    LabeledContent("Kept as recovered versions", value: "\(plan.recovered)")
                    if !plan.unreadable.isEmpty {
                        LabeledContent("Can't be read", value: "\(plan.unreadable.count)")
                    }
                } header: {
                    Text("This backup")
                } footer: {
                    Text(footer)
                }

                Section {
                    Button(plan.hasWork ? "Restore \(entriesText(plan.toAdd + plan.recovered))" : "Nothing to Restore", action: restore)
                        .fontWeight(.semibold)
                        .disabled(!plan.hasWork)
                }
            }
            .navigationTitle("Restore")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: cancel)
                }
            }
            #if os(macOS)
            .formStyle(.grouped)
            #endif
        }
        #if os(macOS)
        .frame(width: 420, height: 380)
        #endif
        .presentationDetents([.large])
    }

    /// Explains the preview, including that restoring never costs an entry slot.
    private var footer: String {
        var lines = ["Nothing is written until you restore. Your current entries stay as they are. Restoring is always free, even past the free entry limit."]
        if plan.recovered > 0 {
            lines.append("A recovered version is saved beside an entry of the same name that holds different writing.")
        }
        if !plan.unreadable.isEmpty {
            lines.append("Can't be read: \(nameList(plan.unreadable)).")
        }
        return lines.joined(separator: " ")
    }
}

/// What restoring added, skipped and couldn't do.
private struct RestoreResult: View {

    let summary: JournalArchive.Summary
    let done: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 28))
                .foregroundStyle(.tint)
                .frame(width: 56, height: 56)
                .background(.tint.opacity(0.12), in: Circle())
                .accessibilityHidden(true)
                .padding(.top, 24)

            Text(title)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .padding(.top, 16)

            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 10)

            if !summary.unreadable.isEmpty {
                Text("\(entriesText(summary.unreadable.count)) in the backup couldn't be read: \(nameList(summary.unreadable)).")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)
            }

            if !summary.datesNotRestored.isEmpty {
                Text("\(entriesText(summary.datesNotRestored.count)) restored, but Coquille couldn't preserve \(summary.datesNotRestored.count == 1 ? "its" : "their") original file dates: \(nameList(summary.datesNotRestored)).")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)
            }

            if !summary.failed.isEmpty {
                Text("\(entriesText(summary.failed.count)) couldn't be saved: \(nameList(summary.failed)). Free up space and restore the same backup again. Nothing already restored is added twice.")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)
            }

            Button(action: done) {
                Text("Done").frame(maxWidth: .infinity, minHeight: 34)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .padding(.top, 24)

            Text(summary.failed.isEmpty
                 ? "Your existing writing wasn't changed. Restoring this backup again adds nothing."
                 : "Your existing writing wasn't changed. Restoring this backup again adds only what's still missing.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 12)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .frame(minWidth: 340)
        .presentationDetents([.medium])
    }

    private var title: String {
        summary.restoredCount > 0 ? "Your journal is back" : "Nothing new to restore"
    }

    /// The counts, in a sentence.
    private var message: String {
        var parts = [String]()
        if summary.restoredCount > 0 {
            parts.append("Restored \(entriesText(summary.restoredCount)).")
        }
        if summary.skipped > 0 {
            parts.append("\(summary.skipped) \(summary.skipped == 1 ? "was" : "were") already here, so \(summary.skipped == 1 ? "it was" : "they were") skipped.")
        }
        if summary.recovered > 0 {
            parts.append("\(summary.recovered) \(summary.recovered == 1 ? "was" : "were") kept as a recovered version, because an entry with that name already had different writing.")
        }
        return parts.isEmpty ? "Everything in this backup was already in your journal." : parts.joined(separator: " ")
    }
}

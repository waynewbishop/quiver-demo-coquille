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

/// Asks for a new title for a saved entry, filled in with its current one. The date
/// stays at the front of the file's name, so the Finder keeps the journal in order.
struct RenameEntrySheet: View {

    let currentTitle: String
    /// The file name a title would give, such as "2026-10-31 Une journée au marché".
    let proposedName: (String) -> String
    let rename: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @FocusState private var titleIsFocused: Bool

    var body: some View {
        #if os(macOS)
        macBody
        #else
        phoneBody
        #endif
    }

    /// Renames only when the title changed, and otherwise just closes.
    private func commit() {
        if title == currentTitle { dismiss() } else { rename(title) }
    }

    #if !os(macOS)
    /// iPhone and iPad: a titled form with Cancel and Rename in the navigation bar.
    private var phoneBody: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                        .focused($titleIsFocused)
                        .submitLabel(.done)
                        .onSubmit(commit)
                } footer: {
                    Text("Saved as “\(proposedName(title)).txt”")
                }
            }
            .navigationTitle("Rename Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Rename", action: commit)
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear {
            title = currentTitle
            titleIsFocused = true
        }
    }
    #endif

    /// The Mac sheet: the title field with Cancel and Rename beneath it.
    private var macBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rename Entry")
                .font(.headline)
            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)
                .focused($titleIsFocused)
                .onSubmit(commit)
            Text("Saved as “\(proposedName(title)).txt”")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Rename", action: commit)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(minWidth: 360)
        .presentationDetents([.height(220)])
        .onAppear {
            title = currentTitle
            titleIsFocused = true
        }
    }
}

extension View {

    /// Shows the rename dialog for the entry in `renaming`, and hands the new title to
    /// `perform` as a rename once it's confirmed.
    func renameSheet(_ renaming: Binding<URL?>, journal: Journal, perform: @escaping (EntryAction) -> Void) -> some View {
        sheet(isPresented: Binding {
            renaming.wrappedValue != nil
        } set: { isShowing in
            if !isShowing { renaming.wrappedValue = nil }
        }) {
            if let url = renaming.wrappedValue {
                RenameEntrySheet(
                    currentTitle: Journal.title(of: url) ?? "",
                    proposedName: { journal.proposedName(renaming: url, to: $0) }
                ) { title in
                    renaming.wrappedValue = nil
                    perform(.rename(url, title))
                }
                .tint(.brand)
            }
        }
    }
}

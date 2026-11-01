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

/// Asks for a title before new writing is saved to the journal, filled in with the
/// story's title when the on-device model has one. The date is added to the file's
/// name automatically, so the Finder keeps the journal in order.
struct SaveEntrySheet: View {

    let suggestedTitle: String
    /// The file name a title would give, such as "2026-10-31 Une journée au marché".
    let proposedName: (String) -> String
    /// Whether this is Save as New Entry, which leaves the open entry as it was saved.
    let isNewEntry: Bool
    let save: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @FocusState private var titleIsFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isNewEntry ? "Save as New Entry" : "Save to Your Journal")
                .font(.headline)
            TextField("Title (optional)", text: $title)
                .textFieldStyle(.roundedBorder)
                .focused($titleIsFocused)
                .onSubmit { save(title) }
            Text("Saved as “\(proposedName(title)).txt”")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save(title) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(minWidth: 360)
        .presentationDetents([.height(220)])
        .onAppear {
            title = suggestedTitle
            titleIsFocused = true
        }
    }
}

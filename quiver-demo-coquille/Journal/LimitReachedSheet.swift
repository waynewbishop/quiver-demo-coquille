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

/// Says a new entry would pass the free limit, that the writing is safe as a draft, and
/// offers Coquille Pro or a way to free a slot.
struct LimitReachedSheet: View {

    let limit: Int
    let choose: (EditorScreen.LimitChoice) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 28))
                .foregroundStyle(.tint)
                .frame(width: 56, height: 56)
                .background(.tint.opacity(0.12), in: Circle())
                .accessibilityHidden(true)
                .padding(.top, 24)

            Text("Your entry is safe as a draft")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .padding(.top, 16)

            Text("You have \(limit) saved entries, the free limit. Coquille Pro gives you an unlimited journal, or you can delete an entry to free a slot.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 10)

            VStack(spacing: 10) {
                Button { choose(.seePro) } label: {
                    Text("See Coquille Pro").frame(maxWidth: .infinity, minHeight: 34)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)

                Button { choose(.manageEntries) } label: {
                    Text("Manage Entries").frame(maxWidth: .infinity, minHeight: 34)
                }
                .buttonStyle(.bordered)

                Button("Keep Writing") { choose(.keepWriting) }
                    .keyboardShortcut(.cancelAction)
            }
            .controlSize(.large)
            .padding(.top, 24)

            Text("The draft stays in the editor, even if you close Coquille.")
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
}

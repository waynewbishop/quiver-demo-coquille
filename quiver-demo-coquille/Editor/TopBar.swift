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

/// The status chip, the file menu with the journal, New beside the phrasebook, the progress button, and the theme toggle.
struct TopBar: View {

    let model: EditorModel
    @Binding var showsIssueList: Bool
    @Binding var showsProgress: Bool
    @Binding var showsPhrasebook: Bool
    @Binding var showsEntries: Bool
    /// Hands a File menu command to the editor, which asks about unsaved changes first.
    let perform: (FileRequest) -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button {
                showsIssueList = true
            } label: {
                StatusChip(errors: model.blockingIssues.count, warnings: model.warnings.count)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows every issue")

            Spacer()

            Menu {
                Button("Journal", systemImage: "list.bullet") { showsEntries = true }
                Divider()
                Button("Save", systemImage: "square.and.arrow.down") { perform(.save) }
                    .disabled(!model.canSave)
                Button("Save as New Entry…", systemImage: "plus.square.on.square") { perform(.saveAsNewEntry) }
                    .disabled(!model.canSave)
                Divider()
                Button("Import…", systemImage: "folder") { perform(.importFile) }
                Button("Export a Copy…", systemImage: "square.and.arrow.up") { perform(.export) }
                    .disabled(!model.hasText)
                ShareLink(item: model.plainText)
                    .disabled(!model.hasText)
            } label: {
                Label("File", systemImage: "folder")
                    .labelStyle(.iconOnly)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)

            Button("New") { perform(.new) }
                .buttonStyle(.bordered)
                .accessibilityLabel("Start a blank page")
                .disabled(!model.hasText && model.fileURL == nil)

            Button("Phrasebook", systemImage: "book") {
                showsPhrasebook.toggle()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())

            Button {
                showsProgress = true
            } label: {
                Label("\(model.stats.stats.streak(asOf: .now))", systemImage: "chart.bar.xaxis")
                    .font(.subheadline.weight(.medium))
                    .frame(minHeight: 44)
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .accessibilityLabel("Your progress: \(model.stats.stats.streak(asOf: .now)) day streak")

            ThemeToggle()
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .padding(.leading, 20)
        .padding(.trailing, 12)
        .padding(.vertical, 6)
    }
}

/// "2 errors · 1 warning", "1 warning", or "No issues".
struct StatusChip: View {

    let errors: Int
    let warnings: Int

    var body: some View {
        HStack(spacing: 8) {
            if errors > 0 {
                Circle().fill(.red).frame(width: 8, height: 8)
                Text(label)
            } else if warnings > 0 {
                RoundedRectangle(cornerRadius: 2).fill(.orange).frame(width: 8, height: 8).rotationEffect(.degrees(45))
                Text(label)
            } else {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
                Text("No issues")
            }
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(errors > 0 ? AnyShapeStyle(.red) : warnings > 0 ? AnyShapeStyle(.orange) : AnyShapeStyle(.tint))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(errors > 0 ? AnyShapeStyle(.red.opacity(0.12)) : warnings > 0 ? AnyShapeStyle(.orange.opacity(0.14)) : AnyShapeStyle(.tint.opacity(0.12)))
        )
        .frame(minHeight: 44)
    }

    /// The counts, as "2 errors · 1 warning".
    private var label: String {
        let parts = [
            errors > 0 ? plural(errors, "error") : nil,
            warnings > 0 ? plural(warnings, "warning") : nil
        ]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }
}

/// Returns "1 error" or "3 errors".
func plural(_ count: Int, _ noun: String) -> String {
    "\(count) \(noun)\(count == 1 ? "" : "s")"
}

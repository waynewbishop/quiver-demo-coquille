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

/// Confirms an exercise link before it can replace any writing in the editor.
struct ExerciseStartView: View {
    let exercise: ExercisePrompt
    let start: (ExercisePrompt) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Type each answer in French. Coquille supplies the prompts, never the answers.")
                            .font(.plexSans(16, relativeTo: .body))
                            .foregroundStyle(.secondary)
                        ForEach(Array(exercise.prompts.enumerated()), id: \.offset) { index, prompt in
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text("\(index + 1).")
                                    .font(.plexMono(15, relativeTo: .body))
                                    .foregroundStyle(Color.brand)
                                Text(prompt)
                                    .font(.plexSans(18, relativeTo: .body))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .padding(24)
                }
                Button("Start writing") { start(exercise) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .padding(20)
                    .background(.bar)
            }
            .navigationTitle(exercise.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .tint(.brand)
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #endif
    }
}

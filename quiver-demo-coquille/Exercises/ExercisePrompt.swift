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

import Foundation

/// A validated, prompt-only exercise handed to Coquille by another app.
nonisolated struct ExercisePrompt: Identifiable, Equatable, Sendable {
    let id = UUID()
    let title: String
    let prompts: [String]
    let hint: String?

    init(title: String = "Exercise", prompts: [String], hint: String? = nil) {
        self.title = title
        self.prompts = prompts
        self.hint = hint
    }
}

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
import WidgetKit

/// The small and medium widget, whose kind stays the same so placed widgets carry over.
struct TodaysPromptWidget: Widget {
    private let kind = "CoquilleTodaysPrompt"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodaysPromptProvider()) { entry in
            CoquilleWidgetView(entry: entry)
        }
        .configurationDisplayName("Coquille")
        .description("Write in French, or jump to today's prompt and your phrasebook.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

#Preview(as: .systemSmall) {
    TodaysPromptWidget()
} timeline: {
    TodaysPromptEntry(date: .now, prompt: PromptCatalog.fallback)
}

#Preview(as: .systemMedium) {
    TodaysPromptWidget()
} timeline: {
    TodaysPromptEntry(date: .now, prompt: PromptCatalog.fallback)
}

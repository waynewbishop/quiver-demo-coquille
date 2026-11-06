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

/// The small and medium Home Screen prompt widget.
struct TodaysPromptWidget: Widget {
    private let kind = "CoquilleTodaysPrompt"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodaysPromptProvider()) { entry in
            TodaysPromptView(entry: entry)
                .widgetURL(CoquilleRoute.widgetURL(for: entry.prompt))
        }
        .configurationDisplayName("Today's Prompt")
        .description("One English sentence each day. Tap to write the French in Coquille.")
        .supportedFamilies([.systemSmall, .systemMedium])
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

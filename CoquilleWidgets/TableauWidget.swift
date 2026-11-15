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

/// Le tableau du jour: one prompt and one painting a day, always in full color. The kind
/// stays the same so widgets already placed carry over.
struct TableauWidget: Widget {
    private let kind = "CoquilleTodaysPrompt"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TableauProvider()) { entry in
            TableauWidgetView(entry: entry)
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        }
        .configurationDisplayName("Le tableau du jour")
        .description("A French writing prompt and a painting for every day. Tap to start writing.")
        .supportedFamilies(Self.families)
        .contentMarginsDisabled()
    }

    /// Home Screen sizes everywhere, extra large on iPad and the Mac desktop, and the Lock
    /// Screen on iPhone and iPad. iPhone leaves out extra large on its own.
    private static var families: [WidgetFamily] {
        #if os(iOS)
        [.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge, .accessoryRectangular, .accessoryCircular]
        #else
        [.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge]
        #endif
    }
}

#Preview("Small", as: .systemSmall) {
    TableauWidget()
} timeline: {
    TableauEntry.sample
}

#Preview("Medium", as: .systemMedium) {
    TableauWidget()
} timeline: {
    TableauEntry.sample
}

#Preview("Large", as: .systemLarge) {
    TableauWidget()
} timeline: {
    TableauEntry.sample
}

#Preview("Extra large", as: .systemExtraLarge) {
    TableauWidget()
} timeline: {
    TableauEntry.sample
}

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

/// Écrire: opens a new entry with today's prompt, worked out when it's tapped. It keeps the
/// old Coquille control's kind, so a control already placed becomes Écrire.
struct EcrireControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.waynebishop.coquille.open") {
            ControlWidgetButton(action: OpenCoquilleRouteIntent(link: CoquilleRoute.todayLink)) {
                Label("Écrire", image: "ShellControl")
            }
        }
        .displayName("Écrire")
        .description("Start a new entry with today's prompt.")
    }
}

/// Opens the phrasebook, for the moment a phrase is needed. Its kind is unchanged, so
/// controls already placed carry over.
struct PhrasebookControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.waynebishop.coquille.phrasebook") {
            ControlWidgetButton(action: OpenCoquilleRouteIntent(link: CoquilleRoute.phrasebookLink)) {
                Label("Phrasebook", systemImage: "book")
            }
        }
        .displayName("Coquille Phrasebook")
        .description("Open your French phrasebook.")
    }
}

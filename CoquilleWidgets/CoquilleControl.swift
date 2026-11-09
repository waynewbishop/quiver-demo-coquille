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

/// A control that goes straight to writing: the current text, or today's entry on an empty page.
struct CoquilleControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.waynebishop.coquille.open") {
            ControlWidgetButton(action: OpenCoquilleRouteIntent(link: CoquilleRoute.writeLink)) {
                Label("Écrivez", image: "ShellControl")
            }
        }
        .displayName("Coquille")
        .description("Carry on writing, or start today's entry.")
    }
}

/// A control that opens the phrasebook, for the moment a phrase is needed.
struct CoquillePhrasebookControl: ControlWidget {
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

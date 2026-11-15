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

/// Écrire: the one Coquille control. It carries on with the writing already open, or starts
/// today's entry with the day's prompt, keyboard up and never a save question. It keeps the
/// old Coquille control's kind, so a control already placed becomes Écrire.
struct EcrireControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.waynebishop.coquille.open") {
            ControlWidgetButton(action: OpenCoquilleRouteIntent(link: CoquilleRoute.writeLink)) {
                Label("Écrire", systemImage: "pencil.and.scribble")
            }
        }
        .displayName("Écrire")
        .description("Write a journal entry in Coquille.")
    }
}

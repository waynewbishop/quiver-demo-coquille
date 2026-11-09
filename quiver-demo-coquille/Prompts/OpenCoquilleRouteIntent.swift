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

import AppIntents
import Observation

/// Holds a link from a widget button until the root view picks it up.
@MainActor @Observable
final class RouteInbox {
    static let shared = RouteInbox()

    /// The link waiting to be opened, which goes through the same validation as a URL.
    var link: String?
}

/// Opens Coquille at one destination. It builds into both the app and the widget, so the
/// button lives in the widget while the work runs in the app.
struct OpenCoquilleRouteIntent: AppIntent {
    static let title: LocalizedStringResource = "Open in Coquille"
    static let isDiscoverable = false
    static let openAppWhenRun = true

    @Parameter(title: "Link") var link: String

    init() {}

    init(link: String) {
        self.link = link
    }

    /// Leaves the link for the root view to open.
    @MainActor
    func perform() async throws -> some IntentResult {
        RouteInbox.shared.link = link
        return .result()
    }
}

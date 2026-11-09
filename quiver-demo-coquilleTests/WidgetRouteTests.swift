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

import XCTest
@testable import quiver_demo_coquille

@MainActor
final class WidgetRouteTests: XCTestCase {

    /// Parses a link the way the app does.
    private func route(_ link: String) throws -> CoquilleRoute? {
        CoquilleRoute.parse(try XCTUnwrap(URL(string: link)))
    }

    // Each widget action's link reaches its destination.
    func testEveryActionLinkParses() throws {
        XCTAssertEqual(try route(CoquilleRoute.writeLink), .write)
        XCTAssertEqual(try route(CoquilleRoute.phrasebookLink), .phrasebook)
        XCTAssertEqual(try route(CoquilleRoute.journalLink), .journal)
        XCTAssertEqual(try route(CoquilleRoute.correctionsLink), .corrections)
    }

    // A destination takes nothing extra, and anything malformed is rejected.
    func testActionLinksRejectExtras() throws {
        XCTAssertNil(try route("coquille://journal?entry=1"))
        XCTAssertNil(try route("coquille://journal/old"))
        XCTAssertNil(try route("coquille://corrections#top"))
        XCTAssertNil(try route("coquille://progress"))
        XCTAssertNil(try route("other://journal"))
    }

    // A widget button leaves its link for the app's root view.
    func testIntentDeliversItsLink() async throws {
        RouteInbox.shared.link = nil
        _ = try await OpenCoquilleRouteIntent(link: CoquilleRoute.journalLink).perform()
        XCTAssertEqual(RouteInbox.shared.link, CoquilleRoute.journalLink)
        RouteInbox.shared.link = nil
    }
}

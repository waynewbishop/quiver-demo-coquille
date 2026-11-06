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
import SwiftUI
@testable import quiver_demo_coquille

@MainActor
final class SettingsTests: XCTestCase {

    func testAppearanceChoices() {
        XCTAssertNil(Appearance.system.colorScheme)
        XCTAssertEqual(Appearance.light.colorScheme, .light)
        XCTAssertEqual(Appearance.dark.colorScheme, .dark)
    }

    func testExistingAppearanceValuesRemainValid() {
        XCTAssertEqual(Appearance(rawValue: "light"), .light)
        XCTAssertEqual(Appearance(rawValue: "dark"), .dark)
        XCTAssertNil(Appearance(rawValue: "unknown"))
    }
}

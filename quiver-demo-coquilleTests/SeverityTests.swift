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

final class SeverityTests: XCTestCase {

    // Only errors gate play and English; warnings and suggestions never block.
    func testOnlyErrorsBlockPlayback() {
        XCTAssertTrue(Severity.error.blocksPlayback)
        XCTAssertFalse(Severity.warning.blocksPlayback)
        XCTAssertFalse(Severity.suggestion.blocksPlayback)
    }

    // Severity round-trips through JSON, since issues are logged for learner stats.
    func testCodableRoundTrip() throws {
        let data = try JSONEncoder().encode(Severity.allCases)
        let decoded = try JSONDecoder().decode([Severity].self, from: data)
        XCTAssertEqual(decoded, Severity.allCases)
    }
}

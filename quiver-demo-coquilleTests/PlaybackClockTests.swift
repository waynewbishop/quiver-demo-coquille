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

final class PlaybackClockTests: XCTestCase {

    private let start = Date(timeIntervalSinceReferenceDate: 0)

    /// Returns `seconds` after the start.
    private func at(_ seconds: TimeInterval) -> Date {
        start.addingTimeInterval(seconds)
    }

    // Before measuring, the total is a guess from length and rate: 140 characters at
    // 14 per second is 10 seconds, and half speed doubles it.
    func testInitialEstimate() {
        XCTAssertEqual(PlaybackClock(characterCount: 140, rateScale: 1).estimatedDuration, 10, accuracy: 1e-9)
        XCTAssertEqual(PlaybackClock(characterCount: 140, rateScale: 0.5).estimatedDuration, 20, accuracy: 1e-9)
    }

    // Time stands still while paused and picks up again on resume.
    func testPauseExcludesPausedTime() {
        var clock = PlaybackClock(characterCount: 140, rateScale: 1)
        XCTAssertEqual(clock.elapsed(at: at(5)), 0)
        clock.resume(at: at(0))
        clock.pause(at: at(2))
        XCTAssertEqual(clock.elapsed(at: at(30)), 2, accuracy: 1e-9)
        clock.resume(at: at(30))
        XCTAssertEqual(clock.elapsed(at: at(31)), 3, accuracy: 1e-9)
        XCTAssertEqual(clock.fraction(at: at(31)), 0.3, accuracy: 1e-9)
    }

    // Once a tenth is spoken, the measured speed replaces the guess:
    // 6 seconds for 30% of the text means 20 seconds in all.
    func testMeasuredEstimate() {
        var clock = PlaybackClock(characterCount: 100, rateScale: 1)
        clock.resume(at: at(0))
        clock.reached(characterOffset: 5, at: at(1))
        XCTAssertEqual(clock.estimatedDuration, 100.0 / 14.0, accuracy: 1e-9)
        clock.reached(characterOffset: 30, at: at(6))
        XCTAssertEqual(clock.estimatedDuration, 20, accuracy: 1e-9)
    }
}

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

/// Checks that the About dialog's stack shows every painting once before any repeats.
@MainActor
final class ShuffleDeckTests: XCTestCase {

    // A new deck holds every painting exactly once.
    func testNewDeckHoldsEveryPaintingOnce() {
        let deck = ShuffleDeck(count: 20)
        XCTAssertEqual(Set(deck.upcoming), Set(0..<20))
        XCTAssertEqual(deck.upcoming.count, 20)
    }

    // A painting never comes back within three places of its last showing.
    func testPaintingsSpaceOutBeforeRepeating() {
        var deck = ShuffleDeck(count: 20)
        var shown: [Int] = []
        for _ in 0..<60 {
            shown.append(deck.top)
            deck.advance()
        }
        for start in 0...(shown.count - 3) {
            XCTAssertEqual(Set(shown[start..<start + 3]).count, 3)
        }
    }

    // The deck never runs below three paintings, so the stack always has its three stamps.
    func testDeckKeepsAtLeastThreeUpcoming() {
        var deck = ShuffleDeck(count: 14)
        for _ in 0..<100 {
            deck.advance()
            XCTAssertGreaterThanOrEqual(deck.upcoming.count, 3)
        }
    }

    // An empty or single-painting catalog doesn't crash.
    func testTinyCatalogsAreSafe() {
        var empty = ShuffleDeck(count: 0)
        empty.advance()
        XCTAssertEqual(empty.top, 0)
        var one = ShuffleDeck(count: 1)
        one.advance()
        XCTAssertEqual(one.upcoming, [0])
    }
}

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

/// Treats every custom URL as untrusted input and checks the complete link contract.
final class CoquilleRouteTests: XCTestCase {

    private let prompt = WritingPrompt(
        id: "shopping-opening-hours",
        text: "What time does it close?",
        level: "A1",
        topic: "Shopping",
        lesson: "Opening hours"
    )

    private func url(_ string: String) throws -> URL {
        try XCTUnwrap(URL(string: string))
    }

    func testWidgetURLRoundTripsExactPrompt() throws {
        let link = try XCTUnwrap(CoquilleRoute.widgetURL(for: prompt))
        XCTAssertEqual(CoquilleRoute.parse(link, catalog: [prompt]), .today(prompt))
        XCTAssertNil(CoquilleRoute.parse(try url("coquille://today?prompt=unknown"), catalog: [prompt]))
        XCTAssertNil(CoquilleRoute.parse(try url("coquille://today?prompt=shopping-opening-hours&prompt=shopping-opening-hours"), catalog: [prompt]))
        XCTAssertNil(CoquilleRoute.parse(try url("coquille://today?prompt=shopping-opening-hours&answer=Bonjour"), catalog: [prompt]))
    }

    func testClaudeExamplePreservesPromptsTitleAndHint() throws {
        let route = CoquilleRoute.parse(try url("coquille://new?title=Nov%203%3A%20C%27est%20ferm%C3%A9&prompt=Is%20it%20open%3F&prompt=It%27s%20open%20until%20ten%20o%27clock.&prompt=I%20went%20to%20the%20museum%2C%20but%20it%20was%20closed.&hint=c%27%C3%A9tait"))
        guard case .exercise(let exercise) = route else {
            return XCTFail("Expected an exercise")
        }
        XCTAssertEqual(exercise.title, "Nov 3: C'est fermé")
        XCTAssertEqual(exercise.prompts, [
            "Is it open?",
            "It's open until ten o'clock.",
            "I went to the museum, but it was closed."
        ])
        XCTAssertEqual(exercise.hint, "c'était")
    }

    func testExerciseDefaultsAndTrimsValues() throws {
        let route = CoquilleRoute.parse(try url("coquille://new?prompt=%20Is%20it%20open%3F%20&hint=%20"))
        guard case .exercise(let exercise) = route else {
            return XCTFail("Expected an exercise")
        }
        XCTAssertEqual(exercise.title, "Exercise")
        XCTAssertEqual(exercise.prompts, ["Is it open?"])
        XCTAssertNil(exercise.hint)
    }

    func testRejectsWrongHostsAndMalformedExercises() throws {
        let invalid = [
            "https://new?prompt=Is%20it%20open%3F",
            "coquille://other?prompt=Is%20it%20open%3F",
            "coquille://new",
            "coquille://new?prompt=%20",
            "coquille://new?prompt=One&answer=Un",
            "coquille://new?prompt=One&title=A&title=B",
            "coquille://new?prompt=One&hint=A&hint=B",
            "coquille://new?prompt=One%0ATwo"
        ]
        for string in invalid {
            XCTAssertNil(CoquilleRoute.parse(try url(string)), string)
        }
    }

    func testRejectsExcessiveCountsAndLengths() throws {
        let elevenPrompts = Array(repeating: "prompt=One", count: 11).joined(separator: "&")
        XCTAssertNil(CoquilleRoute.parse(try url("coquille://new?\(elevenPrompts)")))
        let longPrompt = String(repeating: "a", count: 301)
        XCTAssertNil(CoquilleRoute.parse(try url("coquille://new?prompt=\(longPrompt)")))
        let longTitle = String(repeating: "a", count: 121)
        XCTAssertNil(CoquilleRoute.parse(try url("coquille://new?prompt=One&title=\(longTitle)")))
        let longHint = String(repeating: "a", count: 301)
        XCTAssertNil(CoquilleRoute.parse(try url("coquille://new?prompt=One&hint=\(longHint)")))
        let hugeLink = String(repeating: "a", count: 2_049)
        XCTAssertNil(CoquilleRoute.parse(try url("coquille://new?prompt=\(hugeLink)")))
    }
}

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

/// Checks that the About dialog's slideshow is the widget's paintings and prompts.
@MainActor
final class AboutSlideTests: XCTestCase {

    // Every prompt's painting becomes a slide, in prompt order, with the prompt in both languages.
    func testEveryPromptPaintingIsASlideWithItsPrompt() {
        let prompts = PromptCatalog.bundled()
        XCTAssertEqual(AboutSlide.all.map(\.tableau.promptID), prompts.map(\.id))
        for slide in AboutSlide.all {
            XCTAssertEqual(slide.english, slide.tableau.promptID.flatMap { PromptCatalog.prompt(withID: $0)?.text })
            XCTAssertEqual(slide.french, slide.tableau.french)
        }
    }

    // The dialog opens on the painting for today's prompt, the one the widget shows.
    func testStartsOnTodaysPainting() {
        let date = Date(timeIntervalSince1970: 1_794_700_000)
        let slide = AboutSlide.all[AboutSlide.index(on: date)]
        XCTAssertEqual(slide.tableau.promptID, PromptCatalog.prompt(on: date).id)
    }

    // The app bundle carries every painting, now that the catalog is shared with the widget.
    func testAppBundleHasEveryPainting() {
        for slide in AboutSlide.all {
            #if os(macOS)
            XCTAssertNotNil(Bundle.main.image(forResource: slide.tableau.imageName), slide.tableau.imageName)
            #else
            XCTAssertNotNil(UIImage(named: slide.tableau.imageName), slide.tableau.imageName)
            #endif
        }
    }
}

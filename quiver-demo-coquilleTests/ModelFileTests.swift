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
import Quiver
@testable import quiver_demo_coquille

/// The language pack rejects a model file whose coefficients don't fit its features,
/// rather than crashing on the first prediction.
final class ModelFileTests: XCTestCase {

    /// The bundled model file `name` with its last coefficient taken away.
    private func truncated(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.main.url(forResource: name, withExtension: "json"), name)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var model = try XCTUnwrap(object["model"] as? [String: Any])
        let coefficients = try XCTUnwrap(model["coefficients"] as? [Double])
        model["coefficients"] = Array(coefficients.dropLast())
        object["model"] = model
        return try JSONSerialization.data(withJSONObject: object)
    }

    // The bundled models all have usable coefficients.
    func testBundledModelsAreUsable() throws {
        for name in ["fr.gender-model", "fr.et-est-model", "fr.article-pronoun-model"] {
            let url = try XCTUnwrap(Bundle.main.url(forResource: name, withExtension: "json"), name)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
            let model = try JSONDecoder().decode(LogisticRegression.self,
                                                 from: JSONSerialization.data(withJSONObject: try XCTUnwrap(object["model"])))
            XCTAssertTrue(model.hasUsableCoefficients, name)
        }
    }

    // Each kind of model file is rejected with one coefficient missing.
    func testTruncatedCoefficientsAreRejected() throws {
        XCTAssertThrowsError(try JSONDecoder().decode(EndingGenderModel.self, from: truncated("fr.gender-model")))
        XCTAssertThrowsError(try JSONDecoder().decode(EtOrEstModel.self, from: truncated("fr.et-est-model")))
        XCTAssertThrowsError(try JSONDecoder().decode(ContextDecider.self, from: truncated("fr.article-pronoun-model")))
    }
}

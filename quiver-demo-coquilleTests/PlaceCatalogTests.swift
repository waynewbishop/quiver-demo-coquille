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

/// Checks the bundled place list and the indexes the catalog builds from it.
final class PlaceCatalogTests: XCTestCase {

    private static let pack: LanguagePack? = try? LanguagePack.french()

    /// Returns the bundled catalog, failing the test if the pack didn't load.
    private func catalog() throws -> PlaceCatalog {
        let pack = try XCTUnwrap(Self.pack, "The French language pack failed to load")
        return try XCTUnwrap(pack.grammar as? FrenchGrammar).places
    }

    // The countries moved from fr.patterns.json unchanged: the same 183 names, with the
    // same number of each article.
    func testCountriesMovedUnchanged() throws {
        let countries = try catalog().countries
        XCTAssertEqual(countries.count, 183)
        let articles = Dictionary(grouping: countries.values, by: { $0 }).mapValues(\.count)
        XCTAssertEqual(articles, ["la": 57, "le": 61, "l'": 30, "les": 16, "": 19])
        XCTAssertEqual(countries["Canada"], "le")
        XCTAssertEqual(countries["France"], "la")
        XCTAssertEqual(countries["Iran"], "l'")
        XCTAssertEqual(countries["États-Unis"], "les")
        XCTAssertEqual(countries["Cuba"], "")
        // Regions and cities stay out of the country index.
        XCTAssertNil(countries["Oregon"])
        XCTAssertNil(countries["Chamonix"])
    }

    // A bare city has no article, a city can have its own, and each listing knows where it sits.
    func testListingsKeepTheirArticleAndParents() throws {
        let places = try catalog().places
        let chamonix = try XCTUnwrap(places.first { $0.name == "Chamonix" })
        XCTAssertEqual(chamonix.kind, .city)
        XCTAssertNil(chamonix.article)
        XCTAssertEqual(chamonix.preposition, "à")

        let havre = try XCTUnwrap(places.first { $0.name == "Havre" })
        XCTAssertEqual(havre.article, "le")
        XCTAssertEqual(havre.parents, ["France", "Normandie"])
        XCTAssertEqual(havre.preposition, "au")
        XCTAssertEqual(places.first { $0.name == "Rochelle" }?.preposition, "à la")

        let oregon = try XCTUnwrap(places.first { $0.name == "Oregon" })
        XCTAssertEqual(oregon.kind, .region)
        XCTAssertEqual(oregon.parents, ["États-Unis"])
        XCTAssertEqual(oregon.preposition, "en")
    }

    // Every listed name is known; only names whose listings agree on one preposition are actionable.
    func testKnownAndActionableNames() throws {
        let catalog = try catalog()
        for name in ["Géorgie", "Texas", "Oregon", "Chamonix", "Havre", "Canada"] {
            XCTAssertTrue(catalog.actionableNames.contains(name), name)
        }
        // A province and a city, a name left alone, or an empty article: known, not actionable.
        for name in ["Québec", "New York", "Washington", "Avignon", "Cuba"] {
            XCTAssertTrue(catalog.knownNames.contains(name), name)
            XCTAssertFalse(catalog.actionableNames.contains(name), name)
        }
        XCTAssertFalse(catalog.knownNames.contains("Marseillette"))
    }

    // The catalog's indexes come from its listings alone.
    func testIndexesFromListings() {
        let catalog = PlaceCatalog(places: [
            .init(name: "Géorgie", kind: .country, article: "la", parents: []),
            .init(name: "Géorgie", kind: .region, article: "la", parents: ["États-Unis"]),
            .init(name: "Québec", kind: .region, article: "le", parents: ["Canada"]),
            .init(name: "Québec", kind: .city, article: nil, parents: ["Canada", "Québec"])
        ])
        XCTAssertEqual(catalog.countries, ["Géorgie": "la"])
        XCTAssertEqual(catalog.knownNames, ["Géorgie", "Québec"])
        XCTAssertEqual(catalog.actionableNames, ["Géorgie"])
    }
}

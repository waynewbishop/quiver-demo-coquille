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

import Foundation

/// Every place name Coquille knows, from `fr.places.json`, nested country › region › city,
/// with the article that settles each one's preposition.
///
/// A city's article means one of three things. No article is an ordinary city, which takes
/// à (à Chamonix). An empty article is a city the checker knows but leaves alone, because
/// usage varies (Avignon). Any other article is the city's own (au Havre, à La Rochelle).
/// For countries and regions an empty article means the same: known, but left alone.
///
/// The catalog builds three indexes: `countries` for the country rules, `knownNames` for
/// every listed name, and `actionableNames` for the names whose listings all agree on one
/// preposition. Géorgie, a country and a US state, is actionable; Québec, a province and a
/// city, is known but not actionable.
nonisolated struct PlaceCatalog: Decodable, Sendable {

    /// What a listed place is.
    enum Kind: String, Sendable {
        case country, region, city
    }

    /// One listing of a place name.
    struct Place: Equatable, Sendable {
        let name: String
        let kind: Kind
        /// The article that settles the preposition; `nil` only for an ordinary city.
        let article: String?
        /// The names of the places it sits in, outermost first: ["France", "Normandie"] for Le Havre.
        let parents: [String]

        /// The preposition for going there, such as en, au or à la, or `nil` when the
        /// place is left alone.
        var preposition: String? {
            switch (kind, article) {
            case (.city, nil): return "à"
            case (.city, "la"): return "à la"
            case (.city, "l'"): return "à l'"
            case (_, "la"), (_, "l'"): return "en"
            case (_, "le"): return "au"
            case (_, "les"): return "aux"
            default: return nil
            }
        }
    }

    /// Every listing: each country in alphabetical order, followed by its regions and cities.
    private(set) var places: [Place] = []
    /// Each country's name and its article, such as "Canada": "le".
    private(set) var countries: [String: String] = [:]
    /// Every listed name, including the ambiguous ones and those left alone.
    private(set) var knownNames: Set<String> = []
    /// The names whose listings all agree on one preposition.
    private(set) var actionableNames: Set<String> = []

    /// An empty catalog, which knows no places.
    init() {}

    /// Builds the catalog and its indexes from a list of places.
    init(places: [Place]) {
        self.places = places
        for place in places where place.kind == .country {
            countries[place.name] = place.article ?? ""
        }
        let listings = Dictionary(grouping: places, by: \.name)
        knownNames = Set(listings.keys)
        actionableNames = Set(listings.compactMap { name, listings in
            let prepositions = Set(listings.map(\.preposition))
            return prepositions.count == 1 && !prepositions.contains(nil) ? name : nil
        })
    }

    /// Decodes the nested file into flat listings.
    init(from decoder: Decoder) throws {
        let file = try decoder.container(keyedBy: FileKeys.self)
        let countries = try file.decode([String: Node].self, forKey: .places)
        var places: [Place] = []
        for name in countries.keys.sorted() {
            countries[name]?.flatten(name: name, kind: .country, parents: [], into: &places)
        }
        self.init(places: places)
    }

    /// The keys at the top of `fr.places.json`; its about and sources notes are for people.
    private enum FileKeys: String, CodingKey {
        case places
    }

    /// A country or region as the file nests it.
    private struct Node: Decodable {
        let article: String
        var regions: [String: Node]?
        var cities: [City]?

        /// Appends this place, then its regions and cities, to `places`.
        func flatten(name: String, kind: Kind, parents: [String], into places: inout [Place]) {
            places.append(Place(name: name, kind: kind, article: article, parents: parents))
            let inside = parents + [name]
            for region in (regions ?? [:]).keys.sorted() {
                regions?[region]?.flatten(name: region, kind: .region, parents: inside, into: &places)
            }
            for city in cities ?? [] {
                places.append(Place(name: city.name, kind: .city, article: city.article, parents: inside))
            }
        }
    }

    /// A city, written as a bare name or as a name with its own article.
    private struct City: Decodable {
        let name: String
        let article: String?

        private enum Keys: String, CodingKey {
            case name, article
        }

        /// Reads "Chamonix" or {"name": "Havre", "article": "le"}.
        init(from decoder: Decoder) throws {
            if let name = try? decoder.singleValueContainer().decode(String.self) {
                (self.name, self.article) = (name, nil)
            } else {
                let city = try decoder.container(keyedBy: Keys.self)
                name = try city.decode(String.self, forKey: .name)
                article = try city.decode(String.self, forKey: .article)
            }
        }
    }
}

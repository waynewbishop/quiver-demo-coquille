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

/// The everyday situation a phrase belongs to, in the order the phrasebook lists them.
nonisolated enum Situation: String, CaseIterable, Codable, Sendable {
    case greetings
    case politeness
    case smallTalk
    case today
    case weather
    case feelings
    case clothing
    case people
    case home
    case meals
    case workAndSchool
    case freeTime
    case cafe
    case shopping
    case directions
    case travel
    case journal

    /// The section title shown in the phrasebook.
    var title: String {
        switch self {
        case .greetings: "Greetings"
        case .politeness: "Politeness and apologies"
        case .smallTalk: "Small talk"
        case .today: "Today's date"
        case .weather: "Weather"
        case .feelings: "How I feel"
        case .clothing: "What I'm wearing"
        case .people: "Describing people"
        case .home: "Where I live"
        case .meals: "Meals"
        case .workAndSchool: "Work and school"
        case .freeTime: "Free time"
        case .cafe: "Café and restaurant"
        case .shopping: "Shopping"
        case .directions: "Directions"
        case .travel: "Travel"
        case .journal: "Journal starters and linking phrases"
        }
    }
}

/// Whether a phrase is for someone you call tu, someone you call vous, or either.
nonisolated enum Register: String, Codable, Sendable {
    case tu
    case vous
    case either
}

/// One complete French phrase the learner can read, hear, and then type themselves.
///
/// Phrases come from `fr.phrases.json`. There are no blanks to fill: a phrase is a
/// starting point the learner changes or writes around, and the linter checks the result.
nonisolated struct Phrase: Codable, Equatable, Identifiable, Sendable {
    let situation: Situation
    let french: String
    let english: String
    let register: Register
    /// Why the phrase works, so the learner can reuse its pattern, or `nil` when it needs none.
    let note: String?

    var id: String { french }
}

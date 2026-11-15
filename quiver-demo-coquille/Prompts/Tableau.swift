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

/// The painting that goes with one daily prompt, with the prompt in French for the widget face.
nonisolated struct Tableau: Equatable, Sendable {

    /// Landscapes for outdoor prompts, still lifes for indoor ones.
    enum Genre: Sendable {
        case paysage
        case natureMorte
    }

    /// The catalog ID of the prompt this painting belongs to.
    let promptID: String
    /// The prompt in French, which leads on the widget with the English beneath it.
    let french: String
    /// The painting's short French title.
    let title: String
    let genre: Genre
    /// The painter whose style the painting follows.
    let painter: String
    /// What the painting shows, in English, for VoiceOver.
    let description: String

    /// The widget asset catalog's image for this painting.
    var imageName: String { "Tableau-\(promptID)" }

    /// The genre and painter in French, as in "Paysage · à la Monet".
    var style: String {
        switch genre {
        case .paysage: "Paysage · à la \(painter)"
        case .natureMorte: "Nature morte · à la \(painter)"
        }
    }
}

/// One painting for every prompt in `fr.prompts.json`, matched by prompt ID.
nonisolated enum TableauCatalog {

    /// Every painting, in the prompt catalog's order.
    static let all: [Tableau] = [
        Tableau(promptID: "daily-life-morning", french: "Qu'est-ce que vous avez fait ce matin\u{00A0}?",
                title: "Le thé du matin", genre: .natureMorte, painter: "Cézanne",
                description: "A blue teapot, a cup of tea and bread on a table by a window"),
        Tableau(promptID: "food-favorite-meal", french: "Quel est votre repas préféré\u{00A0}?",
                title: "Pommes et pichet", genre: .natureMorte, painter: "Cézanne",
                description: "Apples on a white cloth beside a cream jug"),
        Tableau(promptID: "weather-outside", french: "Quel temps fait-il\u{00A0}?",
                title: "Meules en été", genre: .paysage, painter: "Monet",
                description: "Haystacks in a golden field under a summer sky"),
        Tableau(promptID: "place-writing-from", french: "D'où écrivez-vous aujourd'hui\u{00A0}?",
                title: "La montagne au loin", genre: .paysage, painter: "Cézanne",
                description: "A village below a violet mountain, framed by pines"),
        Tableau(promptID: "people-friend", french: "Avec qui avez-vous passé du temps récemment\u{00A0}?",
                title: "Le jardin en fleurs", genre: .paysage, painter: "Monet",
                description: "A table and two chairs in a garden full of flowers"),
        Tableau(promptID: "travel-next-trip", french: "Où aimeriez-vous voyager ensuite\u{00A0}?",
                title: "Le lac de montagne", genre: .paysage, painter: "Monet",
                description: "A mountain lake below snowy peaks"),
        Tableau(promptID: "work-today", french: "Qu'est-ce que vous devez faire aujourd'hui\u{00A0}?",
                title: "Le bureau", genre: .natureMorte, painter: "Cézanne",
                description: "Books, a sheet of paper, an inkwell and a lamp on a desk"),
        Tableau(promptID: "free-time-weekend", french: "Qu'est-ce que vous avez aimé faire le week-end dernier\u{00A0}?",
                title: "Les voiliers", genre: .paysage, painter: "Monet",
                description: "Three sailboats on a blue river"),
        Tableau(promptID: "cafe-order", french: "Qu'est-ce que vous voudriez commander au café\u{00A0}?",
                title: "Au café", genre: .natureMorte, painter: "Cézanne",
                description: "A cup of tea, a croissant and a carafe on a café table"),
        Tableau(promptID: "directions-place", french: "Comment allez-vous à un endroit près de chez vous\u{00A0}?",
                title: "Le chemin des peupliers", genre: .paysage, painter: "Monet",
                description: "A sandy path running between tall poplars"),
        Tableau(promptID: "feelings-today", french: "Comment vous sentez-vous, et pourquoi\u{00A0}?",
                title: "Les nymphéas", genre: .paysage, painter: "Monet",
                description: "Water lilies on a still green pond"),
        Tableau(promptID: "clothing-wearing", french: "Qu'est-ce que vous portez\u{00A0}?",
                title: "Le chapeau de paille", genre: .natureMorte, painter: "Cézanne",
                description: "A straw hat and a blue scarf on a wooden chair"),
        Tableau(promptID: "journal-small-pleasure", french: "Quelle petite chose vous a fait plaisir récemment\u{00A0}?",
                title: "Le bouquet", genre: .natureMorte, painter: "Cézanne",
                description: "A bouquet of bright flowers in a blue vase"),
        Tableau(promptID: "daily-life-today", french: "Qu'est-ce que vous avez fait aujourd'hui\u{00A0}?",
                title: "Soleil couchant", genre: .paysage, painter: "Monet",
                description: "The sun setting over a harbor, its light on the water"),
    ]

    /// Returns the painting for `prompt`, or `nil` for a prompt with no painting yet.
    static func tableau(for prompt: WritingPrompt) -> Tableau? {
        all.first { $0.promptID == prompt.id }
    }
}

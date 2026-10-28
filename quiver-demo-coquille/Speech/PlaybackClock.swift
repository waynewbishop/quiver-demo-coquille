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

/// Elapsed and total time for one spoken passage, for the progress bar under play.
///
/// The speech synthesizer never says how long a passage will take, so the total is
/// estimated. It starts as a guess from the length of the text and the speaking rate,
/// then is measured once a tenth of the text has been spoken: if 3 seconds covered
/// 30% of the characters, the whole passage takes about 10 seconds. Time spent paused
/// doesn't count.
nonisolated struct PlaybackClock: Equatable, Sendable {

    /// The passage length in UTF-16 units, the units the synthesizer reports progress in.
    let characterCount: Int
    /// The current estimate of the whole passage's length, in seconds.
    private(set) var estimatedDuration: TimeInterval

    /// Speaking time before the latest start or resume.
    private var elapsedBeforeResume: TimeInterval = 0
    /// When speech last started or resumed, or `nil` while waiting to start or paused.
    private var resumedAt: Date?

    /// A rough French speaking speed at the system's normal rate, used only until
    /// the passage's own speed is measured.
    static let charactersPerSecondAtNormalRate = 14.0
    /// How much of the passage must be spoken before its own speed replaces the guess.
    static let measuredFraction = 0.1

    /// Creates a clock that isn't running yet; `rateScale` is the rate over the normal rate.
    init(characterCount: Int, rateScale: Double) {
        precondition(rateScale > 0, "The speaking rate must be positive")
        self.characterCount = characterCount
        self.estimatedDuration = Double(characterCount) / (Self.charactersPerSecondAtNormalRate * rateScale)
    }

    /// Speaking time so far, excluding pauses, never more than the estimated total.
    func elapsed(at date: Date) -> TimeInterval {
        let running = resumedAt.map { date.timeIntervalSince($0) } ?? 0
        return min(elapsedBeforeResume + max(running, 0), estimatedDuration)
    }

    /// The share of the passage spoken so far, from 0 to 1.
    func fraction(at date: Date) -> Double {
        estimatedDuration > 0 ? elapsed(at: date) / estimatedDuration : 0
    }

    /// Starts or resumes counting.
    mutating func resume(at date: Date) {
        guard resumedAt == nil else { return }
        resumedAt = date
    }

    /// Stops counting until `resume(at:)`.
    mutating func pause(at date: Date) {
        guard let resumedAt else { return }
        elapsedBeforeResume += max(date.timeIntervalSince(resumedAt), 0)
        self.resumedAt = nil
    }

    /// Refines the estimate when the synthesizer reaches `characterOffset`.
    mutating func reached(characterOffset: Int, at date: Date) {
        guard characterCount > 0 else { return }
        let spoken = Double(characterOffset) / Double(characterCount)
        guard spoken >= Self.measuredFraction else { return }
        let running = resumedAt.map { date.timeIntervalSince($0) } ?? 0
        let elapsed = elapsedBeforeResume + max(running, 0)
        estimatedDuration = max(elapsed / spoken, elapsed)
    }
}

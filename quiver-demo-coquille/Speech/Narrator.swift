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

import AVFoundation
import Observation

/// Whether a narrator is silent, speaking, or paused partway through.
enum PlaybackState: Equatable {
    case idle
    case speaking
    case paused
}

/// Reads text aloud. Named to avoid clashing with Apple's own speech types.
protocol Narrator: AnyObject {
    /// Whether speech is idle, playing, or paused.
    var state: PlaybackState { get }
    /// Speaks `text` from the start, replacing anything already playing.
    func speak(_ text: String, rate: Float)
    /// Pauses at the current point, so `resume()` carries on from there.
    func pause()
    /// Carries on from where `pause()` stopped.
    func resume()
    /// Stops speaking immediately; the next `speak` starts from the beginning.
    func stop()
}

/// Speaks French with the system synthesizer, preferring a female voice and the
/// best installed quality, falling back to the language's default voice.
@Observable
final class SpeechNarrator: NSObject, Narrator, AVSpeechSynthesizerDelegate {

    /// The system's normal speaking rate.
    static let normalRate = AVSpeechUtteranceDefaultSpeechRate
    /// About half speed, for a long press on play.
    static let slowRate = AVSpeechUtteranceDefaultSpeechRate * 0.5

    private(set) var state = PlaybackState.idle
    /// Timing for the passage being spoken, or `nil` when idle.
    private(set) var clock: PlaybackClock?

    /// Whether speech is playing right now.
    var isSpeaking: Bool {
        state == .speaking
    }

    /// The voice language, such as "fr-FR".
    let language: String
    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    /// Identifies the utterance in flight, so a late callback from a replaced one is ignored.
    @ObservationIgnored private var currentUtterance: ObjectIdentifier?

    /// Creates a narrator for a voice language.
    init(language: String) {
        self.language = language
        super.init()
        synthesizer.delegate = self
    }

    /// Speaks `text` from the start, replacing anything already playing.
    func speak(_ text: String, rate: Float) {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.preferredVoice(for: language)
        utterance.rate = rate
        currentUtterance = ObjectIdentifier(utterance)
        // The clock starts when the synthesizer reports that audio has begun.
        clock = PlaybackClock(characterCount: text.utf16.count, rateScale: Double(rate / Self.normalRate))
        state = .speaking
        synthesizer.speak(utterance)
    }

    /// Pauses at the current point, so `resume()` carries on from there.
    func pause() {
        guard state == .speaking else { return }
        synthesizer.pauseSpeaking(at: .immediate)
        clock?.pause(at: .now)
        state = .paused
    }

    /// Carries on from where `pause()` stopped.
    func resume() {
        guard state == .paused else { return }
        synthesizer.continueSpeaking()
        clock?.resume(at: .now)
        state = .speaking
    }

    /// Stops speaking immediately; the next `speak` starts from the beginning.
    func stop() {
        currentUtterance = nil
        clock = nil
        state = .idle
        synthesizer.stopSpeaking(at: .immediate)
    }

    /// Returns the installed voice for a language, female first, then highest quality.
    static func preferredVoice(for language: String) -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == language }
        let best = voices.max { score($0) < score($1) }
        return best ?? AVSpeechSynthesisVoice(language: language)
    }

    /// Ranks a voice: a female voice outranks any quality tier, then premium beats enhanced beats default.
    private static func score(_ voice: AVSpeechSynthesisVoice) -> Int {
        (voice.gender == .female ? 10 : 0) + voice.quality.rawValue
    }

    // MARK: - AVSpeechSynthesizerDelegate

    /// Starts the clock once audio actually begins, after the voice has loaded.
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        let date = Date.now
        Task { @MainActor in
            guard self.currentUtterance == id, self.state == .speaking else { return }
            self.clock?.resume(at: date)
        }
    }

    /// Refines the time estimate as each word begins.
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        willSpeakRangeOfSpeechString characterRange: NSRange,
        utterance: AVSpeechUtterance
    ) {
        let id = ObjectIdentifier(utterance)
        let date = Date.now
        Task { @MainActor in
            guard self.currentUtterance == id else { return }
            self.clock?.reached(characterOffset: characterRange.location, at: date)
        }
    }

    /// Marks speech finished when the current utterance ends.
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        finish(ObjectIdentifier(utterance))
    }

    /// Marks speech finished when the current utterance is cancelled.
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        finish(ObjectIdentifier(utterance))
    }

    /// Clears the playback state on the main actor, unless a newer utterance has started.
    nonisolated private func finish(_ utterance: ObjectIdentifier) {
        Task { @MainActor in
            guard self.currentUtterance == utterance else { return }
            self.currentUtterance = nil
            self.clock = nil
            self.state = .idle
        }
    }
}

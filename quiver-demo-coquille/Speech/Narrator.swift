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
    /// The selected system voice identifier, or an empty string for Automatic.
    var voiceID: String { get set }
    /// Whether speech is idle, playing, or paused.
    var state: PlaybackState { get }
    /// The word being spoken, as UTF-16 offsets into the spoken text, or `nil` when idle.
    var spokenRange: Range<Int>? { get }
    /// Speaks `text` from the start, replacing anything already playing.
    func speak(_ text: String)
    /// Pauses at the current point, so `resume()` carries on from there.
    func pause()
    /// Carries on from where `pause()` stopped.
    func resume()
    /// Stops speaking immediately; the next `speak` starts from the beginning.
    func stop()
}

extension Narrator {
    /// Whether speech is playing right now.
    var isSpeaking: Bool {
        state == .speaking
    }
}

/// Speaks French with the system synthesizer, preferring a female voice and the
/// best installed quality, falling back to the language's default voice.
@Observable
final class SpeechNarrator: NSObject, Narrator, AVSpeechSynthesizerDelegate {

    private(set) var state = PlaybackState.idle
    /// The word being spoken, as UTF-16 offsets into the spoken text, or `nil` when idle.
    /// It stays on the current word while paused.
    private(set) var spokenRange: Range<Int>?

    /// The voice language, such as "fr-FR".
    let language: String
    /// The learner's selected voice, or an empty string for Automatic.
    var voiceID = ""
    static let voiceStorageKey = "frenchPlaybackVoice"
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
    func speak(_ text: String) {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.preferredVoice(for: language, voiceID: voiceID)
        currentUtterance = ObjectIdentifier(utterance)
        spokenRange = nil
        state = .speaking
        synthesizer.speak(utterance)
    }

    /// Pauses at the current point, so `resume()` carries on from there.
    func pause() {
        guard state == .speaking else { return }
        synthesizer.pauseSpeaking(at: .immediate)
        state = .paused
    }

    /// Carries on from where `pause()` stopped.
    func resume() {
        guard state == .paused else { return }
        synthesizer.continueSpeaking()
        state = .speaking
    }

    /// Stops speaking immediately; the next `speak` starts from the beginning.
    func stop() {
        currentUtterance = nil
        spokenRange = nil
        state = .idle
        synthesizer.stopSpeaking(at: .immediate)
    }

    /// Returns the selected installed voice, or the language's automatic voice.
    static func preferredVoice(for language: String, voiceID: String = "") -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == language }
        if let selected = voices.first(where: { $0.identifier == voiceID }) {
            return selected
        }
        let best = voices.max { score($0) < score($1) }
        return best ?? AVSpeechSynthesisVoice(language: language)
    }

    /// Ranks a voice: a female voice outranks any quality tier, then premium beats enhanced beats default.
    private static func score(_ voice: AVSpeechSynthesisVoice) -> Int {
        (voice.gender == .female ? 10 : 0) + voice.quality.rawValue
    }

    // MARK: - AVSpeechSynthesizerDelegate

    /// Records each word as the synthesizer begins it.
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        willSpeakRangeOfSpeechString characterRange: NSRange,
        utterance: AVSpeechUtterance
    ) {
        let id = ObjectIdentifier(utterance)
        let range = characterRange.location..<(characterRange.location + characterRange.length)
        Task { @MainActor in
            guard self.currentUtterance == id else { return }
            self.spokenRange = range
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
            self.spokenRange = nil
            self.state = .idle
        }
    }
}

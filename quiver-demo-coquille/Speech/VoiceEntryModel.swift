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
import Speech

/// The installation state of Apple's French speech-recognition assets.
enum SpeechModelStatus: Equatable {
    case unknown
    case checking
    case notInstalled
    case downloading
    case installed
    case unsupported
    case failed(String)

    var label: String {
        switch self {
        case .unknown: "Not Checked"
        case .checking: "Checking…"
        case .notInstalled: "Not Downloaded"
        case .downloading: "Downloading…"
        case .installed: "Installed"
        case .unsupported: "Unavailable"
        case .failed: "Download Failed"
        }
    }
}

/// Owns voice-entry preferences, Apple's speech assets, and the current dictation session.
@MainActor @Observable
final class VoiceEntryModel {

    enum State: Equatable {
        case idle
        case preparing
        case listening
        case stopping
        case denied
        case modelMissing
        case failed(String)
    }

    static let enabledStorageKey = "voiceEntryEnabled"
    static let inactivityDelay = Duration.seconds(2)

    private(set) var modelStatus = SpeechModelStatus.unknown
    private(set) var state = State.idle
    private(set) var interimText = ""
    @ObservationIgnored var onFinalText: (String) -> Void = { _ in }

    private let locale = Locale(identifier: "fr-FR")
    @ObservationIgnored private var analyzer: SpeechAnalyzer?
    @ObservationIgnored private var captureProvider: CaptureInputSequenceProvider?
    @ObservationIgnored private var captureRunner: CaptureSessionRunner?
    @ObservationIgnored private var analysisTask: Task<Void, Never>?
    @ObservationIgnored private var resultsTask: Task<Void, Never>?
    @ObservationIgnored private var inactivityTask: Task<Void, Never>?
    @ObservationIgnored private var sessionID = UUID()

    var isActive: Bool {
        state == .preparing || state == .listening || state == .stopping
    }

    /// Refreshes the asset state without asking for permission or starting a download.
    func refreshModelStatus() async {
        guard modelStatus != .downloading else { return }
        modelStatus = .checking
        guard let transcriber = await makeTranscriber() else {
            modelStatus = .unsupported
            return
        }
        modelStatus = Self.status(await AssetInventory.status(forModules: [transcriber]))
    }

    /// Downloads French speech assets only after the learner asks in Settings.
    func downloadModel() async {
        guard modelStatus != .downloading else { return }
        modelStatus = .downloading
        do {
            guard let transcriber = await makeTranscriber() else {
                modelStatus = .unsupported
                return
            }
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
            }
            modelStatus = Self.status(await AssetInventory.status(forModules: [transcriber]))
        } catch {
            modelStatus = .failed("The French speech model couldn't be downloaded. Check your connection and try again.")
        }
    }

    /// Starts or stops the one microphone session.
    func toggle() async {
        if isActive {
            await stop()
        } else {
            await start()
        }
    }

    /// Starts French dictation after the model is installed and microphone access is allowed.
    func start() async {
        if state != .idle { await stop() }
        state = .preparing
        interimText = ""
        let id = UUID()
        sessionID = id

        if modelStatus != .installed { await refreshModelStatus() }
        guard sessionID == id, state == .preparing else { return }
        guard modelStatus == .installed else {
            state = modelStatus == .unsupported ? .failed("French voice entry isn't available on this device.") : .modelMissing
            return
        }
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            state = .denied
            return
        }
        guard sessionID == id, state == .preparing else { return }

        do {
            guard let device = AVCaptureDevice.default(for: .audio) else {
                state = .failed("No microphone is available.")
                return
            }
            guard let transcriber = await makeTranscriber() else {
                state = .failed("French voice entry isn't available on this device.")
                return
            }
            let provider = try await CaptureInputSequenceProvider.providerWithSession(
                from: device,
                compatibleWith: [transcriber]
            )
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            let runner = CaptureSessionRunner(session: provider.captureSession)
            captureProvider = provider
            captureRunner = runner
            self.analyzer = analyzer

            resultsTask = Task { [weak self] in
                await self?.readResults(from: transcriber, session: id)
            }
            analysisTask = Task { [weak self] in
                do {
                    let lastSampleTime = try await analyzer.analyzeSequence(provider.analyzerInputs)
                    if let lastSampleTime {
                        try await analyzer.finalizeAndFinish(through: lastSampleTime)
                    } else {
                        await analyzer.cancelAndFinishNow()
                    }
                } catch {
                    self?.fail("Voice entry stopped unexpectedly.", session: id)
                }
                self?.analysisFinished(session: id)
            }

            await Task.detached { runner.start() }.value
            guard sessionID == id, state == .preparing else {
                await Task.detached { runner.stop() }.value
                return
            }
            state = .listening
            scheduleInactivityStop(session: id)
        } catch {
            fail("Voice entry couldn't start. Check the microphone and try again.", session: id)
        }
    }

    /// Stops capture, finalizes analysis, and drains any remaining final phrases.
    func stop() async {
        guard state != .idle else { return }
        let id = sessionID
        state = .stopping
        inactivityTask?.cancel()
        if let captureRunner {
            await Task.detached { captureRunner.stop() }.value
        }
        await analysisTask?.value
        await resultsTask?.value
        guard sessionID == id else { return }
        clearSession()
        state = .idle
    }

    private func readResults(from module: any SpeechModule, session id: UUID) async {
        do {
            if let transcriber = module as? SpeechTranscriber {
                for try await result in transcriber.results {
                    receive(String(result.text.characters), isFinal: result.isFinal, session: id)
                }
            } else if let transcriber = module as? DictationTranscriber {
                for try await result in transcriber.results {
                    receive(String(result.text.characters), isFinal: result.isFinal, session: id)
                }
            }
        } catch {
            guard !Task.isCancelled else { return }
            fail("Something went wrong while listening.", session: id)
        }
    }

    private func receive(_ text: String, isFinal: Bool, session id: UUID) {
        guard sessionID == id, state == .listening || state == .stopping else { return }
        if isFinal {
            interimText = ""
            onFinalText(text)
        } else {
            interimText = text
        }
        if state == .listening { scheduleInactivityStop(session: id) }
    }

    private func scheduleInactivityStop(session id: UUID) {
        inactivityTask?.cancel()
        inactivityTask = Task { [weak self] in
            try? await Task.sleep(for: Self.inactivityDelay)
            guard !Task.isCancelled else { return }
            await self?.stop()
        }
    }

    private func fail(_ message: String, session id: UUID) {
        guard sessionID == id, state != .stopping else { return }
        state = .failed(message)
        inactivityTask?.cancel()
        if let captureRunner {
            Task.detached { captureRunner.stop() }
        }
    }

    private func analysisFinished(session id: UUID) {
        guard sessionID == id, state == .preparing || state == .listening else { return }
        clearSession()
        state = .idle
    }

    private func clearSession() {
        analyzer = nil
        captureProvider = nil
        captureRunner = nil
        analysisTask = nil
        resultsTask = nil
        inactivityTask = nil
        interimText = ""
    }

    /// Prefers the general transcriber, falling back to system dictation on older hardware.
    private func makeTranscriber() async -> (any SpeechModule)? {
        if SpeechTranscriber.isAvailable,
           let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) {
            return SpeechTranscriber(locale: supported, preset: .progressiveTranscription)
        }
        if let supported = await DictationTranscriber.supportedLocale(equivalentTo: locale) {
            return DictationTranscriber(locale: supported, preset: .progressiveLongDictation)
        }
        return nil
    }

    private static func status(_ status: AssetInventory.Status) -> SpeechModelStatus {
        switch status {
        case .installed: .installed
        case .downloading: .downloading
        case .supported: .notInstalled
        case .unsupported: .unsupported
        @unknown default: .unsupported
        }
    }
}

/// AVCaptureSession requires its blocking start and stop calls away from the main actor.
private final class CaptureSessionRunner: @unchecked Sendable {
    nonisolated(unsafe) let session: AVCaptureSession

    nonisolated init(session: AVCaptureSession) {
        self.session = session
    }

    nonisolated func start() {
        session.startRunning()
    }

    nonisolated func stop() {
        session.stopRunning()
    }
}

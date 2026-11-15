//
//  LyceumSessionRecorder.swift
//  leanring-buddy
//
//  Long-form microphone capture for a The Lyceum practice run.
//
//  This is intentionally NOT BuddyDictationManager: that class is built for one
//  push-to-talk utterance (single active session, auto-submit on stop). A rehearsal
//  is a five to twenty minute monologue, so we own a second audio engine and drive
//  the same pluggable transcription provider directly.
//
//  The awkward constraint is that AssemblyAI temporary streaming tokens expire after
//  480 seconds. Rather than dying at eight minutes, the recorder rotates the provider
//  session ahead of expiry, commits the finished segment to a prefix, and keeps the
//  audio tap alive — buffering a second of PCM across the gap so the middle of a
//  sentence is not lost.
//

import AVFoundation
import Combine
import Foundation
import Speech

@MainActor
final class LyceumSessionRecorder: NSObject, ObservableObject {
    /// Full transcript so far: committed segments plus the live segment.
    @Published private(set) var transcriptText: String = ""
    @Published private(set) var audioPowerLevel: CGFloat = 0
    @Published private(set) var elapsedSeconds: TimeInterval = 0
    @Published private(set) var isCapturing = false
    @Published private(set) var lastErrorMessage: String?

    /// Rotated well before the 480s AssemblyAI token expiry.
    private static let providerRotationIntervalSeconds: TimeInterval = 300
    /// How long we wait for a segment's final transcript before forcing the commit.
    private static let segmentFinalizationGraceSeconds: TimeInterval = 3
    /// Microphones buffers at ~10ms; 120 buffers ≈ 1.2s of speech kept across a rotation.
    private static let maxHeldBuffersDuringRotation = 120

    private let transcriptionProvider: any BuddyTranscriptionProvider = BuddyTranscriptionProviderFactory.makeDefaultProvider()
    private let audioEngine = AVAudioEngine()
    private var activeTranscriptionSession: (any BuddyStreamingTranscriptionSession)?

    /// Transcript text already committed from earlier segments of the same run.
    private var committedTranscriptPrefix: String = ""
    /// Latest transcript reported by the current segment only.
    private var currentSegmentTranscript: String = ""
    private var heldBuffersDuringRotation: [AVAudioPCMBuffer] = []
    private var rotationInFlight = false

    private var elapsedTimerCancellable: AnyCancellable?
    private var rotationTask: Task<Void, Never>?
    private var runStartedAt: Date?
    private var lastPowerSampleDate = Date.distantPast
    /// Measures the same buffers the level meter already reads. No second tap on
    /// the audio engine, because two taps on one input node is a crash waiting to
    /// happen, and nothing here costs a frame of capture.
    let deliveryMeter = LyceumDeliveryMeter()

    override init() {
        super.init()
    }

    // MARK: - Public

    /// Starts a run. `keyterms` biases the recogniser toward the user's topic —
    /// it is the difference between "myocardial infarction" and "my cardial infection".
    func startRun(keyterms: [String]) async {
        guard !isCapturing else { return }

        lastErrorMessage = nil

        // Push-to-talk asks for permissions on first use; a coaching run can be the
        // first thing a fresh install ever does, so ask here too.
        guard transcriptionProvider.isConfigured else {
            lastErrorMessage = transcriptionProvider.unavailableExplanation
                ?? "no transcription provider is configured in Info.plist"
            return
        }

        let permissionsGranted = await requestCapturePermissions(
            requiresSpeechRecognition: transcriptionProvider.requiresSpeechRecognitionPermission
        )
        guard permissionsGranted else {
            lastErrorMessage = "microphone access is not granted. Enable it in System Settings → Privacy & Security → Microphone."
            return
        }

        transcriptText = ""
        deliveryMeter.reset()
        committedTranscriptPrefix = ""
        currentSegmentTranscript = ""
        heldBuffersDuringRotation = []
        elapsedSeconds = 0
        runStartedAt = Date()

        do {
            try await openTranscriptionSession(keyterms: keyterms)
            try await startAudioEngine()
        } catch {
            lastErrorMessage = "couldn't start the microphone: \(error.localizedDescription)"
            isCapturing = false
            return
        }

        isCapturing = true
        startTickerIfNeeded()
        scheduleProviderRotation(keyterms: keyterms)
        print("🏛️ Lyceum recorder: capture started with \(transcriptionProvider.displayName)")
    }

    /// Stops the run and returns the final transcript.
    func finishRun() async -> String {
        guard isCapturing else {
            return transcriptText
        }

        isCapturing = false
        stopTicker()
        rotationTask?.cancel()
        rotationTask = nil

        let finalTranscriptOfCurrentSegment = await requestSegmentFinalTranscript()
        commitCurrentSegment(finalTranscriptOfCurrentSegment)

        stopAudioEngine()

        let finishedTranscript = composeTranscript()
        transcriptText = finishedTranscript
        print("🏛️ Lyceum recorder: capture finished, \(finishedTranscript.count) characters")
        return finishedTranscript
    }

    /// Microphone arithmetic for the finished run. Called after finishRun so the
    /// filler count works on the final transcript, not a mid-rotation prefix.
    func deliverySnapshot(transcript: String, runSeconds: TimeInterval) -> LyceumDeliveryStats {
        deliveryMeter.snapshot(transcript: transcript, runSeconds: runSeconds)
    }

    /// Abandons the run without waiting for a final transcript (user hit cancel).
    func cancelRun() {
        isCapturing = false
        stopTicker()
        rotationTask?.cancel()
        rotationTask = nil
        activeTranscriptionSession?.cancel()
        activeTranscriptionSession = nil
        stopAudioEngine()
        heldBuffersDuringRotation = []
        committedTranscriptPrefix = ""
        currentSegmentTranscript = ""
    }

    /// Same authorization ladder as the push-to-talk pipeline (continuation around
    /// the completion-handler APIs, which is what this SDK supports).
    private func requestCapturePermissions(requiresSpeechRecognition: Bool) async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            break
        case .notDetermined:
            let isMicrophoneGranted = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { isGranted in
                    continuation.resume(returning: isGranted)
                }
            }
            guard isMicrophoneGranted else { return false }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }

        // Only the local Apple provider needs Apple speech recognition; AssemblyAI
        // and OpenAI stream or upload raw PCM and do not.
        guard requiresSpeechRecognition else { return true }

        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { authorizationStatus in
                    continuation.resume(returning: authorizationStatus == .authorized)
                }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    var displayName: String { transcriptionProvider.displayName }

    // MARK: - Provider session

    private func openTranscriptionSession(keyterms: [String]) async throws {
        let openedSession = try await transcriptionProvider.startStreamingSession(
            keyterms: keyterms,
            onTranscriptUpdate: { [weak self] segmentTranscript in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.currentSegmentTranscript = segmentTranscript
                    self.transcriptText = self.composeTranscript()
                }
            },
            onFinalTranscriptReady: { [weak self] segmentTranscript in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.currentSegmentTranscript = segmentTranscript
                    self.transcriptText = self.composeTranscript()
                }
            },
            onError: { [weak self] error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.lastErrorMessage = self.explainTranscriptionError(error)
                    // A dead websocket must not kill the run: the audio tap keeps
                    // going and the rotation timer opens a fresh session.
                    print("⚠️ Lyceum recorder transcription error: \(error.localizedDescription)")
                }
            }
        )

        activeTranscriptionSession = openedSession

        let buffered = heldBuffersDuringRotation
        heldBuffersDuringRotation = []
        for heldBuffer in buffered {
            openedSession.appendAudioBuffer(heldBuffer)
        }
    }

    /// Asks the current segment for its final text and waits briefly for it to land.
    private func requestSegmentFinalTranscript() async -> String {
        guard let activeTranscriptionSession else { return currentSegmentTranscript }

        let expectedTranscript = currentSegmentTranscript
        activeTranscriptionSession.requestFinalTranscript()

        let deadline = Date().addingTimeInterval(Self.segmentFinalizationGraceSeconds)
        while Date() < deadline {
            if currentSegmentTranscript != expectedTranscript {
                return currentSegmentTranscript
            }
            try? await Task.sleep(nanoseconds: 120_000_000)
        }
        return currentSegmentTranscript
    }

    private func commitCurrentSegment(_ segmentTranscript: String) {
        let trimmedSegment = segmentTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSegment.isEmpty else { return }
        committedTranscriptPrefix = composeValues(committedTranscriptPrefix, trimmedSegment)
    }

    private func composeTranscript() -> String {
        composeValues(committedTranscriptPrefix, currentSegmentTranscript.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func composeValues(_ prefix: String, _ suffix: String) -> String {
        let trimmedPrefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSuffix = suffix.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedPrefix.isEmpty { return trimmedSuffix }
        if trimmedSuffix.isEmpty { return trimmedPrefix }
        return trimmedPrefix + " " + trimmedSuffix
    }

    /// Swaps the provider session before its token expires, keeping the run alive.
    private func rotateProviderSession(keyterms: [String]) async {
        guard isCapturing, !rotationInFlight else { return }
        rotationInFlight = true
        defer { rotationInFlight = false }

        let finishedSegmentTranscript = await requestSegmentFinalTranscript()
        commitCurrentSegment(finishedSegmentTranscript)
        currentSegmentTranscript = ""

        activeTranscriptionSession?.cancel()
        activeTranscriptionSession = nil

        do {
            try await openTranscriptionSession(keyterms: keyterms)
            transcriptText = composeTranscript()
            print("🏛️ Lyceum recorder: rotated transcription session, prefix is \(committedTranscriptPrefix.count) chars")
        } catch {
            lastErrorMessage = "transcription reconnect failed: \(error.localizedDescription)"
            print("⚠️ Lyceum recorder rotation failed: \(error.localizedDescription)")
        }
    }

    private func scheduleProviderRotation(keyterms: [String]) {
        rotationTask?.cancel()
        rotationTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Self.providerRotationIntervalSeconds * 1_000_000_000))
                if Task.isCancelled { return }
                await self?.rotateProviderSession(keyterms: keyterms)
            }
        }
    }

    // MARK: - Audio engine

    private func startAudioEngine() async throws {
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] audioBuffer, _ in
            guard let self else { return }

            Task { @MainActor [weak self] in
                guard let self else { return }
                if let activeTranscriptionSession = self.activeTranscriptionSession {
                    activeTranscriptionSession.appendAudioBuffer(audioBuffer)
                } else if self.isCapturing {
                    // Mid-rotation: hold a bounded window so speech is not dropped.
                    if self.heldBuffersDuringRotation.count >= Self.maxHeldBuffersDuringRotation {
                        self.heldBuffersDuringRotation.removeFirst()
                    }
                    self.heldBuffersDuringRotation.append(audioBuffer)
                }
                self.updateAudioPowerLevel(from: audioBuffer)
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
    }

    private func stopAudioEngine() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        activeTranscriptionSession?.cancel()
        activeTranscriptionSession = nil
    }

    /// Same RMS maths and smoothing curve as the push-to-talk pipeline so the
    /// waveform in the coach panel feels identical to the rest of the app.
    private func updateAudioPowerLevel(from audioBuffer: AVAudioPCMBuffer) {
        guard let channelData = audioBuffer.floatChannelData else { return }

        let channelSamples = channelData[0]
        let frameCount = Int(audioBuffer.frameLength)
        guard frameCount > 0 else { return }
        deliveryMeter.consume(
            samples: Array(UnsafeBufferPointer(start: channelSamples, count: frameCount)),
            sampleRate: Double(audioBuffer.format.sampleRate)
        )


        var summedSquares: Float = 0
        for sampleIndex in 0..<frameCount {
            let sample = channelSamples[sampleIndex]
            summedSquares += sample * sample
        }

        let rootMeanSquare = sqrt(summedSquares / Float(frameCount))
        let boostedLevel = min(max(rootMeanSquare * 10.2, 0), 1)

        audioPowerLevel = max(CGFloat(boostedLevel), audioPowerLevel * 0.72)

        // Silence decays the meter toward zero even between callbacks.
        let now = Date()
        if now.timeIntervalSince(lastPowerSampleDate) > 0.2 {
            lastPowerSampleDate = now
            if boostedLevel < 0.02 {
                audioPowerLevel *= 0.6
            }
        }
    }

    // MARK: - Ticker

    private func startTickerIfNeeded() {
        guard elapsedTimerCancellable == nil else { return }
        elapsedTimerCancellable = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, let runStartedAt = self.runStartedAt else { return }
                self.elapsedSeconds = Date().timeIntervalSince(runStartedAt)
                if !self.isCapturing { self.stopTicker() }
            }
    }

    private func stopTicker() {
        elapsedTimerCancellable?.cancel()
        elapsedTimerCancellable = nil
    }

    private func explainTranscriptionError(_ error: Error) -> String {
        let description = error.localizedDescription
        if description.contains("401") || description.lowercased().contains("unauthorized") {
            return "transcription rejected the token — check the Worker's AssemblyAI key"
        }
        if description.contains("not configured") {
            return "no transcription provider is configured"
        }
        return description
    }
}

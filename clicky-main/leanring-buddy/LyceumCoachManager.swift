//
//  LyceumCoachManager.swift
//  leanring-buddy
//
//  The brain of The Lyceum. It owns a practice run end to end:
//
//    hotkey tap → recorder (mic) + slide watcher (screen) → live nudges →
//    stop → one multimodal Claude call with the slides it saw and the whole
//    transcript → parsed report → spoken verdict → saved session on disk.
//
//  It is deliberately separate from CompanionManager's push-to-talk flow. That
//  flow answers a question in seconds; this one grades a talk in minutes. They
//  share the Worker URL, the transcription provider layer and the design system,
//  and nothing else, so neither can break the other.
//

import AVFoundation
import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class LyceumCoachManager: ObservableObject {
    // MARK: - Published state

    @Published private(set) var phase: LyceumSessionPhase = .idle
    @Published private(set) var liveTranscript: String = ""
    @Published private(set) var audioPowerLevel: CGFloat = 0
    @Published private(set) var elapsedSeconds: TimeInterval = 0
    @Published private(set) var slideCount: Int = 0
    @Published private(set) var watchedDisplayName: String = ""
    @Published private(set) var liveNudge: String?
    @Published private(set) var latestReport: LyceumCoachReport?
    @Published private(set) var latestSavedSession: LyceumSavedSession?
    @Published private(set) var analysisPreviewText: String = ""
    @Published private(set) var recentSessions: [LyceumSavedSession] = []
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var isShowingHistory: Bool = false

    /// Which slide tool opened the room, for the panels and the export header.
    @Published private(set) var slideToolDisplayName: String = ""
    /// The exact window the gate looked at, so a wrong guess is visible and fixable.
    @Published private(set) var gateStatusLine: String = ""
    /// Set when the run ended by itself: "closing slide on screen", "heard …".
    @Published private(set) var runEndingNote: String?

    /// Drill picked in the panel. Persisted because people practise one thing at a time.
    @Published var selectedMode: LyceumCoachMode {
        didSet {
            UserDefaults.standard.set(selectedMode.rawValue, forKey: Self.modeDefaultsKey)
        }
    }

    /// Topic or thesis, used both as speech-recognition keyterms and as context
    /// for the model. "cellular respiration" makes the transcript far better.
    @Published var sessionTopic: String {
        didSet {
            UserDefaults.standard.set(sessionTopic, forKey: Self.topicDefaultsKey)
        }
    }

    /// Watch for the talk finishing on its own — a goodbye slide appearing, or the
    /// speaker thanking the room and then going quiet. Off means only the hotkey
    /// stops a run.
    @Published var monitorsClosingSignals: Bool {
        didSet {
            UserDefaults.standard.set(monitorsClosingSignals, forKey: Self.closingSignalsDefaultsKey)
            if monitorsClosingSignals {
                startClosingWatch()
            } else {
                stopClosingWatch()
            }
        }
    }

    /// Mid-run nudges are optional and default off: most people find a floating
    /// instruction while speaking more distracting than useful.
    @Published var areLiveNudgesEnabled: Bool {
        didSet {
            UserDefaults.standard.set(areLiveNudgesEnabled, forKey: Self.liveNudgesDefaultsKey)
        }
    }

    // MARK: - Dependencies

    private let recorder = LyceumSessionRecorder()
    private let slideWatcher = LyceumSlideWatcher()
    private let coachWindowManager = LyceumCoachWindowManager()
    private let audienceWindowManager = LyceumAudienceWindowManager()
    let gate = LyceumAppGate()
    private let claudeAPI: ClaudeAPI
    private let textToSpeechClient: ElevenLabsTTSClient

    /// Lazy because it needs the Claude and TTS clients this object owns. Sharing
    /// those instances is the point: one audio player between the verdict and the
    /// panel means the room can never talk over the coach.
    private lazy var panel = LyceumAudienceManager(claudeAPI: claudeAPI, textToSpeechClient: textToSpeechClient)

    /// The audience grid, for the panel view and for CompanionManager's routing.
    var audience: LyceumAudienceManager { panel }

    private var cancellables: Set<AnyCancellable> = []
    private var checkpointTask: Task<Void, Never>?
    private var analysisTask: Task<Void, Never>?
    private var transcriptLengthAtLastCheckpoint = 0
    private var closingWatchTask: Task<Void, Never>?
    private var closingWordsHeardAt: Date?
    private var transcriptLengthWhenClosingWordsHeard = 0
    private var classifiedSlideIDs: Set<UUID> = []
    private var runStartedAt: Date?
    private var runTranscript = ""
    private var runSlideSnapshots: [LyceumSlideSnapshot] = []

    private static let modeDefaultsKey = "lyceumCoachMode"
    private static let topicDefaultsKey = "lyceumSessionTopic"
    private static let liveNudgesDefaultsKey = "lyceumLiveNudgesEnabled"
    private static let closingSignalsDefaultsKey = "lyceumMonitorsClosingSignals"
    /// A closing phrase only counts if the room stays quiet this long afterwards —
    /// a speaker who says "thanks" and keeps going was not finished.
    private static let closingWordsSettleSeconds: TimeInterval = LyceumClosingDetector.silenceGraceSeconds
    /// A slide has to be at least this far into the run to be believed as a closer.
    private static let minimumSecondsBeforeClosingSlide: TimeInterval = 12
    private static let checkpointIntervalSeconds: TimeInterval = 75
    /// Payload budget: the model gets the slides that earned screen time, not every frame.
    private static let maximumSlidesSentForReview = 12
    private static let analysisMaxTokens = 4096

    init() {
        let workerBaseURL = CompanionManager.workerBaseURL
        self.claudeAPI = ClaudeAPI(proxyURL: "\(workerBaseURL)/chat")
        self.textToSpeechClient = ElevenLabsTTSClient(proxyURL: "\(workerBaseURL)/tts")

        let storedMode = UserDefaults.standard.string(forKey: Self.modeDefaultsKey)
            .flatMap(LyceumCoachMode.init(rawValue:))
        self.selectedMode = storedMode ?? .feynman

        self.sessionTopic = UserDefaults.standard.string(forKey: Self.topicDefaultsKey) ?? ""
        self.areLiveNudgesEnabled = UserDefaults.standard.bool(forKey: Self.liveNudgesDefaultsKey)
        self.monitorsClosingSignals = UserDefaults.standard.object(forKey: Self.closingSignalsDefaultsKey) as? Bool ?? true

        // LyceumCoachManager is a root class (ObservableObject, not NSObject), so
        // there is no super.init() to call here.
        observeRecorder()
        observePanel()
        recentSessions = LyceumSessionStore.loadRecent(limit: 8)
        if let mostRecent = recentSessions.first {
            latestSavedSession = mostRecent
            latestReport = mostRecent.report
            phase = .ready
        }
    }

    // MARK: - Public API

    /// One button, one key tap: start, or stop and get the verdict.
    func toggleSession() {
        switch phase {
        case .idle, .ready, .failed:
            startSession()
        case .preparing, .recording:
            stopSessionAndReview()
        case .analysing:
            lastErrorMessage = "the last run is still being graded"
            coachWindowManager.show(manager: self)
        }
    }

    func startSession() {
        guard !phase.isSessionLive else { return }

        // The gate is checked at the moment of the press, against whatever was in
        // front of the user, and a refusal has to be legible — a hotkey that
        // silently does nothing reads as a broken app.
        switch gate.evaluateNow() {
        case .blocked(let reason):
            lastErrorMessage = reason.userFacingMessage
            gateStatusLine = reason.frontmost.shortDescription
            runEndingNote = nil
            ClickyAnalytics.trackLyceumGateBlocked(reason: reason.analyticsName)
            coachWindowManager.show(manager: self)
            postNotice(reason.userFacingMessage)
            return
        case .allowed(let tool, let frontmost, let viaWhitelist):
            slideToolDisplayName = viaWhitelist ? "\(frontmost.localizedName) (allowed)" : tool.displayName
            gateStatusLine = frontmost.shortDescription
        }

        analysisTask?.cancel()
        analysisTask = nil
        runEndingNote = nil

        lastErrorMessage = nil
        liveNudge = nil
        liveTranscript = ""
        analysisPreviewText = ""
        runTranscript = ""
        runSlideSnapshots = []
        transcriptLengthAtLastCheckpoint = 0
        classifiedSlideIDs = []
        closingWordsHeardAt = nil
        runStartedAt = Date()
        phase = .preparing

        ClickyAnalytics.trackCoachSessionStarted(mode: selectedMode.rawValue)

        slideWatcher.startWatching()
        coachWindowManager.show(manager: self)

        // The grid appears while you talk, not only when it is time to be grilled:
        // an audience you cannot see is just a timer.
        panel.noteRunStarted()
        if panel.isPanelEnabled {
            audienceWindowManager.show(audience: panel, coach: self)
        }
        startClosingWatch()

        Task {
            await recorder.startRun(keyterms: buildTranscriptionKeyterms())

            // A silent failure here is the worst case: the user talks for ten
            // minutes into a run that never opened the microphone.
            if let recorderErrorMessage = recorder.lastErrorMessage, !recorder.isCapturing {
                finishWithFailure(recorderErrorMessage)
                return
            }

            phase = .recording
            startCheckpointLoopIfNeeded()
        }
    }

    /// Stops capture and asks for the verdict. Safe to call twice.
    /// `endingNote` names the trigger when it was not the user: a farewell slide or
    /// closing words, both of which end the run by themselves.
    func stopSessionAndReview(endingNote: String? = nil) {
        guard phase.isSessionLive else { return }

        stopClosingWatch()
        checkpointTask?.cancel()
        checkpointTask = nil
        runEndingNote = endingNote ?? "stopped by hotkey"
        slideWatcher.stopWatching()
        phase = .analysing
        analysisPreviewText = ""

        Task {
            let finalTranscript = await recorder.finishRun()
            runTranscript = finalTranscript
            runSlideSnapshots = slideWatcher.slides

            elapsedSeconds = runStartedAt.map { Date().timeIntervalSince($0) } ?? elapsedSeconds
            liveTranscript = finalTranscript
            slideCount = runSlideSnapshots.count

            if finalTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                finishWithFailure("the run recorded no speech. check the microphone in System Settings → Privacy & Security → Microphone.")
                return
            }

            await reviewRun()
        }
    }

    /// Abandons the run without grading it.
    func cancelSession() {
        stopClosingWatch()
        panel.leave()
        audienceWindowManager.hide()
        runEndingNote = nil
        checkpointTask?.cancel()
        checkpointTask = nil
        analysisTask?.cancel()
        analysisTask = nil
        recorder.cancelRun()
        slideWatcher.stopWatching()
        phase = .idle
        liveNudge = nil
    }

    /// Keeps the coach on the same model the user picked for push-to-talk, without
    /// the two managers holding each other.
    func applyClaudeModel(_ modelID: String) {
        claudeAPI.model = modelID
    }

    func openCoachPanel() {
        coachWindowManager.show(manager: self)
    }

    /// Restarts the setup screen and immediately begins a new run.
    func beginNewRun() {
        phase = .idle
        latestReport = nil
        startSession()
    }

    /// Reopens a graded run from disk without re-recording anything.
    func showSavedSession(_ savedSession: LyceumSavedSession) {
        latestSavedSession = savedSession
        latestReport = savedSession.report
        slideCount = savedSession.slideCount
        liveTranscript = savedSession.transcript
        elapsedSeconds = savedSession.durationSeconds
        isShowingHistory = false
        phase = .ready
        coachWindowManager.show(manager: self)
    }

    func toggleHistory() {
        isShowingHistory.toggle()
        if isShowingHistory {
            recentSessions = LyceumSessionStore.loadRecent(limit: 12)
        }
        coachWindowManager.show(manager: self)
    }

    func hideHistory() {
        isShowingHistory = false
    }

    func closeCoachPanel() {
        coachWindowManager.hide()
    }

    var isCoachPanelVisible: Bool { coachWindowManager.isVisible }

    /// Feeds the model the words the user is actually likely to say.
    func buildTranscriptionKeyterms() -> [String] {
        var keyterms = ["presentation", "slide", "speaker"]
        let topicWords = sessionTopic
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { $0.count > 2 }
        keyterms.append(contentsOf: topicWords)

        if selectedMode == .debate {
            keyterms.append(contentsOf: ["argument", "counterargument", "evidence", "claim"])
        }
        if selectedMode == .feynman {
            keyterms.append(contentsOf: ["explain", "because", "mechanism"])
        }

        return Array(Set(keyterms)).sorted()
    }

    // MARK: - Audience Q&A

    /// True while the panel expects the user to answer out loud. CompanionManager
    /// routes a held shortcut here instead of starting a normal question.
    var isAwaitingUserAnswer: Bool { panel.isAwaitingUserAnswer }

    func receiveUserAnswer(_ transcript: String) {
        panel.receiveUserAnswer(transcript)
    }

    /// Partial words while the presenter is answering, for the self tile.
    func noteUserAnswerDraft(_ draftText: String) {
        panel.noteUserSpeaking(draftText)
    }

    func skipCurrentQuestion() {
        panel.skipCurrentQuestion()
    }

    /// True from the moment the room forms until it is dismissed, so a hotkey tap
    /// during the Q&A round passes instead of starting a brand new run.
    var isPanelLive: Bool { panel.status != .off }

    var panelStatusSummary: String {
        switch panel.status {
        case .off: return "the room is gone"
        case .convening: return "the room is deciding what to ask"
        case .agentSpeaking: return "asking"
        case .awaitingUserAnswer: return "waiting for your answer"
        case .userAnswering: return "hearing your answer"
        case .roundComplete: return "round finished"
        }
    }

    var isRoomVisible: Bool { audienceWindowManager.isVisible }

    func openRoom() {
        audienceWindowManager.show(audience: panel, coach: self)
    }

    func closeRoom() {
        panel.leave()
        audienceWindowManager.hide()
    }

    func toggleRoom() {
        audienceWindowManager.toggle(audience: panel, coach: self)
    }

    /// With the panel on, the room's first line does the summary job; two monologues
    /// back to back is just noise.
    private func deliverVerdict(report: LyceumCoachReport) async {
        if panel.isPanelEnabled {
            conveneRoom(coachVerdictSummary: report.summary)
            return
        }

        guard let spokenFeedback = report.spokenFeedback, !spokenFeedback.isEmpty else { return }
        try? await textToSpeechClient.speakText(spokenFeedback)
    }

    private func conveneRoom(coachVerdictSummary: String?) {
        guard panel.isPanelEnabled else { return }
        guard !runTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        audienceWindowManager.show(audience: panel, coach: self)
        panel.convenePanel(
            mode: selectedMode,
            topic: sessionTopic,
            durationSeconds: elapsedSeconds,
            slideCount: runSlideSnapshots.count,
            transcript: runTranscript,
            coachVerdictSummary: coachVerdictSummary
        )
    }

    private func observePanel() {
        panel.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        panel.onOpenVerdictRequested = { [weak self] in
            self?.openCoachPanel()
        }

        panel.onRoundFinished = { [weak self] defenseScore in
            self?.mergeDefenseScore(defenseScore)
        }
    }

    /// The Q&A verdict lands after the session was already graded and saved, so it
    /// is merged into the same record rather than left floating in the room window.
    private func mergeDefenseScore(_ defenseScore: LyceumScore?) {
        guard let defenseScore else { return }

        guard var report = latestReport else {
            postNotice("the room scored your answers, but the written verdict is gone")
            return
        }

        report.defenseScore = defenseScore
        latestReport = report

        if var savedSession = latestSavedSession {
            savedSession.report = report
            latestSavedSession = savedSession
            LyceumSessionStore.save(savedSession)
            recentSessions = LyceumSessionStore.loadRecent(limit: 8)
        }

        coachWindowManager.show(manager: self)
        postNotice("defended it \(defenseScore.value)/10 — written verdict updated")
    }

    private func postNotice(_ message: String) {
        NotificationCenter.default.post(name: .lyceumNeedsAttention, object: message)
    }

    // MARK: - Did the talk end on its own?

    private func startClosingWatch() {
        stopClosingWatch()
        guard monitorsClosingSignals else { return }

        closingWatchTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, !Task.isCancelled else { return }
                await self.inspectTranscriptForClosing()
            }
        }
    }

    private func stopClosingWatch() {
        closingWatchTask?.cancel()
        closingWatchTask = nil
        closingWordsHeardAt = nil
        transcriptLengthWhenClosingWordsHeard = 0
    }

    /// Words first: the speaker thanks the room, and then nothing new arrives for a
    /// few seconds. That pause is the signal — "thanks" alone happens mid-talk.
    private func inspectTranscriptForClosing() async {
        guard phase == .recording, monitorsClosingSignals else { return }
        guard elapsedSeconds >= LyceumClosingDetector.minimumSecondsBeforeAutoEnd else { return }

        let transcript = recorder.transcriptText
        let transcriptLength = transcript.count

        if let heardAt = closingWordsHeardAt {
            let hasStayedQuiet = transcriptLength <= transcriptLengthWhenClosingWordsHeard
            let waitedLongEnough = Date().timeIntervalSince(heardAt) >= Self.closingWordsSettleSeconds
            if hasStayedQuiet, waitedLongEnough {
                endRunAutomatically(signal: .closingWords("the room went quiet after the closing words"))
            }
            return
        }

        let tail = String(transcript.suffix(500))
        guard let matchedPhrase = LyceumClosingDetector.detect(inTranscriptTail: tail) else { return }

        closingWordsHeardAt = Date()
        transcriptLengthWhenClosingWordsHeard = transcriptLength
        print("🏛️ Lyceum: heard a closing phrase (\(matchedPhrase)) — waiting for the pause")
    }

    /// Screen second: a goodbye slide needs no silence to prove itself.
    private func inspectSlideForClosing(_ snapshot: LyceumSlideSnapshot) async {
        guard monitorsClosingSignals, phase == .recording else { return }
        guard !classifiedSlideIDs.contains(snapshot.id) else { return }
        guard elapsedSeconds >= Self.minimumSecondsBeforeClosingSlide else { return }

        classifiedSlideIDs.insert(snapshot.id)

        do {
            let (rawVerdictText, _) = try await claudeAPI.analyzeImageStreaming(
                images: [(data: snapshot.imageData, label: "the slide that just appeared on screen")],
                systemPrompt: LyceumClosingDetector.closingSlideSystemPrompt,
                userPrompt: LyceumAudiencePrompts.closingSlideUserPrompt,
                maxTokens: 60,
                onTextChunk: { _ in }
            )

            guard LyceumClosingDetector.parseClosingSlideVerdict(rawVerdictText) else { return }
            endRunAutomatically(signal: .farewellSlide)
        } catch {
            // A failed classification is not worth interrupting a talk over.
            print("⚠️ Lyceum closing-slide check failed: \(error.localizedDescription)")
        }
    }

    private func endRunAutomatically(signal: LyceumClosingSignal) {
        guard phase.isSessionLive else { return }
        print("🏛️ Lyceum: run ended on its own — \(signal.description)")
        ClickyAnalytics.trackLyceumRunAutoEnded(kind: signal.analyticsName)
        postNotice("the talk ended (\(signal.description)) — grading it now")
        stopSessionAndReview(endingNote: signal.description)
    }

    // MARK: - Review

    private func reviewRun() {
        analysisTask?.cancel()

        let selectedSnapshots = selectSnapshotsForReview(from: runSlideSnapshots)
        let labeledImages = selectedSnapshots.map { snapshot in
            (data: snapshot.imageData, label: snapshot.modelLabel)
        }

        let userPrompt = LyceumCoachPrompts.runContext(
            mode: selectedMode,
            spokenDurationSeconds: elapsedSeconds,
            transcriptText: runTranscript,
            slideCount: runSlideSnapshots.count,
            previousNudge: liveNudge
        )

        let systemPrompt = LyceumCoachPrompts.systemPrompt(for: selectedMode) + topicContextLine()

        analysisTask = Task { [weak self] in
            guard let self else { return }
            do {
                let (rawResponseText, responseDuration) = try await self.claudeAPI.analyzeImageStreaming(
                    images: labeledImages,
                    systemPrompt: systemPrompt,
                    userPrompt: userPrompt,
                    maxTokens: Self.analysisMaxTokens,
                    onTextChunk: { partialText in
                        self.analysisPreviewText = partialText
                    }
                )

                guard !Task.isCancelled else { return }

                let report = LyceumCoachReportParser.parse(from: rawResponseText)
                let savedSession = LyceumSavedSession(
                    sessionID: UUID(),
                    mode: self.selectedMode.displayName,
                    startedAt: self.runStartedAt ?? Date(),
                    endedAt: Date(),
                    durationSeconds: self.elapsedSeconds,
                    slideCount: self.runSlideSnapshots.count,
                    transcript: self.runTranscript,
                    report: report,
                    endedBy: self.runEndingNote
                )

                LyceumSessionStore.save(savedSession)
                self.latestSavedSession = savedSession
                self.recentSessions = LyceumSessionStore.loadRecent(limit: 8)
                self.latestReport = report
                self.phase = .ready

                print("🏛️ Lyceum: graded \(self.selectedMode.displayName) run in \(String(format: "%.1f", responseDuration))s, \(report.slideSuggestionRows.count) slide edits")
                ClickyAnalytics.trackCoachSessionCompleted(
                    mode: self.selectedMode.rawValue,
                    durationSeconds: self.elapsedSeconds,
                    slideCount: self.runSlideSnapshots.count,
                    degraded: report.isDegraded
                )

                self.coachWindowManager.show(manager: self)

                await self.deliverVerdict(report: report)
            } catch {
                guard !Task.isCancelled else { return }
                self.finishWithFailure("grading failed: \(error.localizedDescription)")
                // The room can still ask questions from the transcript alone, so a
                // failed grade does not cancel the Q&A round.
                self.conveneRoom(coachVerdictSummary: nil)
            }
        }
    }

    /// The deck may run 30 slides; the model gets the ones that held the room.
    /// Slide 1 and the final slide are always included — openers and closers are
    /// where most talks are won and lost.
    private func selectSnapshotsForReview(from snapshots: [LyceumSlideSnapshot]) -> [LyceumSlideSnapshot] {
        guard snapshots.count > Self.maximumSlidesSentForReview else { return snapshots }

        var picked: [LyceumSlideSnapshot] = []
        if let first = snapshots.first { picked.append(first) }
        if let last = snapshots.last, last.id != first?.id { picked.append(last) }

        let remainingSlots = Self.maximumSlidesSentForReview - picked.count
        let middleCandidates = snapshots
            .filter { snapshot in !picked.contains(where: { $0.id == snapshot.id }) }
            .sorted { $0.secondsOnPreviousSlide > $1.secondsOnPreviousSlide }
            .prefix(max(0, remainingSlots))

        picked.append(contentsOf: middleCandidates)
        return picked.sorted { $0.index < $1.index }
    }

    private func topicContextLine() -> String {
        let trimmedTopic = sessionTopic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTopic.isEmpty else { return "" }
        return "\n\nwhat the user says they were working on (their own words, may be wrong or vague — trust the screen and the transcript over it): \(trimmedTopic)"
    }

    // MARK: - Live checkpoints

    private func startCheckpointLoopIfNeeded() {
        checkpointTask?.cancel()
        checkpointTask = nil
        guard areLiveNudgesEnabled else { return }

        checkpointTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Self.checkpointIntervalSeconds * 1_000_000_000))
                if Task.isCancelled { return }
                await self?.runLiveCheckpoint()
            }
        }
    }

    private func runLiveCheckpoint() async {
        guard phase == .recording else { return }

        let currentTranscript = recorder.transcriptText
        let newSegment = String(currentTranscript.dropFirst(min(transcriptLengthAtLastCheckpoint, currentTranscript.count)))
        transcriptLengthAtLastCheckpoint = currentTranscript.count

        guard newSegment.trimmingCharacters(in: .whitespacesAndNewlines).count > 20 else { return }
        guard let latestSnapshot = slideWatcher.slides.last else { return }

        do {
            let (rawCheckpointText, _) = try await claudeAPI.analyzeImageStreaming(
                images: [(data: latestSnapshot.imageData, label: "the slide currently on screen (slide \(latestSnapshot.index))")],
                systemPrompt: LyceumCoachPrompts.liveCheckpointSystemPrompt,
                userPrompt: LyceumCoachPrompts.checkpointUserPrompt(
                    transcriptSinceLastCheckpoint: newSegment,
                    previousNudge: liveNudge
                ),
                maxTokens: 120,
                onTextChunk: { _ in }
            )

            guard let checkpoint = LyceumLiveNudgeParser.parse(from: rawCheckpointText), !checkpoint.isEmpty else { return }
            liveNudge = checkpoint
            coachWindowManager.show(manager: self)
        } catch {
            // Live nudges are a bonus. Never let them surface as a session error.
            print("⚠️ Lyceum checkpoint failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Wiring

    private func observeRecorder() {
        recorder.$transcriptText
            .receive(on: DispatchQueue.main)
            .sink { [weak self] transcriptText in
                self?.liveTranscript = transcriptText
            }
            .store(in: &cancellables)

        recorder.$audioPowerLevel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] audioPowerLevel in
                self?.audioPowerLevel = audioPowerLevel
            }
            .store(in: &cancellables)

        recorder.$elapsedSeconds
            .receive(on: DispatchQueue.main)
            .sink { [weak self] elapsedSeconds in
                guard let self, self.phase == .recording else { return }
                self.elapsedSeconds = elapsedSeconds
            }
            .store(in: &cancellables)

        recorder.$lastErrorMessage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] recorderErrorMessage in
                guard let self, let recorderErrorMessage else { return }
                if self.phase.isSessionLive { self.lastErrorMessage = recorderErrorMessage }
            }
            .store(in: &cancellables)

        slideWatcher.$slides
            .receive(on: DispatchQueue.main)
            .sink { [weak self] slides in
                guard let self else { return }
                self.slideCount = slides.count

                // Every slide the watcher commits is a candidate closer. One extra
                // 60-token call per slide change is cheap next to the run it saves
                // the user from stopping by hand.
                guard let latestSlide = slides.last else { return }
                Task { await self.inspectSlideForClosing(latestSlide) }
            }
            .store(in: &cancellables)

        slideWatcher.$watchedDisplayName
            .receive(on: DispatchQueue.main)
            .sink { [weak self] watchedDisplayName in
                self?.watchedDisplayName = watchedDisplayName
            }
            .store(in: &cancellables)
    }

    private func finishWithFailure(_ message: String) {
        lastErrorMessage = message
        phase = .failed(message)
        recorder.cancelRun()
        slideWatcher.stopWatching()
        coachWindowManager.show(manager: self)
        ClickyAnalytics.trackCoachSessionFailed(message: message)
    }

    // MARK: - Exports

    /// Writes Markdown (or JSON) through a save panel so the user chooses the name.
    func exportLatestReport(as markdownFormat: Bool) {
        guard let savedSession = latestSavedSession else { return }

        let savePanel = NSSavePanel()
        let fileExtension = markdownFormat ? "md" : "json"
        savePanel.allowedFileTypes = [fileExtension]
        let dateStamp = LyceumSessionStore.fileStamp(for: savedSession.startedAt)
        let modeSlug = savedSession.mode.lowercased().replacingOccurrences(of: " ", with: "-")
        savePanel.nameFieldStringValue = "lyceum-\(modeSlug)-\(dateStamp).\(fileExtension)"

        let data = markdownFormat
            ? LyceumReportExporter.markdown(for: savedSession).data(using: .utf8)
            : LyceumReportExporter.json(for: savedSession)

        guard let data else { return }

        NSApp.activate(ignoringOtherApps: true)
        savePanel.begin { response in
            guard response == .OK, let destinationURL = savePanel.url else { return }
            try? data.write(to: destinationURL)
            ClickyAnalytics.trackCoachReportExported(format: markdownFormat ? "markdown" : "json")
        }
    }

    func deleteLatestSession() {
        guard let savedSession = latestSavedSession else { return }
        LyceumSessionStore.delete(savedSession.sessionID)
        latestSavedSession = nil
        latestReport = nil
        recentSessions = LyceumSessionStore.loadRecent(limit: 8)
        phase = recentSessions.isEmpty ? .idle : .ready
    }
}

// MARK: - Live nudge parsing

enum LyceumLiveNudgeParser {
    static func parse(from rawText: String) -> String? {
        guard let startIndexOfBrace = rawText.firstIndex(of: "{"),
              let endIndexOfBrace = rawText.lastIndex(of: "}"),
              startIndexOfBrace < endIndexOfBrace else { return nil }

        let jsonString = String(rawText[startIndexOfBrace...endIndexOfBrace])
        guard let data = jsonString.data(using: .utf8),
              let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        guard let nudge = decoded["nudge"] as? String else { return nil }
        let trimmedNudge = nudge.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedNudge.isEmpty ? nil : trimmedNudge
    }
}

// MARK: - On-disk session store

enum LyceumSessionStore {
    private static let maximumSessionsOnDisk = 50

    static func sessionsDirectory() -> URL {
        let supportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
        let sessionsURL = supportURL.appendingPathComponent("The Lyceum/Sessions", isDirectory: true)
        try? FileManager.default.createDirectory(at: sessionsURL, withIntermediateDirectories: true)
        return sessionsURL
    }

    @discardableResult
    static func save(_ savedSession: LyceumSavedSession) -> URL? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        guard let data = try? encoder.encode(savedSession) else { return nil }

        let fileURL = sessionsDirectory().appendingPathComponent("lyceum-\(fileStamp(for: savedSession.startedAt)).json")
        do {
            try data.write(to: fileURL)
        } catch {
            print("⚠️ Lyceum session save failed: \(error.localizedDescription)")
            return nil
        }

        pruneOldSessionsIfNeeded()
        return fileURL
    }

    static func loadRecent(limit: Int) -> [LyceumSavedSession] {
        let directory = sessionsDirectory()
        guard let fileURLs = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decodedSessions = fileURLs
            .filter { $0.pathExtension == "json" }
            .compactMap { fileURL -> (URL, LyceumSavedSession)? in
                guard let data = try? Data(contentsOf: fileURL),
                      let decodedSession = try? decoder.decode(LyceumSavedSession.self, from: data) else { return nil }
                return (fileURL, decodedSession)
            }
            .sorted { $0.0.lastPathComponent > $1.0.lastPathComponent }
            .prefix(limit)
            .map { $0.1 }

        return Array(decodedSessions)
    }

    static func delete(_ sessionID: UUID) {
        let directory = sessionsDirectory()
        guard let fileURLs = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        for fileURL in fileURLs where fileURL.pathExtension == "json" {
            guard let data = try? Data(contentsOf: fileURL),
                  let decodedSession = try? decoder.decode(LyceumSavedSession.self, from: data),
                  decodedSession.sessionID == sessionID else { continue }
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    static func fileStamp(for date: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd-HHmmss"
        return dateFormatter.string(from: date)
    }

    private static func pruneOldSessionsIfNeeded() {
        let directory = sessionsDirectory()
        guard let fileURLs = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return }

        let jsonFileURLs = fileURLs.filter { $0.pathExtension == "json" }
        guard jsonFileURLs.count > maximumSessionsOnDisk else { return }

        let sortedFileURLs = jsonFileURLs.sorted { $0.lastPathComponent < $1.lastPathComponent }
        let excessCount = jsonFileURLs.count - maximumSessionsOnDisk
        for oldestFileURL in sortedFileURLs.prefix(excessCount) {
            try? FileManager.default.removeItem(at: oldestFileURL)
        }
    }
}

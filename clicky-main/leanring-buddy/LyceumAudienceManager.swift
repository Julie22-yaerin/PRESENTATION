//
//  LyceumAudienceManager.swift
//  leanring-buddy
//
//  Runs the question round after a rehearsal: turns the finished run into one
//  line per audience member, says each line out loud in that member's voice,
//  listens to the user's spoken answer, lets the member react (and push once
//  more if the answer was a dodge), then scores how the talk was defended.
//
//  It shares the ClaudeAPI and TTS client instances with LyceumCoachManager on
//  purpose: one audio player between them means the panel can never talk over
//  the verdict.
//

import AVFoundation
import Combine
import Foundation
import SwiftUI

@MainActor
final class LyceumAudienceManager: ObservableObject {
    // MARK: - Status

    enum Status: Equatable {
        /// No panel for this run (either disabled, or the run has not ended yet).
        case off
        /// Asking the model for the panel's lines.
        case convening
        /// An agent is at the microphone.
        case agentSpeaking
        /// Waiting for the user to hold the key and answer.
        case awaitingUserAnswer
        /// The user is answering right now.
        case userAnswering
        /// Everyone has spoken; score and log shown.
        case roundComplete
    }

    // MARK: - Published state

    @Published private(set) var status: Status = .off
    @Published private(set) var questions: [LyceumPanelQuestion] = []
    @Published private(set) var exchanges: [LyceumPanelExchange] = []
    @Published private(set) var activeSpeakerMemberID: String?
    @Published private(set) var liveCaption: String = ""
    @Published private(set) var userCaption: String = ""
    @Published private(set) var spokenLanguageCode: String?
    @Published private(set) var defenseScore: LyceumScore?
    @Published private(set) var raisedHandMemberID: String?
    @Published private(set) var errorMessage: String?
    @Published private(set) var currentIndex: Int = 0

    /// Panel state the user controls from the Meet-style bottom bar.
    @Published var areAgentsMuted: Bool {
        didSet { UserDefaults.standard.set(areAgentsMuted, forKey: Self.mutedDefaultsKey) }
    }

    @Published var areCaptionsShown: Bool {
        didSet { UserDefaults.standard.set(areCaptionsShown, forKey: Self.captionsDefaultsKey) }
    }

    /// The whole Q&A round is optional. Some people only want the written verdict.
    @Published var isPanelEnabled: Bool {
        didSet { UserDefaults.standard.set(isPanelEnabled, forKey: Self.panelEnabledDefaultsKey) }
    }

    /// When on, a question nobody answers gets moved past instead of hanging the
    /// room forever. Wired to the hand-raise button in the control bar.
    @Published var skipsUnansweredPrompts: Bool {
        didSet {
            UserDefaults.standard.set(skipsUnansweredPrompts, forKey: Self.skipUnansweredDefaultsKey)
            if skipsUnansweredPrompts {
                preparePassTimer()
            } else {
                standDownPassTimer()
            }
        }
    }

    /// The panel view reaches the written verdict through here so it never needs a
    /// reference to LyceumCoachManager.
    var onOpenVerdictRequested: (() -> Void)?

    func requestOpenVerdict() {
        onOpenVerdictRequested?()
    }

    func addDefaultMember() {
        guard members.count < LyceumAudienceRoster.maximumMembers else { return }
        let takenIDs = Set(members.map { $0.id })
        if let unused = LyceumAudienceRoster.defaultMembers.first(where: { !takenIDs.contains($0.id) }) {
            members.append(unused)
            return
        }
        members.append(LyceumAudienceMember(
            id: "guest-" + String(UUID().uuidString.prefix(6)),
            name: "Guest " + String(members.count + 1),
            role: "audience member",
            persona: "Heard the whole talk and has one thing they still do not buy.",
            tone: .standard,
            avatarSymbol: "person"
        ))
    }

    func resetRoster() {
        LyceumAudienceRoster.resetToDefault()
        members = LyceumAudienceRoster.defaultMembers
    }

    /// Roster, editable in the panel. Kept here so the grid and the prompts read
    /// from one source.
    @Published var members: [LyceumAudienceMember] {
        didSet { LyceumAudienceRoster.save(members) }
    }

    /// Fake but useful: a Meet-like grid needs a room code, and it makes the
    /// screenshot of a rehearsal identifiable.
    private(set) var meetingCode: String = LyceumAudienceManager.makeMeetingCode()

    /// Called when the coach should be told the round is over.
    var onRoundFinished: ((LyceumScore?) -> Void)?

    /// Feeds the roster editor's "who speaks next" label.
    var currentQuestion: LyceumPanelQuestion? {
        guard currentIndex < questions.count else { return nil }
        return questions[currentIndex]
    }

    var isAwaitingUserAnswer: Bool { status == .awaitingUserAnswer || status == .userAnswering }

    var remainingQuestionCount: Int { max(0, questions.count - currentIndex) }

    var answeredCount: Int { exchanges.filter { ($0.userAnswer?.isEmpty == false) }.count }

    // MARK: - Dependencies

    private let claudeAPI: ClaudeAPI
    private let textToSpeechClient: ElevenLabsTTSClient
    private let speechSynthesizer = AVSpeechSynthesizer()

    private var panelTask: Task<Void, Never>?
    private var reactionTask: Task<Void, Never>?
    private var defenseTask: Task<Void, Never>?
    private var captionTask: Task<Void, Never>?
    private var handTask: Task<Void, Never>?

    private static let mutedDefaultsKey = "lyceumPanelMuted"
    private static let captionsDefaultsKey = "lyceumPanelCaptions"
    private static let panelEnabledDefaultsKey = "lyceumPanelEnabled"
    private static let skipUnansweredDefaultsKey = "lyceumPanelSkipsUnanswered"
    private static let maximumQuestionsDefaultsKey = "lyceumPanelMaximumQuestions"
    private static let unansweredTimeoutDefaultsKey = "lyceumPanelUnansweredTimeout"
    /// Frequency and patience as user-settable numbers instead of constants: a
    /// fifteen-year-old who has never been asked a question on purpose cannot start
    /// with five hostile ones, and a defence practice wants all of them. The
    /// dashboard exposes both, which is the onboarding dial the user asked to keep
    /// for later.
    @Published var maximumQuestions: Int {
        didSet {
            let clamped = max(1, min(LyceumAudienceRoster.maximumMembers, maximumQuestions))
            if clamped != maximumQuestions {
                maximumQuestions = clamped
                return
            }
            UserDefaults.standard.set(maximumQuestions, forKey: Self.maximumQuestionsDefaultsKey)
        }
    }

    /// How long the room waits on a silent presenter before calling on the next hand.
    @Published var unansweredTimeoutSeconds: TimeInterval {
        didSet {
            let clamped = max(15, min(180, unansweredTimeoutSeconds))
            if clamped != unansweredTimeoutSeconds {
                unansweredTimeoutSeconds = clamped
                return
            }
            UserDefaults.standard.set(unansweredTimeoutSeconds, forKey: Self.unansweredTimeoutDefaultsKey)
        }
    }
    private static let panelMaxTokens = 1200
    private static let reactionMaxTokens = 220
    private static let defenseMaxTokens = 220
    /// Characters per second for the caption reveal, roughly speaking pace.
    private static let captionCharactersPerSecond = 15.0

    init(claudeAPI: ClaudeAPI, textToSpeechClient: ElevenLabsTTSClient) {
        self.claudeAPI = claudeAPI
        self.textToSpeechClient = textToSpeechClient
        self.areAgentsMuted = UserDefaults.standard.bool(forKey: Self.mutedDefaultsKey)
        self.areCaptionsShown = UserDefaults.standard.object(forKey: Self.captionsDefaultsKey) as? Bool ?? true
        // On by default: the panel is the reason this fork exists.
        self.isPanelEnabled = UserDefaults.standard.object(forKey: Self.panelEnabledDefaultsKey) as? Bool ?? true
        self.skipsUnansweredPrompts = UserDefaults.standard.bool(forKey: Self.skipUnansweredDefaultsKey)
        self.members = LyceumAudienceRoster.load()
        self.maximumQuestions = UserDefaults.standard.object(forKey: Self.maximumQuestionsDefaultsKey) as? Int ?? 3
        self.unansweredTimeoutSeconds = UserDefaults.standard.object(forKey: Self.unansweredTimeoutDefaultsKey) as? Double ?? 45
    }

    private var passTask: Task<Void, Never>?

    private func preparePassTimer() {
        standDownPassTimer()
        guard skipsUnansweredPrompts, status == .awaitingUserAnswer else { return }

        passTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(self.unansweredTimeoutSeconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            guard self.status == .awaitingUserAnswer else { return }
            print("🏛️ Lyceum panel: nobody answered, calling on the next hand")
            self.skipCurrentQuestion()
        }
    }

    private func standDownPassTimer() {
        passTask?.cancel()
        passTask = nil
    }

    // MARK: - Presence during the talk

    /// Called when a run starts. The grid appears immediately, agents silent, so it
    /// feels like a room you are presenting to rather than a verdict machine.
    func noteRunStarted() {
        cancelRound()
        meetingCode = Self.makeMeetingCode()
        status = .off
        errorMessage = nil
        startAmbientHandMotion()
    }

    /// Called when a run is abandoned.
    func noteRunCancelled() {
        cancelRound()
        status = .off
    }

    // MARK: - Convening the panel

    func convenePanel(
        mode: LyceumCoachMode,
        topic: String,
        durationSeconds: TimeInterval,
        slideCount: Int,
        transcript: String,
        coachVerdictSummary: String?
    ) {
        stopAmbientHandMotion()

        guard isPanelEnabled else {
            status = .off
            return
        }

        let roster = members
        guard !roster.isEmpty else {
            status = .off
            errorMessage = "the audience roster is empty"
            return
        }

        panelTask?.cancel()
        questions = []
        exchanges = []
        defenseScore = nil
        currentIndex = 0
        liveCaption = ""
        userCaption = ""
        status = .convening

        panelTask = Task { [weak self] in
            guard let self else { return }
            do {
                let (rawText, _) = try await self.claudeAPI.analyzeImageStreaming(
                    images: [],
                    systemPrompt: LyceumAudiencePrompts.panelSystemPrompt(roster: roster),
                    userPrompt: LyceumAudiencePrompts.panelUserPrompt(
                        mode: mode,
                        topic: topic,
                        durationSeconds: durationSeconds,
                        slideCount: slideCount,
                        transcript: transcript,
                        coachVerdictSummary: coachVerdictSummary
                    ),
                    maxTokens: Self.panelMaxTokens,
                    onTextChunk: { _ in
                        // The panel's lines arrive as one JSON object, so partial text
                        // is noise. The verdict preview already streams elsewhere.
                    }
                )

                guard !Task.isCancelled else { return }

                let parsedPanel = LyceumPanelParser.parsePanel(from: rawText, roster: roster)
                guard !parsedPanel.questions.isEmpty else {
                    self.status = .off
                    self.errorMessage = "the room stayed quiet — the panel call returned no usable questions"
                    return
                }

                let limitedQuestions = self.applyQuestionLimit(to: parsedPanel.questions)
                self.spokenLanguageCode = parsedPanel.spokenLanguageCode ?? self.spokenLanguageCode
                self.questions = limitedQuestions
                ClickyAnalytics.trackLyceumPanelConvened(questionCount: limitedQuestions.count)
                self.askCurrentQuestion()
            } catch {
                guard !Task.isCancelled else { return }
                self.status = .off
                self.errorMessage = "the panel could not convene: \(error.localizedDescription)"
            }
        }
    }

    /// The frequency dial. A short class rehearsal should not face five questions,
    /// and simply taking the first N would drop the harshest voice in the room, so
    /// the limit keeps the kind opening and always ends on whoever was worst.
    private func applyQuestionLimit(to questions: [LyceumPanelQuestion]) -> [LyceumPanelQuestion] {
        let limit = max(1, min(questions.count, maximumQuestions))
        guard questions.count > limit else { return questions }
        guard limit > 1 else { return [questions[questions.count - 1]] }

        var picked = Array(questions.prefix(limit - 1))
        picked.append(questions[questions.count - 1])
        return picked
    }

    // MARK: - One agent's turn

    private func askCurrentQuestion() {
        guard let question = currentQuestion else {
            finishRound()
            return
        }

        status = .agentSpeaking
        activeSpeakerMemberID = question.memberID
        liveCaption = ""
        userCaption = ""
        standDownPassTimer()

        exchanges.append(LyceumPanelExchange(
            memberID: question.memberID,
            memberName: question.memberName,
            question: question.question
        ))

        speak(text: question.spokenLine, memberID: question.memberID) { [weak self] in
            guard let self, !Task.isCancelled else { return }
            self.status = .awaitingUserAnswer
            self.preparePassTimer()
        }
    }

    /// The user held the key and talked. Comes from the coach's push-to-talk routing.
    func receiveUserAnswer(_ transcript: String) {
        let cleanedAnswer = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard status == .awaitingUserAnswer || status == .userAnswering else { return }
        guard !cleanedAnswer.isEmpty else {
            skipCurrentQuestion()
            return
        }

        status = .userAnswering
        standDownPassTimer()
        userCaption = cleanedAnswer
        ClickyAnalytics.trackLyceumAnswerGiven(questionKind: question.kind.rawValue)

        guard var exchange = exchanges.popLast() else {
            advanceToNextQuestion()
            return
        }
        exchange.userAnswer = cleanedAnswer
        exchanges.append(exchange)

        let memberID = exchange.memberID
        let question = exchange.question
        let member = members.first { $0.id == memberID }
            ?? LyceumAudienceRoster.defaultMembers.first { $0.id == memberID }

        reactionTask?.cancel()
        reactionTask = Task { [weak self] in
            guard let self else { return }
            let reaction = await self.requestReaction(
                member: member,
                memberName: exchange.memberName,
                question: question,
                answer: cleanedAnswer
            )

            guard !Task.isCancelled else { return }

            guard let reaction else {
                // No reaction is not a reason to stall the room.
                self.advanceToNextQuestion()
                return
            }

            if var updatedExchange = self.exchanges.popLast() {
                updatedExchange.agentReaction = reaction.reply
                self.exchanges.append(updatedExchange)
            }

            self.status = .agentSpeaking
            self.activeSpeakerMemberID = memberID
            self.speak(text: reaction.reply, memberID: memberID) { [weak self] in
                guard let self, !Task.isCancelled else { return }

                // One push-back per person, at most. A real chair does not let
                // everyone re-litigate the whole talk.
                if let followUp = reaction.followUp, updatedExchangeAllowsFollowUp(reaction.verdict) {
                    if var pushingExchange = self.exchanges.popLast() {
                        pushingExchange.followUpQuestion = followUp
                        self.exchanges.append(pushingExchange)
                    }
                    self.activeSpeakerMemberID = memberID
                    self.status = .agentSpeaking
                    self.speak(text: followUp, memberID: memberID) { [weak self] in
                        guard let self, !Task.isCancelled else { return }
                        self.status = .awaitingUserAnswer
                        self.preparePassTimer()
                    }
                    return
                }

                self.advanceToNextQuestion()
            }
        }
    }

    /// A verdict of "held" ends that person's line of questioning.
    private func updatedExchangeAllowsFollowUp(_ verdict: String) -> Bool {
        verdict != "held"
    }

    private func requestReaction(
        member: LyceumAudienceMember?,
        memberName: String,
        question: String,
        answer: String
    ) async -> LyceumPanelParser.Reaction? {
        let systemPrompt: String
        if let member {
            systemPrompt = LyceumAudiencePrompts.reactionSystemPrompt(for: member)
        } else {
            systemPrompt = LyceumAudiencePrompts.reactionSystemPrompt(
                for: LyceumAudienceMember(
                    id: "guest",
                    name: memberName,
                    role: "audience member",
                    persona: "Asked one question and is listening to the answer.",
                    tone: .standard,
                    avatarSymbol: "person"
                )
            )
        }

        do {
            let (rawText, _) = try await claudeAPI.analyzeImageStreaming(
                images: [],
                systemPrompt: systemPrompt,
                userPrompt: LyceumAudiencePrompts.reactionUserPrompt(member: member ?? LyceumAudienceMember(
                    id: "guest",
                    name: memberName,
                    role: "audience member",
                    persona: "Asked one question and is listening.",
                    tone: .standard,
                    avatarSymbol: "person"
                ), question: question, answer: answer),
                maxTokens: Self.reactionMaxTokens,
                onTextChunk: { _ in }
            )
            return LyceumPanelParser.parseReaction(from: rawText)
        } catch {
            print("🏛️ Lyceum panel: reaction failed — \(error.localizedDescription)")
            return nil
        }
    }

    /// Live partial transcript while the presenter is talking. The self tile shows
    /// it, which is the same job captions do in a call.
    func noteUserSpeaking(_ draftText: String) {
        guard isAwaitingUserAnswer else { return }
        if status == .awaitingUserAnswer {
            status = .userAnswering
            standDownPassTimer()
        }
        userCaption = draftText
    }

    func skipCurrentQuestion() {
        guard status == .awaitingUserAnswer || status == .userAnswering else { return }
        if var exchange = exchanges.popLast() {
            exchange.userAnswer = exchange.userAnswer ?? ""
            exchanges.append(exchange)
        }
        stopSpeaking()
        advanceToNextQuestion()
    }

    private func advanceToNextQuestion() {
        captionTask?.cancel()
        activeSpeakerMemberID = nil
        liveCaption = ""

        guard currentIndex + 1 < questions.count else {
            finishRound()
            return
        }
        currentIndex += 1
        askCurrentQuestion()
    }

    private func finishRound() {
        captionTask?.cancel()
        standDownPassTimer()
        activeSpeakerMemberID = nil
        status = .roundComplete

        // Scoring a round nobody answered is theatre.
        guard answeredCount > 0 else {
            defenseScore = nil
            onRoundFinished?(nil)
            return
        }

        defenseTask?.cancel()
        defenseTask = Task { [weak self] in
            guard let self else { return }
            do {
                let (rawText, _) = try await self.claudeAPI.analyzeImageStreaming(
                    images: [],
                    systemPrompt: LyceumAudiencePrompts.defenseSystemPrompt,
                    userPrompt: LyceumAudiencePrompts.defenseUserPrompt(
                        exchanges: self.exchanges,
                        languageCode: self.spokenLanguageCode
                    ),
                    maxTokens: Self.defenseMaxTokens,
                    onTextChunk: { _ in }
                )
                guard !Task.isCancelled else { return }
                let score = LyceumPanelParser.parseDefenseScore(from: rawText)
                self.defenseScore = score
                ClickyAnalytics.trackLyceumDefenseScored(value: score?.value ?? 0)
                self.onRoundFinished?(score)
            } catch {
                guard !Task.isCancelled else { return }
                print("🏛️ Lyceum panel: defense scoring failed — \(error.localizedDescription)")
                self.onRoundFinished?(nil)
            }
        }
    }

    /// Leaves the room: no more speaking, no more answers, window may close.
    func leave() {
        cancelRound()
        status = .off
        errorMessage = nil
    }

    func cancelRound() {
        standDownPassTimer()
        panelTask?.cancel()
        panelTask = nil
        reactionTask?.cancel()
        reactionTask = nil
        defenseTask?.cancel()
        defenseTask = nil
        captionTask?.cancel()
        captionTask = nil
        stopAmbientHandMotion()
        stopSpeaking()
        activeSpeakerMemberID = nil
    }

    // MARK: - Speaking

    /// Speaks with the member's ElevenLabs voice when one is set, otherwise with a
    /// distinct local macOS voice. Muting the panel keeps the captions and skips the
    /// audio, which is what the mute button in a call actually does.
    private func speak(text: String, memberID: String, completion: @escaping () -> Void) {
        revealCaption(text)

        guard !areAgentsMuted else {
            // Captions are the whole point when muted; give them time to be read.
            DispatchQueue.main.asyncAfter(deadline: .now() + readingDelay(for: text)) {
                completion()
            }
            return
        }

        let member = members.first { $0.id == memberID }

        if let voiceID = member?.elevenLabsVoiceID, !voiceID.isEmpty {
            Task { [weak self] in
                guard let self else { return }
                do {
                    try await self.textToSpeechClient.speakText(text, voiceID: voiceID)
                } catch {
                    print("🏛️ Lyceum panel: ElevenLabs failed (\(error.localizedDescription)), using the local voice")
                    self.speakLocally(text: text, memberID: memberID)
                }
                await self.waitUntilAudioStops(completion: completion)
            }
            return
        }

        speakLocally(text: text, memberID: memberID)
        Task { [weak self] in
            guard let self else { return }
            await self.waitUntilAudioStops(completion: completion)
        }
    }

    private func speakLocally(text: String, memberID: String) {
        let member = members.first { $0.id == memberID }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = LyceumVoiceAllocator.voiceFor(memberID: memberID, languageCode: spokenLanguageCode)
        utterance.rate = member?.tone.speechRate ?? LyceumAudienceTone.standard.speechRate
        utterance.pitchMultiplier = member?.tone.speechPitch ?? LyceumAudienceTone.standard.speechPitch
        utterance.volume = 1.0
        speechSynthesizer.stopSpeaking(at: .immediate)
        speechSynthesizer.speak(utterance)
    }

    private func stopSpeaking() {
        speechSynthesizer.stopSpeaking(at: .immediate)
        textToSpeechClient.stopPlayback()
    }

    /// ElevenLabs playback is a fire-and-forget AVAudioPlayer and an AVSpeech
    /// utterance starts asynchronously, so the only way to know a line ended is to
    /// watch it. Waiting for audio to START first is what stops the next agent from
    /// talking over the one that just began.
    private func waitUntilAudioStops(completion: @escaping () -> Void) async {
        var hasSeenAudio = false
        let startDeadline = Date().addingTimeInterval(1.5)
        while !hasSeenAudio && Date() < startDeadline {
            if textToSpeechClient.isPlaying || speechSynthesizer.isSpeaking {
                hasSeenAudio = true
            } else {
                try? await Task.sleep(nanoseconds: 80_000_000)
            }
        }

        guard hasSeenAudio else {
            completion()
            return
        }

        let stopDeadline = Date().addingTimeInterval(120)
        while (textToSpeechClient.isPlaying || speechSynthesizer.isSpeaking) && Date() < stopDeadline {
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        completion()
    }

    private func readingDelay(for text: String) -> TimeInterval {
        min(14, max(2.5, Double(Int(text.count) / Int(Self.captionCharactersPerSecond))))
    }

    /// Captions type themselves out at speaking pace, which is what makes the grid
    /// feel like a live call instead of a wall of text that appeared.
    private func revealCaption(_ text: String) {
        captionTask?.cancel()
        liveCaption = ""
        guard areCaptionsShown else {
            liveCaption = ""
            return
        }

        captionTask = Task { [weak self] in
            guard let self else { return }
            let characters = Array(text)
            var revealed = ""
            let perCharacterNanoseconds = UInt64(1_000_000_000 / UInt64(Self.captionCharactersPerSecond))

            for character in characters {
                guard !Task.isCancelled else { return }
                revealed.append(character)
                self.liveCaption = revealed
                try? await Task.sleep(nanoseconds: perCharacterNanoseconds)
            }
        }
    }

    // MARK: - Ambient motion

    /// While the user is talking, the room is not frozen: someone nods along,
    /// someone raises a hand to go next. Purely cosmetic, and the whole point of
    /// drawing a grid instead of a status line.
    private func startAmbientHandMotion() {
        stopAmbientHandMotion()
        guard !members.isEmpty else { return }

        handTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64.random(in: 18_000_000_000...34_000_000_000))
                guard !Task.isCancelled else { return }
                let member = self.members.randomElement()
                self.raisedHandMemberID = member?.id
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled else { return }
                self.raisedHandMemberID = nil
            }
        }
    }

    private func stopAmbientHandMotion() {
        handTask?.cancel()
        handTask = nil
        raisedHandMemberID = nil
    }

    /// The live level of whoever is speaking: the agent's tile glows while its audio
    /// runs, the self tile glows while the user's mic is open.
    func isSpeaking(memberID: String) -> Bool {
        activeSpeakerMemberID == memberID
    }

    // MARK: - Room code

    private static func makeMeetingCode() -> String {
        let letters = Array("bcdfghjklmnpqrstvwxyz")
        func group(_ length: Int) -> String {
            String((0..<length).map { _ in letters.randomElement() ?? "x" })
        }
        return "lyc-\(group(4))-\(group(3))"
    }
}

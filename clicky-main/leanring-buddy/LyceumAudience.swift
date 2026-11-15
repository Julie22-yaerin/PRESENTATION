//
//  LyceumAudience.swift
//  leanring-buddy
//
//  The audience panel. Each member of the roster is a separate agent with its own
//  name, brief and voice: they all watched and heard the same run, and when the
//  talk ends they push back in character, one at a time, in the language the user
//  actually spoke.
//
//  This file holds only data and pure functions — prompts, the JSON contract that
//  comes back, the closing-signal detector and the voice allocator. The state
//  machine that drives the Q&A round lives in LyceumAudienceManager.
//

import AVFoundation
import Foundation

// MARK: - Roster

/// How hard an audience member pushes. The onboarding flow will expose these two
/// dials (frequency and severity); until then the roster carries a sane default.
enum LyceumAudienceTone: String, CaseIterable, Codable {
    case gentle
    case standard
    case brutal

    var displayName: String {
        switch self {
        case .gentle: return "Gentle"
        case .standard: return "Standard"
        case .brutal: return "Brutal"
        }
    }

    /// Written for the model, not the user.
    var briefForModel: String {
        switch self {
        case .gentle:
            return "Supportive. Ask the question a friend would ask, and concede what worked."
        case .standard:
            return "Professional. Challenge the weakest claim you heard, without theatre."
        case .brutal:
            return "Adversarial and specific. Attack the load-bearing assumption. No compliments."
        }
    }

    /// Speech synthesis shaping, so tone is audible and not only written.
    var speechRate: Float {
        switch self {
        case .gentle: return 0.46
        case .standard: return 0.50
        case .brutal: return 0.44
        }
    }

    var speechPitch: Float {
        switch self {
        case .gentle: return 1.05
        case .standard: return 1.0
        case .brutal: return 0.88
        }
    }
}

struct LyceumAudienceMember: Codable, Identifiable, Equatable {
    /// Stable key so a saved question can be matched to a member even after the
    /// user renames them.
    let id: String
    var name: String
    var role: String
    var persona: String
    var tone: LyceumAudienceTone
    var avatarSymbol: String
    /// Optional ElevenLabs voice id. Empty means "use the allocated system voice",
    /// which is the default so a fresh install still sounds like five people.
    var elevenLabsVoiceID: String?

    var initials: String {
        let words = name.split(separator: " ")
        let letters = words.prefix(2).compactMap { $0.first }
        if letters.isEmpty { return "?" }
        return String(letters).uppercased()
    }

    var hasCustomVoice: Bool {
        (elevenLabsVoiceID?.isEmpty == false)
    }
}

enum LyceumAudienceRoster {
    private static let defaultsKey = "lyceumAudienceRoster"
    static let maximumMembers = 6
    static let minimumMembers = 1

    /// Five distinct kinds of trouble. Together they cover the ways a real room
    /// decides a talk was not finished: the examiner, the practitioner, the
    /// specialist, the money, and the person watching the clock.
    static let defaultMembers: [LyceumAudienceMember] = [
        LyceumAudienceMember(
            id: "examiner",
            name: "Mara Vidal",
            role: "Committee chair",
            persona: "Has sat through four hundred defences. Only cares about whether the claim was actually justified.",
            tone: .brutal,
            avatarSymbol: "graduationcap"
        ),
        LyceumAudienceMember(
            id: "practitioner",
            name: "Tom Reyes",
            role: "Product lead",
            persona: "Has to ship something on Monday based on this. Asks what breaks in week one.",
            tone: .standard,
            avatarSymbol: "wrench.and.screwdriver"
        ),
        LyceumAudienceMember(
            id: "specialist",
            name: "Ines Okafor",
            role: "Domain expert",
            persona: "Knows the field better than the speaker. Notices the number that was skipped or the term that was used wrongly.",
            tone: .standard,
            avatarSymbol: "microscope"
        ),
        LyceumAudienceMember(
            id: "investor",
            name: "Kenji Sato",
            role: "Funder",
            persona: "Ten minutes of attention. Wants the why-now, the size of the prize, and what they would have to believe.",
            tone: .gentle,
            avatarSymbol: "chart.line.uptrend.xyaxis"
        ),
        LyceumAudienceMember(
            id: "moderator",
            name: "Priya Nair",
            role: "Session chair",
            persona: "Runs the room and the clock. Cuts to structure: what was the promise, was it paid off, what should the audience do next.",
            tone: .gentle,
            avatarSymbol: "clock"
        )
    ]

    static func load() -> [LyceumAudienceMember] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([LyceumAudienceMember].self, from: data),
              !decoded.isEmpty else {
            return defaultMembers
        }
        return Array(decoded.prefix(maximumMembers))
    }

    static func save(_ members: [LyceumAudienceMember]) {
        guard let data = try? JSONEncoder().encode(members) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    static func resetToDefault() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }
}

// MARK: - What the panel produces

enum LyceumPanelQuestionKind: String, Codable {
    case question
    case counterargument
    case clarification

    var displayName: String {
        switch self {
        case .question: return "Question"
        case .counterargument: return "Pushback"
        case .clarification: return "Clarify"
        }
    }

    var symbolName: String {
        switch self {
        case .question: return "questionmark.bubble"
        case .counterargument: return "arrow.turn.up.left"
        case .clarification: return "text.magnifyingglass"
        }
    }
}

/// One audience member's turn at the microphone.
struct LyceumPanelQuestion: Codable, Identifiable, Equatable {
    let memberID: String
    let memberName: String
    let question: String
    let kind: LyceumPanelQuestionKind
    /// One line saying which part of the talk this came from, so the question can
    /// never read as generic.
    let rootedIn: String?

    /// Unique because one member gets one turn at the microphone per round.
    var id: String { memberID }

    /// The text the agent says out loud, spoken-first phrasing.
    var spokenLine: String { question }

    var clipboardText: String { "\(memberName) — \(kind.displayName)\n\(question)" }
}

/// A user answer and what the agent did with it.
struct LyceumPanelExchange: Identifiable, Equatable {
    let id = UUID()
    let memberID: String
    let memberName: String
    let question: String
    var userAnswer: String?
    var agentReaction: String?
    /// Set when the agent decided the answer did not hold and pushed once more.
    var followUpQuestion: String?
    var userFollowUpAnswer: String?
}

enum LyceumPanelParser {
    struct ParsedPanel {
        let questions: [LyceumPanelQuestion]
        /// Two-letter language code the model detected from the transcript, so the
        /// panel speaks and writes in the same language the user presented in.
        let spokenLanguageCode: String?
    }

    static func parsePanel(from rawText: String, roster: [LyceumAudienceMember]) -> ParsedPanel {
        guard let object = LyceumJSON.firstObject(in: rawText),
              let panelArray = object["panel"] as? [[String: Any]] else {
            return ParsedPanel(questions: [], spokenLanguageCode: nil)
        }

        let languageCode = (object["language"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        var questions: [LyceumPanelQuestion] = []
        for (index, panelEntry) in panelArray.enumerated() {
            guard let questionText = (panelEntry["question"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !questionText.isEmpty else { continue }

            let requestedMemberID = (panelEntry["memberId"] as? String) ?? (panelEntry["member_id"] as? String)
            let matchedMember = roster.first { $0.id == requestedMemberID } ?? (index < roster.count ? roster[index] : nil)

            let kind = LyceumPanelQuestionKind(rawValue: (panelEntry["kind"] as? String)?.lowercased() ?? "") ?? .question

            questions.append(LyceumPanelQuestion(
                memberID: matchedMember?.id ?? requestedMemberID ?? "guest-\(index)",
                memberName: matchedMember?.name ?? (panelEntry["memberName"] as? String) ?? "Audience",
                question: questionText,
                kind: kind,
                rootedIn: (panelEntry["rootedIn"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            ))
        }

        return ParsedPanel(
            questions: questions,
            spokenLanguageCode: (languageCode?.isEmpty == false) ? languageCode : nil
        )
    }

    /// The per-answer reaction: {"reply": "...", "verdict": "held|weak|dodged", "followUp": "..."}
    struct Reaction {
        let reply: String
        let verdict: String
        let followUp: String?
    }

    static func parseReaction(from rawText: String) -> Reaction? {
        guard let object = LyceumJSON.firstObject(in: rawText),
              let reply = (object["reply"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !reply.isEmpty else {
            return nil
        }
        let verdict = ((object["verdict"] as? String)?.lowercased()) ?? "unjudged"
        let followUp = (object["followUp"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Reaction(reply: reply, verdict: verdict, followUp: (followUp?.isEmpty == false) ? followUp : nil)
    }

    static func parseDefenseScore(from rawText: String) -> LyceumScore? {
        guard let object = LyceumJSON.firstObject(in: rawText),
              let summary = (object["summary"] as? String), !summary.isEmpty else { return nil }
        let rawValue = object["score"]
        let value: Int
        if let number = rawValue as? NSNumber {
            value = max(0, min(10, number.intValue))
        } else if let string = rawValue as? String, let parsed = Int(string) {
            value = max(0, min(10, parsed))
        } else {
            value = 0
        }
        return LyceumScore(label: summary, value: value)
    }
}

// MARK: - JSON helper

/// Shared by the panel parsers. Models wrap JSON in prose and fences; the outermost
/// brace pair is the only structure worth trusting.
enum LyceumJSON {
    static func firstObject(in rawText: String) -> [String: Any]? {
        var text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            let lines = text.components(separatedBy: "\n")
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("```") }
            text = lines.joined(separator: "\n")
        }

        guard let openIndex = text.firstIndex(of: "{"),
              let closeIndex = text.lastIndex(of: "}"),
              openIndex < closeIndex else {
            return nil
        }

        let jsonString = String(text[openIndex...closeIndex])
        guard let data = jsonString.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }
}

// MARK: - Did the talk actually end?

enum LyceumClosingSignal: Equatable {
    /// The screen settled on a goodbye / "thank you" / "any questions" slide.
    case farewellSlide
    /// The speaker said the equivalent, in any language.
    case closingWords(String)

    var description: String {
        switch self {
        case .farewellSlide: return "closing slide on screen"
        case .closingWords(let phrase): return "heard \u{201C}\(phrase)\u{201D}"
        }
    }

    var analyticsName: String {
        switch self {
        case .farewellSlide: return "farewell_slide"
        case .closingWords: return "closing_words"
        }
    }
}

enum LyceumClosingDetector {
    /// Pairs that only make sense together: a gratitude word AND the thing they are
    /// thanking for, which is what separates "cảm ơn mọi người đã lắng nghe" from a
    /// polite "cảm ơn" in the middle of a slide.
    private static let gratitudeWords: [String] = [
        "thank you", "thanks", "thankyou", "thank", "cảm ơn", "cam on", "cám ơn",
        "gracias", "obrigado", "obrigada", "merci", "danke", "vielen dank", "grazie",
        "ありがとう", "ありがとうございます", "谢谢", "謝謝", "감사합니다", "terima kasih",
        "ขอบคุณ", "salamat", "asante", "شكرا", "teşekkür"
    ]

    private static let closingCompanions: [String] = [
        "listening", "listen", "watching", "attention", "your time", "time today", "joining",
        "attending", "for today", "any question", "questions?", "questions", "lắng nghe",
        "theo dõi", "đã nghe", "dành thời gian", "câu hỏi", "tham gia",
        "por su atención", "por vuestro tiempo", "pour votre attention", "aufmerksamkeit",
        "ご清聴", "聆听", "聆聽", "청취", "pertanyaan"
    ]

    /// Explicit "this is the end" announcements, which need no gratitude word.
    private static let endAnnouncements: [String] = [
        "that's all", "thats all", "that is all", "that's all from me", "that's it",
        "ends here", "kết thúc", "den dây la het", "đến đây là hết", "đến đây là kết thúc",
        "bài thuyết trình kết thúc", "hết rồi", "the end of my presentation",
        "conclude my presentation", "to wrap up", "in conclusion", "to conclude",
        "cuối cùng xin chúc", "j'arrive au bout", "das war's", "isso é tudo", "eso es todo",
        "以上で", "私の発表は以上", "끝납니다", "my time is up", "i'll stop there"
    ]

    /// Scans the tail of a live transcript. Returns the matched phrase so the UI can
    /// say why the run ended, never a bare boolean.
    static func detect(inTranscriptTail transcriptTail: String) -> String? {
        let normalized = transcriptTail.lowercased()

        for announcement in endAnnouncements where normalized.contains(announcement) {
            return announcement
        }

        let hasGratitude = gratitudeWords.contains { normalized.contains($0) }
        guard hasGratitude else { return nil }

        for companion in closingCompanions where normalized.contains(companion) {
            return "gratitude + \(companion)"
        }
        return nil
    }

    /// Minimum talk length before a "thank you" is allowed to end the run. Nobody
    /// opens a rehearsal by closing it.
    static let minimumSecondsBeforeAutoEnd: TimeInterval = 25

    /// How long the room has to stay quiet after the words land. A speaker who says
    /// "thanks" and immediately keeps going was not finished.
    static let silenceGraceSeconds: TimeInterval = 3.0

    // MARK: Closing slide

    static let closingSlideSystemPrompt = """
    You classify ONE slide image. Answer with JSON only, no prose:
    {"isClosing": true | false, "signal": "<=8 words naming what you see"}
    isClosing is true only when the slide's job is to end the talk: a thank-you,
    goodbye, "any questions?", "questions & discussion", "thank you for listening",
    "contact us" paired with a closing line, or a final slide whose only text is a
    closing phrase. A recap, summary, agenda or a slide that merely contains data is
    NOT a closing slide. If the slide is a photo, a logo wall or unreadable, answer false.
    """

    static func parseClosingSlideVerdict(_ rawText: String) -> Bool {
        guard let object = LyceumJSON.firstObject(in: rawText) else { return false }
        if let boolean = object["isClosing"] as? Bool { return boolean }
        if let string = object["isClosing"] as? String { return string.lowercased() == "true" }
        return false
    }
}

// MARK: - Voice allocation

/// Every agent needs to sound like a different person. ElevenLabs can do it, but
/// that needs a voice id per member and the user's plan may not include eleven.
/// macOS already ships dozens of real, local voices, so the default is: pick one
/// distinct local voice per member, shape it by tone, and let an ElevenLabs id
/// override it whenever one is filled in.
@MainActor
enum LyceumVoiceAllocator {
    private static var cachedVoices: [AVSpeechSynthesisVoice] = []
    private static var cachedVoiceLanguage: String?

    static func voices(forLanguageCode languageCode: String?) -> [AVSpeechSynthesisVoice] {
        let requestedLanguage = (languageCode ?? "en").lowercased()

        if cachedVoiceLanguage == requestedLanguage, !cachedVoices.isEmpty {
            return cachedVoices
        }

        let allVoices = AVSpeechSynthesisVoice.speechVoices()
        let languagePrefix = String(requestedLanguage.prefix(2))

        var matching = allVoices.filter { $0.language.lowercased().hasPrefix(languagePrefix) }
        if matching.count < 2 {
            // Only a handful of languages ship more than one voice. Fall back to any
            // English voice rather than have the whole panel speak in unison, but keep
            // the accents distinct so the agents still sound different from each other.
            matching = allVoices.filter { $0.language.lowercased().hasPrefix("en") }
        }
        if matching.isEmpty {
            matching = allVoices
        }
        if matching.isEmpty {
            return []
        }

        // Highest quality first, then deterministic so the same member keeps the
        // same voice across sessions instead of being a different person tomorrow.
        matching.sort { leftVoice, rightVoice in
            if leftVoice.quality != rightVoice.quality {
                return leftVoice.quality.rawValue > rightVoice.quality.rawValue
            }
            return leftVoice.identifier < rightVoice.identifier
        }

        cachedVoices = matching
        cachedVoiceLanguage = requestedLanguage
        return matching
    }

    static func voiceFor(memberID: String, languageCode: String?) -> AVSpeechSynthesisVoice? {
        let pool = voices(forLanguageCode: languageCode)
        guard !pool.isEmpty else { return nil }

        guard let memberIndex = LyceumAudienceRoster.load().firstIndex(where: { $0.id == memberID }) else {
            return pool[0]
        }
        return pool[memberIndex % pool.count]
    }
}

// MARK: - Prompts

enum LyceumAudiencePrompts {
    /// One call turns the finished run into a panel round. Text only — the agents
    /// already saw the slides while they were on screen, so what they need now is
    /// the words, the verdict, and their own character.
    static func panelSystemPrompt(roster: [LyceumAudienceMember]) -> String {
        var lines: [String] = [
            "You are role-playing the audience of a presentation that has just ended.",
            "The speaker finished. It is now the question round.",
            "For EACH audience member below, write exactly one thing they say at the microphone.",
            "",
            "THE PANEL:"
        ]

        for member in roster {
            lines.append("- memberId: \(member.id) | name: \(member.name) | role: \(member.role)")
            lines.append("  character: \(member.persona)")
            lines.append("  how hard they push: \(member.tone.briefForModel)")
        }

        lines.append(contentsOf: [
            "",
            "HARD RULES:",
            "1. Write in the SAME language the speaker spoke. Detect it from the transcript. Never translate into English if the talk was not in English.",
            "2. Every line must be rooted in something the speaker actually said or showed. If you cannot name it, do not ask it.",
            "3. No summaries, no compliments used as padding, no \"great presentation, but…\". They are in a room, not writing review.",
            "4. Each line must be answerable out loud in 20-40 seconds. One question, not three.",
            "5. Order them: kindest first, harshest last, the way a real room warms up.",
            "6. A counterargument must state the opposing position, not just doubt.",
            "7. Never invent numbers, citations or facts the speaker did not mention. Ask about what is missing instead.",
            "",
            "ANSWER WITH JSON ONLY, no prose, no fences:",
            "{\"language\":\"<2-letter code of the language the speaker used>\",\"panel\":[{\"memberId\":\"<one of the ids above>\",\"kind\":\"question|counterargument|clarification\",\"question\":\"<what they say, spoken style, <=45 words>\",\"rootedIn\":\"<=8 words naming the moment it came from\"}]}"
        ])

        return lines.joined(separator: "\n")
    }

    static func panelUserPrompt(
        mode: LyceumCoachMode,
        topic: String,
        durationSeconds: TimeInterval,
        slideCount: Int,
        transcript: String,
        coachVerdictSummary: String?
    ) -> String {
        var sections: [String] = [
            "DRILL: \(mode.displayName)",
            "TOPIC: \(topic.isEmpty ? "not stated by the user" : topic)",
            "RUN: \(Int(durationSeconds))s of speech across \(slideCount) distinct slide(s)."
        ]

        if let coachVerdictSummary, !coachVerdictSummary.isEmpty {
            sections.append("WHAT THE COACH ALREADY FOUND (do not repeat it, exploit it):\n\(coachVerdictSummary)")
        }

        sections.append("TRANSCRIPT:\n\(transcript)")
        return sections.joined(separator: "\n\n")
    }

    /// The agent hears the user's answer and reacts in character, once.
    static func reactionSystemPrompt(for member: LyceumAudienceMember) -> String {
        """
        You are \(member.name), \(member.role), in a presentation Q&A. \(member.persona)
        \(member.tone.briefForModel)
        You asked one question. The speaker has now answered it out loud.
        Reply in character, in the SAME language the speaker is using.
        Two sentences maximum for the reply. It must be sayable out loud — no lists, no markdown.
        Decide honestly whether the answer held up.
        Only add a followUp when the answer was weak or dodged, and make it one short question.
        ANSWER WITH JSON ONLY: {"reply":"...","verdict":"held|weak|dodged","followUp":"... or empty string"}
        """
    }

    static func reactionUserPrompt(member: LyceumAudienceMember, question: String, answer: String) -> String {
        """
        YOUR QUESTION: \(question)

        THE SPEAKER'S ANSWER (live transcript, may contain recognition errors): \(answer)
        """
    }

    /// After the round, one number for how the user defended the talk.
    static let defenseSystemPrompt = """
    You judge how well a presenter defended their talk in the Q&A round.
    Read the question / answer pairs. Score only what they did under questioning:
    directness, evidence brought on demand, honesty about what they do not know,
    and whether they conceded instead of bluffing.
    Do not reward fluency or confidence alone.
    ANSWER WITH JSON ONLY: {"score":<0-10 integer>,"summary":"<=10 words in the speaker's language","notes":"<=2 sentences"}
    """

    static func defenseUserPrompt(exchanges: [LyceumPanelExchange], languageCode: String?) -> String {
        var lines: [String] = ["QUESTION AND ANSWER LOG:"]
        for exchange in exchanges {
            lines.append("- \(exchange.memberName): \(exchange.question)")
            if let userAnswer = exchange.userAnswer, !userAnswer.isEmpty {
                lines.append("  speaker: \(userAnswer)")
            } else {
                lines.append("  speaker: (did not answer)")
            }
            if let reaction = exchange.agentReaction, !reaction.isEmpty {
                lines.append("  \(exchange.memberName) again: \(reaction)")
            }
            if let followUp = exchange.followUpQuestion, !followUp.isEmpty {
                lines.append("  \(exchange.memberName) follow-up: \(followUp)")
                if let followUpAnswer = exchange.userFollowUpAnswer, !followUpAnswer.isEmpty {
                    lines.append("  speaker: \(followUpAnswer)")
                }
            }
        }
        if let languageCode {
            lines.append("Write the summary in language code \(languageCode).")
        }
        return lines.joined(separator: "\n")
    }

    static let closingSlideUserPrompt = "Classify this slide. Is it the closing slide of the talk?"
}

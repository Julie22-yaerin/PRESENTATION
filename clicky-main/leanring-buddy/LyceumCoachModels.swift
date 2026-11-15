//
//  LyceumCoachModels.swift
//  leanring-buddy
//
//  Data model for a The Lyceum coaching session: the mode the user picked, the
//  structured report Claude returns, and the exporters that turn that report into
//  files the user can keep (Markdown for reading, JSON for tooling).
//
//  Everything here is deliberately tolerant: models drop fields, wrap JSON in
//  fences, or add prose. A coaching session that took ten minutes to record must
//  never be lost because one optional key was missing.
//

import Foundation

// MARK: - Mode

/// The drills The Lyceum runs. Each one changes what the AI listens for, but the
/// capture pipeline (mic, slide watcher, optional camera) is identical.
enum LyceumCoachMode: String, CaseIterable, Identifiable {
    /// Feynman technique: the user explains a concept as if teaching it.
    case feynman
    /// A class or competition defence: the user explains a project to a panel that
    /// has to score it, then answers for it.
    case defence
    /// Argument and rhetoric: the user defends a position under pressure.
    case debate
    /// Slide critique: the emphasis is on what is on screen per slide.
    case slideReview

    static let allCases: [LyceumCoachMode] = [.feynman, .defence, .debate, .slideReview]

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .feynman: return "Feynman"
        case .defence: return "Defence"
        case .debate: return "Debate"
        case .slideReview: return "Slide review"
        }
    }

    /// One line shown under the mode picker.
    var drillExplanation: String {
        switch self {
        case .feynman:
            return "Teach it back. Flags jargon, hand-waving and missing links."
        case .debate:
            return "Defend a position. Scores structure, evidence and rhetorical tics."
        case .slideReview:
            return "Present the deck. Rewrites bullets and speaker notes per slide."
        case .defence:
            return "Explain your project to a panel, then answer for it. Scores method, evidence and claim size."
        }
    }

    var symbolName: String {
        switch self {
        case .feynman: return "brain.head.profile"
        case .defence: return "checklist"
        case .debate: return "bubble.left.and.bubble.right"
        case .slideReview: return "rectangle.on.rectangle"
        }
    }

    /// Short word used inside the live status text.
    var sessionWord: String {
        switch self {
        case .feynman: return "explaining"
        case .defence: return "defending a project"
        case .debate: return "arguing"
        case .slideReview: return "presenting"
        }
    }
}

// MARK: - Session state

/// Where the coaching session currently is. Drives both panels' primary button.
enum LyceumSessionPhase: Equatable {
    case idle
    case preparing
    case recording
    case analysing
    case ready
    case failed(String)

    var isSessionLive: Bool {
        switch self {
        case .preparing, .recording: return true
        default: return false
        }
    }
}

// MARK: - Captured slide

/// One distinct screen state seen while the user was talking. The Lyceum treats a
/// slide change as the unit of structure: feedback is anchored to these.
struct LyceumSlideSnapshot: Identifiable {
    let id = UUID()
    let index: Int
    let capturedAt: Date
    let secondsOnPreviousSlide: TimeInterval
    let imageData: Data
    let screenshotWidthInPixels: Int
    let screenshotHeightInPixels: Int
    let displayLabel: String

    /// Label handed to the model so it can name the slide in its suggestions.
    var modelLabel: String {
        "slide \(index) — shown at \(Int(capturedAt.timeIntervalSince1970.rounded())) unix, visible for \(Int(secondsOnPreviousSlide))s, image dimensions: \(screenshotWidthInPixels)x\(screenshotHeightInPixels) pixels, \(displayLabel)"
    }
}

// MARK: - Report

/// A single 0–10 rating line in the report.
struct LyceumScore: Codable, Identifiable {
    let label: String
    let value: Int

    var id: String { label }
}

/// Concrete, copyable edit for one slide the model actually saw.
struct LyceumSlideSuggestion: Codable, Identifiable {
    let slideNumber: Int
    let titleSeenOnSlide: String?
    let problem: String
    let rewriteBullets: [String]?
    let speakerNotes: String?
    let visualHint: String?

    var id: Int { slideNumber }

    /// Text placed on the clipboard when the user hits Copy on a card.
    var clipboardText: String {
        let titleSuffix = titleSeenOnSlide.map { " — \($0)" } ?? ""
        var lines: [String] = ["Slide \(slideNumber)\(titleSuffix)"]
        lines.append("Problem: \(problem)")
        if let rewriteBullets, !rewriteBullets.isEmpty {
            lines.append("Suggested bullets:")
            lines.append(contentsOf: rewriteBullets.map { "  • \($0)" })
        }
        if let speakerNotes, !speakerNotes.isEmpty {
            lines.append("Speaker notes: \(speakerNotes)")
        }
        if let visualHint, !visualHint.isEmpty {
            lines.append("Visual: \(visualHint)")
        }
        return lines.joined(separator: "\n")
    }
}

/// What the presenter looked like, measured and judged. Voice numbers come from
/// the microphone arithmetic in LyceumDeliveryMeter; the notes come from the model
/// reading slides, words and — only if the camera was on — stills of the presenter.
struct LyceumPresenceNotes: Codable {
    /// Voice: pace, loudness movement, pauses, filler words.
    let voiceNotes: String?
    /// Body: facing, posture, hands, movement across the run.
    let bodyLanguageNotes: String?
    /// Where the eyes were when the important sentence arrived.
    let eyeContactNotes: String?
    /// Expression and animation, described as behaviour, never as emotion.
    let facialNotes: String?
    /// One thing to change next rehearsal. The whole section earns its place on this.
    let oneThingToFix: String?

    var isEmpty: Bool {
        [voiceNotes, bodyLanguageNotes, eyeContactNotes, facialNotes, oneThingToFix]
            .allSatisfy { ($0 ?? "").isEmpty }
    }

    var rows: [(label: String, value: String)] {
        var pairs: [(String, String)] = []
        if let voiceNotes, !voiceNotes.isEmpty { pairs.append(("Voice", voiceNotes)) }
        if let bodyLanguageNotes, !bodyLanguageNotes.isEmpty { pairs.append(("Body", bodyLanguageNotes)) }
        if let eyeContactNotes, !eyeContactNotes.isEmpty { pairs.append(("Eyes", eyeContactNotes)) }
        if let facialNotes, !facialNotes.isEmpty { pairs.append(("Face", facialNotes)) }
        if let oneThingToFix, !oneThingToFix.isEmpty { pairs.append(("Fix one thing", oneThingToFix)) }
        return pairs
    }
}

/// Rhetoric-only observations. Present in debate and defence sessions, absent otherwise.
struct LyceumRhetoricNotes: Codable {
    let crutchWords: [String]?
    let pacingNotes: String?
    let structureNotes: String?
    let strongestPoint: String?
    let weakestPoint: String?
}

/// The full coaching verdict for one session.
struct LyceumCoachReport: Codable {
    let summary: String
    let scores: [LyceumScore]? = nil
    let strengths: [String]? = nil
    let gaps: [String]? = nil
    let followUpQuestions: [String]? = nil
    /// Feynman specific: words the user used without actually defining them.
    let jargonWithoutDefinition: [String]? = nil
    /// Debate specific: the counter-arguments the user failed to answer.
    let unansweredCounters: [String]? = nil
    let rhetoric: LyceumRhetoricNotes? = nil
    /// Voice and body observations. Absent when the camera was off and the notes
    /// were not asked for.
    let presence: LyceumPresenceNotes? = nil
    let slideSuggestions: [LyceumSlideSuggestion]? = nil
    /// Two sentences written for the ear; this is what gets spoken aloud.
    let spokenFeedback: String? = nil
    /// Filled after the audience Q&A round, not by the model that graded the talk.
    /// Optional with a default so reports written before the panel existed still decode.
    var defenseScore: LyceumScore? = nil
    /// Set when the reply was not machine-readable and the raw prose was kept.
    var degradedToFallback: Bool? = nil

    var isDegraded: Bool { degradedToFallback ?? false }

    /// Anything worth showing as a number line in the panel.
    var scoreRows: [LyceumScore] { scores ?? [] }

    var slideSuggestionRows: [LyceumSlideSuggestion] { slideSuggestions ?? [] }

    var hasSlideSuggestions: Bool { !slideSuggestionRows.isEmpty }

    var presenceRows: [(label: String, value: String)] { presence?.rows ?? [] }

    var hasPresenceNotes: Bool { (presence?.isEmpty ?? true) == false }
}

// MARK: - Parsing

enum LyceumCoachReportParser {
    /// Pulls the report out of the model's reply. Handles fenced JSON, leading
    /// prose, and a total miss (returns a readable fallback instead of nil).
    static func parse(from rawText: String) -> LyceumCoachReport {
        // Fences, preamble and trailing notes are all tolerated by taking the
        // outermost brace pair, which is the only structure we actually need.
        let cleanedText = stripCodeFences(from: rawText)

        if let startIndexOfBrace = cleanedText.firstIndex(of: "{"),
           let endIndexOfBrace = cleanedText.lastIndex(of: "}"),
           startIndexOfBrace < endIndexOfBrace {
            let jsonString = String(cleanedText[startIndexOfBrace...endIndexOfBrace])
            if let data = jsonString.data(using: .utf8),
               let decoded = try? JSONDecoder().decode(LyceumCoachReport.self, from: data) {
                return decoded
            }
        }

        // Nothing machine-readable arrived. Keep the prose so the user still gets
        // the coaching they recorded ten minutes for.
        var fallbackReport = LyceumCoachReport(summary: rawText.trimmingCharacters(in: .whitespacesAndNewlines))
        fallbackReport.degradedToFallback = true
        return fallbackReport
    }

    private static func stripCodeFences(from text: String) -> String {
        // Only fence markers are removed, and only at the edges, so that prose
        // containing the word json is never mangled.
        var lines = text.components(separatedBy: "\n")
        while let first = lines.first, first.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
            lines.removeFirst()
        }
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Session record that gets persisted

/// What a saved session looks like on disk. Kept separate from the report because
/// the report is the model's output, while this is the whole recording context.
struct LyceumSavedSession: Codable, Identifiable {
    let sessionID: UUID

    var id: UUID { sessionID }
    let mode: String
    let startedAt: Date
    let endedAt: Date
    let durationSeconds: TimeInterval
    let slideCount: Int
    let transcript: String
    /// Mutable because the Q&A round happens after the session was first graded and
    /// saved, and its verdict belongs in the same record.
    var report: LyceumCoachReport
    /// How the run actually ended: a tap, a farewell slide, or heard closing words.
    var endedBy: String? = nil
    /// Microphone arithmetic from the run: pace, silence, loudness range, pitch
    /// movement, filler words. Stored because the dashboard charts it across weeks
    /// without asking the model again, and because a number that can be explained is
    /// a number a student can act on.
    var delivery: LyceumDeliveryStats? = nil
    /// How many camera stills the grade saw. The images themselves are never saved.
    var presenceFrameCount: Int? = nil
}

// MARK: - Exporting

enum LyceumReportExporter {
    /// Markdown reading copy: verdict first, then per-slide edits.
    static func markdown(for savedSession: LyceumSavedSession) -> String {
        let report = savedSession.report
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"

        var markdownLines: [String] = []
        markdownLines.append("# The Lyceum — \(savedSession.mode) session")
        markdownLines.append("")
        let endingNote = savedSession.endedBy.map { " · ended by \($0)" } ?? ""
        markdownLines.append("_\(dateFormatter.string(from: savedSession.startedAt)) · \(formatDuration(savedSession.durationSeconds)) · \(savedSession.slideCount) slide(s) seen\(endingNote)_")
        markdownLines.append("")
        markdownLines.append("## Verdict")
        markdownLines.append("")
        markdownLines.append(report.summary)
        markdownLines.append("")

        if !report.scoreRows.isEmpty {
            markdownLines.append("## Scores")
            markdownLines.append("")
            for scoreRow in report.scoreRows {
                markdownLines.append("- **\(scoreRow.label)**: \(scoreRow.value)/10")
            }
            markdownLines.append("")
        }

        if let strengths = report.strengths, !strengths.isEmpty {
            markdownLines.append("## What landed")
            markdownLines.append("")
            markdownLines.append(contentsOf: strengths.map { "- \($0)" })
            markdownLines.append("")
        }

        if let gaps = report.gaps, !gaps.isEmpty {
            markdownLines.append("## Where it broke down")
            markdownLines.append("")
            markdownLines.append(contentsOf: gaps.map { "- \($0)" })
            markdownLines.append("")
        }

        if let jargon = report.jargonWithoutDefinition, !jargon.isEmpty {
            markdownLines.append("## Said without defining")
            markdownLines.append("")
            markdownLines.append(contentsOf: jargon.map { "- \($0)" })
            markdownLines.append("")
        }

        if let counters = report.unansweredCounters, !counters.isEmpty {
            markdownLines.append("## Counters you did not answer")
            markdownLines.append("")
            markdownLines.append(contentsOf: counters.map { "- \($0)" })
            markdownLines.append("")
        }

        if let rhetoric = report.rhetoric {
            markdownLines.append("## Delivery")
            markdownLines.append("")
            if let crutchWords = rhetoric.crutchWords, !crutchWords.isEmpty {
                markdownLines.append("- Crutch words: \(crutchWords.joined(separator: ", "))")
            }
            if let pacingNotes = rhetoric.pacingNotes { markdownLines.append("- Pacing: \(pacingNotes)") }
            if let structureNotes = rhetoric.structureNotes { markdownLines.append("- Structure: \(structureNotes)") }
            if let strongestPoint = rhetoric.strongestPoint { markdownLines.append("- Strongest point: \(strongestPoint)") }
            if let weakestPoint = rhetoric.weakestPoint { markdownLines.append("- Weakest point: \(weakestPoint)") }
            markdownLines.append("")
        }

        if report.hasPresenceNotes {
            markdownLines.append("## Voice and presence")
            markdownLines.append("")
            for row in report.presenceRows {
                markdownLines.append("- \(row.label): \(row.value)")
            }
            markdownLines.append("")
        }

        if let delivery = savedSession.delivery {
            markdownLines.append("## Measured")
            markdownLines.append("")
            markdownLines.append("- Pace: \(Int(delivery.wordsPerMinute.rounded())) words per minute over \(delivery.wordCount) words")
            markdownLines.append("- Speech: \(Int(delivery.voicedSeconds))s of \(Int(delivery.totalSeconds))s (\(delivery.silencePercent)% silence, longest pause \(String(format: "%.1f", delivery.longestPauseSeconds))s)")
            markdownLines.append("- Loudness: mean \(String(format: "%.1f", delivery.meanLevelDecibels)) dBFS, range \(String(format: "%.1f", delivery.levelRangeDecibels)) dB")
            markdownLines.append("- Pitch movement: \(Int(delivery.pitchProxyHertz.rounded())) Hz proxy, variety \(String(format: "%.2f", delivery.pitchVariety))")
            if !delivery.fillers.isEmpty {
                let top = delivery.fillers.prefix(6).map { "\($0.word) x\($0.count)" }.joined(separator: ", ")
                markdownLines.append("- Filler words: \(top) (\(String(format: "%.1f", delivery.fillerPerMinute)) per minute of speech)")
            }
            if let count = savedSession.presenceFrameCount, count > 0 {
                markdownLines.append("- Camera stills the grade saw: \(count), not stored")
            }
            markdownLines.append("")
        }

        if report.hasSlideSuggestions {
            markdownLines.append("## Slide edits")
            markdownLines.append("")
            for suggestion in report.slideSuggestionRows {
                let suggestionTitleSuffix = suggestion.titleSeenOnSlide.map { " — \($0)" } ?? ""
                markdownLines.append("### Slide \(suggestion.slideNumber)\(suggestionTitleSuffix)")
                markdownLines.append("")
                markdownLines.append("Problem: \(suggestion.problem)")
                if let rewriteBullets = suggestion.rewriteBullets, !rewriteBullets.isEmpty {
                    markdownLines.append("")
                    markdownLines.append("Suggested bullets:")
                    markdownLines.append(contentsOf: rewriteBullets.map { "- \($0)" })
                }
                if let speakerNotes = suggestion.speakerNotes, !speakerNotes.isEmpty {
                    markdownLines.append("")
                    markdownLines.append("Speaker notes: \(speakerNotes)")
                }
                if let visualHint = suggestion.visualHint, !visualHint.isEmpty {
                    markdownLines.append("Visual: \(visualHint)")
                }
                markdownLines.append("")
            }
        }

        if let defenseScore = report.defenseScore {
            markdownLines.append("## Under questioning")
            markdownLines.append("")
            markdownLines.append("**Defended it \(defenseScore.value)/10** — \(defenseScore.label)")
            markdownLines.append("")
        }

        markdownLines.append("## Transcript")
        markdownLines.append("")
        markdownLines.append(savedSession.transcript.isEmpty ? "_no speech captured_" : savedSession.transcript)
        markdownLines.append("")

        return markdownLines.joined(separator: "\n")
    }

    static func json(for savedSession: LyceumSavedSession) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(savedSession)
    }

    static func formatDuration(_ durationSeconds: TimeInterval) -> String {
        let totalSeconds = Int(durationSeconds)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        if minutes == 0 { return "\(seconds)s" }
        return "\(minutes)m \(seconds)s"
    }
}

//
//  LyceumInsights.swift
//  leanring-buddy
//
//  Everything the dashboard shows that is not one session. The coach panel answers
//  "how did that run go"; this answers "what is happening to me across the term",
//  which is the question a student actually has before a competition.
//
//  Deliberately arithmetic over the saved reports. No model call: a trend line that
//  costs money and changes wording every time it is read is not a measurement, and
//  a student needs to be able to point at the number.
//

import Foundation

// MARK: - Pieces the dashboard draws

struct LyceumTrendPoint: Identifiable, Equatable {
    let id: Int
    let date: Date
    let score: Double
    let mode: String
    let sessionID: UUID
}

struct LyceumWeakSpot: Identifiable, Equatable {
    let key: String
    let mentions: Int
    /// Two of the real sentences it came out of, so the word is never abstract.
    let examples: [String]
    /// Where it was found: gaps, jargon or unanswered counters.
    let source: String

    var id: String { key }
}

struct LyceumDayBucket: Identifiable, Equatable {
    let id: Int
    let date: Date
    let runs: Int
    let minutes: Double
}

/// One number line in the dashboard header.
struct LyceumStat: Identifiable, Equatable {
    let title: String
    let value: String
    let detail: String

    var id: String { title }
}

struct LyceumPracticeSummary: Equatable {
    let totalRuns: Int
    let runsLastSevenDays: Int
    let minutesPractised: Double
    let streakDays: Int
    let averageScore: Double
    let bestScore: Double
    let latestScore: Double?
    let defenceAverage: Double?
    let questionsAnswered: Int
    let runsWithCameraStills: Int

    let trend: [LyceumTrendPoint]
    let dayBuckets: [LyceumDayBucket]
    let weakSpots: [LyceumWeakSpot]
    let paceTrend: [LyceumTrendPoint]
    let fillerTrend: [LyceumTrendPoint]
    let modeBreakdown: [(mode: String, runs: Int, average: Double)]
    let mostRecent: LyceumSavedSession?

    static let empty = LyceumPracticeSummary(
        totalRuns: 0,
        runsLastSevenDays: 0,
        minutesPractised: 0,
        streakDays: 0,
        averageScore: 0,
        bestScore: 0,
        latestScore: nil,
        defenceAverage: nil,
        questionsAnswered: 0,
        runsWithCameraStills: 0,
        trend: [],
        dayBuckets: [],
        weakSpots: [],
        paceTrend: [],
        fillerTrend: [],
        modeBreakdown: [],
        mostRecent: nil
    )

    var hasAnything: Bool { totalRuns > 0 }

    /// The header row, in the order a student reads it.
    var headlineStats: [LyceumStat] {
        var stats: [LyceumStat] = [
            LyceumStat(title: "Runs", value: "\(totalRuns)",
                       detail: runsLastSevenDays > 0 ? "\(runsLastSevenDays) this week" : "none this week"),
            LyceumStat(title: "Practised", value: String(format: "%.0f min", minutesPractised),
                       detail: minutesPractised > 0
                           ? String(format: "%.1f min per run average", minutesPractised / Double(max(1, totalRuns)))
                           : "no speech captured yet"),
            LyceumStat(title: "Average", value: totalRuns > 0 ? String(format: "%.1f/10", averageScore) : "—",
                       detail: bestScore > 0 ? "best \(String(format: "%.1f", bestScore))" : "no score yet"),
            LyceumStat(title: "Streak", value: "\(streakDays)d",
                       detail: streakDays > 1 ? "consecutive days with a run" : "one day or none")
        ]

        if let defenceAverage {
            stats.append(LyceumStat(title: "Under questioning",
                                    value: String(format: "%.1f/10", defenceAverage),
                                    detail: "\(questionsAnswered) answers given out loud"))
        } else {
            stats.append(LyceumStat(title: "Under questioning", value: "—",
                                    detail: "finish a run with the room on"))
        }

        return stats
    }
}

// MARK: - The summariser

enum LyceumInsights {
    /// Words that carry no coaching meaning and would dominate every frequency count.
    /// The non-Latin rows are deliberate, not stray characters from a bad paste: the
    /// weak-spot counter runs over whatever language the student presented in, so a
    /// Chinese or Japanese talk is counted with its own particles excluded. If you are
    /// tempted to "clean up" this list, do not — you would only silence those rooms.
    private static let stopWords: Set<String> = [
        "the", "and", "a", "an", "of", "to", "in", "on", "for", "with", "that", "this", "it", "is", "are",
        "was", "were", "you", "your", "we", "our", "they", "their", "i", "my", "me", "be", "been", "have",
        "has", "had", "do", "does", "did", "not", "but", "or", "so", "if", "then", "than", "too", "very",
        "can", "will", "would", "should", "could", "what", "when", "where", "who", "how", "why", "which",
        "này", "那", "và", "của", "để", "cho", "là", "các", "những", "được", "không", "có", "thì", "mà",
        "trong", "với", "nó", "họ", "tôi", "chúng", "bạn", "một", "二", "の", "に", "で", "は", "が", "を"
    ]

    static func summarize(_ sessions: [LyceumSavedSession], now: Date = Date()) -> LyceumPracticeSummary {
        guard !sessions.isEmpty else { return .empty }

        // Oldest first: every series below reads left to right in time.
        let ordered = sessions.sorted { $0.startedAt < $1.startedAt }

        var trend: [LyceumTrendPoint] = []
        var paceTrend: [LyceumTrendPoint] = []
        var fillerTrend: [LyceumTrendPoint] = []
        var scoreValues: [Double] = []
        var defenceValues: [Double] = []
        var minutes: Double = 0
        var answered = 0
        var withStills = 0
        var lastSeven = 0
        var modeAccumulator: [String: (runs: Int, total: Double)] = [:]

        let sevenDaysAgo = now.addingTimeInterval(-7 * 24 * 60 * 60)

        for (index, savedSession) in ordered.enumerated() {
            minutes += savedSession.durationSeconds / 60
            if savedSession.startedAt >= sevenDaysAgo { lastSeven += 1 }
            if (savedSession.presenceFrameCount ?? 0) > 0 { withStills += 1 }

            let scores = reportScores(from: savedSession)
            if let overall = average(scores) {
                scoreValues.append(overall)
                trend.append(LyceumTrendPoint(id: index, date: savedSession.startedAt,
                                              score: overall, mode: savedSession.mode,
                                              sessionID: savedSession.sessionID))
                modeAccumulator[savedSession.mode, default: (0, 0)].runs += 1
                modeAccumulator[savedSession.mode, default: (0, 0)].total += overall
            }

            if let delivery = savedSession.delivery {
                paceTrend.append(LyceumTrendPoint(id: index, date: savedSession.startedAt,
                                                  score: delivery.wordsPerMinute, mode: savedSession.mode,
                                                  sessionID: savedSession.sessionID))
                fillerTrend.append(LyceumTrendPoint(id: index, date: savedSession.startedAt,
                                                    score: delivery.fillerPerMinute, mode: savedSession.mode,
                                                    sessionID: savedSession.sessionID))
            }

            if let defenseScore = savedSession.report.defenseScore {
                defenceValues.append(Double(defenseScore.value))
            }
            answered += savedSession.report.followUpQuestions?.count ?? 0
        }

        return LyceumPracticeSummary(
            totalRuns: ordered.count,
            runsLastSevenDays: lastSeven,
            minutesPractised: minutes,
            streakDays: streak(of: ordered, now: now),
            averageScore: average(scoreValues) ?? 0,
            bestScore: scoreValues.max() ?? 0,
            latestScore: scoreValues.last,
            defenceAverage: average(defenceValues),
            // The room's own answer count is not persisted per session, so this is
            // the number of follow-ups the coach said the student still owes. It is
            // labelled that way in the UI rather than pretending to be more.
            questionsAnswered: answered,
            runsWithCameraStills: withStills,
            trend: trend,
            dayBuckets: buckets(of: ordered, days: 21, now: now),
            weakSpots: weakSpots(in: ordered),
            paceTrend: paceTrend,
            fillerTrend: fillerTrend,
            modeBreakdown: modeAccumulator
                .map { (mode: $0.key, runs: $0.value.runs, average: $0.value.total / Double(max(1, $0.value.runs))) }
                .sorted { $0.runs > $1.runs },
            mostRecent: ordered.last
        )
    }

    // MARK: - Parts

    /// The run's own scores, plus the defence score counted as one more line. Mixing
    /// them is deliberate: one number per run is what makes a trend readable.
    private static func reportScores(from savedSession: LyceumSavedSession) -> [Double] {
        var values = (savedSession.report.scores ?? []).map { Double($0.value) }
        if let defenseScore = savedSession.report.defenseScore {
            values.append(Double(defenseScore.value))
        }
        return values
    }

    private static func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Consecutive calendar days that contain at least one run, counting back from
    /// today. Yesterday counts even if today is empty, because a student who
    /// rehearsed last night has not broken anything yet.
    private static func streak(of sessions: [LyceumSavedSession], now: Date) -> Int {
        let calendar = Calendar.current
        let days = Set(sessions.map { calendar.startOfDay(for: $0.startedAt) })
        guard !days.isEmpty else { return 0 }

        var cursor = calendar.startOfDay(for: now)
        if !days.contains(cursor) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) else { return 0 }
            if !days.contains(yesterday) { return 0 }
            cursor = yesterday
        }

        var count = 0
        while days.contains(cursor) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }

    private static func buckets(of sessions: [LyceumSavedSession], days: Int, now: Date) -> [LyceumDayBucket] {
        let calendar = Calendar.current
        guard let firstDay = calendar.date(byAdding: .day, value: -(days - 1),
                                          to: calendar.startOfDay(for: now)) else { return [] }

        var counts: [Date: (runs: Int, minutes: Double)] = [:]
        for savedSession in sessions {
            let day = calendar.startOfDay(for: savedSession.startedAt)
            guard day >= firstDay else { continue }
            var entry = counts[day] ?? (0, 0)
            entry.runs += 1
            entry.minutes += savedSession.durationSeconds / 60
            counts[day] = entry
        }

        var buckets: [LyceumDayBucket] = []
        for offset in 0..<days {
            guard let day = calendar.date(byAdding: .day, value: offset, to: firstDay) else { continue }
            let entry = counts[day] ?? (0, 0)
            buckets.append(LyceumDayBucket(id: offset, date: day, runs: entry.runs, minutes: entry.minutes))
        }
        return buckets
    }

    /// Which problems come back run after run. Word stems are counted across the
    /// "where it broke down", "said without defining" and "counters you never
    /// answered" lists, because a student cannot fix what they only ever see one
    /// session at a time.
    private static func weakSpots(in sessions: [LyceumSavedSession]) -> [LyceumWeakSpot] {
        struct Accumulator {
            var mentions = 0
            var examples: [String] = []
            var sources: [String: Int] = [:]
        }

        var table: [String: Accumulator] = [:]

        let groups: [(source: String, keyPath: (LyceumCoachReport) -> [String]?)] = [
            ("where it broke down", { $0.gaps }),
            ("said without defining", { $0.jargonWithoutDefinition }),
            ("never answered", { $0.unansweredCounters }),
            ("still owed", { $0.followUpQuestions })
        ]

        for savedSession in sessions {
            for group in groups {
                guard let items = group.keyPath(savedSession.report) else { continue }
                for item in items {
                    let keywords = keywords(from: item)
                    guard !keywords.isEmpty else { continue }
                    for keyword in keywords {
                        var entry = table[keyword] ?? Accumulator()
                        entry.mentions += 1
                        entry.sources[group.source, default: 0] += 1
                        if entry.examples.count < 2, !entry.examples.contains(item) {
                            entry.examples.append(item)
                        }
                        table[keyword] = entry
                    }
                }
            }
        }

        return table
            .filter { $0.value.mentions >= 2 }
            .map { key, value in
                let dominant = value.sources.max { $0.value < $1.value }?.key ?? "practice"
                return LyceumWeakSpot(key: key, mentions: value.mentions,
                                      examples: value.examples, source: dominant)
            }
            .sorted { left, right in
                if left.mentions != right.mentions { return left.mentions > right.mentions }
                return left.key < right.key
            }
            .prefix(8)
            .map { $0 }
    }

    /// Content words only, lowercased, with the trailing s and Vietnamese
    /// particles left alone rather than stemmed by guesswork. Two-word phrases are
    /// not built: "pricing model" and "model pricing" are the same concern, and a
    /// single honest keyword is easier to act on than a bigram that might be wrong.
    private static func keywords(from sentence: String) -> [String] {
        let pieces = sentence.lowercased()
            .split { character in
                character.isWhitespace || character.isNewline
                    || ",.;:()\"'’—-?!".contains(character)
            }

        var picked: [String] = []
        for piece in pieces {
            let word = String(piece)
            guard word.count >= 4 else { continue }
            guard !stopWords.contains(word) else { continue }
            if word.allSatisfy({ $0.isNumber }) { continue }
            picked.append(word)
            if picked.count >= 3 { break }
        }
        return picked
    }
}

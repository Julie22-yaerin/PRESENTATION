//
//  LyceumDeliveryMeter.swift
//  leanring-buddy
//
//  Everything this file measures is arithmetic on the microphone buffers the
//  recorder was already reading, plus string matching on the transcript. There is
//  no embedding, no feature vector, no model: pitch is a zero-crossing proxy,
//  loudness is RMS, pacing is words per minute. That is a deliberate limit. A
//  student rehearsing for a class deserves numbers the app can explain, not a
//  black box that says "confidence: 62%".
//
//  The numbers are handed to the grading model as text, so its feedback about
//  voice can say "you dropped to -24 dB in the last two minutes" instead of
//  guessing from the words alone.
//

import Foundation

// MARK: - Measured numbers

/// Filler word and phrase counts. Language is carried in the row because a
/// Vietnamese "kiểu là" and an English "kind of" must never be merged, and the word
/// itself is the identity: one hit per word per run.
struct LyceumFillerHit: Codable, Equatable, Identifiable {
    var id: String { word }
    let word: String
    let count: Int
    let language: String
}

/// The measured half of a run's delivery. Stored on the saved session so the
/// dashboard can chart it across weeks without asking the model again.
struct LyceumDeliveryStats: Codable, Equatable {
    /// Seconds the microphone actually heard voice in, not wall-clock time.
    let voicedSeconds: TimeInterval
    let totalSeconds: TimeInterval
    /// Share of the run that was not speech: slides being read, pauses, thinking.
    let silenceRatio: Double
    /// The single longest stretch of nothing. A long pause before a hard question
    /// is fine; a long pause in the middle of a definition is a hole.
    let longestPauseSeconds: Double
    /// Level statistics in dBFS, which is what a room-scale microphone actually sees.
    let meanLevelDecibels: Double
    let loudestWindowDecibels: Double
    let quietestWindowDecibels: Double
    /// Difference between the loud and quiet windows. Near zero means a flat
    /// delivery, which is the number behind "you sounded monotone".
    var levelRangeDecibels: Double { loudestWindowDecibels - quietestWindowDecibels }
    /// Zero-crossing rate in the voiced signal, in hertz. It is not a real pitch
    /// estimate, but its drift over a run tracks a rising or flattening voice.
    let pitchProxyHertz: Double
    /// Spread of that proxy across the run: low means little melodic movement.
    let pitchVariety: Double
    /// Words divided by seconds actually spoken, so a talk padded with pauses does
    /// not look fast.
    let wordsPerMinute: Double
    let wordCount: Int
    let fillerPerMinute: Double
    let fillers: [LyceumFillerHit]

    var silencePercent: Int { Int((silenceRatio * 100).rounded()) }

    /// One line that fits under a score bar in the panel.
    var summaryLine: String {
        let pace = Int(wordsPerMinute.rounded())
        let fillers = fillerPerMinute >= 1
            ? String(format: ", %.0f filler/min", fillerPerMinute)
            : ""
        return "\(pace) wpm · \(silencePercent)% silence · \(String(format: "%.0f", levelRangeDecibels)) dB range\(fillers)"
    }

    /// Written for the model. Numbers first, interpretation last, and an explicit
    /// note about what these cannot see.
    var promptBlock: String {
        var lines: [String] = [
            "measured from the microphone (arithmetic, not a model):",
            "- speech: \(String(format: "%.0f", voicedSeconds))s of \(String(format: "%.0f", totalSeconds))s run (\(silencePercent)% of the time was not speech)",
            "- pace: \(Int(wordsPerMinute.rounded())) words per minute over \(wordCount) words",
            "- longest single pause: \(String(format: "%.1f", longestPauseSeconds))s",
            "- loudness: mean \(String(format: "%.1f", meanLevelDecibels)) dBFS, range \(String(format: "%.1f", levelRangeDecibels)) dB between the loudest and quietest minute",
            "- pitch proxy (zero-crossing rate): \(Int(pitchProxyHertz.rounded())) Hz, variety index \(String(format: "%.2f", pitchVariety))"
        ]

        if fillers.isEmpty {
            lines.append("- filler words: none detected in the transcript")
        } else {
            let top = fillers.prefix(6).map { "\($0.word) ×\($0.count)" }.joined(separator: ", ")
            lines.append("- filler words: \(top) (\(String(format: "%.1f", fillerPerMinute)) per minute of speech)")
        }

        lines.append("- these numbers cannot see emphasis, stress or meaning. a low variety index is a hint to check, not a verdict.")
        return lines.joined(separator: "\n")
    }
}

// MARK: - Filler words

/// The words a rehearsal coach wants counted, by language. The transcript is what
/// the recogniser produced, so this is a floor, never an exact count: many
/// providers silently drop "um". The meter says so rather than pretending.
enum LyceumFillerWords {
    struct Entry {
        let phrase: String
        let language: String
    }

    static let entries: [Entry] = [
        // English
        Entry(phrase: "um", language: "en"), Entry(phrase: "uh", language: "en"),
        Entry(phrase: "er", language: "en"), Entry(phrase: "ah", language: "en"),
        Entry(phrase: "like", language: "en"), Entry(phrase: "you know", language: "en"),
        Entry(phrase: "kind of", language: "en"), Entry(phrase: "sort of", language: "en"),
        Entry(phrase: "basically", language: "en"), Entry(phrase: "actually", language: "en"),
        Entry(phrase: "literally", language: "en"), Entry(phrase: "so basically", language: "en"),
        Entry(phrase: "at the end of the day", language: "en"),
        // Vietnamese — classroom filler, counted on the unaccented form too because
        // the recogniser drops diacritics on short interjections.
        Entry(phrase: "à", language: "vi"), Entry(phrase: "á", language: "vi"),
        Entry(phrase: "ừ", language: "vi"), Entry(phrase: "ờ", language: "vi"),
        Entry(phrase: "ờn", language: "vi"), Entry(phrase: "kiểu là", language: "vi"),
        Entry(phrase: "kiểu như", language: "vi"), Entry(phrase: "dạng như", language: "vi"),
        Entry(phrase: "thì mình", language: "vi"), Entry(phrase: "nè", language: "vi"),
        Entry(phrase: "nhen", language: "vi"), Entry(phrase: "hả", language: "vi"),
        Entry(phrase: "vậy đó", language: "vi"), Entry(phrase: "cái này", language: "vi"),
        Entry(phrase: "đại loại", language: "vi"), Entry(phrase: "nói chung là", language: "vi"),
        // Other languages a student may present in.
        Entry(phrase: "えー", language: "ja"), Entry(phrase: "あの", language: "ja"),
        Entry(phrase: "いわゆる", language: "ja"),
        Entry(phrase: "음", language: "ko"), Entry(phrase: "어", language: "ko"),
        Entry(phrase: "este", language: "es"), Entry(phrase: "digamos", language: "es"),
        Entry(phrase: "euh", language: "fr"), Entry(phrase: "en fait", language: "fr"),
        Entry(phrase: "äh", language: "de"), Entry(phrase: "also", language: "de"),
        Entry(phrase: "cioè", language: "it"), Entry(phrase: "diciamo", language: "it"),
        Entry(phrase: "isso", language: "pt"), Entry(phrase: "né", language: "pt"),
        Entry(phrase: "đúng không", language: "vi"), Entry(phrase: "ok không", language: "vi")
    ]

    /// Phrases that are legitimate content words in a science talk and must not be
    /// counted as filler even though they look like it.
    static let doNotCount: Set<String> = ["like", "actually", "literally", "so basically", "cái này", "isso", "este"]

    static func count(in transcript: String) -> [LyceumFillerHit] {
        let normalized = transcript.lowercased()
        let words = Set(normalized.split { !$0.isLetter && !$0.isNumber && !$0.isWhitespace }.filter { !$0.isEmpty })

        var hits: [LyceumFillerHit] = []
        for entry in entries {
            let occurrences = occurrencesOfPhrase(entry.phrase.lowercased(), in: normalized, wholeWords: words)
            guard occurrences > 0 else { continue }
            // "like" as a comparison ("it works like a filter") is not a crutch word.
            // Counting it anyway would tell a student to stop using similes, which is
            // the opposite of the advice that helps, so ambiguous words are only
            // reported when they also show up standalone.
            if doNotCount.contains(entry.phrase.lowercased()), occurrences < 3 { continue }
            hits.append(LyceumFillerHit(word: entry.phrase, count: occurrences, language: entry.language))
        }
        return hits.sorted { $0.count > $1.count }
    }

    private static func occurrencesOfPhrase(_ phrase: String, in text: String, wholeWords: Set<String>) -> Int {
        guard !phrase.isEmpty else { return 0 }

        // Latin scripts get word-boundary matching; scripts without spaces (CJK)
        // get plain substring counting.
        let isSpacedScript = phrase.unicodeScalars.allSatisfy { $0.value < 0x2E80 }

        var count = 0
        var searchRange = text.startIndex..<text.endIndex

        while let found = text.range(of: phrase, options: [], range: searchRange) {
            if isSpacedScript {
                let leftBoundaryOK = found.lowerBound == text.startIndex
                    || !text[text.index(before: found.lowerBound)].isLetter
                let rightBoundaryOK = found.upperBound == text.endIndex
                    || !text[found.upperBound].isLetter
                if leftBoundaryOK, rightBoundaryOK {
                    count += 1
                }
            } else {
                count += 1
            }
            searchRange = found.upperBound..<text.endIndex
        }

        // A single-letter interjection in Vietnamese ("à", "ừ") is also a real word
        // elsewhere, so require it to appear as a standalone token as well.
        if isSpacedScript, phrase.count <= 2, !wholeWords.contains(phrase) {
            return 0
        }
        return count
    }
}

// MARK: - The meter

/// Fed every buffer the recorder taps. Runs on the main actor because that is
/// where the recorder already publishes its levels; the arithmetic per buffer is
/// tiny (a few thousand float operations) and never blocks a presentation.
@MainActor
final class LyceumDeliveryMeter {
    /// Windows are 100 ms; long enough to hold a pitch period, short enough that a
    /// five-second pause is still visible.
    private static let windowSeconds: TimeInterval = 0.1
    /// A window counts as speech when its RMS is above this. Measured on quiet
    /// laptop microphones in a room: below it the buffer is almost always noise.
    private static let voicedThresholdRMS: Float = 0.012
    /// Minute-sized buckets, so the loudness range is "loudest minute vs quietest
    /// minute" and not "loudest tenth of a second vs a breath".
    private static let secondsPerBucket: TimeInterval = 60

    private(set) var windowCount = 0
    private(set) var voicedWindowCount = 0

    private var levelSum: Float = 0
    private var levelSumOfSquares: Float = 0
    private var pitchSum: Float = 0
    private var pitchSumOfSquares: Float = 0

    private var bucketLevels: [Float] = []
    private var currentBucketSum: Float = 0
    private var currentBucketWindows = 0

    private var currentSilenceRun: TimeInterval = 0
    private(set) var longestSilenceRun: TimeInterval = 0
    private var elapsed: TimeInterval = 0

    func reset() {
        windowCount = 0
        voicedWindowCount = 0
        levelSum = 0
        levelSumOfSquares = 0
        pitchSum = 0
        pitchSumOfSquares = 0
        bucketLevels.removeAll()
        currentBucketSum = 0
        currentBucketWindows = 0
        currentSilenceRun = 0
        longestSilenceRun = 0
        elapsed = 0
    }

    /// One buffer of mono float samples. `sampleRate` is read per call because the
    /// engine's hardware rate varies by device and a wrong rate would shift every
    /// hertz number in the report.
    func consume(samples: [Float], sampleRate: Double) {
        guard !samples.isEmpty, sampleRate > 0 else { return }

        let rms = rootMeanSquare(samples)
        let zeroCrossings = countZeroCrossings(samples)
        let duration = TimeInterval(samples.count) / sampleRate
        elapsed += duration

        windowCount += 1
        let isVoiced = rms >= Self.voicedThresholdRMS

        if isVoiced {
            voicedWindowCount += 1
            currentSilenceRun = 0
            levelSum += rms
            levelSumOfSquares += rms * rms
            // Crossing rate is half the highest frequency present; as a proxy for
            // where the voice sits it only needs to be comparable across the run.
            let crossingsPerSecond = Float(Double(zeroCrossings) / duration)
            pitchSum += crossingsPerSecond
            pitchSumOfSquares += crossingsPerSecond * crossingsPerSecond
        } else {
            currentSilenceRun += duration
            longestSilenceRun = max(longestSilenceRun, currentSilenceRun)
        }

        currentBucketSum += rms
        currentBucketWindows += 1
        if currentBucketWindows >= Int(Self.secondsPerBucket / Self.windowSeconds) {
            bucketLevels.append(currentBucketSum / Float(currentBucketWindows))
            currentBucketSum = 0
            currentBucketWindows = 0
        }
    }

    /// Called when a run stops. Everything optional is guarded: a three-second run
    /// should still return numbers rather than crash a ten-minute session's save.
    func snapshot(transcript: String, runSeconds: TimeInterval) -> LyceumDeliveryStats {
        let voicedSeconds = TimeInterval(voicedWindowCount) * Self.windowSeconds
        let totalSeconds = max(runSeconds, elapsed)
        let silenceRatio = totalSeconds > 0 ? max(0, min(1, 1 - (voicedSeconds / totalSeconds))) : 1

        let meanLevel = voicedWindowCount > 0 ? levelSum / Float(voicedWindowCount) : 0
        let meanSquare = voicedWindowCount > 0 ? levelSumOfSquares / Float(voicedWindowCount) : 0
        let levelSpread = (meanSquare - meanLevel * meanLevel).squareRoot()

        let meanPitch = voicedWindowCount > 0 ? pitchSum / Float(voicedWindowCount) : 0
        let meanPitchSquare = voicedWindowCount > 0 ? pitchSumOfSquares / Float(voicedWindowCount) : 0
        let pitchSpread = (meanPitchSquare - meanPitch * meanPitch).squareRoot()
        let pitchVariety = meanPitch > 0 ? Double(pitchSpread / meanPitch) : 0

        // A partially filled last bucket is still a minute of speech, and dropping it
        // would bias every run shorter than two minutes.
        if currentBucketWindows > 0 {
            bucketLevels.append(currentBucketSum / Float(currentBucketWindows))
            currentBucketWindows = 0
            currentBucketSum = 0
        }
        let loudestBucket = bucketLevels.max() ?? meanLevel
        let quietestBucket = bucketLevels.min() ?? meanLevel

        let wordCount = countWords(transcript)
        let wordsPerMinute = voicedSeconds > 5 ? Double(wordCount) / (voicedSeconds / 60) : 0
        let fillers = LyceumFillerWords.count(in: transcript)
        let fillerCount = fillers.reduce(0) { $0 + $1.count }
        let fillerPerMinute = voicedSeconds > 5 ? Double(fillerCount) / (voicedSeconds / 60) : 0

        return LyceumDeliveryStats(
            voicedSeconds: voicedSeconds,
            totalSeconds: totalSeconds,
            silenceRatio: Double(silenceRatio),
            longestPauseSeconds: longestSilenceRun,
            meanLevelDecibels: decibels(meanLevel),
            loudestWindowDecibels: decibels(max(loudestBucket, meanLevel)),
            quietestWindowDecibels: decibels(quietestBucket > 0 ? quietestBucket : meanLevel),
            pitchProxyHertz: Double(meanPitch),
            pitchVariety: pitchVariety,
            wordsPerMinute: wordsPerMinute,
            wordCount: wordCount,
            fillerPerMinute: fillerPerMinute,
            fillers: fillers
        )
    }

    /// A short explanation of what the numbers say, used in the panel before the
    /// model has even been asked. Kept factual: this is a measuring tape, not a coach.
    static func plainReading(of stats: LyceumDeliveryStats) -> [String] {
        var lines: [String] = []

        if stats.wordsPerMinute > 0 {
            if stats.wordsPerMinute > 190 {
                lines.append("Fast: \(Int(stats.wordsPerMinute.rounded())) words per minute. A class needs 130-160.")
            } else if stats.wordsPerMinute < 105 {
                lines.append("Slow: \(Int(stats.wordsPerMinute.rounded())) words per minute. Under 105 reads as unsure of the material.")
            } else {
                lines.append("Pace is in the usable band: \(Int(stats.wordsPerMinute.rounded())) words per minute.")
            }
        }

        if stats.silenceRatio > 0.45 {
            lines.append("\(stats.silencePercent)% of the run was silence — either reading slides or losing the thread.")
        } else if stats.longestPauseSeconds > 6 {
            lines.append("One pause ran \(String(format: "%.1f", stats.longestPauseSeconds))s. Where did you stop, and why?")
        }

        if stats.levelRangeDecibels < 4 {
            lines.append("Loudness barely moved (\(String(format: "%.1f", stats.levelRangeDecibels)) dB across the whole run). Nothing was emphasised.")
        }

        if stats.pitchVariety < 0.14, stats.voicedSeconds > 20 {
            lines.append("Pitch stayed flat (variety \(String(format: "%.2f", stats.pitchVariety))). The important sentence should sound different from the rest.")
        }

        if let top = stats.fillers.first, top.count >= 3 {
            lines.append("Top filler: “\(top.word)” ×\(top.count).")
        }

        return lines
    }

    // MARK: - Arithmetic

    private func rootMeanSquare(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for sample in samples {
            sum += sample * sample
        }
        return (sum / Float(samples.count)).squareRoot()
    }

    private func countZeroCrossings(_ samples: [Float]) -> Int {
        var crossings = 0
        var previousSign: Float = 0
        for sample in samples {
            let sign: Float = sample >= 0 ? 1 : -1
            if previousSign != 0, sign != previousSign {
                crossings += 1
            }
            previousSign = sign
        }
        return crossings
    }

    private func decibels(_ level: Float) -> Double {
        guard level > 0.0000001 else { return -90 }
        return 20 * log10(Double(level))
    }

    /// Words per minute is only meaningful if the word count is. Languages written
    /// without spaces need the character estimate instead, and the estimate has to
    /// be labelled where it is read.
    private func countWords(_ transcript: String) -> Int {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }

        let spaced = trimmed.split { character in
            character.isWhitespace || character.isNewline || character == "." || character == ","
        }

        let hasSpaces = spaced.count > 3
        let needsCharacterEstimate = !hasSpaces && trimmed.count > 40

        if needsCharacterEstimate {
            // CJK speech runs roughly 3 characters per second of meaning; this is an
            // estimate and every consumer labels it as one.
            return Int(Double(trimmed.count) / 2.4)
        }
        return spaced.count
    }
}

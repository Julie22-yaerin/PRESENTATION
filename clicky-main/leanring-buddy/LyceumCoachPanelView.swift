//
//  LyceumCoachPanelView.swift
//  leanring-buddy
//
//  The Lyceum coaching panel: pick a drill, run it, read the verdict.
//
//  It lives in its own floating NSPanel (bottom-right, away from the deck) instead
//  of the menu bar dropdown, because a graded run needs room: transcript while you
//  speak, then scores, then per-slide edits you can copy.
//

import AppKit
import Combine
import SwiftUI

struct LyceumCoachPanelView: View {
    @ObservedObject var coachManager: LyceumCoachManager

    private static let panelWidth: CGFloat = 460
    private static let levelHistoryLength = 28

    @State private var levelHistory: [CGFloat] = Array(repeating: 0, count: 28)
    @State private var copiedSlideNumber: Int?

    private let levelTicker = Timer.publish(every: 0.12, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            panelHeader
            Divider().background(DS.Colors.borderSubtle)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 16) {
                    if coachManager.isShowingHistory {
                        historySection
                    }

                    switch coachManager.phase {
                    case .idle:
                        setupSection
                        emptyReportHint
                    case .preparing, .recording:
                        liveRunSection
                    case .analysing:
                        analysingSection
                    case .ready:
                        if let report = coachManager.latestReport {
                            reportSection(for: report)
                        } else {
                            setupSection
                        }
                    case .failed(let failureMessage):
                        setupSection
                        failureCard(failureMessage)
                    }
                }
                .padding(16)
            }

            panelFooter
        }
        .frame(width: Self.panelWidth)
        .frame(minHeight: 320, maxHeight: 620)
        .background(panelBackground)
        .onReceive(levelTicker) { _ in
            advanceLevelHistory()
        }
    }

    // MARK: - Header

    private var panelHeader: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .shadow(color: statusColor.opacity(0.6), radius: 4)

            Text("The Lyceum")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(DS.Colors.textPrimary)

            Text(statusLabel)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(DS.Colors.textTertiary)
                .padding(.leading, 2)

            Spacer()

            if coachManager.phase.isSessionLive {
                Text(formatClock(coachManager.elapsedSeconds))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(DS.Colors.blue400)
            }

            Button(action: {
                coachManager.closeCoachPanel()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(DS.Colors.textTertiary)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .pointerCursor()
            .help("Close")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - Setup

    private var setupSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pick a drill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(DS.Colors.textTertiary)
                .textCase(.uppercase)

            HStack(spacing: 8) {
                ForEach(LyceumCoachMode.allCases) { coachMode in
                    modeChip(for: coachMode)
                }
            }

            Text(coachManager.selectedMode.drillExplanation)
                .font(.system(size: 11))
                .foregroundColor(DS.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Text("What are you working on? (optional)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DS.Colors.textTertiary)

                TextField("cellular respiration, our Q3 pricing model…", text: Binding(
                    get: { coachManager.sessionTopic },
                    set: { coachManager.sessionTopic = $0 }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(DS.Colors.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: DS.CornerRadius.small, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DS.CornerRadius.small, style: .continuous)
                        .stroke(DS.Colors.borderSubtle, lineWidth: 0.5)
                )

                Text("Used to bias the recogniser and to frame the verdict.")
                    .font(.system(size: 10))
                    .foregroundColor(DS.Colors.textTertiary)
            }

            HStack {
                Text("Live nudges while presenting")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DS.Colors.textSecondary)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { coachManager.areLiveNudgesEnabled },
                    set: { coachManager.areLiveNudgesEnabled = $0 }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .tint(DS.Colors.accent)
                .scaleEffect(0.8)
            }

            VStack(alignment: .leading, spacing: 8) {
                toggleRow(
                    title: "End the run when the talk ends",
                    detail: "Watches for a goodbye slide, or the closing words in any language followed by a quiet room.",
                    isOn: Binding(
                        get: { coachManager.monitorsClosingSignals },
                        set: { coachManager.monitorsClosingSignals = $0 }
                    )
                )

                toggleRow(
                    title: "Audience asks afterwards",
                    detail: "\(coachManager.audience.members.count) agents watched and heard the run; they push back one at a time.",
                    isOn: Binding(
                        get: { coachManager.audience.isPanelEnabled },
                        set: { coachManager.audience.isPanelEnabled = $0 }
                    )
                )
            }

            gateCard

            roomCard

            presenceCard

            Button(action: {
                RunCueSound.play()
                coachManager.startSession()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "record.circle")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Start run")
                        .font(.system(size: 13, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(DSPrimaryButtonStyle())

            Text("Or press and release control + option to start, and again to stop. \(LyceumAppGate.detectionCaveat)")
                .font(.system(size: 10))
                .foregroundColor(DS.Colors.textTertiary)
        }
    }

    private func modeChip(for coachMode: LyceumCoachMode) -> some View {
        let isSelected = coachManager.selectedMode == coachMode
        return Button(action: {
            coachManager.selectedMode = coachMode
        }) {
            VStack(spacing: 5) {
                Image(systemName: coachMode.symbolName)
                    .font(.system(size: 14, weight: .medium))
                Text(coachMode.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundColor(isSelected ? DS.Colors.textPrimary : DS.Colors.textTertiary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.10) : Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
                    .stroke(isSelected ? DS.Colors.blue500.opacity(0.7) : DS.Colors.borderSubtle, lineWidth: isSelected ? 1 : 0.5)
            )
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }

    private func toggleRow(title: String, detail: String, isOn: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DS.Colors.textSecondary)
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundColor(DS.Colors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Toggle("", isOn: isOn)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .tint(DS.Colors.accent)
                    .scaleEffect(0.8)
            }
        }
    }

    /// What the app is looking at right now, and the two escape hatches: allow this
    /// one, or stop requiring a slide tool at all.
    private var gateCard: some View {
        let frontmost = coachManager.gate.latestFrontmost
        let isAllowed = coachManager.gate.latestDecision.isAllowed
        let hasBeenEvaluated = frontmost != .nothing

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: isAllowed ? "checkmark.seal.fill" : "seal.slash.fill")
                    .font(.system(size: 11))
                    .foregroundColor(isAllowed ? DS.Colors.success : DS.Colors.warningText)
                Text(gateTitle(isAllowed: isAllowed, hasBeenEvaluated: hasBeenEvaluated))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DS.Colors.textPrimary)
                Spacer()
                Button("Re-check") {
                    _ = coachManager.gate.evaluateNow()
                }
                .font(.system(size: 10))
                .buttonStyle(.plain)
                .foregroundColor(DS.Colors.accentText)
                .pointerCursor()
            }

            Text(frontmost.shortDescription.isEmpty ? "Nothing checked yet — press the hotkey or hit Re-check." : frontmost.shortDescription)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(DS.Colors.textTertiary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if !coachManager.gate.enforcesSlideTool {
                Text("The slide-tool requirement is switched off, so a run starts anywhere.")
                    .font(.system(size: 10))
                    .foregroundColor(DS.Colors.warningText)
            } else if !isAllowed && hasBeenEvaluated {
                HStack(spacing: 8) {
                    Button("Allow this app") {
                        coachManager.gate.whitelistCurrentApp()
                    }
                    .font(.system(size: 11, weight: .medium))
                    .buttonStyle(.plain)
                    .foregroundColor(DS.Colors.accentText)
                    .pointerCursor()

                    Toggle("Require a slide tool", isOn: Binding(
                        get: { coachManager.gate.enforcesSlideTool },
                        set: { coachManager.gate.enforcesSlideTool = $0 }
                    ))
                    .toggleStyle(.switch)
                    .font(.system(size: 10))
                    .labelsHidden()
                    .tint(DS.Colors.accent)
                    .scaleEffect(0.7)
                }
            }
        }
        .padding(12)
        .background(cardBackground)
        .overlay(cardOverlay)
    }

    private func gateTitle(isAllowed: Bool, hasBeenEvaluated: Bool) -> String {
        guard hasBeenEvaluated else { return "Slide tool check" }
        if !coachManager.gate.enforcesSlideTool { return "Any app allowed" }
        return isAllowed ? "Ready: \(coachManager.slideToolDisplayName)" : "Blocked: not a slide tool"
    }

    /// The room's status, with the two things a user reaches for during a round:
    /// open the grid, or hand the floor back to the presenter.
    private var roomCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "person.3.fill")
                    .font(.system(size: 11))
                    .foregroundColor(DS.Colors.blue400)
                Text("The room")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DS.Colors.textPrimary)
                Spacer()
                if coachManager.audience.isPanelEnabled {
                    Text(coachManager.panelStatusSummary)
                        .font(.system(size: 10))
                        .foregroundColor(DS.Colors.textTertiary)
                } else {
                    Text("off")
                        .font(.system(size: 10))
                        .foregroundColor(DS.Colors.textTertiary)
                }
            }

            if coachManager.audience.isPanelEnabled {
                Text(rosterSummary)
                    .font(.system(size: 10))
                    .foregroundColor(DS.Colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Button(coachManager.isRoomVisible ? "Bring room forward" : "Open the room") {
                        coachManager.openRoom()
                    }
                    .font(.system(size: 11, weight: .medium))
                    .buttonStyle(.plain)
                    .foregroundColor(DS.Colors.accentText)
                    .pointerCursor()

                    if coachManager.audience.isAwaitingUserAnswer {
                        Button("Pass this question") {
                            coachManager.skipCurrentQuestion()
                        }
                        .font(.system(size: 11, weight: .medium))
                        .buttonStyle(.plain)
                        .foregroundColor(DS.Colors.warningText)
                        .pointerCursor()
                    }

                    Spacer()
                }
            }
        }
        .padding(12)
        .background(cardBackground)
        .overlay(cardOverlay)
    }

    private var rosterSummary: String {
        let names = coachManager.audience.members.map { "\($0.name) (\($0.role))" }
        guard !names.isEmpty else { return "Nobody is in the room. Add a seat in the room window." }
        return names.joined(separator: " · ")
    }

    /// The camera and microphone dials, kept together because they answer the same
    /// question a nervous student asks first: what else is this thing watching?
    private var presenceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "waveform")
                    .font(.system(size: 11))
                    .foregroundColor(DS.Colors.blue400)
                Text("Voice and presence")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DS.Colors.textPrimary)
                Spacer()
            }

            toggleRow(
                title: "Measure my delivery",
                detail: "Pace, silence, loudness range and filler words, from arithmetic on the microphone. The audio itself never leaves the run.",
                isOn: Binding(
                    get: { coachManager.measuresDelivery },
                    set: { coachManager.measuresDelivery = $0 }
                )
            )

            toggleRow(
                title: "Stills from the camera",
                detail: coachManager.isPresenceCameraEnabled
                    ? "One small still every \(Int(coachManager.cameraIntervalSeconds))s, sent with your slides, then dropped. Nothing is written to disk."
                    : "Off. Feedback about posture and eye contact needs this switched on.",
                isOn: Binding(
                    get: { coachManager.isPresenceCameraEnabled },
                    set: { coachManager.isPresenceCameraEnabled = $0 }
                )
            )

            if coachManager.isPresenceCameraEnabled {
                HStack(spacing: 8) {
                    Text("Still every")
                        .font(.system(size: 10))
                        .foregroundColor(DS.Colors.textTertiary)
                    Slider(value: Binding(
                        get: { coachManager.cameraIntervalSeconds },
                        set: { coachManager.cameraIntervalSeconds = $0 }
                    ), in: 5...60, step: 5)
                    .controlSize(.small)
                    .frame(width: 90)
                    Text("\(Int(coachManager.cameraIntervalSeconds))s")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(DS.Colors.textSecondary)
                        .frame(width: 26, alignment: .trailing)
                }

                if coachManager.presenceFrameCount > 0 {
                    Text("\(coachManager.presenceFrameCount) stills went into the last grade. None were kept.")
                        .font(.system(size: 10))
                        .foregroundColor(DS.Colors.textTertiary)
                }
            }
        }
        .padding(12)
        .background(cardBackground)
        .overlay(cardOverlay)
    }

    /// Numbers the app measured itself, shown before anything the model believes
    /// about them. A student has to be able to tell a measurement from an opinion.
    private var measuredSection: some View {
        let delivery = coachManager.latestSavedSession?.delivery
        let reading = delivery.map { LyceumDeliveryMeter.plainReading(of: $0) } ?? []

        return VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Measured, not judged")

            if let delivery {
                Text(delivery.summaryLine)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(DS.Colors.textPrimary)

                ForEach(Array(reading.enumerated()), id: "\.offset") { _, line in
                    HStack(alignment: .top, spacing: 6) {
                        Circle()
                            .fill(DS.Colors.textTertiary)
                            .frame(width: 3, height: 3)
                            .padding(.top, 5)
                        Text(line)
                            .font(.system(size: 11))
                            .foregroundColor(DS.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if !delivery.fillers.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(delivery.fillers.prefix(5)) { hit in
                            Text("\(hit.word) x\(hit.count)")
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundColor(DS.Colors.warningText)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(
                                    RoundedRectangle(cornerRadius: DS.CornerRadius.small, style: .continuous)
                                        .fill(DS.Colors.warning.opacity(0.12))
                                )
                        }
                    }
                }

                if (coachManager.latestSavedSession?.presenceFrameCount ?? 0) == 0 {
                    Text("No camera stills this run, so nothing was said about posture or eye contact.")
                        .font(.system(size: 10))
                        .foregroundColor(DS.Colors.textTertiary)
                }
            } else {
                Text("Delivery measurement was switched off for this run. Turn it on above — it costs nothing.")
                    .font(.system(size: 11))
                    .foregroundColor(DS.Colors.textTertiary)
            }
        }
        .padding(12)
        .background(cardBackground)
        .overlay(cardOverlay)
    }

    /// What the model saw of the presenter as a body in a room. Separate from the
    /// scores because a note about hands is not a grade, and students hear it that way.
    private var presenceSection: some View {
        let rows = coachManager.latestReport?.presenceRows ?? []

        return VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Voice and presence")

            ForEach(Array(rows.enumerated()), id: "\.offset") { _, row in
                HStack(alignment: .top, spacing: 8) {
                    Text(row.label)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(DS.Colors.textTertiary)
                        .frame(width: 84, alignment: .leading)
                    Text(row.value)
                        .font(.system(size: 11))
                        .foregroundColor(row.label == "Fix one thing" ? DS.Colors.textPrimary : DS.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(12)
        .background(cardBackground)
        .overlay(cardOverlay)
    }


    private var emptyReportHint: some View {
        Group {
            if let mostRecent = coachManager.latestSavedSession {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Last run")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(DS.Colors.textTertiary)
                        .textCase(.uppercase)
                    Button(action: {
                        coachManager.showSavedSession(mostRecent)
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.text")
                            Text("\(mostRecent.mode) — \(LyceumReportExporter.formatDuration(mostRecent.durationSeconds)), \(mostRecent.slideCount) slides")
                        }
                        .font(.system(size: 12, weight: .medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(DSSecondaryButtonStyle())
                }
            }
        }
    }

    // MARK: - Live run

    private var liveRunSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recording")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(DS.Colors.textPrimary)
                    Text("Slide changes: \(coachManager.slideCount) · watching \(coachManager.watchedDisplayName.isEmpty ? "your screen" : coachManager.watchedDisplayName)")
                        .font(.system(size: 11))
                        .foregroundColor(DS.Colors.textTertiary)
                }
                Spacer()
                levelMeter
            }

            liveTranscriptCard

            if let liveNudge = coachManager.liveNudge {
                nudgeCard(liveNudge)
            }

            HStack(spacing: 10) {
                Button(action: {
                    RunCueSound.play()
                    coachManager.stopSessionAndReview()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "stop.fill")
                        Text("Stop & grade")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(DSPrimaryButtonStyle())

                Button(action: {
                    coachManager.cancelSession()
                }) {
                    Text("Discard")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(DSDestructiveButtonStyle())
            }

            Text("Talk like you would to the room. The deck stays yours — nothing is typed for you.")
                .font(.system(size: 10))
                .foregroundColor(DS.Colors.textTertiary)
        }
    }

    private var levelMeter: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<Self.levelHistoryLength, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(DS.Colors.blue400.opacity(levelBarOpacity(at: index)))
                    .frame(width: 3, height: max(2, levelBarHeight(at: index)))
            }
        }
        .frame(height: 26, alignment: .bottom)
    }

    private func levelBarHeight(at index: Int) -> CGFloat {
        guard index < levelHistory.count else { return 2 }
        return 2 + levelHistory[index] * 24
    }

    private func levelBarOpacity(at index: Int) -> Double {
        guard index < levelHistory.count else { return 0.1 }
        return 0.25 + Double(levelHistory[index]) * 0.75
    }

    private var liveTranscriptCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("What I am hearing")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(DS.Colors.textTertiary)
                .textCase(.uppercase)

            ScrollViewReader { scrollProxy in
                ScrollView(.vertical, showsIndicators: false) {
                    Text(coachManager.liveTranscript.isEmpty ? "…" : coachManager.liveTranscript)
                        .font(.system(size: 12))
                        .foregroundColor(DS.Colors.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id("lyceumTranscriptBottom")
                }
                .frame(height: 120)
                .onChange(of: coachManager.liveTranscript) { _ in
                    scrollProxy.scrollTo("lyceumTranscriptBottom", anchor: .bottom)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
                .stroke(DS.Colors.borderSubtle, lineWidth: 0.5)
        )
    }

    private func nudgeCard(_ nudgeText: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "bolt.horizontal")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(DS.Colors.warningText)
            Text(nudgeText)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(DS.Colors.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: DS.CornerRadius.small, style: .continuous)
                .fill(DS.Colors.warning.opacity(0.10))
        )
    }

    // MARK: - Analysing

    private var analysingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Grading the run")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(DS.Colors.textPrimary)
            }

            Text("\(coachManager.slideCount) slide(s) and \(coachManager.liveTranscript.count) characters to read. Verdict in a few seconds.")
                .font(.system(size: 11))
                .foregroundColor(DS.Colors.textSecondary)

            if !coachManager.analysisPreviewText.isEmpty {
                ScrollView(.vertical, showsIndicators: false) {
                    Text(coachManager.analysisPreviewText)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(DS.Colors.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 140)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: DS.CornerRadius.small, style: .continuous)
                        .fill(Color.black.opacity(0.25))
                )
            }
        }
    }

    // MARK: - Report

    private func reportSection(for report: LyceumCoachReport) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Verdict — \(reportTitlePrefix)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(DS.Colors.textPrimary)
                    Spacer()
                    if report.isDegraded {
                        Text("prose only")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(DS.Colors.warningText)
                    }
                }

                Text(report.summary)
                    .font(.system(size: 12))
                    .foregroundColor(DS.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(cardBackground)
            .overlay(cardOverlay)

            if let endedBy = coachManager.latestSavedSession?.endedBy {
                HStack(spacing: 6) {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(DS.Colors.textTertiary)
                    Text("ended by \(endedBy)")
                        .font(.system(size: 10))
                        .foregroundColor(DS.Colors.textTertiary)
                    Spacer()
                }
            }

            if let defenseScore = report.defenseScore {
                VStack(alignment: .leading, spacing: 6) {
                    sectionLabel("Under questioning")
                    HStack(spacing: 8) {
                        Text("\(defenseScore.value)/10")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(defenseScore.value >= 7 ? DS.Colors.success : DS.Colors.warningText)
                        Text(defenseScore.label)
                            .font(.system(size: 11))
                            .foregroundColor(DS.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("\(coachManager.audience.answeredCount) of \(coachManager.audience.questions.count) answered out loud")
                        .font(.system(size: 10))
                        .foregroundColor(DS.Colors.textTertiary)
                }
                .padding(12)
                .background(cardBackground)
                .overlay(cardOverlay)
            }

            if !report.scoreRows.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    sectionLabel("Scores")
                    ForEach(report.scoreRows) { scoreRow in
                        scoreRowView(scoreRow)
                    }
                }
            }

            if coachManager.latestSavedSession != nil {
                measuredSection
            }

            if report.hasPresenceNotes {
                presenceSection
            }

            if let strengths = report.strengths, !strengths.isEmpty {
                bulletSection(title: "What landed", symbol: "checkmark.circle.fill", color: DS.Colors.success, items: strengths)
            }

            if let gaps = report.gaps, !gaps.isEmpty {
                bulletSection(title: "Where it broke down", symbol: "exclamationmark.triangle.fill", color: DS.Colors.warning, items: gaps)
            }

            if let jargon = report.jargonWithoutDefinition, !jargon.isEmpty {
                chipSection(title: "Said without defining", chips: jargon)
            }

            if let counters = report.unansweredCounters, !counters.isEmpty {
                bulletSection(title: "Counters you never answered", symbol: "shield.lefthalf.filled", color: DS.Colors.destructiveText, items: counters)
            }

            if let rhetoric = report.rhetoric {
                rhetoricSection(rhetoric)
            }

            if let questions = report.followUpQuestions, !questions.isEmpty {
                bulletSection(title: "Answer these next run", symbol: "questionmark.circle.fill", color: DS.Colors.blue400, items: questions)
            }

            if report.hasSlideSuggestions {
                VStack(alignment: .leading, spacing: 10) {
                    sectionLabel("Slide edits")
                    ForEach(report.slideSuggestionRows) { suggestion in
                        slideSuggestionCard(suggestion)
                    }
                }
            }

            Button(action: {
                coachManager.beginNewRun()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise.circle")
                    Text("New run")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(DSSecondaryButtonStyle())
        }
    }

    private var reportTitlePrefix: String {
        coachManager.latestSavedSession?.mode ?? coachManager.selectedMode.displayName
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(DS.Colors.textTertiary)
            .textCase(.uppercase)
    }

    private func scoreRowView(_ scoreRow: LyceumScore) -> some View {
        HStack(spacing: 10) {
            Text(scoreRow.label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(DS.Colors.textPrimary)
                .frame(width: 110, alignment: .leading)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(scoreColor(scoreRow.value))
                        .frame(width: max(2, geometry.size.width * CGFloat(scoreRow.value) / 10.0))
                }
            }
            .frame(height: 6)

            Text("\(scoreRow.value)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(DS.Colors.textSecondary)
                .frame(width: 22, alignment: .trailing)
        }
    }

    private func scoreColor(_ value: Int) -> Color {
        if value >= 8 { return DS.Colors.success }
        if value >= 5 { return DS.Colors.blue400 }
        return DS.Colors.warning
    }

    private func bulletSection(title: String, symbol: String, color: Color, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(title)
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: symbol)
                        .font(.system(size: 11))
                        .foregroundColor(color)
                        .frame(width: 14)
                    Text(item)
                        .font(.system(size: 12))
                        .foregroundColor(DS.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func chipSection(title: String, chips: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(title)
            HStack(spacing: 6) {
                ForEach(chips, id: \.self) { chip in
                    Text(chip)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(DS.Colors.textPrimary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(Color.white.opacity(0.07))
                        )
                }
            }
        }
    }

    private func rhetoricSection(_ rhetoric: LyceumRhetoricNotes) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Delivery")
            if let crutchWords = rhetoric.crutchWords, !crutchWords.isEmpty {
                labelledLine("Crutch words", crutchWords.joined(separator: ", "))
            }
            if let pacingNotes = rhetoric.pacingNotes { labelledLine("Pacing", pacingNotes) }
            if let structureNotes = rhetoric.structureNotes { labelledLine("Structure", structureNotes) }
            if let strongestPoint = rhetoric.strongestPoint { labelledLine("Strongest", strongestPoint) }
            if let weakestPoint = rhetoric.weakestPoint { labelledLine("Weakest", weakestPoint) }
        }
    }

    private func labelledLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(DS.Colors.textTertiary)
                .frame(width: 74, alignment: .leading)
            Text(value)
                .font(.system(size: 12))
                .foregroundColor(DS.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func slideSuggestionCard(_ suggestion: LyceumSlideSuggestion) -> some View {
        let isCopied = copiedSlideNumber == suggestion.slideNumber
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Slide \(suggestion.slideNumber)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DS.Colors.blue400)
                if let titleSeenOnSlide = suggestion.titleSeenOnSlide {
                    Text(titleSeenOnSlide)
                        .font(.system(size: 11))
                        .foregroundColor(DS.Colors.textTertiary)
                        .lineLimit(1)
                }
                Spacer()
                Button(action: {
                    copyToPasteboard(suggestion.clipboardText)
                    withAnimation(.easeInOut(duration: DS.Animation.fast)) {
                        copiedSlideNumber = suggestion.slideNumber
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                        if copiedSlideNumber == suggestion.slideNumber { copiedSlideNumber = nil }
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 9))
                        Text(isCopied ? "Copied" : "Copy")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(isCopied ? DS.Colors.success : DS.Colors.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: DS.CornerRadius.small, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
                }
                .buttonStyle(.plain)
                .pointerCursor()
            }

            Text(suggestion.problem)
                .font(.system(size: 12))
                .foregroundColor(DS.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if let rewriteBullets = suggestion.rewriteBullets, !rewriteBullets.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(rewriteBullets.enumerated()), id: \.offset) { _, bullet in
                        HStack(alignment: .top, spacing: 6) {
                            Text("•")
                                .font(.system(size: 11))
                                .foregroundColor(DS.Colors.textTertiary)
                            Text(bullet)
                                .font(.system(size: 11))
                                .foregroundColor(DS.Colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            if let speakerNotes = suggestion.speakerNotes, !speakerNotes.isEmpty {
                labelledLine("Notes", speakerNotes)
            }

            if let visualHint = suggestion.visualHint, !visualHint.isEmpty {
                labelledLine("Visual", visualHint)
            }
        }
        .padding(12)
        .background(cardBackground)
        .overlay(cardOverlay)
    }

    // MARK: - Failure

    private func failureCard(_ failureMessage: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "xmark.octagon.fill")
                    .foregroundColor(DS.Colors.destructiveText)
                Text("That run did not make it")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DS.Colors.textPrimary)
            }
            Text(failureMessage)
                .font(.system(size: 11))
                .foregroundColor(DS.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
                .fill(DS.Colors.destructive.opacity(0.10))
        )
    }

    // MARK: - Footer

    private var panelFooter: some View {
        VStack(spacing: 0) {
            Divider().background(DS.Colors.borderSubtle)

            HStack(spacing: 10) {
                if coachManager.latestSavedSession != nil {
                    footerButton(title: "Copy all", symbol: "doc.on.doc") {
                        if let savedSession = coachManager.latestSavedSession {
                            copyToPasteboard(LyceumReportExporter.markdown(for: savedSession))
                        }
                    }
                    footerButton(title: "Markdown", symbol: "arrow.down.doc") {
                        coachManager.exportLatestReport(as: true)
                    }
                    footerButton(title: "JSON", symbol: "curlybraces") {
                        coachManager.exportLatestReport(as: false)
                    }
                } else {
                    Text("Nothing graded yet")
                        .font(.system(size: 11))
                        .foregroundColor(DS.Colors.textTertiary)
                }

                Spacer()

                footerButton(title: "Dashboard", symbol: "square.grid.2x2") {
                    NotificationCenter.default.post(name: .lyceumOpenDashboard, object: nil)
                }

                footerButton(title: "History", symbol: "clock.arrow.circlepath") {
                    coachManager.toggleHistory()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private func footerButton(title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 9))
                Text(title).font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(DS.Colors.textTertiary)
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }

    // MARK: - History

    @ViewBuilder
    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionLabel("Saved runs")
                Spacer()
                Button(action: { coachManager.hideHistory() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(DS.Colors.textTertiary)
                }
                .buttonStyle(.plain)
                .pointerCursor()
            }

            if coachManager.recentSessions.isEmpty {
                Text("Nothing saved yet. A run is stored here as soon as it is graded.")
                    .font(.system(size: 11))
                    .foregroundColor(DS.Colors.textTertiary)
            }

            ForEach(coachManager.recentSessions, id: \.sessionID) { savedSession in
                Button(action: {
                    coachManager.showSavedSession(savedSession)
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.richtext")
                            .font(.system(size: 11))
                            .foregroundColor(DS.Colors.blue400)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(savedSession.mode)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(DS.Colors.textPrimary)
                            Text(String(savedSession.report.summary.prefix(72)))
                                .font(.system(size: 10))
                                .foregroundColor(DS.Colors.textTertiary)
                                .lineLimit(2)
                        }
                        Spacer()
                        Text(LyceumReportExporter.formatDuration(savedSession.durationSeconds))
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(DS.Colors.textTertiary)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .background(
                        RoundedRectangle(cornerRadius: DS.CornerRadius.small, style: .continuous)
                            .fill(Color.white.opacity(0.04))
                    )
                }
                .buttonStyle(.plain)
                .pointerCursor()
            }
        }
    }

    // MARK: - Helpers

    private var statusColor: Color {
        switch coachManager.phase {
        case .idle: return DS.Colors.textTertiary
        case .preparing: return DS.Colors.warning
        case .recording: return DS.Colors.destructiveText
        case .analysing: return DS.Colors.blue400
        case .ready: return DS.Colors.success
        case .failed: return DS.Colors.destructiveText
        }
    }

    private var statusLabel: String {
        switch coachManager.phase {
        case .idle: return "ready"
        case .preparing: return "opening mic"
        case .recording: return coachManager.selectedMode.sessionWord
        case .analysing: return "grading"
        case .ready: return "report"
        case .failed: return "failed"
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
            .fill(Color.white.opacity(0.04))
    }

    private var cardOverlay: some View {
        RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
            .stroke(DS.Colors.borderSubtle, lineWidth: 0.5)
    }

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(DS.Colors.background)
            .shadow(color: Color.black.opacity(0.5), radius: 20, x: 0, y: 10)
            .shadow(color: Color.black.opacity(0.3), radius: 4, x: 0, y: 2)
    }

    private func formatClock(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    private func advanceLevelHistory() {
        var updatedHistory = levelHistory
        updatedHistory.removeFirst()
        updatedHistory.append(coachManager.phase.isSessionLive ? coachManager.audioPowerLevel : 0)
        levelHistory = updatedHistory
    }

    private func copyToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

/// A short system sound so a run visibly starts even if the user was looking at
/// the deck instead of the panel. Kept tiny on purpose — the panel is the real cue.
enum RunCueSound {
    static func play() {
        NSSound(named: "Tink")?.play()
    }
}

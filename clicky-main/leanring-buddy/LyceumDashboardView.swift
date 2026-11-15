//
//  LyceumDashboardView.swift
//  leanring-buddy
//
//  The Lyceum dashboard: one term of practice in a normal window.
//
//  The coach panel answers "how did that run go". This answers the question a
//  student actually has a week before a competition: "what is happening to me
//  across the term". Every number here comes out of the saved runs and the
//  arithmetic in LyceumInsights, so anything on this screen can be pointed at.
//
//  The charts are drawn by hand instead of through Swift Charts. The progress
//  picture is one line and one row of bars, and the only way that ever fails to
//  draw is a versioned dependency this window does not need.
//

import AppKit
import Combine
import SwiftUI

// MARK: - Dashboard

struct LyceumDashboardView: View {
    /// The four places a term of practice can be looked at from.
    enum DashboardTab: CaseIterable, Identifiable {
        case overview
        case progress
        case runs
        case guide

        var id: DashboardTab { self }

        var title: String {
            switch self {
            case .overview: return "Overview"
            case .progress: return "Progress"
            case .runs: return "Runs"
            case .guide: return "Guide"
            }
        }

        var symbol: String {
            switch self {
            case .overview: return "list.bullet.below.rectangle"
            case .progress: return "chart.xyaxis.line"
            case .runs: return "doc.on.doc"
            case .guide: return "questionmark.circle"
            }
        }

        /// One line under the title, so the header says what a tab is for.
        var subtitle: String {
            switch self {
            case .overview: return "This term so far, and the next run."
            case .progress: return "Scores, pace and the problems that come back."
            case .runs: return "Every saved run and its whole report."
            case .guide: return "How to drive this, in six short answers."
            }
        }
    }

    @ObservedObject var coach: LyceumCoachManager
    @ObservedObject var audience: LyceumAudienceManager
    @ObservedObject var gate: LyceumAppGate
    @ObservedObject var companion: CompanionManager
    var onClose: () -> Void

    private static let recentRunLimit = 7
    private static let barTrackWidth: CGFloat = 150
    private static let sidebarWidth: CGFloat = 200

    @State private var selection: DashboardTab = .overview
    @State private var sessions: [LyceumSavedSession] = []
    @State private var summary: LyceumPracticeSummary = .empty
    @State private var selectedSessionID: UUID?
    /// Set by the delete button. The confirm strip is drawn inline rather than as a
    /// dialog, so the run being deleted is still on screen while deciding.
    @State private var pendingDeletionID: UUID?
    @State private var copiedSlideNumber: Int?

    /// Configuration lives behind one gear at the foot of the sidebar:
    /// the tabs are for practising, the sheet is for setting up.
    @State private var isShowingSettings = false
    @State private var isShowingAgentStudio = false
    /// The five questions the app asks once. Read as state, not as a flag, so finishing
    /// onboarding repaints the window without reopening it.
    @ObservedObject private var profileStore = LyceumProfileStore.shared
    @ObservedObject private var appearance = LyceumAppearanceController.shared

    init(coach: LyceumCoachManager,
         audience: LyceumAudienceManager,
         gate: LyceumAppGate,
         companion: CompanionManager,
         onClose: @escaping () -> Void) {
        self.coach = coach
        self.audience = audience
        self.gate = gate
        self.companion = companion
        self.onClose = onClose
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().background(DS.Colors.borderSubtle)
            detailColumn
        }
        .frame(minWidth: 940, maxWidth: .infinity, minHeight: 620, maxHeight: .infinity)
        .background(DS.Colors.background).lyceumColorScheme(appearance.colorScheme).onAppear(perform: reloadData)
        // A graded run changes the tables and the trend together, so the
        // aggregation runs once per change and never inside the drawing code.
        .onChange(of: coach.phase) { _ in
            reloadData()
        }
        .onChange(of: coach.recentSessions.count) { _ in
            reloadData()
        }
        .sheet(isPresented: $isShowingSettings) {
            LyceumDashboardSettingsView(
                coach: coach,
                audience: audience,
                gate: gate,
                companion: companion
            )
        }
        .sheet(isPresented: $isShowingAgentStudio) {
            LyceumAgentStudioView(audience: audience) {
                isShowingAgentStudio = false
            }
        }
        // First run takes the whole window: these five answers decide the rubric, the
        // harshness of the room and the prompt the coach writes, so there is no point
        // letting anyone browse a dashboard built on guesses.
        .overlay {
            if !profileStore.hasCompletedOnboarding {
                LyceumOnboardingView(
                    profile: profileStore,
                    onOpenAgentStudio: { isShowingAgentStudio = true },
                    onFinish: finishOnboarding
                )
            }
        }
    }

    /// Writes the answers down, then shapes the default room around them. A seat the
    /// student has already briefed themselves is never rewritten by this.
    private func finishOnboarding() {
        let profile = profileStore.profile
        let tuned = LyceumAudienceTuning.tuned(audience.members, for: profile)
        if tuned != audience.members {
            audience.members = tuned
        }
        // The view already wrote the answers and raised the done flag before calling
        // this, so the store must not be marked a second time here.
        ClickyAnalytics.trackLyceumOnboardingCompleted(
            gradeKind: profile.gradeKindForAnalytics,
            audienceKinds: profile.audiences.map { $0.rawValue },
            hasOtherAudienceNote: !profile.otherAudienceNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            isCompetition: profile.isCompeting,
            agentsCustomised: LyceumAudienceTuning.customisedSeatCount(in: audience.members)
        )
        reloadData()
    }

    // MARK: - Shell

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            sidebarIdentity

            ForEach(DashboardTab.allCases) { tab in
                sidebarRow(for: tab)
            }

            Spacer(minLength: 0)

            sidebarFooter

            sidebarSettingsRow
        }
        .frame(width: Self.sidebarWidth).frame(maxHeight: .infinity).background(DS.Colors.surface1)
    }

    private var sidebarIdentity: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("The Lyceum")
                .font(.system(size: 13, weight: .semibold)).foregroundColor(DS.Colors.textPrimary)
            Text("dashboard")
                .font(.system(size: 10, weight: .medium)).foregroundColor(DS.Colors.textTertiary).textCase(.uppercase)
        }
        .padding(.horizontal, 14).padding(.top, 16).padding(.bottom, 12)
    }

    private func sidebarRow(for tab: DashboardTab) -> some View {
        let isSelected = selection == tab
        return Button(action: {
            selection = tab
        }) {
            HStack(spacing: 8) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isSelected ? DS.Colors.blue400 : DS.Colors.textTertiary).frame(width: 16)
                Text(tab.title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? DS.Colors.textPrimary : DS.Colors.textSecondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 8).background(
                RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.08) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).pointerCursor().padding(.horizontal, 8).padding(.vertical, 1)
    }

    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider().background(DS.Colors.borderSubtle)

            Text(summary.hasAnything
                 ? "\(summary.totalRuns) run(s) saved"
                 : "No runs saved yet")
                .font(.system(size: 10, weight: .medium)).foregroundColor(DS.Colors.textTertiary)

            Text(coach.gateStatusLine)
                .font(.system(size: 10)).foregroundColor(DS.Colors.textTertiary).lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }

    /// The gear at the foot of the sidebar. Voice, room and rules used to be
    /// tabs up here; all of it, plus data, appearance and onboarding, is behind
    /// this button now.
    private var sidebarSettingsRow: some View {
        Button(action: {
            isShowingSettings = true
        }) {
            HStack(spacing: 8) {
                Image(systemName: "gearshape")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DS.Colors.textTertiary).frame(width: 16)
                Text("Settings")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(DS.Colors.textSecondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).pointerCursor()
        .help("Settings: voice, room, rules, data, appearance and onboarding")
        .padding(.horizontal, 8).padding(.bottom, 10)
    }

    private var detailColumn: some View {
        VStack(spacing: 0) {
            detailHeader
            Divider().background(DS.Colors.borderSubtle)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 16) {
                    detailBody
                }
                .padding(20).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// The window has no toolbar of its own, so the header carries the Close
    /// control for every tab instead of each tab repeating one.
    private var detailHeader: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(selection.title)
                    .font(.system(size: 14, weight: .semibold)).foregroundColor(DS.Colors.textPrimary)
                Text(selection.subtitle)
                    .font(.system(size: 11)).foregroundColor(DS.Colors.textTertiary)
            }

            Spacer()

            statusPill

            Button(action: onClose) {
                Text("Close")
                    .font(.system(size: 11, weight: .medium)).foregroundColor(DS.Colors.textSecondary)
                    .padding(.horizontal, 10).padding(.vertical, 6).background(
                        RoundedRectangle(cornerRadius: DS.CornerRadius.small, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
            }
            .buttonStyle(.plain).pointerCursor().help("Close the dashboard")
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    private var statusPill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor).frame(width: 6, height: 6)
            Text(statusLabel)
                .font(.system(size: 11, weight: .medium)).foregroundColor(DS.Colors.textSecondary)
            if coach.phase.isSessionLive {
                Text(formatClock(coach.elapsedSeconds))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(DS.Colors.blue400)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6).background(
            RoundedRectangle(cornerRadius: DS.CornerRadius.small, style: .continuous)
                .fill(DS.Colors.surface2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.CornerRadius.small, style: .continuous)
                .stroke(DS.Colors.borderSubtle, lineWidth: 0.5)
        )
    }

    /// One screen per tab, so the sidebar only ever keeps one of them alive.
    @ViewBuilder
    private var detailBody: some View {
        switch selection {
        case .overview:
            overviewTab
        case .progress:
            progressTab
        case .runs:
            runsTab
        case .guide:
            guideTab
        }
    }

    // MARK: - Data

    private func reloadData() {
        sessions = coach.loadAllSavedSessions()
        summary = LyceumInsights.summarize(sessions)

        if let selectedSessionID, !sessions.contains(where: { $0.sessionID == selectedSessionID }) {
            self.selectedSessionID = nil
            pendingDeletionID = nil
        }
    }

    private var mostRecentSessions: [LyceumSavedSession] {
        Array(coach.recentSessions.prefix(Self.recentRunLimit))
    }

    // MARK: - Overview

    private var overviewTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let lastErrorMessage = coach.lastErrorMessage {
                problemCard(lastErrorMessage)
            }

            liveStrip

            VStack(alignment: .leading, spacing: 10) {
                sectionLabel("This term")
                HStack(alignment: .top, spacing: 10) {
                    ForEach(summary.headlineStats) { headlineStat in
                        statCard(headlineStat)
                    }
                }
            }

            if !summary.hasAnything {
                emptyTermCard
            }

            recentRunsBlock
        }
    }

    /// The run controls live here too: the dashboard is a place to start practice,
    /// not only to read about it.
    private var liveStrip: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(phaseLabel(coach.phase))
                        .font(.system(size: 14, weight: .semibold)).foregroundColor(DS.Colors.textPrimary)

                    HStack(spacing: 8) {
                        Text("Slides seen: \(coach.slideCount)")
                        Text("·")
                        Text(coach.gateStatusLine.isEmpty ? "No app check yet." : coach.gateStatusLine)
                    }
                    .font(.system(size: 11)).foregroundColor(DS.Colors.textTertiary).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                if coach.phase.isSessionLive {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(formatClock(coach.elapsedSeconds))
                            .font(.system(size: 18, weight: .semibold, design: .monospaced))
                            .foregroundColor(DS.Colors.blue400)
                        micLevelBar
                    }
                }

                if coach.presenceFrameCount > 0 {
                    VStack(alignment: .trailing, spacing: 3) {
                        Image(systemName: "video.fill")
                            .font(.system(size: 13)).foregroundColor(DS.Colors.blue400)
                        Text("\(coach.presenceFrameCount) still(s) this run")
                            .font(.system(size: 10)).foregroundColor(DS.Colors.textTertiary)
                    }
                }
            }

            HStack(spacing: 10) {
                primaryActionButton

                Button(action: {
                    coach.openCoachPanel()
                }) {
                    Text("Coach panel")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button(action: {
                    coach.toggleRoom()
                }) {
                    Text("The room")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).disabled(!audience.isPanelEnabled)
            }

            if let runEndingNote = coach.runEndingNote {
                HStack(spacing: 6) {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 10)).foregroundColor(DS.Colors.textTertiary)
                    Text("ended by \(runEndingNote)")
                        .font(.system(size: 11)).foregroundColor(DS.Colors.textTertiary)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(14).background(cardBackground).overlay(cardOverlay)
    }

    /// Level as a proportion, with no invented decibel claim: the recorder publishes
    /// a 0...1 figure and that is all this can honestly show.
    private var micLevelBar: some View {
        VStack(alignment: .trailing, spacing: 3) {
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(DS.Colors.blue400).frame(width: max(2, 90 * min(1.0, max(0.0, coach.audioPowerLevel))))
            }
            .frame(width: 90, height: 5)

            Text("microphone")
                .font(.system(size: 9)).foregroundColor(DS.Colors.textTertiary)
        }
    }

    @ViewBuilder
    private var primaryActionButton: some View {
        switch coach.phase {
        case .preparing, .recording:
            HStack(spacing: 10) {
                Button(action: {
                    RunCueSound.play()
                    coach.stopSessionAndReview()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "stop.fill")
                        Text("Stop and grade")
                    }
                }
                .buttonStyle(DSPrimaryButtonStyle(isFullWidth: false))

                Button("Discard") {
                    coach.cancelSession()
                }
                .buttonStyle(.bordered)
            }
        case .analysing:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Grading…")
                    .font(.system(size: 12, weight: .semibold)).foregroundColor(DS.Colors.textSecondary)
            }
            .padding(.horizontal, 16).padding(.vertical, 10).background(
                RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
        default:
            Button(action: {
                RunCueSound.play()
                coach.startSession()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "record.circle")
                    Text("Start run")
                }
            }
            .buttonStyle(DSPrimaryButtonStyle(isFullWidth: false))
        }
    }

    private func statCard(_ headlineStat: LyceumStat) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(headlineStat.title)
                .font(.system(size: 10, weight: .semibold)).foregroundColor(DS.Colors.textTertiary)
                .textCase(.uppercase)
            Text(headlineStat.value)
                .font(.system(size: 19, weight: .bold, design: .rounded)).foregroundColor(DS.Colors.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(headlineStat.detail)
                .font(.system(size: 10)).foregroundColor(DS.Colors.textTertiary).lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading).background(cardBackground).overlay(cardOverlay)
    }

    private var emptyTermCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Nothing saved yet")
                .font(.system(size: 12, weight: .semibold)).foregroundColor(DS.Colors.textPrimary)
            Text("Tap control + option while a slide tool is in front of you, talk through the deck, then tap again. A run is stored here as soon as it is graded.")
                .font(.system(size: 11)).foregroundColor(DS.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading).background(cardBackground).overlay(cardOverlay)
    }

    private var recentRunsBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionLabel("Last runs")
                Spacer()
                Button("See all") {
                    selection = .runs
                }
                .font(.system(size: 10, weight: .medium)).buttonStyle(.plain).foregroundColor(DS.Colors.accentText)
                .pointerCursor()
            }

            if mostRecentSessions.isEmpty {
                Text("No graded runs yet.")
                    .font(.system(size: 11)).foregroundColor(DS.Colors.textTertiary)
            }

            ForEach(mostRecentSessions) { savedSession in
                Button(action: {
                    selectedSessionID = savedSession.sessionID
                    selection = .runs
                }) {
                    HStack(spacing: 10) {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(shortDate(savedSession.startedAt))
                            Text(shortTime(savedSession.startedAt))
                        }
                        .font(.system(size: 10, design: .monospaced)).foregroundColor(DS.Colors.textTertiary)
                        .frame(width: 58, alignment: .trailing)

                        Text(savedSession.mode)
                            .font(.system(size: 12, weight: .medium)).foregroundColor(DS.Colors.textPrimary)
                            .frame(width: 100, alignment: .leading).lineLimit(1)

                        Text(String(savedSession.report.summary.prefix(90)))
                            .font(.system(size: 11)).foregroundColor(DS.Colors.textSecondary).lineLimit(1)

                        Spacer(minLength: 8)

                        Text(LyceumReportExporter.formatDuration(savedSession.durationSeconds))
                            .font(.system(size: 10, design: .monospaced)).foregroundColor(DS.Colors.textTertiary)

                        Text(averageScoreText(for: savedSession))
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(scoreColor(averageScore(for: savedSession)))
                            .frame(width: 42, alignment: .trailing)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 8).background(
                        RoundedRectangle(cornerRadius: DS.CornerRadius.small, style: .continuous)
                            .fill(Color.white.opacity(0.04))
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain).pointerCursor()
            }
        }
    }

    // MARK: - Progress

    private var progressTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                sectionLabel("Score over time")
                if summary.trend.count < 2 {
                    Text("Run more to see a trend. The line needs two graded runs, because one point is not a direction.")
                        .font(.system(size: 12)).foregroundColor(DS.Colors.textTertiary).padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading).background(cardBackground)
                        .overlay(cardOverlay)
                } else {
                    trendCard
                }
            }

            if summary.hasAnything {
                VStack(alignment: .leading, spacing: 10) {
                    sectionLabel("Runs per day, last 21 days")
                    paceCard
                }

                VStack(alignment: .leading, spacing: 10) {
                    sectionLabel("By drill")
                    modeBreakdownCard
                }

                VStack(alignment: .leading, spacing: 10) {
                    sectionLabel("What keeps coming back")
                    weakSpotsCard
                }
            }
        }
    }

    /// The score line plus the two measured series that usually explain it. They are
    /// drawn separately because pace and fillers are not on a nought-to-ten scale.
    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            LyceumDashboardSparkline(
                values: summary.trend.map { $0.score / 10.0 },
                color: DS.Colors.blue400,
                showsGridLines: true
            )
            .frame(height: 130)

            HStack(spacing: 16) {
                legendDot(color: DS.Colors.blue400, text: "run score, out of 10")
                Spacer()
                Text("\(summary.trend.count) graded run(s)")
                    .font(.system(size: 10)).foregroundColor(DS.Colors.textTertiary)
            }

            if summary.paceTrend.count >= 2 {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Words per minute")
                        .font(.system(size: 10, weight: .medium)).foregroundColor(DS.Colors.textTertiary)
                    LyceumDashboardSparkline(
                        values: summary.paceTrend.map { $0.score / 220.0 },
                        color: DS.Colors.success,
                        showsGridLines: false
                    )
                    .frame(height: 46)
                }
            }

            if summary.fillerTrend.count >= 2 {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Filler words per minute of speech")
                        .font(.system(size: 10, weight: .medium)).foregroundColor(DS.Colors.textTertiary)
                    LyceumDashboardSparkline(
                        values: summary.fillerTrend.map { $0.score / 12.0 },
                        color: DS.Colors.warning,
                        showsGridLines: false
                    )
                    .frame(height: 46)
                }
            }

            Divider().background(DS.Colors.borderSubtle)

            HStack(spacing: 12) {
                miniMetric(title: "Average", value: String(format: "%.1f", summary.averageScore))
                miniMetric(title: "Best", value: String(format: "%.1f", summary.bestScore))
                miniMetric(title: "Latest", value: summary.latestScore.map { String(format: "%.1f", $0) } ?? "—")
                miniMetric(title: "Defence", value: summary.defenceAverage.map { String(format: "%.1f", $0) } ?? "—")
                miniMetric(title: "Streak", value: "\(summary.streakDays) d")
            }
        }
        .padding(14).background(cardBackground).overlay(cardOverlay)
    }

    private var paceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            LyceumDashboardBarChart(bars: dayBars)
                .frame(height: 74)

            HStack {
                Text(shortDate(summary.dayBuckets.first?.date ?? Date()))
                Spacer()
                Text("21 days")
                Spacer()
                Text(shortDate(summary.dayBuckets.last?.date ?? Date()))
            }
            .font(.system(size: 9, design: .monospaced)).foregroundColor(DS.Colors.textTertiary)

            Text("A gap is not a failure. Two quiet weeks before a competition are how a talk stops changing.")
                .font(.system(size: 10)).foregroundColor(DS.Colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14).background(cardBackground).overlay(cardOverlay)
    }

    /// The bars are normalised to the busiest day rather than to one run, so a week
    /// of three-a-day practice does not flatten everything else into noise.
    private var dayBars: [LyceumDashboardBar] {
        let busiest = max(1, summary.dayBuckets.map { $0.runs }.max() ?? 1)
        return summary.dayBuckets.map { bucket in
            LyceumDashboardBar(
                label: shortDate(bucket.date),
                fraction: CGFloat(bucket.runs) / CGFloat(busiest),
                detail: "\(bucket.runs) run(s) · \(String(format: "%.0f", bucket.minutes)) min"
            )
        }
    }

    private var modeBreakdownCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if summary.modeBreakdown.isEmpty {
                Text("No graded runs yet.")
                    .font(.system(size: 11)).foregroundColor(DS.Colors.textTertiary)
            }

            ForEach(Array(summary.modeBreakdown.enumerated()), id: \.offset) { _, entry in
                HStack(spacing: 10) {
                    Text(entry.mode)
                        .font(.system(size: 12, weight: .medium)).foregroundColor(DS.Colors.textPrimary)
                        .frame(width: 110, alignment: .leading).lineLimit(1)

                    labelledBar(fraction: entry.average / 10.0, color: scoreColor(entry.average))

                    Text("\(entry.runs) run(s)")
                        .font(.system(size: 10, design: .monospaced)).foregroundColor(DS.Colors.textTertiary)
                        .frame(width: 66, alignment: .trailing)

                    Text(String(format: "%.1f", entry.average))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(DS.Colors.textSecondary).frame(width: 36, alignment: .trailing)
                }
            }
        }
        .padding(14).background(cardBackground).overlay(cardOverlay)
    }

    private var weakSpotsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if summary.weakSpots.isEmpty {
                Text("Nothing repeats often enough to be called a weakness yet. That is either good, or too few runs.")
                    .font(.system(size: 11)).foregroundColor(DS.Colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(summary.weakSpots) { weakSpot in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(weakSpot.key)
                            .font(.system(size: 12, weight: .semibold)).foregroundColor(DS.Colors.textPrimary)
                        Text("mentioned \(weakSpot.mentions) times")
                            .font(.system(size: 10)).foregroundColor(DS.Colors.warningText)
                        Text("from \(weakSpot.source)")
                            .font(.system(size: 10)).foregroundColor(DS.Colors.textTertiary)
                        Spacer(minLength: 0)
                    }

                    ForEach(Array(weakSpot.examples.enumerated()), id: \.offset) { _, example in
                        if !example.isEmpty {
                            Text(example)
                                .font(.system(size: 11).italic()).foregroundColor(DS.Colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(10).frame(maxWidth: .infinity, alignment: .leading).background(
                    RoundedRectangle(cornerRadius: DS.CornerRadius.small, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                )
            }
        }
    }

    private func miniMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .medium)).foregroundColor(DS.Colors.textTertiary).textCase(.uppercase)
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundColor(DS.Colors.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func legendDot(color: Color, text: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color).frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: 10)).foregroundColor(DS.Colors.textTertiary)
        }
    }

    // MARK: - Runs

    private var runsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                sectionLabel("\(sessions.count) saved run(s)")
                Spacer()
                Button("Reload from disk") {
                    reloadData()
                }
                .font(.system(size: 10, weight: .medium)).buttonStyle(.plain).foregroundColor(DS.Colors.accentText)
                .pointerCursor().help("Reads every saved run again, including any written while this window was open")
            }

            Text("Average is the run's own score lines with the defence score counted as one more, which is how the trend line counts it.")
                .font(.system(size: 10)).foregroundColor(DS.Colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            if sessions.isEmpty {
                emptyTermCard
            } else {
                ForEach(sessions) { savedSession in
                    runRow(savedSession)
                }
            }
        }
    }

    private func runRow(_ savedSession: LyceumSavedSession) -> some View {
        let isOpen = selectedSessionID == savedSession.sessionID
        return VStack(alignment: .leading, spacing: 0) {
            Button(action: {
                if isOpen {
                    selectedSessionID = nil
                    pendingDeletionID = nil
                } else {
                    selectedSessionID = savedSession.sessionID
                    pendingDeletionID = nil
                }
            }) {
                HStack(spacing: 10) {
                    Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold)).foregroundColor(DS.Colors.textTertiary)
                        .frame(width: 12)

                    VStack(alignment: .trailing, spacing: 1) {
                        Text(shortDate(savedSession.startedAt))
                        Text(shortTime(savedSession.startedAt))
                    }
                    .font(.system(size: 10, design: .monospaced)).foregroundColor(DS.Colors.textTertiary)
                    .frame(width: 58, alignment: .trailing)

                    Text(savedSession.mode)
                        .font(.system(size: 12, weight: .medium)).foregroundColor(DS.Colors.textPrimary)
                        .frame(width: 92, alignment: .leading).lineLimit(1)

                    columnValue(LyceumReportExporter.formatDuration(savedSession.durationSeconds), width: 50)
                    columnValue("\(savedSession.slideCount) slide(s)", width: 62)
                    columnValue(endedByLabel(savedSession), width: 104)

                    Spacer(minLength: 8)

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(averageScoreText(for: savedSession))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(scoreColor(averageScore(for: savedSession)))
                        if let defenseScore = savedSession.report.defenseScore {
                            Text("defence \(defenseScore.value)")
                                .font(.system(size: 9)).foregroundColor(DS.Colors.textTertiary)
                        }
                    }

                    if (savedSession.presenceFrameCount ?? 0) > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "video.fill")
                                .font(.system(size: 8))
                            Text("\(savedSession.presenceFrameCount ?? 0)")
                                .font(.system(size: 10))
                        }
                        .foregroundColor(DS.Colors.blue400).help("Camera stills went with this run.")
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 10).contentShape(Rectangle())
            }
            .buttonStyle(.plain).pointerCursor()

            if isOpen {
                Divider().background(DS.Colors.borderSubtle)
                runDetail(savedSession)
                    .padding(14)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: DS.CornerRadius.large, style: .continuous)
                .fill(isOpen ? DS.Colors.surface2 : DS.Colors.surface1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.CornerRadius.large, style: .continuous)
                .stroke(isOpen ? DS.Colors.borderStrong : DS.Colors.borderSubtle, lineWidth: isOpen ? 1 : 0.5)
        )
    }

    private func columnValue(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .font(.system(size: 10, design: .monospaced)).foregroundColor(DS.Colors.textTertiary)
            .frame(width: width, alignment: .leading).lineLimit(1)
    }

    private func endedByLabel(_ savedSession: LyceumSavedSession) -> String {
        guard let endedBy = savedSession.endedBy, !endedBy.isEmpty else { return "stopped by hand" }
        return "stopped by \(endedBy)"
    }

    /// One saved run, whole. The panel shows the verdict a run earned; this shows
    /// everything that was graded, because a term is reviewed by reading back.
    private func runDetail(_ savedSession: LyceumSavedSession) -> some View {
        let report = savedSession.report
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(savedSession.mode) — \(shortDate(savedSession.startedAt)) \(shortTime(savedSession.startedAt))")
                        .font(.system(size: 12, weight: .semibold)).foregroundColor(DS.Colors.textPrimary)
                    Text(LyceumReportExporter.formatDuration(savedSession.durationSeconds) + " · \(savedSession.slideCount) slide(s)")
                        .font(.system(size: 10, design: .monospaced)).foregroundColor(DS.Colors.textTertiary)
                }
                Spacer()
                if report.isDegraded {
                    Text("prose only")
                        .font(.system(size: 10, weight: .medium)).foregroundColor(DS.Colors.warningText)
                        .help("The model did not return structured scores for this run.")
                }
            }

            Text(report.summary)
                .font(.system(size: 12)).foregroundColor(DS.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if !report.scoreRows.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    sectionLabel("Scores")
                    ForEach(report.scoreRows) { scoreRow in
                        scoreRowView(scoreRow)
                    }
                }
            }

            if let delivery = savedSession.delivery {
                VStack(alignment: .leading, spacing: 6) {
                    sectionLabel("Measured by the microphone")
                    Text(delivery.summaryLine)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(DS.Colors.codeText).fixedSize(horizontal: false, vertical: true)
                    // Read here, in the view, because the plain wording is main-actor work.
                    ForEach(Array(LyceumDeliveryMeter.plainReading(of: delivery).enumerated()), id: \.offset) { _, readingLine in
                        bulletLine(readingLine, symbol: "ruler", color: DS.Colors.textTertiary)
                    }
                }
            }

            if let strengths = report.strengths, !strengths.isEmpty {
                bulletSection(title: "What landed", symbol: "checkmark.circle.fill", color: DS.Colors.success, items: strengths)
            }

            if let gaps = report.gaps, !gaps.isEmpty {
                bulletSection(title: "Where it broke down", symbol: "exclamationmark.triangle.fill", color: DS.Colors.warningText, items: gaps)
            }

            if let jargon = report.jargonWithoutDefinition, !jargon.isEmpty {
                bulletSection(title: "Said without defining", symbol: "textformat", color: DS.Colors.warningText, items: jargon)
            }

            if let counters = report.unansweredCounters, !counters.isEmpty {
                bulletSection(title: "Counters you never answered", symbol: "shield.lefthalf.filled", color: DS.Colors.destructiveText, items: counters)
            }

            if let questions = report.followUpQuestions, !questions.isEmpty {
                bulletSection(title: "Answer these next run", symbol: "questionmark.circle.fill", color: DS.Colors.blue400, items: questions)
            }

            if let rhetoric = report.rhetoric {
                VStack(alignment: .leading, spacing: 6) {
                    sectionLabel("Delivery notes")
                    if let crutchWords = rhetoric.crutchWords, !crutchWords.isEmpty {
                        labelledLine("Crutch words", crutchWords.joined(separator: ", "))
                    }
                    if let pacingNotes = rhetoric.pacingNotes { labelledLine("Pacing", pacingNotes) }
                    if let structureNotes = rhetoric.structureNotes { labelledLine("Structure", structureNotes) }
                    if let strongestPoint = rhetoric.strongestPoint { labelledLine("Strongest", strongestPoint) }
                    if let weakestPoint = rhetoric.weakestPoint { labelledLine("Weakest", weakestPoint) }
                }
            }

            if report.hasPresenceNotes {
                VStack(alignment: .leading, spacing: 6) {
                    sectionLabel("What the room saw")
                    ForEach(Array(report.presenceRows.enumerated()), id: \.offset) { _, presenceRow in
                        labelledLine(presenceRow.label, presenceRow.value)
                    }
                    if (savedSession.presenceFrameCount ?? 0) > 0 {
                        Text("\(savedSession.presenceFrameCount ?? 0) camera still(s) went with this run. The images themselves are gone.")
                            .font(.system(size: 10)).foregroundColor(DS.Colors.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
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
                            .font(.system(size: 11)).foregroundColor(DS.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if report.hasSlideSuggestions {
                VStack(alignment: .leading, spacing: 10) {
                    sectionLabel("Slide edits")
                    ForEach(report.slideSuggestionRows) { suggestion in
                        slideEditCard(suggestion)
                    }
                }
            }

            transcriptBlock(savedSession)

            runActions(savedSession)
        }
    }

    private func transcriptBlock(_ savedSession: LyceumSavedSession) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Transcript — \(savedSession.transcript.count) characters")
                .font(.system(size: 10, weight: .semibold)).foregroundColor(DS.Colors.textTertiary)
                .textCase(.uppercase)

            ScrollView(.vertical, showsIndicators: false) {
                Text(savedSession.transcript.isEmpty ? "Nothing was heard." : savedSession.transcript)
                    .font(.system(size: 11)).foregroundColor(DS.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            }
            .frame(height: 140).padding(10).background(
                RoundedRectangle(cornerRadius: DS.CornerRadius.small, style: .continuous)
                    .fill(Color.black.opacity(0.25))
            )
        }
    }

    private func runActions(_ savedSession: LyceumSavedSession) -> some View {
        let isConfirmingDelete = pendingDeletionID == savedSession.sessionID
        return VStack(alignment: .leading, spacing: 10) {
            Divider().background(DS.Colors.borderSubtle)

            HStack(spacing: 8) {
                Button("Copy markdown") {
                    copyToPasteboard(LyceumReportExporter.markdown(for: savedSession))
                }
                .buttonStyle(.bordered)

                Button("Export markdown") {
                    // The exporter writes the run the coach is holding, so the run
                    // being read is put in front of it first.
                    coach.focusSavedSession(savedSession)
                    coach.exportLatestReport(as: true)
                }
                .buttonStyle(.bordered)

                Button("Export JSON") {
                    coach.focusSavedSession(savedSession)
                    coach.exportLatestReport(as: false)
                }
                .buttonStyle(.bordered)

                Button("Show in coach panel") {
                    coach.focusSavedSession(savedSession)
                    coach.openCoachPanel()
                }
                .buttonStyle(.bordered)

                Spacer(minLength: 0)

                Button(action: {
                    pendingDeletionID = isConfirmingDelete ? nil : savedSession.sessionID
                }) {
                    Text(isConfirmingDelete ? "Confirm delete" : "Delete")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(isConfirmingDelete ? DS.Colors.textOnAccent : DS.Colors.destructiveText)
                        .padding(.horizontal, 10).padding(.vertical, 6).background(
                            RoundedRectangle(cornerRadius: DS.CornerRadius.small, style: .continuous)
                                .fill(isConfirmingDelete ? DS.Colors.destructive : DS.Colors.destructive.opacity(0.12))
                        )
                }
                .buttonStyle(.plain).pointerCursor()
            }

            if isConfirmingDelete {
                Text("This removes the saved run and the only copy of its report. The trend is rebuilt from whatever is left.")
                    .font(.system(size: 11)).foregroundColor(DS.Colors.destructiveText)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Button("Delete it now") {
                        coach.deleteSavedSession(savedSession)
                        selectedSessionID = nil
                        pendingDeletionID = nil
                        reloadData()
                    }
                    .buttonStyle(.bordered)

                    Button("Keep it") {
                        pendingDeletionID = nil
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private func slideEditCard(_ suggestion: LyceumSlideSuggestion) -> some View {
        let isCopied = copiedSlideNumber == suggestion.slideNumber
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Slide \(suggestion.slideNumber)")
                    .font(.system(size: 12, weight: .semibold)).foregroundColor(DS.Colors.blue400)
                if let titleSeenOnSlide = suggestion.titleSeenOnSlide {
                    Text(titleSeenOnSlide)
                        .font(.system(size: 11)).foregroundColor(DS.Colors.textTertiary).lineLimit(1)
                }
                Spacer()
                Button(action: {
                    copyToPasteboard(suggestion.clipboardText)
                    withAnimation(.easeInOut(duration: DS.Animation.fast)) {
                        copiedSlideNumber = suggestion.slideNumber
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                        if copiedSlideNumber == suggestion.slideNumber {
                            copiedSlideNumber = nil
                        }
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 9))
                        Text(isCopied ? "Copied" : "Copy")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(isCopied ? DS.Colors.success : DS.Colors.textSecondary).padding(.horizontal, 8)
                    .padding(.vertical, 4).background(
                        RoundedRectangle(cornerRadius: DS.CornerRadius.small, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
                }
                .buttonStyle(.plain).pointerCursor()
            }

            Text(suggestion.problem)
                .font(.system(size: 12)).foregroundColor(DS.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if let rewriteBullets = suggestion.rewriteBullets, !rewriteBullets.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(rewriteBullets.enumerated()), id: \.offset) { _, bullet in
                        HStack(alignment: .top, spacing: 6) {
                            Text("•")
                                .font(.system(size: 11)).foregroundColor(DS.Colors.textTertiary)
                            Text(bullet)
                                .font(.system(size: 11)).foregroundColor(DS.Colors.textSecondary)
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
        .padding(12).frame(maxWidth: .infinity, alignment: .leading).background(cardBackground).overlay(cardOverlay)
    }

    // MARK: - Guide

    private var guideTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(guideEntries) { guideEntry in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: guideEntry.symbol)
                            .font(.system(size: 12, weight: .medium)).foregroundColor(DS.Colors.blue400)
                            .frame(width: 18)
                        Text(guideEntry.title)
                            .font(.system(size: 13, weight: .semibold)).foregroundColor(DS.Colors.textPrimary)
                        Spacer(minLength: 0)
                    }
                    Text(guideEntry.body)
                        .font(.system(size: 12)).foregroundColor(DS.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true).padding(.leading, 26)
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading).background(cardBackground)
                .overlay(cardOverlay)
            }

            HStack(spacing: 10) {
                Button("Open the coach panel") {
                    coach.openCoachPanel()
                }
                .buttonStyle(DSSecondaryButtonStyle(isFullWidth: false))

                Button("Close the dashboard") {
                    onClose()
                }
                .buttonStyle(DSSecondaryButtonStyle(isFullWidth: false))

                Spacer(minLength: 0)
            }
        }
    }

    private var guideEntries: [LyceumDashboardGuideEntry] {
        [
            LyceumDashboardGuideEntry(
                title: "The key does four things",
                symbol: "keyboard",
                body: "Press and release control + option to start a run, and again to stop it. Hold it down instead, when the room is not waiting, to ask The Lyceum something. Hold it while the room is waiting to record your answer, and release to send it. Tap it while the room is waiting, and you pass the question."
            ),
            LyceumDashboardGuideEntry(
                title: "A run can end itself",
                symbol: "stop.circle",
                body: "If a farewell slide appears, or the recogniser hears closing words in any language and then the room goes quiet, the run ends on its own. The Runs list says who ended it: you, the slide, or the words."
            ),
            LyceumDashboardGuideEntry(
                title: "The defence score is a different number",
                symbol: "shield.lefthalf.filled",
                body: "After a graded run the room asks, out loud, one question per seat. That score is how well the talk held up under those questions, not how well the talk read. A nine with the room off is not comparable to a nine with it on, so the two are shown separately everywhere."
            ),
            LyceumDashboardGuideEntry(
                title: "What the camera does, and does not do",
                symbol: "video",
                body: "Only if you turn it on: one small still every few seconds, sent with the slides for one grading request, kept in memory until the grade is written and then dropped. Never on disk, never in the saved run, never used to judge anything about how you look. With it off, the delivery notes are written from the microphone and the transcript alone."
            ),
            LyceumDashboardGuideEntry(
                title: "Three permissions before the first good run",
                symbol: "hand.raised",
                body: "Microphone so a run has words, Screen Recording so the app can see the slides and a browser tab title, and Speech recognition if the on-device recogniser is not enough for your language. Camera is a fourth, and only matters with stills on. The gear at the foot of this sidebar opens Settings, and its Rules section has the buttons for each one."
            ),
            LyceumDashboardGuideEntry(
                title: "Reading the trend honestly",
                symbol: "chart.xyaxis.line",
                body: "One number per run: the run's own score lines averaged, with the defence score counted as one more. It is arithmetic over what the model already wrote, so a run never changes grade by being looked at twice, and you can point at the number when you disagree with it."
            )
        ]
    }

    // MARK: - Shared pieces

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold)).foregroundColor(DS.Colors.textTertiary).textCase(.uppercase)
    }

    private func bulletSection(title: String, symbol: String, color: Color, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(title)
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                bulletLine(item, symbol: symbol, color: color)
            }
        }
    }

    private func bulletLine(_ text: String, symbol: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 11)).foregroundColor(color).frame(width: 14)
            Text(text)
                .font(.system(size: 12)).foregroundColor(DS.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func labelledLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .semibold)).foregroundColor(DS.Colors.textTertiary)
                .frame(width: 96, alignment: .leading)
            Text(value)
                .font(.system(size: 12)).foregroundColor(DS.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func labelledBar(fraction: Double, color: Color) -> some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Color.white.opacity(0.08))
            Capsule()
                .fill(color).frame(width: max(2, Self.barTrackWidth * CGFloat(min(1, max(0, fraction)))))
        }
        .frame(width: Self.barTrackWidth, height: 6)
    }

    private func scoreRowView(_ scoreRow: LyceumScore) -> some View {
        HStack(spacing: 10) {
            Text(scoreRow.label)
                .font(.system(size: 11, weight: .medium)).foregroundColor(DS.Colors.textPrimary)
                .frame(width: 160, alignment: .leading).lineLimit(2).fixedSize(horizontal: false, vertical: true)

            labelledBar(fraction: Double(scoreRow.value) / 10.0, color: scoreColor(Double(scoreRow.value)))

            Text("\(scoreRow.value)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(DS.Colors.textSecondary).frame(width: 24, alignment: .trailing)
        }
    }

    private func problemCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "xmark.octagon.fill")
                    .font(.system(size: 12)).foregroundColor(DS.Colors.destructiveText)
                Text("The last thing that went wrong")
                    .font(.system(size: 12, weight: .semibold)).foregroundColor(DS.Colors.destructiveText)
                Spacer(minLength: 0)
            }
            Text(message)
                .font(.system(size: 12)).foregroundColor(DS.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading).background(
            RoundedRectangle(cornerRadius: DS.CornerRadius.large, style: .continuous)
                .fill(DS.Colors.destructive.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.CornerRadius.large, style: .continuous)
                .stroke(DS.Colors.destructive.opacity(0.30), lineWidth: 0.5)
        )
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: DS.CornerRadius.large, style: .continuous)
            .fill(DS.Colors.surface2)
    }

    private var cardOverlay: some View {
        RoundedRectangle(cornerRadius: DS.CornerRadius.large, style: .continuous)
            .stroke(DS.Colors.borderSubtle, lineWidth: 0.5)
    }

    // MARK: - Status and numbers

    private var statusColor: Color {
        switch coach.phase {
        case .idle: return DS.Colors.textTertiary
        case .preparing: return DS.Colors.warning
        case .recording: return DS.Colors.destructiveText
        case .analysing: return DS.Colors.blue400
        case .ready: return DS.Colors.success
        case .failed: return DS.Colors.destructiveText
        }
    }

    private var statusLabel: String {
        switch coach.phase {
        case .idle: return "ready"
        case .preparing: return "opening mic"
        case .recording: return coach.selectedMode.sessionWord
        case .analysing: return "grading"
        case .ready: return "report"
        case .failed: return "failed"
        }
    }

    private func phaseLabel(_ phase: LyceumSessionPhase) -> String {
        switch phase {
        case .idle: return "Ready when you are"
        case .preparing: return "Opening the microphone"
        case .recording: return "Run in progress"
        case .analysing: return "Grading the run"
        case .ready: return "Last run graded"
        case .failed(let failureMessage): return "That run did not make it: \(failureMessage)"
        }
    }

    /// The same average the trend line uses, so the number under a row and the
    /// point on the chart are one number and not two.
    private func averageScore(for savedSession: LyceumSavedSession) -> Double? {
        var values = savedSession.report.scoreRows.map { Double($0.value) }
        if let defenseScore = savedSession.report.defenseScore {
            values.append(Double(defenseScore.value))
        }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private func averageScoreText(for savedSession: LyceumSavedSession) -> String {
        guard let average = averageScore(for: savedSession) else { return "—" }
        return String(format: "%.1f", average)
    }

    private func scoreColor(_ value: Double?) -> Color {
        guard let value else { return DS.Colors.textTertiary }
        if value >= 8 { return DS.Colors.success }
        if value >= 5 { return DS.Colors.blue400 }
        return DS.Colors.warning
    }

    private func formatClock(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    private func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date)
    }

    private func shortTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func copyToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

// MARK: - Chart and list rows

/// One bar's worth of information. A struct rather than a tuple because the chart
/// wants something Identifiable to walk.
private struct LyceumDashboardBar: Identifiable {
    let label: String
    /// Height as a share of the busiest day, already normalised.
    let fraction: CGFloat
    let detail: String

    var id: String { label + detail }
}

/// One answer in the guide.
private struct LyceumDashboardGuideEntry: Identifiable {
    let title: String
    let symbol: String
    let body: String

    var id: String { title }
}

/// A line over an ordered series, drawn as one path. Points are spaced by order
/// rather than by date on purpose: a fortnight with nothing in it should not
/// stretch the line and hide the change that did happen.
private struct LyceumDashboardSparkline: View {
    /// Already normalised to nought through one.
    let values: [Double]
    let color: Color
    let showsGridLines: Bool

    private static let edgeInset: CGFloat = 4
    private static let dotDiameter: CGFloat = 6

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if showsGridLines {
                    gridLines(in: geometry.size)
                        .stroke(DS.Colors.borderSubtle, lineWidth: 0.5)
                }

                if values.count >= 2 {
                    linePath(in: geometry.size)
                        .stroke(color, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))

                    Circle()
                        .fill(color).frame(width: Self.dotDiameter, height: Self.dotDiameter)
                        .position(point(at: values.count - 1, in: geometry.size))
                } else if values.count == 1 {
                    Circle()
                        .fill(color).frame(width: Self.dotDiameter, height: Self.dotDiameter)
                        .position(point(at: 0, in: geometry.size))
                }
            }
        }
    }

    private func point(at index: Int, in size: CGSize) -> CGPoint {
        let usableWidth = max(1, size.width - Self.edgeInset * 2)
        let usableHeight = max(1, size.height - Self.edgeInset * 2)
        let horizontal: CGFloat
        if values.count > 1 {
            horizontal = Self.edgeInset + usableWidth * CGFloat(index) / CGFloat(values.count - 1)
        } else {
            horizontal = size.width / 2
        }
        let clamped = min(1.0, max(0.0, values[index]))
        let vertical = Self.edgeInset + usableHeight * (1 - CGFloat(clamped))
        return CGPoint(x: horizontal, y: vertical)
    }

    private func linePath(in size: CGSize) -> Path {
        var path = Path()
        for index in 0..<values.count {
            let point = point(at: index, in: size)
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        return path
    }

    private func gridLines(in size: CGSize) -> Path {
        var path = Path()
        // Nought, five and ten on a nought-to-ten score axis.
        for level in [0.0, 0.5, 1.0] {
            let usableHeight = max(1, size.height - Self.edgeInset * 2)
            let y = Self.edgeInset + usableHeight * (1 - CGFloat(level))
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
        }
        return path
    }
}

/// The rhythm of a term: how many days have a run in them at all.
private struct LyceumDashboardBarChart: View {
    let bars: [LyceumDashboardBar]

    private static let minimumBarWidth: CGFloat = 4

    var body: some View {
        GeometryReader { geometry in
            let slotWidth = bars.isEmpty ? geometry.size.width : geometry.size.width / CGFloat(bars.count)
            let barWidth = max(Self.minimumBarWidth, slotWidth - 4)

            HStack(alignment: .bottom, spacing: max(1, slotWidth - barWidth)) {
                ForEach(Array(bars.enumerated()), id: \.offset) { _, bar in
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(bar.fraction > 0 ? DS.Colors.blue500.opacity(0.85) : DS.Colors.borderSubtle.opacity(0.6))
                            .frame(
                                width: barWidth,
                                height: max(2, geometry.size.height * min(1.0, bar.fraction))
                            )
                    }
                    .frame(width: slotWidth).help("\(bar.label): \(bar.detail)")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }
}

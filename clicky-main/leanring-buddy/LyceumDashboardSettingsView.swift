//
//  LyceumDashboardSettingsView.swift
//  leanring-buddy
//
//  Everything behind the dashboard's gear. What used to be three tabs — Voice
//  & camera, Room, Rules — is configuration, not practice, so it moved here
//  verbatim: same bindings, same wording, same cards. Data, Appearance and
//  Getting started are new, and they use only APIs that exist on disk:
//  LyceumSessionStore for the folder, the coach managers' own @Published
//  settings, LyceumProfileStore and LyceumAgentStudioView from their files.
//
//  Layout notes: the sheet is a fixed 760x560 with a rail on the left and a
//  scrollable column on the right, deliberately the same shell as the
//  dashboard at half the size. The shared drawing helpers below (sectionLabel,
//  bulletLine, labelledBar, the card chrome, shortDate) are a second copy
//  because the originals are private to the dashboard's own struct; the
//  helpers only the moved tabs used — toggleRow, measuredTable, measuredRows,
//  shownDelivery, openPrivacyPane, audienceStatusLine and the row struct —
//  came across for real, and no longer exist in the dashboard.
//

import AppKit
import SwiftUI

struct LyceumDashboardSettingsView: View {
    /// The six places configuration can be looked at from.
    /// Raw values double as analytics section names, so a case renamed here shows up as
    /// a renamed bucket there instead of silently breaking a `section.rawValue` call.
    enum SettingsSection: String, CaseIterable, Identifiable {
        case voice
        case room
        case rules
        case data
        case appearance
        case gettingStarted

        var id: SettingsSection { self }

        var title: String {
            switch self {
            case .voice: return "Voice & camera"
            case .room: return "Room"
            case .rules: return "Rules"
            case .data: return "Data"
            case .appearance: return "Appearance"
            case .gettingStarted: return "Getting started"
            }
        }

        var symbol: String {
            switch self {
            case .voice: return "waveform"
            case .room: return "person.3.fill"
            case .rules: return "slider.horizontal.below.rectangle"
            case .data: return "externaldrive"
            case .appearance: return "circle.lefthalf.filled"
            case .gettingStarted: return "sparkles"
            }
        }

        var subtitle: String {
            switch self {
            case .voice: return "What the microphone measures, and what the camera may see."
            case .room: return "Who asks, how they ask, and what they asked."
            case .rules: return "When a run is allowed to start, and what it may use."
            case .data: return "The saved runs, the folder they live in, and what leaves it."
            case .appearance: return "Light, dark, or the system's own choice."
            case .gettingStarted: return "The learner profile, and the first run start to finish."
            }
        }
    }

    @ObservedObject var coach: LyceumCoachManager
    @ObservedObject var audience: LyceumAudienceManager
    @ObservedObject var gate: LyceumAppGate
    @ObservedObject var companion: CompanionManager

    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var appearance = LyceumAppearanceController.shared
    @ObservedObject private var profileStore = LyceumProfileStore.shared

    private static let railWidth: CGFloat = 176
    private static let barTrackWidth: CGFloat = 150

    /// A literal list rather than a fetched one: nothing here may need the network
    /// just to say which model the next run will use.
    private static let modelChoices: [String] = [
        "claude-sonnet-4-6",
        "claude-opus-4-7",
        "claude-opus-4-8"
    ]

    @State private var selection: SettingsSection = .voice
    /// The voice and data cards read the same shelf the dashboard reads, so
    /// this sheet loads it itself on appear rather than trusting a copy.
    @State private var sessions: [LyceumSavedSession] = []
    @State private var summary: LyceumPracticeSummary = .empty
    @State private var folderSizeText = "counting…"
    /// 30 / 90 / 0 (= everything) days for the bulk delete.
    @State private var deleteAgeDays = 30
    /// Set by the delete button; the confirm strip is drawn inline, the same
    /// way the Runs tab handles a single deletion.
    @State private var pendingBulkDeleteDays: Int?
    @State private var dataStatusMessage: String?
    @State private var isStudioOpen = false
    @State private var didRestartOnboarding = false

    init(coach: LyceumCoachManager,
         audience: LyceumAudienceManager,
         gate: LyceumAppGate,
         companion: CompanionManager) {
        self.coach = coach
        self.audience = audience
        self.gate = gate
        self.companion = companion
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(DS.Colors.borderSubtle)

            HStack(spacing: 0) {
                rail
                Divider().background(DS.Colors.borderSubtle)
                content
            }
        }
        .frame(width: 760, height: 560)
        .background(DS.Colors.background)
        .lyceumColorScheme(appearance.colorScheme)
        .onChange(of: selection) { section in
            ClickyAnalytics.trackLyceumSettingsOpened(section: section.rawValue)
        }
        .onAppear {
            reloadData()
            measureDataFolder()
        }
    }

    // MARK: - Shell

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Settings")
                    .font(.system(size: 14, weight: .semibold)).foregroundColor(DS.Colors.textPrimary)
                Text("Everything that configures a run, kept out of the tabs you practise in.")
                    .font(.system(size: 11)).foregroundColor(DS.Colors.textTertiary)
            }

            Spacer()

            Button(action: {
                dismiss()
            }) {
                Text("Close")
                    .font(.system(size: 11, weight: .medium)).foregroundColor(DS.Colors.textSecondary)
                    .padding(.horizontal, 10).padding(.vertical, 6).background(
                        RoundedRectangle(cornerRadius: DS.CornerRadius.small, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
            }
            .buttonStyle(.plain).pointerCursor().help("Close settings")
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    private var rail: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("This app")
                .font(.system(size: 10, weight: .medium)).foregroundColor(DS.Colors.textTertiary)
                .textCase(.uppercase)
                .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 8)

            ForEach(SettingsSection.allCases) { section in
                railRow(for: section)
            }

            Spacer(minLength: 0)
        }
        .frame(width: Self.railWidth).frame(maxHeight: .infinity).background(DS.Colors.surface1)
    }

    private func railRow(for section: SettingsSection) -> some View {
        let isSelected = selection == section
        return Button(action: {
            selection = section
        }) {
            HStack(spacing: 8) {
                Image(systemName: section.symbol)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isSelected ? DS.Colors.blue400 : DS.Colors.textTertiary).frame(width: 16)
                Text(section.title)
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

    @ViewBuilder
    private var content: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 16) {
                Text(selection.subtitle)
                    .font(.system(size: 11)).foregroundColor(DS.Colors.textTertiary)

                switch selection {
                case .voice:
                    voiceTab
                case .room:
                    roomTab
                case .rules:
                    rulesTab
                case .data:
                    dataSection
                case .appearance:
                    appearanceSection
                case .gettingStarted:
                    gettingStartedSection
                }
            }
            .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Data

    /// The shelf the runs live on, counted and weighed, with the three things a
    /// student actually wants to do to it: look at it, take it with them, empty
    /// it. Sizes are measured off the main thread with a depth cap because a
    /// settings sheet must never stall on someone's ten-thousand-file folder.
    private var dataSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "externaldrive")
                        .font(.system(size: 12)).foregroundColor(DS.Colors.blue400)
                    Text("Saved runs")
                        .font(.system(size: 13, weight: .semibold)).foregroundColor(DS.Colors.textPrimary)
                    Spacer()
                    Text("\(sessions.count) of \(LyceumSessionStore.maximumSessionsOnDisk) kept")
                        .font(.system(size: 10, design: .monospaced)).foregroundColor(DS.Colors.textTertiary)
                }

                if summary.hasAnything {
                    Text("\(summary.totalRuns) graded run(s), \(String(format: "%.0f", summary.minutesPractised)) minutes of speech"
                         + (summary.runsWithCameraStills > 0
                            ? ". \(summary.runsWithCameraStills) were graded with camera stills attached; the stills themselves were never written to disk."
                            : ". No camera stills went into any saved run."))
                        .font(.system(size: 11)).foregroundColor(DS.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Nothing saved yet. A run lands on the shelf the moment it is graded.")
                        .font(.system(size: 11)).foregroundColor(DS.Colors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if coach.presenceFrameCount > 0 {
                    Text("This live run has taken \(coach.presenceFrameCount) camera still(s). They stay in memory until the grade is written, then are dropped.")
                        .font(.system(size: 10)).foregroundColor(DS.Colors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(LyceumSessionStore.sessionsDirectory().path)
                        .font(.system(size: 10, design: .monospaced)).foregroundColor(DS.Colors.codeText)
                        .lineLimit(2).textSelection(.enabled)
                    Text("\(folderSizeText) on disk")
                        .font(.system(size: 10)).foregroundColor(DS.Colors.textTertiary)
                }

                HStack(spacing: 8) {
                    Button("Open folder") {
                        NSWorkspace.shared.open(LyceumSessionStore.sessionsDirectory())
                    }
                    .buttonStyle(.bordered)
                    .help("Reveals the Sessions folder in Finder")

                    Button("Export all as JSON") {
                        exportAllSessions()
                    }
                    .buttonStyle(.bordered)
                    .disabled(sessions.isEmpty)
                    .help("One JSON file holding every saved run, in the store's own format")
                }

                if let dataStatusMessage {
                    Text(dataStatusMessage)
                        .font(.system(size: 11)).foregroundColor(DS.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14).background(cardBackground).overlay(cardOverlay)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "trash")
                        .font(.system(size: 12)).foregroundColor(DS.Colors.destructiveText)
                    Text("Clear out old runs")
                        .font(.system(size: 13, weight: .semibold)).foregroundColor(DS.Colors.textPrimary)
                    Spacer(minLength: 0)
                }

                HStack(spacing: 10) {
                    Text("Delete runs older than")
                        .font(.system(size: 12, weight: .medium)).foregroundColor(DS.Colors.textSecondary)
                    Spacer()
                    Picker("", selection: $deleteAgeDays) {
                        Text("30 days").tag(30)
                        Text("90 days").tag(90)
                        Text("everything").tag(0)
                    }
                    .labelsHidden().frame(width: 130)
                }

                let doomedCount = doomedSessions(for: deleteAgeDays).count

                Button(action: {
                    pendingBulkDeleteDays = deleteAgeDays
                }) {
                    Text(doomedCount == 0 ? "Nothing older than that" : "Delete \(doomedCount) run(s)")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).disabled(doomedCount == 0)

                if let pendingBulkDeleteDays {
                    Divider().background(DS.Colors.borderSubtle)

                    Text(pendingBulkDeleteDays == 0
                         ? "This removes every saved run: \(doomedSessions(for: 0).count) transcript(s), report(s) and all. There is no undo, and the trend starts again from nothing."
                         : "This removes the \(doomedSessions(for: pendingBulkDeleteDays).count) saved run(s) older than \(pendingBulkDeleteDays) days. There is no undo; the trend rebuilds from whatever is left.")
                        .font(.system(size: 11)).foregroundColor(DS.Colors.destructiveText)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        Button("Delete them now") {
                            runBulkDelete(for: pendingBulkDeleteDays)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(DS.Colors.destructive)

                        Button("Keep them") {
                            self.pendingBulkDeleteDays = nil
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(14).background(cardBackground).overlay(
                RoundedRectangle(cornerRadius: DS.CornerRadius.large, style: .continuous)
                    .stroke(DS.Colors.destructive.opacity(0.25), lineWidth: 0.5)
            )
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                sectionLabel("Mode")

                HStack(spacing: 8) {
                    ForEach(LyceumAppearanceMode.allCases) { mode in
                        appearanceModeButton(mode)
                    }
                }

                Text(appearance.mode.brief)
                    .font(.system(size: 10)).foregroundColor(DS.Colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider().background(DS.Colors.borderSubtle)

                toggleRow(
                    title: "Reduce motion",
                    detail: "The app starts from the macOS accessibility setting and you can override it here. Views that animate fade instead of sliding while it is on.",
                    isOn: Binding(
                        get: { appearance.reduceMotion },
                        set: { appearance.reduceMotion = $0 }
                    )
                )
            }
            .padding(14).background(cardBackground).overlay(cardOverlay)
        }
    }

    private func appearanceModeButton(_ mode: LyceumAppearanceMode) -> some View {
        let isSelected = appearance.mode == mode
        return Button(action: {
            appearance.mode = mode
        }) {
            HStack(spacing: 6) {
                Image(systemName: mode.symbol)
                    .font(.system(size: 11))
                    .foregroundColor(isSelected ? DS.Colors.blue400 : DS.Colors.textTertiary)
                Text(mode.displayName)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? DS.Colors.textPrimary : DS.Colors.textSecondary)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .semibold)).foregroundColor(DS.Colors.blue400)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 10).background(
                RoundedRectangle(cornerRadius: DS.CornerRadius.small, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.08) : Color.white.opacity(0.03))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).pointerCursor()
        .frame(maxWidth: .infinity)
        .help(mode.brief)
    }

    // MARK: - Getting started

    private var gettingStartedSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "person.text.rectangle")
                        .font(.system(size: 12)).foregroundColor(DS.Colors.blue400)
                    Text("Your learner profile")
                        .font(.system(size: 13, weight: .semibold)).foregroundColor(DS.Colors.textPrimary)
                    Spacer(minLength: 0)
                }

                if profileStore.hasCompletedOnboarding {
                    Text(profileStore.contextLineForModel)
                        .font(.system(size: 11, design: .monospaced)).foregroundColor(DS.Colors.codeText)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Onboarding is not marked as finished, so the coach is grading without a learner profile line.")
                        .font(.system(size: 11)).foregroundColor(DS.Colors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button("Run onboarding again") {
                    profileStore.restartOnboarding()
                    didRestartOnboarding = true
                }
                .buttonStyle(.bordered)
                .help("Clears the done flag; the next Lyceum window starts at welcome")

                if didRestartOnboarding {
                    Text("Done. The next Lyceum window this app opens starts at welcome. Nothing saved was touched.")
                        .font(.system(size: 10)).foregroundColor(DS.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14).background(cardBackground).overlay(cardOverlay)

            VStack(alignment: .leading, spacing: 10) {
                sectionLabel("From install to first grade")
                bulletLine("Allow microphone, screen recording and speech recognition when macOS asks — the Rules section here has the buttons again.", symbol: "hand.raised", color: DS.Colors.textTertiary)
                bulletLine("Answer onboarding: what grade you are in, who you present to, and whether it is a competition.", symbol: "list.bullet", color: DS.Colors.textTertiary)
                bulletLine("Sit the five agents, or leave the defaults — the Room section here opens the studio.", symbol: "person.3", color: DS.Colors.textTertiary)
                bulletLine("Hold the deck in front of you, tap control + option, talk, tap again. The grade lands in the dashboard's Runs tab.", symbol: "keyboard", color: DS.Colors.textTertiary)
            }
            .padding(14).background(cardBackground).overlay(cardOverlay)
        }
    }

    // MARK: - Agent studio

    /// The studio is where the five agents' functions, traits and focus get
    /// chosen; this sheet only opens it. The studio writes into the same
    /// roster the seat list above shows — one list, two editors.
    private var agentStudioCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12)).foregroundColor(DS.Colors.blue400)
                Text("Agent studio")
                    .font(.system(size: 13, weight: .semibold)).foregroundColor(DS.Colors.textPrimary)
                Spacer()
                Button(action: {
                    withAnimation(appearance.reduceMotion ? nil : .easeInOut(duration: DS.Animation.fast)) {
                        isStudioOpen.toggle()
                    }
                }) {
                    Text(isStudioOpen ? "Close the studio" : "Open the studio")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(DS.Colors.textSecondary)
                        .padding(.horizontal, 10).padding(.vertical, 6).background(
                            RoundedRectangle(cornerRadius: DS.CornerRadius.small, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                        )
                }
                .buttonStyle(.plain).pointerCursor()
                .help("Name, tone and up to five criteria for each of the five agents")
            }

            Text("Each agent gets a name, a tone and at most five criteria: what it does, how it behaves, what it weighs. The seats above stay in sync.")
                .font(.system(size: 10)).foregroundColor(DS.Colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            if isStudioOpen {
                LyceumAgentStudioView(audience: audience, onClose: {
                    isStudioOpen = false
                })
            }
        }
        .padding(14).background(cardBackground).overlay(cardOverlay)
    }

    // MARK: - Plumbing

    private func reloadData() {
        sessions = coach.loadAllSavedSessions()
        summary = LyceumInsights.summarize(sessions)
    }

    /// 0 days means everything: "older than nothing" is the whole shelf.
    private func doomedSessions(for days: Int) -> [LyceumSavedSession] {
        guard days > 0 else { return sessions }
        let cutoff = Date().addingTimeInterval(-TimeInterval(days) * 86_400)
        return sessions.filter { $0.startedAt < cutoff }
    }

    private func runBulkDelete(for days: Int) {
        let doomed = doomedSessions(for: days)
        for savedSession in doomed {
            LyceumSessionStore.delete(savedSession.sessionID)
        }
        coach.reloadRecentSessions()
        reloadData()
        measureDataFolder()
        pendingBulkDeleteDays = nil
        dataStatusMessage = "Removed \(doomed.count) saved run(s). The trend is rebuilt from whatever is left."
    }

    /// There is no whole-shelf export in the model files, so it is written
    /// here, against the same Codable types and the same encoder settings the
    /// store itself writes with — the file out reloads exactly like the files
    /// in. One run at a time still goes through LyceumReportExporter.
    private func exportAllSessions() {
        let allSessions = coach.loadAllSavedSessions()
        guard !allSessions.isEmpty else {
            dataStatusMessage = "Nothing is saved, so there is nothing to export."
            return
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(allSessions) else {
            dataStatusMessage = "The saved runs could not be encoded. Export single runs from the Runs tab instead."
            return
        }

        let savePanel = NSSavePanel()
        savePanel.allowedFileTypes = ["json"]
        savePanel.nameFieldStringValue = "lyceum-all-runs-\(LyceumSessionStore.fileStamp(for: Date())).json"

        NSApp.activate(ignoringOtherApps: true)
        savePanel.begin { response in
            guard response == .OK, let destinationURL = savePanel.url else { return }
            do {
                try data.write(to: destinationURL)
                dataStatusMessage = "Wrote \(allSessions.count) saved run(s) to \(destinationURL.lastPathComponent)."
            } catch {
                dataStatusMessage = "The export could not be written: \(error.localizedDescription)"
            }
        }
    }

    /// Weighs the Sessions folder without holding the sheet open: a capped
    /// walk on a background queue, one label back on the main one.
    private func measureDataFolder() {
        let directory = LyceumSessionStore.sessionsDirectory()
        folderSizeText = "counting…"
        DispatchQueue.global(qos: .utility).async {
            let byteCount = Self.directoryByteCount(of: directory, maxDepth: 3, maxEntries: 2_000)
            DispatchQueue.main.async {
                folderSizeText = Self.formatBytes(byteCount)
            }
        }
    }

    private static func directoryByteCount(of url: URL, maxDepth: Int, maxEntries: Int) -> Int64 {
        let fileManager = FileManager.default
        let baseDepth = url.pathComponents.count
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total: Int64 = 0
        var walked = 0
        for case let fileURL as URL in enumerator {
            if fileURL.pathComponents.count - baseDepth > maxDepth {
                enumerator.skipDescendants()
                continue
            }
            walked += 1
            if walked > maxEntries { break }
            let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey])
            total += Int64(values?.fileSize ?? 0)
        }
        return total
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    // MARK: - Moved out of the dashboard

    /// The measurement this window shows: the run that just finished if there is
    /// one, otherwise the newest saved run that has any.
    private var shownDelivery: LyceumDeliveryStats? {
        if let lastDeliveryStats = coach.lastDeliveryStats { return lastDeliveryStats }
        return summary.mostRecent?.delivery
    }

    // MARK: - Voice and camera

    private var voiceTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                toggleRow(
                    title: "Measure the voice",
                    detail: "This switch does not ask a model anything. It turns the microphone you already allowed into numbers: how long you were audible, how loud each minute was, how far the pitch moved, how many filler words the transcript kept. The arithmetic costs nothing and happens on this machine.",
                    isOn: Binding(
                        get: { coach.measuresDelivery },
                        set: { coach.measuresDelivery = $0 }
                    )
                )

                Divider().background(DS.Colors.borderSubtle)

                toggleRow(
                    title: "See the presenter",
                    detail: "Off by default, and off until you turn it on. When it is on, the app takes one still from your own front camera every few seconds: stills, not video, so there is no recording that could leak. Each still is made small, about 512 pixels on the long edge, goes to the model with the slides for that one grading request, is never written to disk, is never attached to the saved run, and is dropped the moment grading finishes. Switching it off discards whatever it had already taken.",
                    isOn: Binding(
                        get: { coach.isPresenceCameraEnabled },
                        set: { coach.isPresenceCameraEnabled = $0 }
                    )
                )

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("One still every")
                            .font(.system(size: 12, weight: .medium)).foregroundColor(DS.Colors.textSecondary)
                        Spacer()
                        Text("\(Int(coach.cameraIntervalSeconds.rounded())) s")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(DS.Colors.blue400)
                    }

                    Slider(
                        value: Binding(
                            get: { coach.cameraIntervalSeconds },
                            set: { coach.cameraIntervalSeconds = $0 }
                        ),
                        in: 5...60,
                        step: 1
                    )
                    .tint(DS.Colors.accent).disabled(!coach.isPresenceCameraEnabled)

                    Text("roughly \(Int(600 / max(1, coach.cameraIntervalSeconds))) stills for a ten-minute run")
                        .font(.system(size: 10)).foregroundColor(DS.Colors.textTertiary)
                }

                Text("A still can show where you were facing, and whether anything changed across the talk. It cannot show emphasis, intent or feeling, and the app will not pretend otherwise.")
                    .font(.system(size: 11)).foregroundColor(DS.Colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14).background(cardBackground).overlay(cardOverlay)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    sectionLabel("Last measurement")
                    Spacer()
                    if let recentSession = summary.mostRecent, recentSession.delivery != nil {
                        Text("\(recentSession.mode) · \(shortDate(recentSession.startedAt))")
                            .font(.system(size: 10, design: .monospaced)).foregroundColor(DS.Colors.textTertiary)
                    }
                }

                if let delivery = shownDelivery {
                    Text(delivery.summaryLine)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(DS.Colors.codeText).fixedSize(horizontal: false, vertical: true)

                    measuredTable(delivery)

                    if !delivery.fillers.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            sectionLabel("Filler words counted")
                            ForEach(Array(delivery.fillers.enumerated()), id: \.offset) { _, filler in
                                HStack(spacing: 8) {
                                    Text(filler.word)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(DS.Colors.textPrimary).frame(width: 110, alignment: .leading)
                                        .lineLimit(1)

                                    labelledBar(
                                        fraction: Double(filler.count) / Double(max(1, delivery.fillers.map { $0.count }.max() ?? 1)),
                                        color: DS.Colors.warning
                                    )

                                    Text("\(filler.count)")
                                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                        .foregroundColor(DS.Colors.textSecondary)
                                        .frame(width: 28, alignment: .trailing)

                                    Text(filler.language)
                                        .font(.system(size: 10)).foregroundColor(DS.Colors.textTertiary)
                                        .frame(width: 44, alignment: .leading)
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        sectionLabel("In plain words")
                        // Asked here, in the view, because the reading is main-actor work.
                        ForEach(Array(LyceumDeliveryMeter.plainReading(of: delivery).enumerated()), id: \.offset) { _, readingLine in
                            bulletLine(readingLine, symbol: "ruler", color: DS.Colors.textTertiary)
                        }
                    }

                    Text("Measuring tape readings. A flat variety index is something to check, not a verdict about you.")
                        .font(.system(size: 10)).foregroundColor(DS.Colors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Nothing measured yet. Start a run with the switch above on and the numbers appear here before the model has been asked anything.")
                        .font(.system(size: 12)).foregroundColor(DS.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if summary.runsWithCameraStills > 0 {
                    Divider().background(DS.Colors.borderSubtle)
                    Text("\(summary.runsWithCameraStills) of \(summary.totalRuns) saved runs were graded with camera stills attached. Only the count of stills is kept; the images are not on disk.")
                        .font(.system(size: 10)).foregroundColor(DS.Colors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14).background(cardBackground).overlay(cardOverlay)
        }
    }

    private func measuredTable(_ delivery: LyceumDeliveryStats) -> some View {
        VStack(spacing: 2) {
            ForEach(measuredRows(for: delivery)) { measuredRow in
                HStack(spacing: 10) {
                    Text(measuredRow.label)
                        .font(.system(size: 11, weight: .medium)).foregroundColor(DS.Colors.textSecondary)
                        .frame(width: 150, alignment: .leading)
                    Text(measuredRow.value)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(DS.Colors.textPrimary).frame(maxWidth: .infinity, alignment: .leading)
                    Text(measuredRow.note)
                        .font(.system(size: 10)).foregroundColor(DS.Colors.textTertiary)
                        .frame(width: 180, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 10).padding(.vertical, 6).background(
                    RoundedRectangle(cornerRadius: DS.CornerRadius.small, style: .continuous)
                        .fill(Color.white.opacity(0.03))
                )
            }
        }
    }

    /// Row data as structs rather than tuples, because the table needs something
    /// stable for ForEach to walk and a label is stable enough.
    private func measuredRows(for delivery: LyceumDeliveryStats) -> [LyceumDashboardRow] {
        [
            LyceumDashboardRow(label: "Speech in the run", value: "\(Int(delivery.voicedSeconds.rounded())) s", note: "of \(Int(delivery.totalSeconds.rounded())) s recorded"),
            LyceumDashboardRow(label: "Silence", value: "\(delivery.silencePercent) %", note: "slides read, pauses, thinking"),
            LyceumDashboardRow(label: "Pace", value: "\(Int(delivery.wordsPerMinute.rounded())) wpm", note: "over speech time only"),
            LyceumDashboardRow(label: "Words counted", value: "\(delivery.wordCount)", note: "as the recogniser heard them"),
            LyceumDashboardRow(label: "Longest pause", value: "\(String(format: "%.1f", delivery.longestPauseSeconds)) s", note: "one pause, not the total"),
            LyceumDashboardRow(label: "Mean level", value: "\(String(format: "%.1f", delivery.meanLevelDecibels)) dBFS", note: "microphone scale, not room volume"),
            LyceumDashboardRow(label: "Level range", value: "\(String(format: "%.1f", delivery.levelRangeDecibels)) dB", note: "loudest minute minus quietest"),
            LyceumDashboardRow(label: "Pitch proxy", value: "\(Int(delivery.pitchProxyHertz.rounded())) Hz", note: "zero-crossing rate, not a note"),
            LyceumDashboardRow(label: "Pitch variety", value: String(format: "%.2f", delivery.pitchVariety), note: "a flat delivery shows here"),
            LyceumDashboardRow(label: "Fillers", value: "\(String(format: "%.1f", delivery.fillerPerMinute)) / min", note: "only words the transcript kept")
        ]
    }

    // MARK: - Room

    private var roomTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            roomSettingsCard
            rosterCard
            roomRoundCard
            agentStudioCard
        }
    }

    private var roomSettingsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "person.3.fill")
                    .font(.system(size: 12)).foregroundColor(DS.Colors.blue400)
                Text("The round")
                    .font(.system(size: 13, weight: .semibold)).foregroundColor(DS.Colors.textPrimary)
                Spacer()
                Text(audienceStatusLine)
                    .font(.system(size: 10, weight: .medium)).foregroundColor(DS.Colors.textTertiary)
            }

            toggleRow(
                title: "Audience asks afterwards",
                detail: "Off means the run ends at the written verdict.",
                isOn: Binding(
                    get: { audience.isPanelEnabled },
                    set: { audience.isPanelEnabled = $0 }
                )
            )

            toggleRow(
                title: "Move on if nobody answers",
                detail: "A question nobody takes is logged as unanswered and the next hand goes up.",
                isOn: Binding(
                    get: { audience.skipsUnansweredPrompts },
                    set: { audience.skipsUnansweredPrompts = $0 }
                )
            )

            toggleRow(
                title: "Mute the room",
                detail: "The questions still arrive, as text on the tiles.",
                isOn: Binding(
                    get: { audience.areAgentsMuted },
                    set: { audience.areAgentsMuted = $0 }
                )
            )

            toggleRow(
                title: "Show captions",
                detail: "The line being spoken, written under the grid.",
                isOn: Binding(
                    get: { audience.areCaptionsShown },
                    set: { audience.areCaptionsShown = $0 }
                )
            )

            Divider().background(DS.Colors.borderSubtle)

            HStack(spacing: 10) {
                Text("Questions per round")
                    .font(.system(size: 12, weight: .medium)).foregroundColor(DS.Colors.textSecondary)
                Spacer()
                Text("\(audience.maximumQuestions)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(DS.Colors.blue400).frame(width: 24, alignment: .trailing)
                Stepper(
                    "",
                    value: Binding(
                        get: { audience.maximumQuestions },
                        set: { audience.maximumQuestions = $0 }
                    ),
                    in: 1...6
                )
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Wait for an answer")
                        .font(.system(size: 12, weight: .medium)).foregroundColor(DS.Colors.textSecondary)
                    Spacer()
                    Text("\(Int(audience.unansweredTimeoutSeconds.rounded())) s")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(DS.Colors.blue400)
                }

                Slider(
                    value: Binding(
                        get: { audience.unansweredTimeoutSeconds },
                        set: { audience.unansweredTimeoutSeconds = $0 }
                    ),
                    in: 15...120,
                    step: 5
                )
                .tint(DS.Colors.accent)

                Text("How long the room stays quiet before it moves on. Someone who has never been asked on purpose needs the long end.")
                    .font(.system(size: 10)).foregroundColor(DS.Colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Button("Open the room") {
                    coach.openRoom()
                }
                .buttonStyle(.bordered)

                Button("Leave the room") {
                    audience.leave()
                }
                .buttonStyle(.bordered)

                Spacer(minLength: 0)

                if audience.isAwaitingUserAnswer {
                    Button("Pass this question") {
                        audience.skipCurrentQuestion()
                    }
                    .buttonStyle(.bordered)
                }
            }

            if let audienceError = audience.errorMessage, !audienceError.isEmpty {
                Text(audienceError)
                    .font(.system(size: 11)).foregroundColor(DS.Colors.destructiveText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14).background(cardBackground).overlay(cardOverlay)
    }

    private var rosterCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("The seats")
                    .font(.system(size: 13, weight: .semibold)).foregroundColor(DS.Colors.textPrimary)
                Spacer()
                Text("\(audience.members.count) of \(LyceumAudienceRoster.maximumMembers)")
                    .font(.system(size: 10, design: .monospaced)).foregroundColor(DS.Colors.textTertiary)
            }

            Text("A persona is one sentence about what this person cares about. That sentence is what the questions are built from, so it is worth editing.")
                .font(.system(size: 10)).foregroundColor(DS.Colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            // Bindings straight into the roster, the way the room's own popover does
            // it, so both editors write to one list.
            ForEach($audience.members) { $member in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: member.avatarSymbol)
                            .font(.system(size: 11)).foregroundColor(DS.Colors.textSecondary)
                            .frame(width: 24, height: 24).background(Circle().fill(DS.Colors.surface3))

                        Text(member.initials)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(DS.Colors.textTertiary)

                        TextField("Name", text: $member.name)
                            .textFieldStyle(.plain).font(.system(size: 12, weight: .medium))
                            .foregroundColor(DS.Colors.textPrimary)

                        Spacer(minLength: 4)

                        Picker("", selection: $member.tone) {
                            ForEach(LyceumAudienceTone.allCases, id: \.self) { tone in
                                Text(tone.displayName).tag(tone)
                            }
                        }
                        .labelsHidden().frame(width: 96)

                        Button(action: {
                            audience.members.removeAll { $0.id == member.id }
                        }) {
                            Image(systemName: "minus.circle")
                                .font(.system(size: 11)).foregroundColor(DS.Colors.destructiveText)
                        }
                        .buttonStyle(.plain).pointerCursor()
                        .disabled(audience.members.count <= LyceumAudienceRoster.minimumMembers)
                        .help("Remove this seat")
                    }

                    TextField("Role, e.g. Head of Research", text: $member.role)
                        .textFieldStyle(.plain).font(.system(size: 11)).foregroundColor(DS.Colors.textSecondary)

                    TextField("What they care about", text: $member.persona)
                        .textFieldStyle(.plain).font(.system(size: 11)).foregroundColor(DS.Colors.textTertiary)
                        .lineLimit(2, reservesSpace: true)

                    HStack(spacing: 6) {
                        Image(systemName: "waveform")
                            .font(.system(size: 9)).foregroundColor(DS.Colors.textTertiary)
                        TextField("ElevenLabs voice id (optional)", text: Binding(
                            get: { member.elevenLabsVoiceID ?? "" },
                            set: { member.elevenLabsVoiceID = $0.isEmpty ? nil : $0 }
                        ))
                        .textFieldStyle(.plain).font(.system(size: 10, design: .monospaced))
                        .foregroundColor(DS.Colors.codeText)
                        Text(member.hasCustomVoice ? "own voice" : "system voice")
                            .font(.system(size: 9)).foregroundColor(DS.Colors.textTertiary)
                    }
                }
                .padding(10).frame(maxWidth: .infinity, alignment: .leading).background(
                    RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
                        .fill(DS.Colors.surface2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
                        .stroke(DS.Colors.borderSubtle, lineWidth: 0.5)
                )
            }

            HStack(spacing: 8) {
                Button("Add a seat") {
                    audience.addDefaultMember()
                }
                .buttonStyle(.bordered).disabled(audience.members.count >= LyceumAudienceRoster.maximumMembers)

                Button("Reset to the default room") {
                    audience.resetRoster()
                }
                .buttonStyle(.bordered)

                Spacer(minLength: 0)
            }
        }
        .padding(14).background(cardBackground).overlay(cardOverlay)
    }

    private var roomRoundCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Last round")
                    .font(.system(size: 13, weight: .semibold)).foregroundColor(DS.Colors.textPrimary)
                Spacer()
                if let languageCode = audience.spokenLanguageCode {
                    Text("spoken in \(languageCode)")
                        .font(.system(size: 10, design: .monospaced)).foregroundColor(DS.Colors.textTertiary)
                }
            }

            if let defenseScore = audience.defenseScore {
                HStack(spacing: 8) {
                    Text("\(defenseScore.value)/10")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(defenseScore.value >= 7 ? DS.Colors.success : DS.Colors.warningText)
                    Text(defenseScore.label)
                        .font(.system(size: 11)).foregroundColor(DS.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if audience.questions.isEmpty && audience.exchanges.isEmpty {
                Text("No round yet. Finish a run with the room on and this fills in.")
                    .font(.system(size: 11)).foregroundColor(DS.Colors.textTertiary)
            }

            ForEach(audience.exchanges) { exchange in
                exchangeRow(exchange)
            }

            if audience.exchanges.isEmpty {
                ForEach(audience.questions) { question in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Image(systemName: question.kind.symbolName)
                                .font(.system(size: 10)).foregroundColor(DS.Colors.blue400)
                            Text("\(question.memberName) — \(question.kind.displayName)")
                                .font(.system(size: 11, weight: .semibold)).foregroundColor(DS.Colors.textPrimary)
                            Spacer(minLength: 0)
                        }
                        Text(question.question)
                            .font(.system(size: 12)).foregroundColor(DS.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let rootedIn = question.rootedIn, !rootedIn.isEmpty {
                            Text("about \(rootedIn)")
                                .font(.system(size: 10).italic()).foregroundColor(DS.Colors.textTertiary)
                        }
                    }
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading).background(
                        RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
                            .fill(Color.white.opacity(0.04))
                    )
                }
            }

            HStack(spacing: 10) {
                Text("\(audience.answeredCount) answered out loud")
                Spacer()
                Text("\(audience.remainingQuestionCount) still open")
            }
            .font(.system(size: 10)).foregroundColor(DS.Colors.textTertiary)
        }
        .padding(14).background(cardBackground).overlay(cardOverlay)
    }

    private func exchangeRow(_ exchange: LyceumPanelExchange) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(exchange.memberName)
                .font(.system(size: 11, weight: .semibold)).foregroundColor(DS.Colors.textPrimary)

            Text(exchange.question)
                .font(.system(size: 12)).foregroundColor(DS.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let userAnswer = exchange.userAnswer, !userAnswer.isEmpty {
                Text(userAnswer)
                    .font(.system(size: 11)).foregroundColor(DS.Colors.codeText).padding(.leading, 8)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("(no answer given)")
                    .font(.system(size: 10).italic()).foregroundColor(DS.Colors.textTertiary).padding(.leading, 8)
            }

            if let agentReaction = exchange.agentReaction, !agentReaction.isEmpty {
                Text("\(exchange.memberName): \(agentReaction)")
                    .font(.system(size: 10)).foregroundColor(DS.Colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let followUpQuestion = exchange.followUpQuestion, !followUpQuestion.isEmpty {
                Text(followUpQuestion)
                    .font(.system(size: 11, weight: .medium)).foregroundColor(DS.Colors.warningText)
                    .padding(.leading, 8).fixedSize(horizontal: false, vertical: true)

                if let userFollowUpAnswer = exchange.userFollowUpAnswer, !userFollowUpAnswer.isEmpty {
                    Text(userFollowUpAnswer)
                        .font(.system(size: 11)).foregroundColor(DS.Colors.codeText).padding(.leading, 8)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading).background(
            RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }

    private var audienceStatusLine: String {
        switch audience.status {
        case .off: return "no round running"
        case .convening: return "the room is deciding what to ask"
        case .agentSpeaking: return "an agent has the floor"
        case .awaitingUserAnswer: return "waiting for you"
        case .userAnswering: return "you are answering"
        case .roundComplete: return "round over"
        }
    }

    // MARK: - Rules

    private var rulesTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            gateCard

            runRulesCard

            modelCard

            permissionsCard
        }
    }

    private var gateCard: some View {
        let frontmost = gate.latestFrontmost
        let isAllowed = gate.latestDecision.isAllowed
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: isAllowed ? "checkmark.seal.fill" : "seal.slash.fill")
                    .font(.system(size: 12)).foregroundColor(isAllowed ? DS.Colors.success : DS.Colors.warningText)
                Text("The slide tool gate")
                    .font(.system(size: 13, weight: .semibold)).foregroundColor(DS.Colors.textPrimary)
                Spacer()
                Button("Re-check") {
                    _ = gate.evaluateNow()
                }
                .font(.system(size: 11, weight: .medium)).buttonStyle(.bordered)
            }

            HStack(spacing: 8) {
                Text(frontmost.shortDescription.isEmpty ? "Nothing has been looked at yet." : frontmost.shortDescription)
                    .font(.system(size: 11, design: .monospaced)).foregroundColor(DS.Colors.textSecondary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text(isAllowed ? "a run may start" : "a run will be refused")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(isAllowed ? DS.Colors.success : DS.Colors.warningText)
            }

            toggleRow(
                title: "Require a slide tool",
                detail: "Switched off, the hotkey starts a run in any app. Switched on, it refuses anything that is not Keynote, PowerPoint, Google Slides, Canva, Gamma, Pitch, Prezi or Impress.",
                isOn: Binding(
                    get: { gate.enforcesSlideTool },
                    set: { gate.enforcesSlideTool = $0 }
                )
            )

            if !isAllowed {
                Button("Allow this app") {
                    gate.whitelistCurrentApp()
                    _ = gate.evaluateNow()
                }
                .buttonStyle(.bordered).disabled(frontmost.isNothing)
            }

            Divider().background(DS.Colors.borderSubtle)

            HStack {
                sectionLabel("Allowed by hand")
                Spacer()
                Text("\(gate.whitelistedIdentifiers.count)")
                    .font(.system(size: 10, design: .monospaced)).foregroundColor(DS.Colors.textTertiary)
            }

            if gate.whitelistedIdentifiers.isEmpty {
                Text("Nothing added by hand. The built-in list is enough so far.")
                    .font(.system(size: 11)).foregroundColor(DS.Colors.textTertiary)
            }

            ForEach(gate.whitelistedIdentifiers, id: \.self) { identifier in
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 10)).foregroundColor(DS.Colors.success)
                    Text(identifier)
                        .font(.system(size: 11, design: .monospaced)).foregroundColor(DS.Colors.codeText).lineLimit(1)
                    Spacer()
                    Button(action: {
                        gate.removeWhitelistEntry(identifier)
                    }) {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 11)).foregroundColor(DS.Colors.textTertiary)
                    }
                    .buttonStyle(.plain).pointerCursor().help("Take this app off the allowed list")
                }
                .padding(.horizontal, 10).padding(.vertical, 6).background(
                    RoundedRectangle(cornerRadius: DS.CornerRadius.small, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                )
            }

            Text(LyceumAppGate.detectionCaveat)
                .font(.system(size: 10)).foregroundColor(DS.Colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14).background(cardBackground).overlay(cardOverlay)
    }

    private var runRulesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("How a run behaves")

            toggleRow(
                title: "End the run when the talk ends",
                detail: "Watches for a goodbye slide, or the closing words in any language followed by a quiet room. Never before twenty seconds in.",
                isOn: Binding(
                    get: { coach.monitorsClosingSignals },
                    set: { coach.monitorsClosingSignals = $0 }
                )
            )

            toggleRow(
                title: "Live nudges while presenting",
                detail: "One short line in the panel when the room is going quiet or a slide has been up far too long.",
                isOn: Binding(
                    get: { coach.areLiveNudgesEnabled },
                    set: { coach.areLiveNudgesEnabled = $0 }
                )
            )

            HStack(spacing: 8) {
                Text("Drill")
                    .font(.system(size: 12, weight: .medium)).foregroundColor(DS.Colors.textSecondary)
                Spacer()
                Picker("", selection: Binding(
                    get: { coach.selectedMode },
                    set: { coach.selectedMode = $0 }
                )) {
                    ForEach(LyceumCoachMode.allCases) { coachMode in
                        Text(coachMode.displayName).tag(coachMode)
                    }
                }
                .labelsHidden().frame(width: 170)
            }

            Text(coach.selectedMode.drillExplanation)
                .font(.system(size: 10)).foregroundColor(DS.Colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14).background(cardBackground).overlay(cardOverlay)
    }

    private var modelCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Model")

            ForEach(Self.modelChoices, id: \.self) { modelIdentifier in
                let isSelected = companion.selectedModel == modelIdentifier
                Button(action: {
                    companion.setSelectedModel(modelIdentifier)
                    coach.applyClaudeModel(modelIdentifier)
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                            .font(.system(size: 11))
                            .foregroundColor(isSelected ? DS.Colors.blue400 : DS.Colors.textTertiary)
                        Text(modelIdentifier)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(isSelected ? DS.Colors.textPrimary : DS.Colors.textSecondary)
                        Spacer()
                        if isSelected {
                            Text("in use")
                                .font(.system(size: 10)).foregroundColor(DS.Colors.textTertiary)
                        }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 8).background(
                        RoundedRectangle(cornerRadius: DS.CornerRadius.small, style: .continuous)
                            .fill(isSelected ? Color.white.opacity(0.08) : Color.white.opacity(0.03))
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain).pointerCursor()
            }

            Text("The same model grades the run and voices the room. A stronger model reads a weak explanation more kindly, so compare runs at one setting.")
                .font(.system(size: 10)).foregroundColor(DS.Colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14).background(cardBackground).overlay(cardOverlay)
    }

    private var permissionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Permissions")

            Text("The Lyceum can only coach what it is allowed to see. A missing one shows up as a run with no slides, or no words at all.")
                .font(.system(size: 11)).foregroundColor(DS.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button("Microphone") {
                    openPrivacyPane("Privacy_Microphone")
                }
                .buttonStyle(.bordered)

                Button("Speech recognition") {
                    openPrivacyPane("Privacy_SpeechRecognition")
                }
                .buttonStyle(.bordered)

                Button("Screen recording") {
                    openPrivacyPane("Privacy_ScreenCapture")
                }
                .buttonStyle(.bordered)

                Button("Camera") {
                    openPrivacyPane("Privacy_Camera")
                }
                .buttonStyle(.bordered)
            }

            Text("Screen Recording is what lets the app read a browser tab title and the slide itself. Without it the gate only sees the app name, and a graded run has no slides in it.")
                .font(.system(size: 10)).foregroundColor(DS.Colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14).background(cardBackground).overlay(cardOverlay)
    }

    private func openPrivacyPane(_ pane: String) {
        let address = "x-apple.systempreferences:com.apple.preference.security?\(pane)"
        guard let url = URL(string: address) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Shared pieces

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold)).foregroundColor(DS.Colors.textTertiary).textCase(.uppercase)
    }

    private func toggleRow(title: String, detail: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium)).foregroundColor(DS.Colors.textSecondary)
                Text(detail)
                    .font(.system(size: 10)).foregroundColor(DS.Colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: isOn)
                .toggleStyle(.switch).labelsHidden().tint(DS.Colors.accent).scaleEffect(0.8)
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

    private func labelledBar(fraction: Double, color: Color) -> some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Color.white.opacity(0.08))
            Capsule()
                .fill(color).frame(width: max(2, Self.barTrackWidth * CGFloat(min(1, max(0, fraction)))))
        }
        .frame(width: Self.barTrackWidth, height: 6)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: DS.CornerRadius.large, style: .continuous)
            .fill(DS.Colors.surface2)
    }

    private var cardOverlay: some View {
        RoundedRectangle(cornerRadius: DS.CornerRadius.large, style: .continuous)
            .stroke(DS.Colors.borderSubtle, lineWidth: 0.5)
    }

    private func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date)
    }

}

// MARK: - Rows the measured table walks

/// One line of a measured table.
private struct LyceumDashboardRow: Identifiable {
    let label: String
    let value: String
    let note: String

    var id: String { label }
}

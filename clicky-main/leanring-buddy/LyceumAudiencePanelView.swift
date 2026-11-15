//
//  LyceumAudiencePanelView.swift
//  leanring-buddy
//
//  The room, drawn like a call. Meet's desktop layout is deliberately copied:
//  participant tiles fill the window, a permanent control bar runs along the
//  bottom, the room code and clock sit bottom-left, the utility panels sit
//  bottom-right, and the self view floats at the bottom edge of the grid.
//
//  The reason for the mimicry is behavioural, not aesthetic: everyone already
//  knows how a call looks when somebody is about to speak, so "the panel is
//  waiting for your answer" needs no explanation.
//

import AppKit
import SwiftUI

struct LyceumAudiencePanelView: View {
    @ObservedObject var audience: LyceumAudienceManager
    /// The run itself lives on the coach: mic level for the self tile, elapsed time,
    /// and which slide tool opened the room.
    @ObservedObject var coach: LyceumCoachManager
    let onClose: () -> Void

    /// Level of the user's microphone, so the self tile breathes while they talk.
    private var userAudioLevel: CGFloat { coach.audioPowerLevel }
    private var runElapsedSeconds: TimeInterval { coach.elapsedSeconds }
    private var slideToolName: String { coach.slideToolDisplayName }

    @State private var isShowingRoster = false
    @State private var isShowingLog = false

    private static let tileAspectRatio: CGFloat = 16.0 / 10.0
    private static let controlBarHeight: CGFloat = 58

    var body: some View {
        VStack(spacing: 0) {
            participantGrid
            captionStrip
            controlBar
        }
        .background(DS.Colors.background)
        .environment(\.colorScheme, .dark)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Grid

    private var participantGrid: some View {
        GeometryReader { geometry in
            let columns = gridColumns(forWidth: geometry.size.width)
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(audience.members) { member in
                        LyceumAudienceTile(
                            member: member,
                            isSpeaking: audience.isSpeaking(memberID: member.id),
                            hasRaisedHand: audience.raisedHandMemberID == member.id,
                            isMuted: audience.areAgentsMuted,
                            spokenCaption: audience.isSpeaking(memberID: member.id) ? audience.liveCaption : ""
                        )
                        .aspectRatio(Self.tileAspectRatio, contentMode: .fit)
                    }
                }
                .padding(12)
            }
            .overlay {
                if audience.status == .convening {
                    conveningOverlay
                }
            }
        }
    }

    private func gridColumns(forWidth width: CGFloat) -> [GridItem] {
        // Meet picks tiles by room size; two or three columns reads as a call at
        // 660pt wide and keeps faces legible.
        let desiredColumns = audience.members.count <= 3 ? audience.members.count : 3
        let safeColumns = max(1, min(3, desiredColumns))
        let columnWidth = max(120, (width - 24 - CGFloat(safeColumns - 1) * 10) / CGFloat(safeColumns))
        return Array(repeating: GridItem(.fixed(columnWidth), spacing: 10), count: safeColumns)
    }

    private var conveningOverlay: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
                .tint(DS.Colors.textPrimary)
            Text("the room is deciding what to ask")
                .font(.system(size: 11))
                .foregroundColor(DS.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.Colors.background.opacity(0.72))
    }

    // MARK: - Captions

    @ViewBuilder
    private var captionStrip: some View {
        if audience.areCaptionsShown && !audience.liveCaption.isEmpty {
            HStack(alignment: .top, spacing: 8) {
                Text(activeSpeakerName)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(DS.Colors.textOnAccent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(DS.Colors.accent))

                Text(audience.liveCaption)
                    .font(.system(size: 12.5))
                    .foregroundColor(DS.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
                    .fill(Color.black.opacity(0.55))
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
        } else if audience.isAwaitingUserAnswer {
            VStack(spacing: 4) {
                Text("hold ⌃⌥ and answer \(activeSpeakerName)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DS.Colors.textSecondary)
                Text("release when done · tap the hand to let them move on")
                    .font(.system(size: 10))
                    .foregroundColor(DS.Colors.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    private var activeSpeakerName: String {
        if let memberID = audience.activeSpeakerMemberID,
           let member = audience.members.first(where: { $0.id == memberID }) {
            return member.name
        }
        return audience.currentQuestion?.memberName ?? "Audience"
    }

    // MARK: - Control bar

    private var controlBar: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 0)
                .fill(DS.Colors.surface1)
                .overlay(alignment: .top) {
                    Divider().overlay(DS.Colors.borderSubtle)
                }

            HStack(spacing: 10) {
                roomIdentity
                Spacer(minLength: 4)
                centerControls
                Spacer(minLength: 4)
                trailingControls
            }
            .padding(.horizontal, 12)
        }
        .frame(height: Self.controlBarHeight)
    }

    private var roomIdentity: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(audience.meetingCode)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(DS.Colors.textSecondary)
            HStack(spacing: 4) {
                Image(systemName: "rectangle.on.rectangle")
                    .font(.system(size: 8))
                Text(slideToolName.isEmpty ? "no slide tool" : slideToolName)
                    .font(.system(size: 10))
            }
            .foregroundColor(DS.Colors.textTertiary)
        }
        .fixedSize()
    }

    private var centerControls: some View {
        HStack(spacing: 8) {
            LyceumCallButton(
                symbol: audience.areAgentsMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                isActive: audience.areAgentsMuted,
                help: audience.areAgentsMuted ? "Agents are muted" : "Mute the room",
                action: { audience.areAgentsMuted.toggle() }
            )

            LyceumCallButton(
                symbol: "captions.bubble",
                isActive: !audience.areCaptionsShown,
                help: "Captions",
                action: { audience.areCaptionsShown.toggle() }
            )

            LyceumCallButton(
                symbol: "hand.raised",
                isActive: audience.skipsUnansweredPrompts,
                help: audience.skipsUnansweredPrompts
                    ? "Moving on without you: off"
                    : "Let the room move on if you stay quiet",
                action: { audience.skipsUnansweredPrompts.toggle() }
            )

            LyceumCallButton(
                symbol: "rectangle.on.rectangle.odd",
                isActive: false,
                help: "Open the written verdict",
                action: { audience.requestOpenVerdict() }
            )

            Button(action: onClose) {
                HStack(spacing: 5) {
                    Image(systemName: "phone.down.fill").font(.system(size: 12, weight: .semibold))
                    Text("Leave").font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(Capsule().fill(DS.Colors.destructive))
            }
            .buttonStyle(LyceumHoverButtonStyle())
            .help("Leave the room")
        }
    }

    private var trailingControls: some View {
        HStack(spacing: 6) {
            LyceumCallButton(
                symbol: "person.2.fill",
                isActive: isShowingRoster,
                help: "People",
                action: {
                    isShowingLog = false
                    isShowingRoster.toggle()
                }
            )
            .popover(isPresented: $isShowingRoster, arrowEdge: .bottom) {
                LyceumRosterPopover(audience: audience)
            }

            LyceumCallButton(
                symbol: "text.bubble",
                isActive: isShowingLog,
                help: "Questions and answers",
                action: {
                    isShowingRoster = false
                    isShowingLog.toggle()
                }
            )
            .popover(isPresented: $isShowingLog, arrowEdge: .bottom) {
                LyceumQuestionLogPopover(audience: audience)
            }

            selfViewTile
        }
    }

    /// Meet keeps your own feed floating at the edge of the grid. Same idea, but the
    /// tile is small because what you need from it is proof the mic is open.
    private var selfViewTile: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(DS.Colors.surface4)
                    .frame(width: 26, height: 26)
                Image(systemName: "person.fill")
                    .font(.system(size: 12))
                    .foregroundColor(DS.Colors.textSecondary)
                Circle()
                    .stroke(Color.white.opacity(min(0.9, Double(userAudioLevel) * 1.6)), lineWidth: 2)
                    .frame(width: 30, height: 30)
                    .scaleEffect(1 + min(0.25, userAudioLevel * 0.4))
                    .animation(.easeOut(duration: 0.12), value: userAudioLevel)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 0) {
                Text("You")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(DS.Colors.textPrimary)
                Text(selfViewStatusLabel)
                    .font(.system(size: 9))
                    .foregroundColor(DS.Colors.textTertiary)
            }
            .fixedSize()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(DS.Colors.surface2)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(
                            audience.status == .userAnswering ? Color.white : DS.Colors.borderSubtle,
                            lineWidth: audience.status == .userAnswering ? 1.6 : 1
                        )
                )
        )
    }

    private var selfViewStatusLabel: String {
        switch audience.status {
        case .userAnswering: return "answering…"
        case .awaitingUserAnswer: return "your turn"
        case .roundComplete: return "logged out"
        case .convening: return "waiting"
        case .agentSpeaking: return "listening"
        case .off: return runElapsedSeconds > 0 ? "presenting" : "idle"
        }
    }
}

// MARK: - One tile

private struct LyceumAudienceTile: View {
    let member: LyceumAudienceMember
    let isSpeaking: Bool
    let hasRaisedHand: Bool
    let isMuted: Bool
    let spokenCaption: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(DS.Colors.surface2)

            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(avatarColor.opacity(isSpeaking ? 0.9 : 0.55))
                        .frame(width: 40, height: 40)
                    Image(systemName: member.avatarSymbol)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white.opacity(0.92))
                }
                .scaleEffect(isSpeaking ? 1.08 : 1.0)
                .animation(.easeInOut(duration: 0.35).repeatForever(autoreverses: true), value: isSpeaking)

                Text(member.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DS.Colors.textPrimary)
                    .lineLimit(1)

                Text(member.role)
                    .font(.system(size: 9))
                    .foregroundColor(DS.Colors.textTertiary)
                    .lineLimit(1)

                if isSpeaking && !spokenCaption.isEmpty {
                    Text(spokenCaption)
                        .font(.system(size: 9))
                        .foregroundColor(DS.Colors.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 6)
                }
            }
            .padding(6)

            VStack {
                HStack {
                    Spacer()
                    if hasRaisedHand {
                        Text("✋")
                            .font(.system(size: 12))
                            .padding(5)
                            .background(Circle().fill(Color.black.opacity(0.45)))
                    }
                }
                Spacer()
                HStack {
                    Spacer()
                    if isMuted {
                        Image(systemName: "speaker.slash.fill")
                            .font(.system(size: 9))
                            .foregroundColor(DS.Colors.textTertiary)
                            .padding(4)
                    }
                }
            }
            .padding(6)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isSpeaking ? Color.white : DS.Colors.borderSubtle,
                        lineWidth: isSpeaking ? 2.2 : 1)
        )
        .shadow(color: isSpeaking ? Color.white.opacity(0.12) : .clear, radius: 8)
        .help("\(member.name) — \(member.role) · \(member.tone.displayName)")
    }

    private var avatarColor: Color {
        switch member.tone {
        case .brutal: return Color(hex: "#B4483F")
        case .standard: return Color(hex: "#3E6D8E")
        case .gentle: return Color(hex: "#4F7A55")
        }
    }
}

// MARK: - Buttons

private struct LyceumCallButton: View {
    let symbol: String
    let isActive: Bool
    let help: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(isActive ? DS.Colors.textPrimary : DS.Colors.textSecondary)
                .frame(width: 36, height: 36)
                .background(
                    Circle().fill(isActive ? DS.Colors.surface4 : (isHovered ? DS.Colors.surface3 : DS.Colors.surface2))
                )
                .overlay(Circle().stroke(isActive ? DS.Colors.warning.opacity(0.7) : DS.Colors.borderSubtle, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .help(help)
    }
}

private struct LyceumHoverButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : (isHovered ? 1.02 : 1.0))
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .onHover { isHovered = $0 }
    }
}

// MARK: - Popovers

private struct LyceumRosterPopover: View {
    @ObservedObject var audience: LyceumAudienceManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("The room")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(DS.Colors.textPrimary)
                    Spacer()
                    Text("\(audience.members.count)/\(LyceumAudienceRoster.maximumMembers)")
                        .font(.system(size: 11))
                        .foregroundColor(DS.Colors.textTertiary)
                }

                ForEach($audience.members) { $member in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            TextField("Name", text: $member.name)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(DS.Colors.textPrimary)
                            Spacer(minLength: 4)
                            Picker("", selection: $member.tone) {
                                ForEach(LyceumAudienceTone.allCases, id: \.self) { tone in
                                    Text(tone.displayName).tag(tone)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 92)

                            if audience.members.count > LyceumAudienceRoster.minimumMembers {
                                Button {
                                    audience.members.removeAll { $0.id == member.id }
                                } label: {
                                    Image(systemName: "minus.circle")
                                        .font(.system(size: 11))
                                        .foregroundColor(DS.Colors.destructiveText)
                                }
                                .buttonStyle(.plain)
                                .help("Remove from the room")
                            }
                        }

                        TextField("Role, e.g. Head of Research", text: $member.role)
                            .textFieldStyle(.plain)
                            .font(.system(size: 10))
                            .foregroundColor(DS.Colors.textSecondary)

                        TextField("What they care about", text: $member.persona)
                            .textFieldStyle(.plain)
                            .font(.system(size: 10))
                            .foregroundColor(DS.Colors.textTertiary)
                            .lineLimit(2, reservesSpace: true)

                        HStack(spacing: 6) {
                            Image(systemName: "waveform")
                                .font(.system(size: 9))
                                .foregroundColor(DS.Colors.textTertiary)
                            TextField("ElevenLabs voice id (optional)", text: Binding(
                                get: { member.elevenLabsVoiceID ?? "" },
                                set: { member.elevenLabsVoiceID = $0.isEmpty ? nil : $0 }
                            ))
                            .textFieldStyle(.plain)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(DS.Colors.codeText)
                        }
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(DS.Colors.surface2)
                    )
                }

                if audience.members.count < LyceumAudienceRoster.maximumMembers {
                    Button {
                        audience.addDefaultMember()
                    } label: {
                        Label("Add a seat", systemImage: "plus.circle")
                            .font(.system(size: 11))
                            .foregroundColor(DS.Colors.accentText)
                    }
                    .buttonStyle(.plain)
                }

                Button("Restore the default room") {
                    audience.resetRoster()
                }
                .font(.system(size: 11))
                .foregroundColor(DS.Colors.textTertiary)
                .buttonStyle(.plain)
            }
            .padding(12)
        }
        .frame(width: 330, height: 420)
        .background(DS.Colors.surface1)
        .environment(\.colorScheme, .dark)
    }
}

private struct LyceumQuestionLogPopover: View {
    @ObservedObject var audience: LyceumAudienceManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Questions and answers")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DS.Colors.textPrimary)

                if audience.exchanges.isEmpty {
                    Text("nothing asked yet")
                        .font(.system(size: 11))
                        .foregroundColor(DS.Colors.textTertiary)
                }

                ForEach(audience.exchanges) { exchange in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 5) {
                            Text(exchange.memberName)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(DS.Colors.textPrimary)
                            Spacer()
                        }
                        Text(exchange.question)
                            .font(.system(size: 11))
                            .foregroundColor(DS.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if let userAnswer = exchange.userAnswer, !userAnswer.isEmpty {
                            Text(userAnswer)
                                .font(.system(size: 11))
                                .foregroundColor(DS.Colors.codeText)
                                .padding(.leading, 8)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text("(no answer given)")
                                .font(.system(size: 10).italic())
                                .foregroundColor(DS.Colors.textTertiary)
                                .padding(.leading, 8)
                        }

                        if let reaction = exchange.agentReaction, !reaction.isEmpty {
                            Text("\(exchange.memberName): \(reaction)")
                                .font(.system(size: 10))
                                .foregroundColor(DS.Colors.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(DS.Colors.surface2))
                }

                if let defenseScore = audience.defenseScore {
                    HStack(spacing: 6) {
                        Text("Held up")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(DS.Colors.textPrimary)
                        Text("\(defenseScore.value)/10")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(defenseScore.value >= 7 ? DS.Colors.success : DS.Colors.warningText)
                    }
                    Text(defenseScore.label)
                        .font(.system(size: 10))
                        .foregroundColor(DS.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
        }
        .frame(width: 340, height: 420)
        .background(DS.Colors.surface1)
        .environment(\.colorScheme, .dark)
    }
}

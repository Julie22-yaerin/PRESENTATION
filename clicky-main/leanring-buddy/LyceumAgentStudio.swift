//
//  LyceumAgentStudio.swift
//  leanring-buddy
//
//  Where a user builds the five agents that will question them.
//
//  Two columns, not one expandable list: the whole point of the room is that it
//  is five distinct people, so the roster should read as a roster (left) while
//  one person is edited in full (right). An expandable list would show all five
//  chip groups at once and turn the studio into a form.
//
//  Everything writes straight through to `audience.members`, whose `didSet`
//  already persists the roster — which is why there is no Save button and no
//  second copy of the room living in this file.
//

import SwiftUI

struct LyceumAgentStudioView: View {
    @ObservedObject var audience: LyceumAudienceManager
    var onClose: () -> Void

    @State private var selectedMemberID: String?

    // MARK: Fixed choices

    /// Symbols that really exist on macOS 14, so a saved room can never point at a
    /// glyph the participant grid cannot draw. Covers every `defaultMembers` avatar.
    static let avatarSymbols: [String] = [
        "person.fill",
        "person.2.fill",
        "graduationcap",
        "microscope",
        "eye",
        "clock",
        "person.fill.questionmark",
        "sparkles"
    ]

    /// Long enough for "Prof. Okonkwo", short enough to fit a tile label.
    static let nameLimit = 24

    private static let chipColumns = [GridItem(.adaptive(minimum: 130, maximum: 240), spacing: 6)]

    init(audience: LyceumAudienceManager, onClose: @escaping () -> Void) {
        _audience = ObservedObject(wrappedValue: audience)
        _selectedMemberID = State<String?>(initialValue: nil)
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 0) {
            studioHeader

            Divider()

            HStack(spacing: 0) {
                agentRail
                    .frame(width: 250)

                Divider()

                editorOrEmptyRoom
            }
        }
        .background(DS.Colors.background)
        // The studio is presented both as a sheet and inside the settings card, so it
        // reads the shared appearance controller instead of freezing itself to dark:
        // the palette was drawn dark, but the user's choice wins from here on.
        .lyceumColorScheme()
        // No minimum width: the dashboard settings card embeds this view, so the
        // host decides how wide it is. Height has a floor because both columns
        // scroll and a collapsed parent would give them none.
        .frame(idealWidth: 820, maxWidth: .infinity, minHeight: 440, idealHeight: 520)
    }

    // MARK: - Header

    private var studioHeader: some View {
        HStack(spacing: 9) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 13))
                .foregroundColor(DS.Colors.accentText)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: DS.CornerRadius.small, style: .continuous).fill(DS.Colors.surface3))

            VStack(alignment: .leading, spacing: 1) {
                Text("Agent Studio")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DS.Colors.textPrimary)
                Text("Five agents, five choices each")
                    .font(.system(size: 10))
                    .foregroundColor(DS.Colors.textTertiary)
            }

            Spacer(minLength: 12)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(DS.Colors.textTertiary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .pointerCursor()
            .keyboardShortcut(.cancelAction)
            .help("Close — every change is already saved")

            Button("Done") { onClose() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(DS.Colors.accent)
                .keyboardShortcut(.defaultAction)
                .pointerCursor()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(DS.Colors.surface1)
    }

    // MARK: - Left rail

    private var agentRail: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(audience.members) { member in
                        agentRow(for: member)
                    }
                }
                .padding(10)
            }

            Divider()

            Button("Restore the five defaults") {
                // Cleared first so the selection falls back onto the restored room
                // instead of pointing at an id that no longer exists.
                selectedMemberID = nil
                audience.resetRoster()
            }
            .font(.system(size: 11))
            .foregroundColor(DS.Colors.textSecondary)
            .buttonStyle(.plain)
            .pointerCursor()
            .help("Put the original five agents back: their names, roles, personas and tones, with no criteria chosen.")
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .background(DS.Colors.surface1)
    }

    private func agentRow(for member: LyceumAudienceMember) -> some View {
        let isSelected = member.id == selectedMember?.id
        let summary = member.criteriaSummaryForModel

        return Button {
            selectedMemberID = member.id
        } label: {
            HStack(spacing: 8) {
                Image(systemName: member.avatarSymbol)
                    .font(.system(size: 12))
                    .foregroundColor(isSelected ? DS.Colors.accentText : DS.Colors.textSecondary)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(isSelected ? DS.Colors.surface4 : DS.Colors.surface3))

                VStack(alignment: .leading, spacing: 2) {
                    Text(member.name.isEmpty ? "Unnamed agent" : member.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DS.Colors.textPrimary)
                        .lineLimit(1)

                    Text(summary.isEmpty ? "\(member.tone.displayName) · persona only" : summary)
                        .font(.system(size: 9.5))
                        .foregroundColor(DS.Colors.textTertiary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
                    .fill(isSelected ? DS.Colors.surface3 : DS.Colors.surface2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
                    .stroke(isSelected ? DS.Colors.accent.opacity(0.6) : DS.Colors.borderSubtle, lineWidth: isSelected ? 1 : 0.5)
            )
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }

    // MARK: - Editor

    @ViewBuilder
    private var editorOrEmptyRoom: some View {
        if let member = selectedMember {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    identityCard(for: member)
                    toneCard(for: member)
                    criteriaCard(for: member)
                    promptPreviewCard(for: member)
                    clearRow(for: member)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "person.2.slash")
                    .font(.system(size: 22))
                    .foregroundColor(DS.Colors.textTertiary)
                Text("Nobody is sitting in the room yet.")
                    .font(.system(size: 12))
                    .foregroundColor(DS.Colors.textSecondary)
                Text("Restore the five defaults to bring the panel back.")
                    .font(.system(size: 10))
                    .foregroundColor(DS.Colors.textTertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// The agent on the right. Falls back to the first seat whenever the stored
    /// choice is gone, which happens the moment another editor or the restore
    /// button rewrites the roster underneath the studio.
    private var selectedMember: LyceumAudienceMember? {
        if let selectedMemberID,
           let member = audience.members.first(where: { $0.id == selectedMemberID }) {
            return member
        }
        return audience.members.first
    }

    private func identityCard(for member: LyceumAudienceMember) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Identity")

            HStack(spacing: 8) {
                TextField("Agent name", text: nameBinding(for: member.id))
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(DS.Colors.textPrimary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(fieldBackground)
                    .frame(maxWidth: 220)
                    .onSubmit { selectedMemberID = member.id }

                Text("\(member.name.count)/\(Self.nameLimit)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(member.name.count >= Self.nameLimit ? DS.Colors.warningText : DS.Colors.textTertiary)

                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Avatar")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(DS.Colors.textSecondary)

                HStack(spacing: 6) {
                    ForEach(Self.avatarSymbols, id: \.self) { symbol in
                        avatarButton(symbol, isCurrent: symbol == member.avatarSymbol, memberID: member.id)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .overlay(cardOverlay)
    }

    private func avatarButton(_ symbol: String, isCurrent: Bool, memberID: String) -> some View {
        Button {
            mutate(memberID) { $0.avatarSymbol = symbol }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .foregroundColor(isCurrent ? DS.Colors.accentText : DS.Colors.textTertiary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(isCurrent ? DS.Colors.accentSubtle : DS.Colors.surface3))
                .overlay(Circle().stroke(isCurrent ? DS.Colors.accent.opacity(0.6) : DS.Colors.borderSubtle, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .help("Avatar: \(symbol)")
    }

    private func toneCard(for member: LyceumAudienceMember) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("How hard they push")

            HStack(spacing: 6) {
                ForEach(LyceumAudienceTone.allCases, id: \.self) { tone in
                    choiceButton(title: tone.displayName,
                                 symbol: toneSymbol(tone),
                                 isOn: member.tone == tone) {
                        mutate(member.id) { $0.tone = tone }
                    }
                    .help(tone.briefForModel)
                }
            }

            Text(member.tone.briefForModel)
                .font(.system(size: 10))
                .italic()
                .foregroundColor(DS.Colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .overlay(cardOverlay)
    }

    private func toneSymbol(_ tone: LyceumAudienceTone) -> String {
        switch tone {
        case .gentle: return "leaf"
        case .standard: return "bolt"
        case .brutal: return "flame"
        }
    }

    // MARK: Criteria

    private func criteriaCard(for member: LyceumAudienceMember) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                sectionLabel("Criteria")
                Spacer(minLength: 4)
                Text("\(member.criteriaCount) / \(LyceumAudienceMember.maximumCriteria) criteria")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(member.isAtCriteriaLimit ? DS.Colors.warningText : DS.Colors.textSecondary)
            }

            if member.isAtCriteriaLimit {
                Text("This agent is full at five criteria. Switch one off above to free a slot. The cap is deliberate: past five choices an agent stops sounding like a person you can picture and starts sounding like a form, and the questions stop changing.")
                    .font(.system(size: 10))
                    .foregroundColor(DS.Colors.warningText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(LyceumAgentCriterionGroup.allCases, id: \.self) { group in
                chipGroupSection(group, for: member)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .overlay(cardOverlay)
    }

    private func chipGroupSection(_ group: LyceumAgentCriterionGroup, for member: LyceumAudienceMember) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: group.symbol)
                    .font(.system(size: 9))
                    .foregroundColor(DS.Colors.textTertiary)
                Text(group.displayName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(DS.Colors.textPrimary)
                Text(group.hintForUser)
                    .font(.system(size: 10))
                    .foregroundColor(DS.Colors.textTertiary)
            }

            LazyVGrid(columns: Self.chipColumns, alignment: .leading, spacing: 6) {
                ForEach(group.options) { option in
                    criterionChip(option, for: member)
                }
            }
        }
    }

    private func criterionChip(_ option: LyceumAgentCriterionOption, for member: LyceumAudienceMember) -> some View {
        let isSelected = member.isSelected(option)
        // At the limit an unchosen chip goes dead instead of vanishing, so the
        // trade is visible before the user switches something else off.
        let isRefused = member.isAtCriteriaLimit && !isSelected

        return Button {
            mutate(member.id) { $0 = $0.toggling(option) }
            // Read back after the write: the list is the only truth about how much
            // shape a seat has, and this is the one action that can change it.
            let after = audience.members.first { $0.id == member.id }
            ClickyAnalytics.trackLyceumAgentSaved(
                criteriaCount: after?.criteriaCount ?? 0,
                hasOwnName: after?.hasOwnName ?? false
            )
        } label: {
            HStack(spacing: 5) {
                Image(systemName: option.symbol)
                    .font(.system(size: 9))
                Text(option.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundColor(isSelected ? DS.Colors.accentText : DS.Colors.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .center)
            .background(Capsule().fill(isSelected ? DS.Colors.accentSubtle : DS.Colors.surface3))
            .overlay(
                Capsule().stroke(isSelected ? DS.Colors.accent.opacity(0.6) : DS.Colors.borderSubtle, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .pointerCursor(isEnabled: !isRefused)
        .disabled(isRefused)
        .opacity(isRefused ? 0.4 : 1)
        .help(option.briefForModel)
    }

    private func choiceButton(title: String, symbol: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 9))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(isOn ? DS.Colors.accentText : DS.Colors.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(isOn ? DS.Colors.accentSubtle : DS.Colors.surface3))
            .overlay(Capsule().stroke(isOn ? DS.Colors.accent.opacity(0.6) : DS.Colors.borderSubtle, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }

    // MARK: Prompt preview

    private func promptPreviewCard(for member: LyceumAudienceMember) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Into the prompt")

            Text(previewLine(for: member))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(member.hasCriteria ? DS.Colors.codeText : DS.Colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: DS.CornerRadius.small, style: .continuous)
                        .fill(DS.Colors.background)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DS.CornerRadius.small, style: .continuous)
                        .stroke(DS.Colors.borderSubtle, lineWidth: 0.5)
                )

            Text(previewExplanation(for: member))
                .font(.system(size: 10))
                .foregroundColor(DS.Colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .overlay(cardOverlay)
    }

    /// The label and the string are the same ones `panelSystemPrompt(roster:)`
    /// writes, so what is previewed here is what the panel actually reads.
    private func previewLine(for member: LyceumAudienceMember) -> String {
        if member.hasCriteria {
            return "what the user set for them: \(member.criteriaSummaryForModel)"
        }
        let persona = member.persona.trimmingCharacters(in: .whitespacesAndNewlines)
        return persona.isEmpty ? "character: (nothing written yet)" : "character: \(persona)"
    }

    private func previewExplanation(for member: LyceumAudienceMember) -> String {
        if member.hasCriteria {
            return "Every chip also travels as its own sentence, so the panel gets the label line above and the reasons for it."
        }
        return "No criteria chosen, so the panel builds this agent from the persona line above. Edit it in the room's own roster editor."
    }

    private func clearRow(for member: LyceumAudienceMember) -> some View {
        HStack(spacing: 8) {
            Button("Clear this agent") {
                mutate(member.id) { $0 = $0.clearingCriteria() }
            }
            .font(.system(size: 11))
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!member.hasCriteria)
            .pointerCursor(isEnabled: member.hasCriteria)
            .help("Drop every criterion for this agent. The name, avatar, tone and persona stay, so the prompt goes back to the written character.")

            Spacer(minLength: 0)
        }
    }

    // MARK: - Writing through to the roster

    private func nameBinding(for memberID: String) -> Binding<String> {
        Binding(
            get: { audience.members.first { $0.id == memberID }?.name ?? "" },
            set: { newValue in
                mutate(memberID) { $0.name = String(newValue.prefix(Self.nameLimit)) }
            }
        )
    }

    /// The one write path in this file. `members` persists itself on `didSet`, and
    /// prompts, tiles and the grid all read the same list, so nothing here keeps a
    /// draft copy that could drift from the room.
    private func mutate(_ memberID: String, _ change: (inout LyceumAudienceMember) -> Void) {
        guard let index = audience.members.firstIndex(where: { $0.id == memberID }) else { return }
        var copy = audience.members[index]
        change(&copy)
        audience.members[index] = copy
    }

    // MARK: - Shared styling

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(DS.Colors.textTertiary)
            .textCase(.uppercase)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: DS.CornerRadius.large, style: .continuous)
            .fill(DS.Colors.surface2)
    }

    private var cardOverlay: some View {
        RoundedRectangle(cornerRadius: DS.CornerRadius.large, style: .continuous)
            .stroke(DS.Colors.borderSubtle, lineWidth: 0.5)
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
            .fill(DS.Colors.background)
    }
}

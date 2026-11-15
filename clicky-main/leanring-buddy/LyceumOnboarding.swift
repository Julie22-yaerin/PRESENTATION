//

//  LyceumOnboarding.swift

//  leanring-buddy

//

//  Who is sitting in front of the deck: the grade, the audience, and whether this

//  is a judged competition.

//

//  The first version of The Lyceum graded every run with the same rubric, which is

//  the wrong rubric for a grade 6 class show and for a science-fair panel on the

//  same day. Everything in the first five minutes of a fresh install feeds one

//  sentence (`contextLineForModel`) that the coach and the audience prompts carry.

//

//  Two rules hold here. Nothing is force-unwrapped, because a broken preferences

//  file must never stop the app from launching: a profile that will not decode

//  reads as an empty one and the flow simply asks again. And no answer is required

//  to be typed when a button can carry it, so only three fields in the whole flow

//  are free text.

//

import Combine
import Foundation
import SwiftUI

// MARK: - Grade

/// Where the learner stands. Kept as an enum with payloads rather than an `Int`
/// plus a free-text field: the two ways a first version can disagree with each
/// other disappear, and "Other" carries its own wording to the model.
enum LyceumGrade: Codable, Equatable {
    case k12(Int)
    case university
    case other(String)

    /// The twelve school years the grid offers. "Other" is not in here: it is its
    /// own control, because it needs a text field next to it.
    static let schoolYears: [LyceumGrade] = (1...12).map { year in LyceumGrade.k12(year) }

    /// What the button on screen says.
    var displayName: String {
        switch self {
        case .k12(let year):
            return "Grade \(year)"
        case .university:
            return "University"
        case .other(let note):
            let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? "Other" : text
        }
    }

    var isOther: Bool {
        if case .other = self { return true }
        return false
    }

    var otherNote: String {
        if case .other(let note) = self { return note }
        return ""
    }

    /// Written for the model, so it stays lower case and reads inside a sentence.
    var contextPhrase: String {
        switch self {
        case .k12(let year):
            return "grade \(year)"
        case .university:
            return "university"
        case .other(let note):
            let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? "an education stage that was not listed" : text.lowercased()
        }
    }
}

// MARK: - Audience

/// Who the talk is aimed at. Multi-select: a school assembly is teachers, a
/// class and a panel at the same time, and the panel that practises it should be
/// built out of all three.
enum LyceumAudienceKind: String, CaseIterable, Codable {
    case teachers
    case classmates
    case judgingPanel
    case parents
    case club
    case publicAudience
    case other

    var displayName: String {
        switch self {
        case .teachers: return "Teachers"
        case .classmates: return "Classmates"
        case .judgingPanel: return "Judging panel"
        case .parents: return "Parents & family"
        case .club: return "Club or society"
        case .publicAudience: return "Public audience"
        case .other: return "Other…"
        }
    }

    var symbol: String {
        switch self {
        case .teachers: return "graduationcap.fill"
        case .classmates: return "person.2.fill"
        case .judgingPanel: return "checkmark.seal.fill"
        case .parents: return "house.fill"
        case .club: return "person.3.fill"
        case .publicAudience: return "megaphone.fill"
        case .other: return "ellipsis.circle"
        }
    }

    /// Reads inside "presenting to …" in the model line.
    var contextPhrase: String {
        switch self {
        case .teachers: return "teachers"
        case .classmates: return "classmates"
        case .judgingPanel: return "a judging panel"
        case .parents: return "parents and family"
        case .club: return "a club or society"
        case .publicAudience: return "a public audience"
        case .other: return "an audience that was not on the list"
        }
    }
}

// MARK: - Profile

/// The whole onboarding answer in one value type, so the store can hand out a
/// copy, mutate the copy and write the copy back.
struct LyceumLearnerProfile: Codable, Equatable {
    /// nil means "never answered", which is different from an empty string: the
    /// first hides the model line, the second would put a blank into a prompt.
    var grade: LyceumGrade?

    var audiences: [LyceumAudienceKind] = []

    /// Only meaningful when `audiences` contains `.other`.
    var otherAudienceNote: String = ""

    var isCompeting: Bool = false

    var competitionName: String = ""

    /// Optional on purpose: a student who knows the event name but not the
    /// federation behind it should still be able to finish.
    var competitionOrganiser: String = ""

    var completedOnboardingAt: Date?

    static let empty = LyceumLearnerProfile()

    /// A coarse bucket for analytics: "k12", "university", "other" or "none". Never the
    /// year itself and never the note a student typed, which is how a school name escapes
    /// a product that promised it stays on the Mac.
    var gradeKindForAnalytics: String {
        switch grade {
        case .k12: return "k12"
        case .university: return "university"
        case .other: return "other"
        case nil: return "none"
        }
    }

    var hasAnyAnswer: Bool {
        grade != nil || !audiences.isEmpty
    }
}

// MARK: - Store

/// One key in UserDefaults, one shared instance. Deliberately not a second roster:
/// the five agents live in `LyceumAudienceManager`, and this only says who the
/// speaker is.
@MainActor
final class LyceumProfileStore: ObservableObject {
    private static let defaultsKey = "lyceumLearnerProfile"

    static let shared = LyceumProfileStore()

    @Published private(set) var profile: LyceumLearnerProfile

    private init() {
        profile = LyceumProfileStore.storedProfile()
    }

    var hasCompletedOnboarding: Bool {
        profile.completedOnboardingAt != nil
    }

    /// Mutate a copy, publish it, persist it. Callers cannot forget the save.
    func update(_ mutate: (inout LyceumLearnerProfile) -> Void) {
        var draft = profile
        mutate(&draft)
        profile = draft
        save()
    }

    func markCompleted() {
        update { draft in
            draft.completedOnboardingAt = Date()
        }
    }

    /// Clears the flag but keeps every answer, so "run it again" from settings
    /// walks the user through their own replies instead of a blank form.
    func restartOnboarding() {
        update { draft in
            draft.completedOnboardingAt = nil
        }
    }

    /// One dense sentence for the system prompts. Empty when nothing is known, so
    /// the prompt builders can test for `isEmpty` and leave the line out rather
    /// than send a sentence full of placeholders.
    var contextLineForModel: String {
        guard profile.hasAnyAnswer else { return "" }

        var clauses: [String] = []
        if let grade = profile.grade {
            clauses.append("audience level: \(grade.contextPhrase)")
        }

        let audiencePhrases = profile.audiences.map { kind -> String in
            if kind == .other {
                let note = Self.trimmed(profile.otherAudienceNote)
                return note.isEmpty ? kind.contextPhrase : note.lowercased()
            }

            return kind.contextPhrase
        }

        if !audiencePhrases.isEmpty {
            clauses.append("presenting to \(Self.joined(audiencePhrases))")
        }

        let name = Self.trimmed(profile.competitionName)
        if profile.isCompeting, !name.isEmpty {
            let organiser = Self.trimmed(profile.competitionOrganiser)
            clauses.append(organiser.isEmpty
                ? "this is a competition: “\(name)”"
                : "this is a competition: “\(name)”, run by \(organiser)")
        }

        guard !clauses.isEmpty else { return "" }
        return "Learner: \(clauses.joined(separator: ", ")). Grade their talk accordingly."
    }

    // MARK: Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }

    private static func storedProfile() -> LyceumLearnerProfile {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode(LyceumLearnerProfile.self, from: data) else {
            return .empty
        }

        return decoded
    }

    // MARK: Text helpers

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// "teachers, classmates and a judging panel" — the shape a prompt should read.
    private static func joined(_ phrases: [String]) -> String {
        guard phrases.count > 1 else { return phrases.first ?? "" }
        let head = phrases.dropLast().joined(separator: ", ")
        return "\(head) and \(phrases.last ?? "")"
    }
}

// MARK: - Onboarding

/// Five linear steps with progress dots. A sheet rather than a wizard window: the
/// flow has no branches, and the only way to lose a nervous fourteen-year-old in a
/// first run is a screen that looks like it has more screens behind it.
struct LyceumOnboardingView: View {
    @ObservedObject var profile: LyceumProfileStore

    var onOpenAgentStudio: () -> Void

    var onFinish: () -> Void

    private enum Step: Int, CaseIterable, Identifiable {
        case welcome
        case grade
        case audiences
        case competition
        case agents

        var id: Step { self }

        var title: String {
            switch self {
            case .welcome: return "Welcome to The Lyceum"
            case .grade: return "Which year are you in?"
            case .audiences: return "Who are you presenting to?"
            case .competition: return "Is this for a competition?"
            case .agents: return "Your five agents"
            }
        }

        var subtitle: String {
            switch self {
            case .welcome: return "Five questions, about a minute. Your answers stay on this Mac."
            case .grade: return "The rubric, the vocabulary ceiling and how hard the panel pushes all scale off this."
            case .audiences: return "Pick every room that applies. The practice panel is built out of your answer."
            case .competition: return "A judged event gets a stricter pass: the panel quotes the mark scheme it would really use."
            case .agents: return "Five seats are already filled. Keep them, or name and brief your own."
            }
        }

        var symbol: String {
            switch self {
            case .welcome: return "mic"
            case .grade: return "graduationcap.fill"
            case .audiences: return "person.3.fill"
            case .competition: return "trophy.fill"
            case .agents: return "person.2.fill"
            }
        }
    }

    private static let cardWidth: CGFloat = 560

    private static let gradeColumns = [GridItem(.adaptive(minimum: 92), spacing: 8)]

    private static let audienceColumns = [GridItem(.adaptive(minimum: 150), spacing: 8)]

    // The flow edits a draft, not the store: a step halfway through must not turn
    // `hasCompletedOnboarding` on and skip itself next launch.
    @State private var step: Step = .welcome
    @State private var grade: LyceumGrade?
    @State private var audiences: [LyceumAudienceKind] = []
    @State private var otherAudienceNote: String = ""
    @State private var isCompeting: Bool = false
    @State private var competitionName: String = ""
    @State private var competitionOrganiser: String = ""
    @State private var prefersOwnAgents: Bool = false

    /// A disabled Continue teaches nothing. Tapping it is what earns the reason.
    @State private var isShowingBlocker: Bool = false

    /// Restates the saved answers, so "run it again" from settings walks through
    /// what the user already said instead of a blank form. The init reads the
    /// store, so it is called out as main-actor work.
    @MainActor
    init(profile: LyceumProfileStore,
         onOpenAgentStudio: @escaping () -> Void,
         onFinish: @escaping () -> Void) {
        self.profile = profile
        self.onOpenAgentStudio = onOpenAgentStudio
        self.onFinish = onFinish

        let saved = profile.profile
        _grade = State(initialValue: saved.grade)
        _audiences = State(initialValue: saved.audiences)
        _otherAudienceNote = State(initialValue: saved.otherAudienceNote)
        _isCompeting = State(initialValue: saved.isCompeting)
        _competitionName = State(initialValue: saved.competitionName)
        _competitionOrganiser = State(initialValue: saved.competitionOrganiser)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(DS.Colors.borderSubtle)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 12) {
                    stepContent
                    blockerLine
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider().background(DS.Colors.borderSubtle)
            footer
        }
        .frame(width: Self.cardWidth)
        .frame(minHeight: 480, maxHeight: 640)
        .background(DS.Colors.background)
        // Every DS colour in this repo is a literal dark hex, so the native
        // controls (fields, the switch) have to be told they are on a dark card.
        .lyceumColorScheme()
    }

    // MARK: Chrome

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: step.symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(DS.Colors.blue400)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
                        .fill(DS.Colors.accentSubtle)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(step.title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(DS.Colors.textPrimary)

                Text(step.subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(DS.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            progressDots
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var progressDots: some View {
        HStack(spacing: 5) {
            ForEach(Step.allCases) { candidate in
                Capsule()
                    .fill(dotColor(for: candidate))
                    .frame(width: candidate == step ? 18 : 6, height: 6)
            }
        }
        .padding(.top, 4)
        .animation(.easeOut(duration: DS.Animation.fast), value: step)
    }

    private func dotColor(for candidate: Step) -> Color {
        if candidate == step { return DS.Colors.blue400 }
        if candidate.rawValue < step.rawValue { return DS.Colors.blue500.opacity(0.55) }
        return DS.Colors.borderStrong
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if step == .welcome {
                Text("About a minute, and you can change all of it later.")
                    .font(.system(size: 10))
                    .foregroundColor(DS.Colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Button(action: goBack) {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Back")
                            .font(.system(size: 13, weight: .medium))
                    }
                }
                .buttonStyle(DSSecondaryButtonStyle(isFullWidth: false))
                .keyboardShortcut(.cancelAction)
            }

            Spacer(minLength: 12)

            Button(action: advance) {
                HStack(spacing: 6) {
                    Text(primaryTitle)
                        .font(.system(size: 14, weight: .semibold))
                    if step != .agents {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
            }
            .buttonStyle(DSPrimaryButtonStyle(isFullWidth: false))
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: Steps

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome:
            welcomeStep
        case .grade:
            gradeStep
        case .audiences:
            audiencesStep
        case .competition:
            competitionStep
        case .agents:
            agentsStep
        }
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            bullet(symbol: "mic",
                   title: "Rehearse out loud",
                   detail: "One run records the real thing: what you said, how fast, where you went quiet and which slide you stalled on.")
            bullet(symbol: "person.3.fill",
                   title: "Five agents push back",
                   detail: "A chair, a subject teacher, an outside judge, a classmate and a timekeeper ask the questions an actual room asks, one at a time.")
            bullet(symbol: "chart.xyaxis.line",
                   title: "Watch the term move",
                   detail: "Scores, transcripts and per-slide fixes stay on this Mac, so the trend is visible after a handful of runs.")
        }
    }

    private var gradeStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: Self.gradeColumns, spacing: 8) {
                ForEach(LyceumGrade.schoolYears, id: \.displayName) { candidate in
                    choiceButton(title: candidate.displayName,
                                subtitle: nil,
                                isSelected: grade == candidate) {
                        grade = candidate
                    }
                }

                choiceButton(title: LyceumGrade.university.displayName,
                             subtitle: nil,
                             isSelected: grade == .university) {
                    grade = .university
                }

                choiceButton(title: "Other",
                             subtitle: nil,
                             isSelected: grade?.isOther == true) {
                    grade = .other(grade?.otherNote ?? "")
                }
            }

            if grade?.isOther == true {
                fieldCard(label: "Say it in your own words",
                          hint: "This goes to the model as your audience level.",
                          placeholder: "IB prep year, adult evening class, homeschool co-op…",
                          text: otherGradeBinding)
            }

            Text("Numbers 1–12 are school years. University and everything else have their own button.")
                .font(.system(size: 10))
                .foregroundColor(DS.Colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var audiencesStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: Self.audienceColumns, spacing: 8) {
                ForEach(LyceumAudienceKind.allCases, id: \.rawValue) { kind in
                    audienceChip(kind)
                }
            }

            if audiences.contains(.other) {
                fieldCard(label: "Who else is in the room?",
                          hint: "One phrase is enough — it is written into the brief the panel reads.",
                          placeholder: "A youth council, a livestream chat, my company's board…",
                          text: $otherAudienceNote)
            }

            Text(audienceFootnote)
                .font(.system(size: 10))
                .foregroundColor(DS.Colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var competitionStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            toggleRow(title: "This is a judged competition",
                      detail: "The panel scores against a mark scheme and quotes the rule you are closest to breaking.",
                      isOn: $isCompeting)

            if isCompeting {
                fieldCard(label: "What is it called?",
                          hint: "Required — it names the stakes in the feedback.",
                          placeholder: "Cuộc thi KHKT cấp thành phố…",
                          text: $competitionName)

                fieldCard(label: "Who runs it? (optional)",
                          hint: "A federation, a school, a university. Leave it blank if you do not know.",
                          placeholder: "Sở Giáo dục, the district board…",
                          text: $competitionOrganiser)
            } else {
                Text("Off means ordinary class practice: same panel, gentler scoring.")
                    .font(.system(size: 11))
                    .foregroundColor(DS.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var agentsStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Read from the roster itself so this screen can never disagree with
            // the room the app actually opens.
            ForEach(LyceumAudienceRoster.defaultMembers) { member in
                agentRow(member)
            }

            VStack(spacing: 8) {
                choiceButton(title: "Keep the five defaults",
                             subtitle: "The roles that break most school talks.",
                             isSelected: !prefersOwnAgents) {
                        prefersOwnAgents = false
                    }

                choiceButton(title: "Build my own",
                             subtitle: "Names, what each agent does, personality, focus.",
                             isSelected: prefersOwnAgents) {
                        prefersOwnAgents = true
                        onOpenAgentStudio()
                    }
            }
            .padding(.top, 4)

            Text("Either way, Finish leaves you a room you can edit later from the gear at the bottom of the dashboard.")
                .font(.system(size: 10))
                .foregroundColor(DS.Colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func agentRow(_ member: LyceumAudienceMember) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: member.avatarSymbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(DS.Colors.blue300)
                .frame(width: 28, height: 28)
                .background(
                    Circle().fill(DS.Colors.blue500.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(member.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(DS.Colors.textPrimary)
                    Text(member.tone.displayName)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(DS.Colors.blue400)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            Capsule().fill(DS.Colors.blue500.opacity(0.12))
                        )
                }

                Text(member.role)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DS.Colors.textSecondary)

                Text(member.persona)
                    .font(.system(size: 10))
                    .foregroundColor(DS.Colors.textTertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(cardBackground)
        .overlay(cardOverlay)
    }

    // MARK: Controls

    /// `Text` has two overloads a bare literal ternary could bind to either of, so
    /// both branches are resolved into a String away from the view builder.
    private var primaryTitle: String {
        step == .agents ? "Finish" : "Continue"
    }

    private var audienceFootnote: String {
        audiences.isEmpty
            ? "Pick at least one. Tap again to take it off."
            : "\(audiences.count) selected — the panel borrows their habits, not their faces."
    }

    private func audienceChip(_ kind: LyceumAudienceKind) -> some View {
        let isSelected = audiences.contains(kind)
        return Button(action: {
            toggle(kind)
        }) {
            HStack(spacing: 7) {
                Image(systemName: kind.symbol)
                    .font(.system(size: 11, weight: .medium))
                Text(kind.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                }
            }
            .foregroundColor(isSelected ? DS.Colors.textPrimary : DS.Colors.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
                    .fill(isSelected ? DS.Colors.surface3 : DS.Colors.surface1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
                    .stroke(isSelected ? DS.Colors.blue500.opacity(0.7) : DS.Colors.borderSubtle,
                            lineWidth: isSelected ? 1 : 0.5)
            )
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }

    private func choiceButton(title: String,
                              subtitle: String?,
                              isSelected: Bool,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .center, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 9))
                        .foregroundColor(DS.Colors.textTertiary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .foregroundColor(isSelected ? DS.Colors.textPrimary : DS.Colors.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, subtitle == nil ? 10 : 8)
            .background(
                RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
                    .fill(isSelected ? DS.Colors.surface3 : DS.Colors.surface1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
                    .stroke(isSelected ? DS.Colors.blue500.opacity(0.7) : DS.Colors.borderSubtle,
                            lineWidth: isSelected ? 1 : 0.5)
            )
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }

    private func bullet(symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(DS.Colors.blue400)
                .frame(width: 22)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DS.Colors.textPrimary)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundColor(DS.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(cardBackground)
        .overlay(cardOverlay)
    }

    private func toggleRow(title: String, detail: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DS.Colors.textPrimary)
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
                .scaleEffect(0.85)
        }
        .padding(12)
        .background(cardBackground)
        .overlay(cardOverlay)
    }

    private func fieldCard(label: String, hint: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(DS.Colors.textTertiary)
                .textCase(.uppercase)

            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(DS.Colors.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: DS.CornerRadius.small, style: .continuous)
                        .fill(DS.Colors.surface2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DS.CornerRadius.small, style: .continuous)
                        .stroke(DS.Colors.borderSubtle, lineWidth: 0.5)
                )

            Text(hint)
                .font(.system(size: 10))
                .foregroundColor(DS.Colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(cardBackground)
        .overlay(cardOverlay)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
            .fill(DS.Colors.surface1)
    }

    private var cardOverlay: some View {
        RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
            .stroke(DS.Colors.borderSubtle, lineWidth: 0.5)
    }

    /// The "Other" grade keeps its text inside the `grade` value rather than in a
    /// second piece of state, so the two can never drift apart.
    private var otherGradeBinding: Binding<String> {
        Binding(
            get: { grade?.otherNote ?? "" },
            set: { grade = .other($0) }
        )
    }

    // MARK: Flow

    private func toggle(_ kind: LyceumAudienceKind) {
        if let index = audiences.firstIndex(of: kind) {
            audiences.remove(at: index)
        } else {
            audiences.append(kind)
        }
    }

    /// Why the flow will not move, in the user's terms. Shown under the step
    /// instead of an alert: a dialog that says "pick something" on a screen that
    /// is already showing buttons is a bad joke.
    private var blocker: String? {
        switch step {
        case .welcome, .agents:
            return nil
        case .grade:
            if grade == nil {
                return "Pick a school year, University, or Other — the marking scale depends on it."
            }

            if grade?.isOther == true && Self.trimmed(grade?.otherNote ?? "").isEmpty {
                return "Other needs a word or two, or nothing can be scaled to it."
            }

            return nil
        case .audiences:
            if audiences.isEmpty {
                return "Choose at least one audience, so there is a room to practise in."
            }

            if audiences.contains(.other) && Self.trimmed(otherAudienceNote).isEmpty {
                return "You picked Other — say who that audience is, or take the chip off."
            }

            return nil
        case .competition:
            if isCompeting && Self.trimmed(competitionName).isEmpty {
                return "Type the name of the competition, or switch it off to practise as a normal class talk."
            }

            return nil
        }
    }

    @ViewBuilder
    private var blockerLine: some View {
        if isShowingBlocker, let reason = blocker {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 11, weight: .semibold))
                Text(reason)
                    .font(.system(size: 11))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundColor(DS.Colors.destructiveText)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
                    .fill(DS.Colors.destructive.opacity(0.10))
            )
        }
    }

    private func advance() {
        if blocker != nil {
            isShowingBlocker = true
            return
        }

        guard let next = Step(rawValue: step.rawValue + 1) else {
            finish()
            return
        }
        isShowingBlocker = false
        withAnimation(.easeOut(duration: DS.Animation.fast)) {
            step = next
        }
    }

    private func goBack() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        isShowingBlocker = false
        withAnimation(.easeOut(duration: DS.Animation.fast)) {
            step = previous
        }
    }

    /// The view owns completion, not the launcher: whoever hosts this only decides
    /// whether the card is on screen, and cannot accidentally ship a half profile.
    private func finish() {
        profile.update { draft in
            draft.grade = grade
            draft.audiences = audiences
            draft.otherAudienceNote = audiences.contains(.other) ? Self.trimmed(otherAudienceNote) : ""
            draft.isCompeting = isCompeting
            draft.competitionName = isCompeting ? Self.trimmed(competitionName) : ""
            draft.competitionOrganiser = isCompeting ? Self.trimmed(competitionOrganiser) : ""
        }
        profile.markCompleted()
        onFinish()
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

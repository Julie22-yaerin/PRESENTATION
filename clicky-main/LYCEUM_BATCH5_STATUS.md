# Đợt 5 — TRẠNG THÁI (cập nhật 2026-11-15 21:01)

Làm việc trong `/home/ubuntu/presentation/clicky-main`, nguồn `leanring-buddy/`.
KHÔNG có Swift compiler ở đây → mọi thứ kiểm bằng 2 script:
`python3 /tmp/swiftcheck.py <files>` (cân bằng ngoặc + API tồn tại) và
`python3 /tmp/xcheck_batch5.py` (mọi `Type.member` phải có khai báo).
Chạy gần nhất: **9 file OK, 0 structural issues; xcheck chỉ còn 3 dương tính giả là
comment đầu file (`//  X.swift`) và 1 dòng hợp lệ ở LyceumInsights.swift:342.**

## File mới (do 3 subagent viết, tôi đã soát)

| File | Dòng | Nội dung | API công khai đã kiểm |
| --- | --- | --- | --- |
| `LyceumOnboarding.swift` | ~985 | profile + 5 bước onboarding | `LyceumGrade {k12(Int), university, other(String)}` có `displayName/isOther/otherNote/contextPhrase`, `schoolYears`; `LyceumAudienceKind {teachers, classmates, judgingPanel, parents, club, publicAudience, other}` có `displayName/symbol/contextPhrase`; `LyceumLearnerProfile {grade?, audiences, otherAudienceNote, isCompeting, competitionName, competitionOrganiser, completedOnboardingAt}` + `empty/hasAnyAnswer/gradeKindForAnalytics`; `LyceumProfileStore.shared` (`@Published private(set) profile`, `hasCompletedOnboarding`, `update(_:)`, `markCompleted()`, `restartOnboarding()`, `contextLineForModel`), key `lyceumLearnerProfile`; `LyceumOnboardingView(profile:onOpenAgentStudio:onFinish:)` — view TỰ gọi `profile.markCompleted()` rồi `onFinish()`. |
| `LyceumAgentStudio.swift` | ~545 | studio 5 agent | `LyceumAgentStudioView(audience:onClose:)`, `avatarSymbols` (8), `nameLimit = 24`, write path duy nhất `mutate(_:_)` |
| `LyceumTheme.swift` | 145 | theme | `LyceumAppearanceMode {system, light, dark}` (`displayName/symbol/brief`), `LyceumAppearanceController.shared` (`mode`, `reduceMotion`, `colorScheme: ColorScheme?`, `apply()`), key `lyceumAppearanceMode`, `lyceumReduceMotion`; modifier `.lyceumColorScheme(_:)` |
| `LyceumDashboardSettingsView.swift` | ~1449 | sheet cài đặt | `LyceumDashboardSettingsView(coach:audience:gate:companion:)`, `enum SettingsSection: String, CaseIterable, Identifiable {voice, room, rules, data, appearance, gettingStarted}` (tôi vừa thêm `: String` để `.rawValue` dùng cho analytics), frame 760×560, section `gettingStartedSection` có nút "Run onboarding again" → `profileStore.restartOnboarding()` |

## File đã sửa (tôi)

- `LyceumAudience.swift` (1138): `functions/traits/focus: [String]?` (optional để data cũ decode được),
  `maximumCriteria = 5`, `criteriaCount`, `hasCriteria`, `isAtCriteriaLimit`, `criteriaSlotsLeft`,
  `isSelected(_:)`, `toggling(_:_:)` + `toggling(_ option:)` (từ chối cái thứ 6),
  `criteriaSummaryForModel`, `criteriaBriefsForModel`, `hasOwnName` (tôi thêm),
  `maximumMembers` **6 → 5**, `panelSystemPrompt` in dòng tiêu chí + **dòng "WHO IS IN FRONT OF
  THIS ROOM"** từ `LyceumProfileStore.shared.contextLineForModel`, và enum mới
  `LyceumAudienceTuning {schoolYear(of:), isSeatCustomised(_:), customisedSeatCount(in:), tuned(_:for:)}`
  (tuning CHỈ đụng seat chưa có criteria; competition → harsher, grade ≤ 8 → bỏ brutal,
  classmate đổi vai khi audience là parents/public).
- `LyceumCoachManager.swift`: `systemPrompt + topicContextLine() + profileContextLine()`
  (`profileContextLine()` mới, đọc `contextLineForModel`).
- `ClickyAnalytics.swift` (241): 3 event mới — `trackLyceumOnboardingCompleted(gradeKind:audienceKinds:hasOtherAudienceNote:isCompetition:agentsCustomised:)`,
  `trackLyceumAgentSaved(criteriaCount:hasOwnName:)`, `trackLyceumSettingsOpened(section:)`.
  **Chỉ số, không bao giờ gửi tên trường/tên cuộc thi.**
- `LyceumDashboardView.swift` (1573): `DashboardTab` còn `overview, progress, runs, guide`;
  `sidebarSettingsRow` (nút ⚙ góc dưới) → `.sheet` settings; `@ObservedObject appearance` +
  `.lyceumColorScheme(appearance.colorScheme)` (đã bỏ hard-code `.dark`); tôi thêm
  `isShowingAgentStudio`, `profileStore`, `.overlay` onboarding khi `!hasCompletedOnboarding`,
  `.sheet` studio, và `finishOnboarding()` (tuning → gán `audience.members` → analytics → reloadData).
- `LyceumAgentStudio.swift`: chip gọi `mutate` rồi `trackLyceumAgentSaved`.
- `LyceumDashboardSettingsView.swift`: `.onChange(of: selection)` → `trackLyceumSettingsOpened`.
- `leanring_buddyApp.swift`: `LyceumAppearanceController.shared.apply()` ngay sau `register(defaults:)`;
  và `if !LyceumProfileStore.shared.hasCompletedOnboarding { companionManager.openLyceumDashboard() }`
  (API có thật: `CompanionManager.openLyceumDashboard()` dòng 135; notification `.lyceumOpenDashboard`).

## Landing (repo cùng cấp, đã xong một phần)

`/home/ubuntu/presentation/landing`: "sau khi cài" đổi thành **4 bước** khớp flow thật
(dmg → Applications → 4 câu hỏi onboarding → quyền → luyện). `node scripts/check-i18n.mjs` =
**179 keys, parity OK**. Chưa commit (sẽ commit cùng đợt này).

## CÒN LẠI (thứ tự)

1. Docs: `README.md` (heading: "## The Lyceum" dòng 1, "### A dashboard for a term of practice" 46,
   "### It only starts in a slide tool" 51, "### Permissions the app needs" 204,
   "## Project structure" 226, "## Landing page" 256) + `AGENTS.md` (bảng Key Files, luật self-update).
   Cần mô tả: gear settings, onboarding 5 câu, agent studio ≤5 tiêu chí, theme, data section.
2. `git add` + commit + push `main` (token GitHub: user dán trong chat, KHÔNG lưu vào file;
   dùng `umask 077` + `/tmp/ght` + `GIT_ASKPASS`, xoá sau khi push). Attribution:
   `git -c user.name="Manus" -c user.email="dev-agent@manus.ai" commit` + trailer
   `Co-authored-by: Manus <dev-agent@manus.ai>`.
3. Cập nhật `/home/ubuntu/The-Lyceum-Handoff.md` thêm "Đợt 5".
4. Báo user: build cần Cmd+R trên máy họ; list 4 runtime check họ nên làm.

## Rủi ro thật (nói thẳng với user khi bàn giao)

- Không compiler ⇒ lỗi kiểu/còn sót chỉ bắt được khi build thật trên Xcode.
- Onboarding overlay nằm trên dashboard: nếu user đóng dashboard khi chưa xong thì lần mở lại
  mới hiện tiếp (đã chủ đích, note trong code).
- `LyceumAudienceTuning` ghi đè `persona` của seat mặc định nếu user chưa tự sửa ⇒ chủ đích,
  nhưng nếu họ muốn giữ nguyên văn 5 vai gốc thì phải bấm "Restore the five defaults" sau onboarding.

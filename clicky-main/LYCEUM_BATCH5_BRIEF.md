# The Lyceum — đợt 5: settings sau bánh răng, onboarding, agent studio

Repo `/home/ubuntu/presentation/clicky-main`, nguồn ở `leanring-buddy/`.
Không có Xcode ở đây: code phải tự kiểm bằng `python3 /tmp/swiftcheck.py <file…>`
(cân bằng ngoặc + API tham chiếu) và đọc file thật trước khi sửa.

## Yêu cầu của user (verbatim ý)

1. Ở dashboard: **mọi thứ thuộc về cài đặt** (giọng nói, dữ liệu, theme, v.v.) dồn vào
   một **nút bánh răng đặt ở góc dưới**.
2. Sau khi tải dmg, kéo vào Applications, mở lên → **onboarding** hỏi: học **lớp mấy**;
   chuẩn bị trình bày cho **đối tượng nào** (thầy cô, bạn bè, hội đồng/giám khảo, …
   **chọn nhiều** + có **Other** tự ghi); **có phải cuộc thi không** + **tên cuộc thi**.
3. Sau đó user **tự set up 5 agent** của mình: tên, **chức năng** (chọn nhiều: đặt câu hỏi,
   phê bình, …), **tính cách**, **điểm chú trọng**. Tóm lại: một bản customization toàn
   diện nhưng **tối đa 5 tiêu chí / agent**.

## Sự thật đã đọc trong code (đừng tự bịa API)

- `LyceumDashboardView.swift` (2294 dòng): `enum DashboardTab { overview, progress, runs,
  voice, room, rules, guide }` với `title/symbol/subtitle`; `sidebar` = identity +
  `ForEach(DashboardTab.allCases)` + `Spacer` + `sidebarFooter` (rộng `Self.sidebarWidth = 200`);
  `body` có `.background(DS.Colors.background).environment(\.colorScheme, .dark)` — **dark
  bị hard-code**, chỗ này phải nối vào controller theme.
  `detailColumn` switch tới `overviewTab/progressTab/runsTab/voiceTab/roomTab/rulesTab/guideTab`
  (dòng ~267-279). `init(coach:audience:gate:companion:onClose:)`.
- `LyceumAudience.swift`: `LyceumAudienceMember { id, name, role, persona, tone,
  avatarSymbol, elevenLabsVoiceID? }` (Codable, tổng hợp), `LyceumAudienceTone
  { gentle, standard, brutal }` có `displayName/briefForModel/speechRate/speechPitch`,
  `LyceumAudienceRoster.maximumMembers = 6`, `minimumMembers = 1`, `defaultMembers` (5 người),
  `load/save/resetToDefault` qua UserDefaults key `lyceumAudienceRoster`.
- `LyceumAudienceManager`: `@Published var members: [LyceumAudienceMember] { didSet
  LyceumAudienceRoster.save(members) }` — **đây là nguồn roster sống**, Agent Studio bind vào
  nó, đừng tạo store song song. Có `addMember()` (chặn khi ≥ maximumMembers),
  `resetRosterToDefault()`, `maximumQuestions`, `areAgentsMuted`, `areCaptionsShown`,
  `isPanelEnabled`, `skipsUnansweredPrompts`, `unansweredTimeoutSeconds`.
  Prompt: `LyceumAudiencePrompts.panelSystemPrompt(roster:)`.
- `LyceumCoachManager`: settings @Published + UserDefaults riêng từng key
  (`selectedMode, sessionTopic, monitorsClosingSignals, areLiveNudgesEnabled,
  measuresDelivery, isPresenceCameraEnabled, cameraIntervalSeconds`),
  `LyceumCoachPrompts.systemPrompt(for:)` + `runContext(mode:…)` là chỗ nhét ngữ cảnh người học.
- `DesignSystem` token: `DS.Colors.{background,surface1,borderSubtle,textPrimary,
  textSecondary,textTertiary,blue400,…}`, `DS.CornerRadius.{small,medium,large}`,
  `.pointerCursor()`, font hệ thống (không có `DS.Font`).
- UI app **đang là tiếng Anh** ("Voice & camera", "Overview"). Giữ tiếng Anh cho nhãn mới
  để app không nửa Tây nửa Ta; phần tiếng Việt thuộc về landing page.

## Hợp đồng 3 file mới (các agent chỉ được đụng file mình sở hữu)

### A. `LyceumOnboarding.swift` — profile + onboarding (agent 1)

```swift
enum LyceumGrade: Codable, Equatable { case k12(Int); case university; case other(String) }
enum LyceumAudienceKind: String, CaseIterable, Codable {
    case teachers, classmates, judgingPanel, parents, club, publicAudience, other
    var displayName: String; var symbol: String
}
struct LyceumLearnerProfile: Codable, Equatable {
    var grade: LyceumGrade?              // nil = chưa trả lời
    var audiences: [LyceumAudienceKind]  // chọn nhiều
    var otherAudienceNote: String        // chỉ dùng khi có .other
    var isCompeting: Bool
    var competitionName: String
    var competitionOrganiser: String     // tuỳ chọn, để trống được
    var completedOnboardingAt: Date?
}
final class LyceumProfileStore: ObservableObject {   // @MainActor
    static let shared
    @Published private(set) var profile: LyceumLearnerProfile
    var hasCompletedOnboarding: Bool { get }
    func update(_ mutate: (inout LyceumLearnerProfile) -> Void)  // tự save
    func markCompleted()
    func restartOnboarding()             // xoá cờ để xem lại
    var contextLineForModel: String      // 1 dòng EN cho prompt, ví dụ:
    // "Learner: grade 11, presenting to teachers and a judging panel, competition —
    //  'Cuộc thi KHKT cấp thành phố'. Grade their talk accordingly."
}
struct LyceumOnboardingView: View {
    // LyceumOnboardingView(profile:onOpenAgentStudio:onFinish:)
    // 5 bước: welcome → grade → audiences (chips multi + Other text field)
    // → competition (toggle, hiện 2 field khi bật) → agents (2 nút: giữ default /
    //   mở studio) → done. Progress dots, Back/Continue, Enter/Escape hợp lệ.
}
```
Ràng buộc: không force-unwrap; mọi thứ persist bằng một key UserDefaults
`lyceumLearnerProfile`; decode lỗi → profile rỗng (không crash); không mạng, không file.

### B. `LyceumAudience.swift` (sửa) + `LyceumAgentStudio.swift` (mới) — agent 2

Thêm vào `LyceumAudienceMember` các field **optional** để dữ liệu cũ vẫn decode được:
```swift
var functions: [String]?   // rawValue của LyceumAgentFunction
var traits: [String]?      // rawValue của LyceumAgentTrait
var focus: [String]?       // rawValue của LyceumAgentFocus
```
Enum mới (String, CaseIterable, Codable, mỗi case có `displayName`, `symbol`,
`briefForModel` — dòng ngắn viết cho model):
- `LyceumAgentFunction`: `asksQuestions, critiques, factChecks, suggestsSlideEdits,
  checksClarity, keepsTime, encourages, playsDevilsAdvocate`
- `LyceumAgentTrait`: `curious, blunt, patient, skeptical, warm, strict, playful, formal`
- `LyceumAgentFocus`: `evidence, structure, mechanism, plainLanguage, claimsMatters,
  slidesAndVisuals, delivery, originality`
Rule **tối đa 5 tiêu chí/agent** (functions+traits+focus, không tính tên):
```swift
var criteriaCount: Int { (functions?.count ?? 0) + (traits?.count ?? 0) + (focus?.count ?? 0) }
static let maximumCriteria = 5
var isAtCriteriaLimit: Bool
func toggling(_ kind: …, _ raw: String) -> LyceumAudienceMember  // pure, từ chối cái thứ 6
var criteriaSummaryForModel: String  // "Asks questions, fact-checks · skeptical · evidence, mechanism"
```
`LyceumAudienceRoster.maximumMembers`: **6 → 5** và `defaultMembers` vẫn 5 ✓.
`panelSystemPrompt(roster:)`: mỗi member in thêm `criteriaSummaryForModel` khi có,
nếu không thì giữ `persona` như cũ.
`LyceumAgentStudioView(audience:onClose:)`: danh sách 5 agent, chọn 1 để sửa
(tên, avatar symbol picker đơn giản, tone 3 nút, 3 nhóm chip, bộ đếm "3/5 tiêu chí",
nút "Clear" cho từng agent, "Restore the five defaults" cho cả phòng), khi chạm trần thì
chip disabled + hint giải thích tại sao. Bind thẳng vào `audience.members`.

### C. `LyceumTheme.swift` (mới) + `LyceumDashboardSettingsView.swift` (mới) + sửa
`LyceumDashboardView.swift` — agent 3

`LyceumAppearanceController: ObservableObject` (`@MainActor`): `mode { system, light, dark }`
(UserDefaults `lyceumAppearanceMode`), `apply()` set `NSApp.appearance`, gọi lúc launch;
`colorSchemeOverride` để dashboard dùng thay vì hard-code `.dark`.
`LyceumDashboardSettingsView`: sheet ~760×560, rail trái + nội dung phải, các mục:
**Voice & camera** (chuyển nguyên nội dung `voiceTab` cũ), **Room** (nội dung `roomTab` cũ
+ nút mở Agent Studio), **Rules** (`rulesTab` cũ), **Data** (mới: số run đã lưu, dung lượng
thư mục, "Open folder", "Export all as JSON", "Delete runs older than…" + xác nhận inline,
ghi nhớ camera frames), **Appearance** (theme mode, accent, giảm hiệu ứng), **Getting started**
(chạy lại onboarding). Giữ đúng DS tokens.
`LyceumDashboardView`: xoá `voice/room/rules` khỏi `DashboardTab` (giữ overview, progress,
runs, guide), thêm nút `gearshape` ở **góc dưới sidebar** (dưới `sidebarFooter`, cùng hàng với
dòng "n run(s) saved"), `@State isShowingSettings` + `.sheet`; `body` bỏ
`.environment(\.colorScheme, .dark)` → dùng controller. Phần thân của 3 tab cũ phải **chuyển
sang settings view**, không để code chết.

## Ai làm gì (tôi giữ các file nối)

- Agent 1: `LyceumOnboarding.swift` (mới, duy nhất).
- Agent 2: `LyceumAudience.swift`, `LyceumAgentStudio.swift`.
- Agent 3: `LyceumTheme.swift`, `LyceumDashboardSettingsView.swift`, `LyceumDashboardView.swift`.
- Tôi: `LyceumDashboardWindowManager.swift` (nối onboarding + theme lúc launch),
  `LyceumCoachManager.swift` + `LyceumCoachPrompts.swift` (nhét `contextLineForModel`),
  `CompanionManager.swift` (menu/gọi onboarding), `ClickyAnalytics.swift` (event), README/AGENTS.

Báo cáo về: đường dẫn file, số dòng, kết quả swiftcheck, API công khai cuối cùng (nếu lệch
hợp đồng), và 3 dòng "cần tôi nối gì". Không commit.

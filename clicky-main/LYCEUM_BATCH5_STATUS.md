# Đợt 5 — ĐÃ SHIP (2026-11-15 21:07, commit `d1f4de5` + `e94c8c4`)

File này dành cho agent kế tiếp. Những gì bên dưới là API đã kiểm bằng script, không phải ý định.

## Kiểm chứng (chạy lại được)

- `python3 /tmp/swiftcheck.py <files>` — cân bằng ngoặc + API có tồn tại. Kết quả: 16 file, 0 issue.
- `python3 /tmp/xcheck_batch5.py` — mọi `Type.member` của các type mới phải có khai báo.
  dương tính giả đã biết: comment đầu file (`//  X.swift`) và biến local tên `profile` thật ra là store.
- KHÔNG có Swift compiler ở đây ⇒ build thật vẫn phải làm bằng Cmd+R trên máy Mac.

## API đáng nhớ

`LyceumProfileStore.shared` (`lyceumLearnerProfile`)
: `profile`, `hasCompletedOnboarding`, `update(_:)`, `markCompleted()`, `restartOnboarding()`,
`contextLineForModel: String` (rỗng khi chưa có hồ sơ ⇒ prompt không đổi).
`LyceumLearnerProfile`: `grade: LyceumGrade?`, `audiences: [LyceumAudienceKind]`,
`otherAudienceNote`, `isCompeting`, `competitionName`, `competitionOrganiser`,
`completedOnboardingAt`, `hasAnyAnswer`, `gradeKindForAnalytics` (chỉ `k12`/`university`/`other`/`none`).
`LyceumOnboardingView(profile:onOpenAgentStudio:onFinish:)` — view TỰ `markCompleted()` rồi mới gọi
`onFinish()`. Host không được đánh dấu hoàn tất hộ.

`LyceumAudienceTuning` (trong `LyceumAudience.swift`)
: `schoolYear(of:)`, `isSeatCustomised(_:)`, `customisedSeatCount(in:)`, `tuned(_:for:)`.
Bất biến quan trọng: **ghế đã có criteria không bị viết lại**; chỉ roster mặc định bị nắn.
`LyceumAudienceMember`: `functions/traits/focus: [String]?` (optional ⇒ data cũ decode được),
`maximumCriteria = 5`, `criteriaCount`, `hasCriteria`, `isAtCriteriaLimit`, `criteriaSlotsLeft`,
`isSelected(_:)`, `toggling(_:)` (pure, từ chối cái thứ 6), `criteriaSummaryForModel`,
`criteriaBriefsForModel`, `hasOwnName`. `LyceumAudienceRoster.maximumMembers = 5`.

`LyceumAppearanceController.shared` (`lyceumAppearanceMode`, `lyceumReduceMotion`)
: `mode`, `colorScheme: ColorScheme?`, `apply()` — gọi ở `applicationDidFinishLaunching`.
View: dùng `.lyceumColorScheme()` (không tham số) cho mọi thứ dựng một lần trong `NSHostingView`
(panel), vì nó giữ subscription sống. Cấm viết lại `.environment(\.colorScheme, .dark)`.

`LyceumDashboardSettingsView(coach:audience:gate:companion:)` — sheet 760×560,
`enum SettingsSection: String` (`voice`, `room`, `rules`, `data`, `appearance`, `gettingStarted`);
`rawValue` được dùng làm tên bucket analytics ⇒ đừng đổi case mà không biết analytics đổi theo.
`LyceumAgentStudioView(audience:onClose:)` — write path duy nhất là `mutate(_:_)` → `audience.members`
(`didSet` tự lưu).

Analytics mới (toàn bộ là scalar): `lyceum_onboarding_completed`, `lyceum_agent_saved`,
`lyceum_settings_opened`. Không chữ ký nào nhận tên trường/tên cuộc thi/transcript.

## Dashboard giờ chỉ còn 4 tab

`DashboardTab = overview | progress | runs | guide`. Cài đặt nằm sau ⚙ dưới góc sidebar
(`sidebarSettingsRow`). Onboarding là `.overlay` toàn cửa sổ khi `!hasCompletedOnboarding`,
và `finishOnboarding()` là chỗ duy nhất áp tuning + báo analytics.

## Landing (`/landing`)

"Sau khi cài" = 4 bước khớp flow thật (dmg → Applications → 4 câu hỏi → quyền → luyện).
`node scripts/check-i18n.mjs` = 179 keys, parity Việt/Anh. Link tải vẫn là
`landing/download-config.json` (chưa có asset release ⇒ hiển thị "coming soon" + ★ tự chọn bản
theo máy). Pages deploy #4 = success.

## Việc kế tiếp nên làm

1. Onboarding/tuning mới chỉ được kiểm bằng đọc code. Chạy 5 bước test ở
   `/home/ubuntu/The-Lyceum-Handoff.md` (mục Đợt 5) trên máy Mac trước khi thêm tính năng.
2. Nếu theme Light lộ chỗ nào lệch (màu hard-code còn sót trong panel cũ), sửa bằng DS tokens,
   không thêm màu mới.
3. `Data → Delete runs older than` dùng `LyceumSessionStore`; nếu sau này thêm archive, nhớ rằng
   exports đang gộp mọi session vào một file JSON.
4. Camera và voice dials (đợt 3) vẫn chưa có "onboarding frequency" đầy đủ — user hẹn chỉnh tần suất
   và mức độ trong onboarding; giờ đã có chỗ (Getting started) để nối mà không tạo màn hình mới.

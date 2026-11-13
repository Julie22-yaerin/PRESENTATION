# AI Bubble

Ứng dụng Electron desktop (cross-platform) gồm hai phần:

1. **Dashboard** — trung tâm cấu hình, sức khỏe hệ thống và lịch sử phiên hỏi.
2. **Bong bóng AI overlay** — một viên bubble bo tròn luôn nổi trên mọi ứng dụng. Khi bạn bấm phím nóng, app **nghe mic** và **chụp màn hình đúng khoảnh khắc đó**, gửi cả hai cho AI, rồi trả lời ngay trong bubble.

```
bấm ⇧⇧  →  nghe + chụp  →  nói câu hỏi  →  bấm ⇧⇧  →  AI trả lời trong bubble
```

---

## Ảnh chụp từ chính app

Cả bốn ảnh dưới đây do `npm run ui:shots` render từ Electron thật (Xvfb 1440×900), không phải mockup.

| Dashboard Tổng quan | Bong bóng đang trả lời |
| --- | --- |
| ![Dashboard tổng quan](https://private-us-east-1.manuscdn.com/sessionFile/lGeLWuDhOcjdcmJyvRAdWN/sandbox/acgiMdY0ymdlnA6Uuq4GrG-images_1794577228493_na1fn_L2hvbWUvdWJ1bnR1L2FpLWJ1YmJsZS9kb2NzL3NjcmVlbnNob3RzL2Rhc2hib2FyZC1vdmVydmlldw.png?Policy=eyJTdGF0ZW1lbnQiOlt7IlJlc291cmNlIjoiaHR0cHM6Ly9wcml2YXRlLXVzLWVhc3QtMS5tYW51c2Nkbi5jb20vc2Vzc2lvbkZpbGUvbEdlTFd1RGhPY2pkY21KeXZSQWRXTi9zYW5kYm94L2FjZ2lNZFkweW1kbG5BNlV1cTRHckctaW1hZ2VzXzE3OTQ1NzcyMjg0OTNfbmExZm5fTDJodmJXVXZkV0oxYm5SMUwyRnBMV0oxWW1Kc1pTOWtiMk56TDNOamNtVmxibk5vYjNSekwyUmhjMmhpYjJGeVpDMXZkbVZ5ZG1sbGR3LnBuZyIsIkNvbmRpdGlvbiI6eyJEYXRlTGVzc1RoYW4iOnsiQVdTOkVwb2NoVGltZSI6MTc5NjA4MzIwMH19fV19&Key-Pair-Id=K2QY5QTL8JSY6C&Signature=MEUCIQD6vJvZVmykQTvaC~raw54ZiyrTmSUWSldB-kNGTqRQEQIgPTL5a2EfV9bPuNyuCCOQq4uvr20c603-xNzyETL6E1I_) | ![Bong bóng AI](https://private-us-east-1.manuscdn.com/sessionFile/lGeLWuDhOcjdcmJyvRAdWN/sandbox/acgiMdY0ymdlnA6Uuq4GrG-images_1794577228493_na1fn_L2hvbWUvdWJ1bnR1L2FpLWJ1YmJsZS9kb2NzL3NjcmVlbnNob3RzL2J1YmJsZS1hbnN3ZXI.png?Policy=eyJTdGF0ZW1lbnQiOlt7IlJlc291cmNlIjoiaHR0cHM6Ly9wcml2YXRlLXVzLWVhc3QtMS5tYW51c2Nkbi5jb20vc2Vzc2lvbkZpbGUvbEdlTFd1RGhPY2pkY21KeXZSQWRXTi9zYW5kYm94L2FjZ2lNZFkweW1kbG5BNlV1cTRHckctaW1hZ2VzXzE3OTQ1NzcyMjg0OTNfbmExZm5fTDJodmJXVXZkV0oxYm5SMUwyRnBMV0oxWW1Kc1pTOWtiMk56TDNOamNtVmxibk5vYjNSekwySjFZbUpzWlMxaGJuTjNaWEkucG5nIiwiQ29uZGl0aW9uIjp7IkRhdGVMZXNzVGhhbiI6eyJBV1M6RXBvY2hUaW1lIjoxNzk2MDgzMjAwfX19XX0_&Key-Pair-Id=K2QY5QTL8JSY6C&Signature=MEQCIBwl~d6grYOez6xTLjudA5L0tK8jFxIylgG1LEp4MMXDAiBtTL-jlb6MiSFO0NP6HjrtyE7XnLe94k6p7ijXam13wg__) |
| ![Dashboard sau một phiên](https://private-us-east-1.manuscdn.com/sessionFile/lGeLWuDhOcjdcmJyvRAdWN/sandbox/acgiMdY0ymdlnA6Uuq4GrG-images_1794577228493_na1fn_L2hvbWUvdWJ1bnR1L2FpLWJ1YmJsZS9kb2NzL3NjcmVlbnNob3RzL2Rhc2hib2FyZC1zZXNzaW9u.png?Policy=eyJTdGF0ZW1lbnQiOlt7IlJlc291cmNlIjoiaHR0cHM6Ly9wcml2YXRlLXVzLWVhc3QtMS5tYW51c2Nkbi5jb20vc2Vzc2lvbkZpbGUvbEdlTFd1RGhPY2pkY21KeXZSQWRXTi9zYW5kYm94L2FjZ2lNZFkweW1kbG5BNlV1cTRHckctaW1hZ2VzXzE3OTQ1NzcyMjg0OTNfbmExZm5fTDJodmJXVXZkV0oxYm5SMUwyRnBMV0oxWW1Kc1pTOWtiMk56TDNOamNtVmxibk5vYjNSekwyUmhjMmhpYjJGeVpDMXpaWE56YVc5dS5wbmciLCJDb25kaXRpb24iOnsiRGF0ZUxlc3NUaGFuIjp7IkFXUzpFcG9jaFRpbWUiOjE3OTYwODMyMDB9fX1dfQ__&Key-Pair-Id=K2QY5QTL8JSY6C&Signature=MEQCIDEUtSXXCgug-ky7w2eXl5Sx6WybeDPBcsZMi3oul3JxAiAagYalBa2tss0T4Ih8MDsyjNQW6zh~JzH5NxB7G3zrZQ__) | ![Tab Cài đặt](https://private-us-east-1.manuscdn.com/sessionFile/lGeLWuDhOcjdcmJyvRAdWN/sandbox/acgiMdY0ymdlnA6Uuq4GrG-images_1794577228493_na1fn_L2hvbWUvdWJ1bnR1L2FpLWJ1YmJsZS9kb2NzL3NjcmVlbnNob3RzL2Rhc2hib2FyZC1zZXR0aW5ncw.png?Policy=eyJTdGF0ZW1lbnQiOlt7IlJlc291cmNlIjoiaHR0cHM6Ly9wcml2YXRlLXVzLWVhc3QtMS5tYW51c2Nkbi5jb20vc2Vzc2lvbkZpbGUvbEdlTFd1RGhPY2pkY21KeXZSQWRXTi9zYW5kYm94L2FjZ2lNZFkweW1kbG5BNlV1cTRHckctaW1hZ2VzXzE3OTQ1NzcyMjg0OTNfbmExZm5fTDJodmJXVXZkV0oxYm5SMUwyRnBMV0oxWW1Kc1pTOWtiMk56TDNOamNtVmxibk5vYjNSekwyUmhjMmhpYjJGeVpDMXpaWFIwYVc1bmN3LnBuZyIsIkNvbmRpdGlvbiI6eyJEYXRlTGVzc1RoYW4iOnsiQVdTOkVwb2NoVGltZSI6MTc5NjA4MzIwMH19fV19&Key-Pair-Id=K2QY5QTL8JSY6C&Signature=MEQCIF2ffwD4Q1dDpfl3Lx9KKUHAcAng~yEl9f5TQUWXTgdMAiBNMzE9e-rLTX~U9KATXtEaljav02HEm5wOnXNMTSu~XQ__) |

## Tính năng

| Nhóm | Nội dung |
| --- | --- |
| Kích hoạt | Bấm đúp (mặc định) hoặc bấm một lần Shift / Command / Fn / Ctrl / Alt hoặc phím tự học; kèm phím dự phòng toàn cục `Alt+Shift+Space`; bật/tắt bằng công tắc |
| Thu nhận | `desktopCapturer` chụp màn hình nơi con trỏ đang ở (JPEG thu nhỏ theo cấu hình), mic ghi PCM 16 kHz mono → WAV, không cần ffmpeg |
| AI | Endpoint tương thích OpenAI (bất kỳ baseUrl nào), hai chiến lược: **audio + ảnh trong một lượt gọi** (multimodal) hoặc **chữ hoá trước** (whisper-1 → vision model). Trả lời stream về bubble, tự thử lại khi endpoint không hỗ trợ stream |
| Overlay | Always-on-top mọi Space/desktop, trong suốt, click-through (chỉ tương tác khi con trỏ vào bubble), kéo thả và lưu vị trí, tự đóng sau N giây, `Ctrl/Cmd+C` copy cả câu trả lời, `Esc` đóng |
| Dashboard | Tổng quan + health check, Lịch sử (ảnh, bản ghi WAV phát lại, transcript, kết quả, timing, ghim, xoá, xuất JSON), Cài đặt đầy đủ, Hướng dẫn theo từng OS |
| Hệ thống | Tray icon (nếu desktop hỗ trợ), chạy nền khi đóng dashboard, single-instance, mở khi đăng nhập, API key mã hoá bằng kho của hệ điều hành |

## Yêu cầu

- Node.js 20+ và npm
- Electron 45 (tự tải khi `npm install`)
- `uiohook-napi` (binary native) — cần công cụ build nếu Electron không có sẵn prebuild cho nền tảng của bạn
- Linux: thư viện X11/GTK cho Electron: `libxcomposite1 libxdamage1 libxrandr2 libnss3 libgbm1 libasound2 libatk-bridge2.0-0 libcups2`

## Cài đặt & chạy

```bash
npm install
npm run dev          # electron-vite dev (HMR, 2 cửa sổ)
npm run build        # xuất ra out/
npm start            # chạy bản build
```

Kiểm chứng nhanh bằng chính app (không cần thao tác tay):

```bash
npm run typecheck    # tsc cho node target + web target
npm run smoke        # boot Electron trong Xvfb: chụp màn hình thật + một lượt gọi AI thật
npm run ui:shots     # kết xuất dashboard + bubble thật ra shots/*.png
```

`smoke` và `ui:shots` cần key trong môi trường: `OPENAI_API_KEY` (hoặc `AIBUBBLE_API_KEY`) và `OPENAI_API_BASE` (hoặc `AIBUBBLE_BASE_URL`).

## Đóng gói từng nền tảng

```bash
npm run package -- --mac     # .dmg + .zip (arm64, x64)
npm run package -- --win     # NSIS installer .exe (x64)
npm run package -- --linux   # AppImage + .deb
```

Cấu hình electron-builder nằm trong `package.json` (khối `build`), icon sinh bằng `npm run icons`.

### macOS

- Cần 2 quyền trong **System Settings → Privacy & Security**: **Microphone** và **Screen Recording**. Sau khi cấp Screen Recording phải khởi động lại app.
- Phím **Fn** thường bị macOS giữ cho Đổi bàn phím / Mission Control. Nếu “Học phím” không bắt được Fn, hãy gán **Command (⌘)** hoặc dùng phím dự phòng. (Trong `uiohook`, ⌘ có mã 3675/3676 nên vẫn hook được.)
- Bản build chưa ký: lần mở đầu cần chuột phải → Open, hoặc `xattr -dr com.apple.quarantine`.

### Windows

- **Settings → Privacy & security → Microphone** → bật cho app desktop.
- Phím **Shift** là lựa chọn an toàn nhất; phím **Win** hay bị system shortcut chiếm.

### Linux

- **X11**: đầy đủ (hook bàn phím + overlay always-on-top).
- **Wayland**: compositor chặn hook bàn phím toàn cục và đôi khi chặn always-on-top → app tự rơi về phím dự phòng. Để có trải nghiệm gốc, đăng nhập phiên “Xorg”.
- Chạy trực tiếp từ source trong container/CI cần `--no-sandbox` (script smoke tự bật qua `AIBUBBLE_NO_SANDBOX=1`).

## Hành vi phím nóng (đọc nếu thấy “bấm không ăn”)

- Mặc định là **bấm đúp**: hai lần nhấn–nhả liên tiếp của cùng một phím, mỗi lần dưới 450 ms, khoảng nghỉ giữa hai lần dưới 600 ms.
- Nếu trong lúc giữ phím có bất kỳ phím nào khác được bấm (vd. `Shift+A` gõ hoa), lần bấm đó **bị loại** — tránh kích hoạt khi bạn đang gõ.
- Bấm lần thứ hai khi đang nghe = **dừng và gửi**. Đang phân tích thì bấm lại = bỏ qua.
- Đổi sang **Bấm một lần** trong Cài đặt → Phím nóng nếu bạn chắc chắn (dễ kích hoạt nhầm khi gõ hoa).
- Phím dự phòng dùng `globalShortcut` của Electron, luôn hoạt động kể cả khi hook bàn phím bị chặn.

## Dữ liệu

Tất cả nằm trong `app.getPath('userData')` (macOS: `~/Library/Application Support/AI Bubble`, Windows: `%APPDATA%\AI Bubble`, Linux: `~/.config/AI Bubble`):

```
settings.json          # cấu hình, không chứa key
history.json           # danh mục phiên
vault.bin              # API key đã mã hoá (safeStorage)
captures/<id>/         # screenshot.jpg · audio.wav · meta.json
```

Xoá một phiên trong Lịch sử sẽ xoá luôn tệp; “Xuất JSON” lưu toàn bộ metadata ra tệp bạn chọn (không kèm ảnh/audio).

## Kiến trúc

```
src/main/         index.ts (bootstrap, IPC, health, smoke/shot mode)
                  session.ts (máy trạng thái phiên: arming→listening→thinking→answer)
                  capture.ts (desktopCapturer + resize/JPEG)
                  ai.ts (chat completions + audio transcriptions, SSE-tolerant)
                  hotkeys.ts (uiohook tap/double-tap + globalShortcut fallback + learn-key)
                  overlay.ts / dashboard.ts (cửa sổ), store.ts (settings/history/vault), tray.ts
src/preload/      bridge duy nhất, contextIsolation bật, không Node trong renderer
src/renderer/     dashboard/ (React, 4 tab) + overlay/ (Bubble + useRecorder PCM→WAV)
src/shared/       types.ts, ipc.ts, bridge.ts — hợp đồng dùng chung ba bên
```

## Giới hạn đã biết

- AI chỉ nhìn được **một khoảnh khắc tĩnh** tại thời điểm bấm, không thấy nội dung cuộn ra sau đó, không thấy nội dung được DRM bảo vệ (ngân hàng, trình phát).
- Overlay không nổi trên một số chế độ full-screen chiếm quyền màn hình của app khác (hành vi hệ điều hành).
- Endpoint không hỗ trợ `input_audio` sẽ tự chuyển sang đường whisper-1; nếu endpoint cũng không có `/audio/transcriptions` thì phần giọng nói bị bỏ và chỉ ảnh được gửi (app ghi cảnh báo vào phiên).
- Chụp màn hình bằng `desktopCapturer` chậm hơn native API (~0,1–0,4 s); ảnh được chụp song song với lúc bật mic để độ trễ không cộng dồn.

## Gỡ lỗi

- Mở DevTools dashboard: `Ctrl/Cmd+Shift+I`.
- xem log main trên terminal (`npm start`), dòng `[ai-bubble] ready · …` in ra trạng thái hotkey và thư mục dữ liệu.
- “Không lấy được ghi âm từ overlay” → mic chưa được cấp quyền; “Câu trả lời rỗng” → tăng Max tokens; “Streaming is not supported” đã được xử lý tự động.

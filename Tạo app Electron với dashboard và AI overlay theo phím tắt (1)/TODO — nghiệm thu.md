# TODO — nghiệm thu

Trạng thái: **toàn bộ hạng mục MVP đã chạy và đã đo**. Mục chưa kiểm chứng được trong sandbox ghi rõ ở cuối.

## 1. Khung ứng dụng

- [x] Electron 45.3.1 + electron-vite 6 + React 19 + TypeScript 7, ba target main/preload/renderer với hai entry (`index.html`, `overlay.html`)
- [x] `npm run typecheck` sạch cho cả `tsconfig.node.json` và `tsconfig.web.json`
- [x] Cửa sổ dashboard (1320×860, đóng = ẩn, app vẫn chạy nền), `contextIsolation: true`, không nodeIntegration
- [x] Cửa sổ overlay trong suốt, không viền, bo tròn, always-on-top trên mọi Space/desktop, click-through
- [x] `uiohook-napi` là dependency, `externalizeDepsPlugin` + `asarUnpack` giữ native binary
- [x] `plan.md` mô tả kiến trúc, luồng dữ liệu, risk register; `NOTES.md` ghi các sự thật đã đo

## 2. Bong bóng overlay

- [x] `idle` → `arming` → `listening` → `thinking` → `answer` / `error`; bấm lại = dừng và gửi
- [x] Visualizer mức âm thanh thật (RMS từ PCM, cập nhật 90 ms), không animation giả
- [x] Câu trả lời hiển thị trong bong bóng (stream khi endpoint hỗ trợ, nguyên khối khi không)
- [x] Nút copy kết quả, nút mở lịch sử, ô gõ chữ để hỏi khi không tiện nói
- [x] `Ctrl/Cmd+C` copy nguyên câu trả lời (khi không có selection), `Esc` đóng
- [x] Kéo thả bubble, giới hạn trong work area, lưu vị trí vào settings, neo lại khi đổi resolution
- [x] Tự đóng về idle sau `overlay.autoCollapseSeconds` (mặc định 24 s)
- [x] Chỉ nhận chuột khi con trỏ nằm trong bubble (`setIgnoreMouseEvents` + forward); bật keyboard tạm thời khi gõ

## 3. Phím nóng cross-platform

- [x] `uiohook-napi` theo dõi keydown/keyup, phân biệt tap / double-tap với timeout 450 ms / 600 ms
- [x] Chuỗi `Shift+phím khác` (gõ hoa) **không** kích hoạt — chặn bằng combo flag
- [x] `globalShortcut` dự phòng `Alt+Shift+Space` (đổi được), luôn chạy khi hook bị chặn
- [x] macOS ⌘ dùng mã 3675/3676 (uiohook không có `UiohookKey.Meta*`); Windows Ctrl/Alt/Win; Linux Ctrl/Alt/Super
- [x] **Học phím**: main lắng nghe 15 s, ghi `customKeycode` + nhãn tự đoán (cần cho Fn)
- [x] Bật/tắt hoàn toàn bằng settings; Wayland tự chuyển fallback

## 4. Nghe

- [x] Mic bật **ngay khi bấm phím**: overlay ghi PCM 16 kHz mono (`AudioContext` + `ScriptProcessorNode`)
- [x] Đóng WAV tay (`encodeWav`) → `captures/<id>/audio.wav`, không phụ thuộc codec MediaRecorder hay ffmpeg
- [x] `whisper-1` cho đường `transcribe_first`; phát lại bản ghi trong Lịch sử
- [x] Giới hạn `maxRecordSeconds` (mặc định 60 s) tự dừng và gửi
- [x] Không mic / từ chối quyền → bubble hiện nguyên nhân, health báo vàng, phiên vẫn lưu

## 5. Nhìn

- [x] `desktopCapturer` chụp **đúng khoảnh khắc bấm phím** (đo: 1280×720 JPEG ≈ 7,4 KB từ Xvfb 1920×1080)
- [x] Chọn display theo vị trí con trỏ hoặc màn hình chính
- [x] Thu nhỏ theo `capture.maxWidth` + JPEG quality, lưu `captures/<id>/screenshot.jpg`
- [x] Ảnh kèm prompt vision ở cả hai chiến lược; tắt ảnh được bằng settings (chỉ nghe)

## 6. AI client

- [x] OpenAI-compatible qua `baseUrl` bất kỳ (đo với llm-proxy thật): chat completions, audio transcriptions, `/models`
- [x] Hai chiến lược: **multimodal** (audio + ảnh một lượt gọi, đo `aiMs ≈ 3,3 s`) và **transcribe_first**
- [x] Endpoint từ chối stream → **tự thử lại không stream** (hành vi thật đã đo của proxy)
- [x] Endpoint từ chối `input_audio` → tự xoay sang `transcribe_first`, ghi cảnh báo vào phiên
- [x] Model không nhận `reasoning effort` → thử lại không dùng effort
- [x] System prompt, max tokens, timeout, model, stt model chỉnh trong dashboard; không hardcode SDK/nhà cung cấp

## 7. Dashboard

- [x] **Tổng quan**: phiên hiện tại, hướng dẫn 3 bước theo phím thật, health 5 mục, số liệu hôm nay, máy & display, phiên gần đây
- [x] **Lịch sử**: tìm kiếm, lọc, thumbnail, ảnh lớn, transcript, audio player, kết quả, timing, token, ghim, xoá, xuất JSON
- [x] **Cài đặt**: AI · Phím nóng · Nghe & Nhìn · Bong bóng · Khác, lưu/hoàn tác, badge "Chưa lưu", chọn model từ endpoint (badge 👁 vision)
- [x] **Hướng dẫn**: quyền macOS/Windows/Linux, giải thích bấm đúp, bảng 6 sự cố, mục quyền riêng tư
- [x] Tray icon + menu (đo: `tray=true`), single instance, mở khi đăng nhập, ảnh/audio serve qua `aibubble://asset/…`

## 8. Kiểm chứng tự động

- [x] `npm run typecheck` + `npm run build` sạch (`out/main`, `out/preload`, `out/renderer/{index,overlay}.html`)
- [x] `npm run smoke` → exit 0: Electron boot thật, capture thật, uiohook thật (`listening: true`), một lượt AI thật trả lời đúng nội dung màn hình
- [x] `npm run ui:shots` → 5 PNG render từ app thật (`docs/screenshots/`), gồm card bubble đang hiển thị câu trả lời
- [x] Health: key/env OK, 10 model, screen OK, hotkey OK; mic vàng vì Xvfb không có thiết bị — đúng thiết kế

## Còn cần máy của bạn để xác nhận

1. **macOS**: hộp thoại quyền Microphone + Screen Recording; bấm thật của ⌘ và Fn (Fn hay bị system giữ — đã có Học phím + fallback).
2. **Windows**: quyền mic, double-tap Shift khi gõ hoa, installer NSIS (`npm run package -- --win`).
3. **Wayland**: mức độ always-on-top và hook bàn phím (khác nhau theo compositor) — fallback globalShortcut là con đường an toàn.
4. Ghi âm giọng người thật (smoke mới chỉ đo đường ảnh + tone tổng hợp).
5. `.icns` / `.ico` cho bản đóng gói: electron-builder tự sinh từ `build/icon.png`, cần cài thử trên máy đích.

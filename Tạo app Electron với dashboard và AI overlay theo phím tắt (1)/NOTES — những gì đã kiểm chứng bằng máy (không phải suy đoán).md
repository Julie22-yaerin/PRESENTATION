# NOTES — những gì đã kiểm chứng bằng máy (không phải suy đoán)

Ngày ghi: 2026-11-13. Môi trường kiểm chứng: sandbox Linux x64, Electron 45.3.1 (Chromium + Node 22 đi kèm).

## Nền tảng

| Hạng mục | Giá trị đã đo |
| --- | --- |
| Electron | 45.3.1 (Chromium đi kèm, Node 22.x) |
| electron-vite / vite | 6.0.0 / 8.3.8 |
| React | 19.3.1 |
| TypeScript | 7.0.2 (`tsc --noEmit` chạy cho `tsconfig.node.json` và `tsconfig.web.json`) |
| uiohook-napi | 1.5.5 — `UiohookKey` **không có** `Meta*`, `Command*`, `OSX*`; phím ⌘ dùng mã 3675/3676, Fn không có trong bảng mã |
| Chạy trong container | cần `--no-sandbox` (đã bật tự động khi `AIBUBBLE_SMOKE`/`AIBUBBLE_NO_SANDBOX`), và `libxcomposite1`, `libxdamage1`, `libxrandr2` |

## API endpoint (OpenAI-compatible)

`$OPENAI_API_BASE` trỏ tới llm-proxy của Manus (`.../api/llm-proxy/v1`). Đo trực tiếp bằng curl:

- `POST /chat/completions` với `{"stream": true}` trả về **HTTP 200 + JSON `{"error":"Streaming is not supported"}`**.
  Vì thế `ai.ts` thử có stream trước, nếu bị từ chối thì **tự thử lại không stream** và vẫn giao đủ chữ cho bong bóng.
- `POST /audio/transcriptions` chỉ nhận `whisper-1`; các model audio khác (gpt-4o-transcribe, gpt-4o-mini-transcribe) bị từ chối.
- `gpt-6-luna` nhận `input_audio` (WAV base64) **kèm** `image_url` trong cùng một message → chiến lược `multimodal` chạy được.
- Body trả về dùng `max_completion_tokens` cho họ GPT; proxy có trường `capabilities.supports_vision` trong `/models` — UI dùng nó để gắn badge 👁.
- Key: `keySource` = `env` khi không có key trong kho; `OPENAI_API_KEY`/`AIBUBBLE_API_KEY` đều được chấp nhận.

## Kết quả smoke (`npm run smoke`, có AI thật)

Lần chạy cuối: **exit 0, ok = true**.

- Chụp màn hình thật qua `desktopCapturer`: 1280×720 JPEG, 7 394 byte (đã thu nhỏ theo `capture.maxWidth`).
- Hotkey: engine `uiohook`, `listening: true`, nhãn `⇧ (bấm đúp)`, phím dự phòng `Alt+Shift+Space`.
- Lượt gọi đa phương thức (ảnh + WAV): 3,3 s, mô tả đúng nội dung màn hình bằng tiếng Việt; `warnings: []`.
- Cung ghi-âm-trước: whisper trả bản trống cho file tone tổng hợp → app ghi cảnh báo "Ghi âm không ra chữ…" và vẫn trả lời từ ảnh.
- Health: key ok (env), ai ok (10 model), screen ok (1 display), hotkey ok; mic ở mức **cảnh báo** cho tới khi có một phiên thật đo được thiết bị.

## Ảnh UI (`npm run ui:shots`)

`shots/01…05` sinh từ chính app chạy trong Xvfb: dashboard Tổng quan/Cài đặt/Lịch sử, và bong bóng đang hiển thị câu trả lời (card 424px, header có chip "nhập chữ", nút Copy/Lịch sử, ô gõ).

## Những quyết định kỹ thuật đáng nhớ

- **Ghi âm không dùng MediaRecorder**: PCM thô qua `createScriptProcessor` ở 16 kHz mono, đóng WAV tay trong `useRecorder.ts`. Lý do: mọi endpoint nhận WAV, không phụ thuộc codec webm/opus của Chromium và không cần ffmpeg.
- **Tab keyboard toàn cục tự viết** bằng `uiohook-napi` vì Electron không cho phép hook phím thuần modifier làm globalShortcut; đơn tap/double tap tự phân biệt, có timeout 450/600 ms.
- **Bong bóng click-through**: `setIgnoreMouseEvents(true, { forward: true })`, chỉ bật tương tác khi con trỏ nằm trong shell; kéo thả bằng delta `screenX/screenY` gửi lên main.
- **Ảnh/audio mở bằng scheme `aibubble://asset/…`** thay vì `file://` để không phải tắt webSecurity.
- **API key** không nằm trong `settings.json`; mã hoá qua safeStorage (Electron 45 dùng `isAsyncEncryptionAvailable`, đã cache lại).

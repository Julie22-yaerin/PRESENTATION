# AI Bubble — Electron desktop app (plan)

## Sản phẩm

Một app desktop chạy nền gồm 2 phần:

1. **Dashboard** — cửa sổ chính: trạng thái, sức khỏe hệ thống (AI key, mic, screen capture, hotkey engine), lịch sử lượt hỏi, cài đặt.
2. **AI Bubble overlay** — bong tròn bo góc, `alwaysOnTop`, trong suốt, không chiếm focus, nằm trên mọi app (kể cả fullscreen). Bấm phím nóng để **bật** nghe + chụp màn hình đúng khoảnh khắc đó, bấm lần nữa để **tắt** và gửi lên AI; kết quả trả về ngay trong bong bóng.

Quy tắc đã chốt với người dùng: **cross-platform** (macOS/Windows/Linux), **toggle bằng một lần bấm**, **gọi AI API thật** (OpenAI-compatible).

## Kỹ thuật

- **Stack:** Electron + electron-vite + React + TypeScript. Renderer dùng 2 entry: `index.html` (dashboard) và `overlay.html` (bubble).
- **Cửa sổ overlay:** `frame:false`, `transparent:true`, `alwaysOnTop('screen-screen' level → 'screen-saver')`, `skipTaskbar`, `focusable:false` khi thu gọn, `setFocusable(true)` chỉ khi người dùng cần gõ. Chuột xuyên qua (`setIgnoreMouseEvents(true,{forward:true})`) ngoại trừ vùng bong bóng; kéo thả bằng IPC `overlay:drag` để không phá vỡ `ignoreMouseEvents`.
- **Phím nóng:** `uiohook-napi` bắt keydown/keyup globally để nhận diện "tap" của phím thuần (Shift/Command/Fn). Logic: một tap = down→up < 450ms và không có phím khác bấm xen giữa (tránh kích hoạt khi gõ HOA hoặc tổ hợp phím). `single_tap` hoặc `double_tap` (mặc định `double_tap` vì an toàn khi gõ). Fallback chắc chắn bằng `globalShortcut` (mặc định `Alt+Shift+Space`) cho Win/Linux/Wayland, nơi uiohook có thể không đọc được input.
- **Chụp màn hình đúng thời điểm bấm:** trong main, `desktopCapturer.getSources({types:['screen'], thumbnailSize})`, chọn display chứa con trỏ (`screen.getCursorScreenPoint()` + `source.display_id`), scale bằng `nativeImage.resize()`, xuất JPEG làm gọn payload.
- **Thu âm không cần ffmpeg:** overlay renderer dùng `AudioContext({sampleRate:16000})` + `MediaStreamAudioSourceNode` (mono) + `ScriptProcessorNode` gom Float32, tự đóng gói **WAV PCM 16-bit mono 16kHz**. RMS tính từ cùng buffer → visualizer. WAV là định dạng OpenAI-compatible ổn định nhất, dùng được cho cả 2 chiến lược AI. Giới hạn `maxRecordSeconds` (mặc định 60) tự tắt.
- **AI (client tự viết bằng fetch, không thêm SDK):**
  - `strategy: multimodal` (mặc định): MỘT lượt gọi `chat/completions` với `text + image_url(data jpeg) + input_audio(data wav)` → latency thấp nhất.
  - `strategy: transcribe_first`: `POST /audio/transcriptions` (`whisper-1`) → transcript, rồi gọi chat với `text + image_url + transcript`.
  - Tự động fallback multimodal → transcribe_first khi API báo lỗi liên quan audio; nếu STT lỗi thì vẫn trả lời từ screenshot và thông báo mất audio.
  - `stream:true` + parse SSE để chữ hiện dần vào bubble; lỗi stream thì retry non-streaming.
  - Model mặc định `gpt-6-luna` (multimodal, chi phí/thời gian phản hồi thấp). Dòng GPT-5 bị khai tử 2026-12-11 nên không đặt làm mặc định; Dashboard có nút **Tải danh sách model** từ endpoint thật và tick `supports_vision` khi catalog cung cấp.
  - Credential: `safeStorage` của Electron (mã hóa theo máy) lưu trong `userData`; fallback biến môi trường `AIBUBBLE_API_KEY`/`OPENAI_API_KEY` + `AIBUBBLE_BASE_URL`/`OPENAI_API_BASE`.
- **Trạng thái phiên (state machine ở main):** `idle → listening → thinking → answer | error`. Overlay và Dashboard cùng subscribe một snapshot qua IPC broadcast, nên Dashboard hiển thị trực tiếp phiên đang diễn ra.
- **Lưu trữ:** `userData/settings.json` (deep-merge defaults khi migrate), `userData/history.json` (cap `keepHistoryCount`), artifact mỗi phiên ở `userData/captures/<id>/` (`screen.jpg`, `audio.wav`). Ảnh thumbnail hiển thị bằng custom scheme `aibubble://asset/<path>` đã đăng ký `registerSchemesAsPrivileged` (an toàn, không phụ thuộc `file://` subresource).
- **Đóng gói:** `electron-builder` với `mac` (dmg/zip, `NSMicrophoneUsageDescription`, `com.apple.security.screen-capture` entitlements, asarUnpack native module), `win` (nsis), `linux` (AppImage/deb).

## Cấu trúc dự án

```
ai-bubble/
├── package.json                 # scripts dev/build/typecheck/smoke/package + cấu hình electron-builder
├── electron.vite.config.ts      # 3 target: main / preload / renderer (2 entry)
├── plan.md · TODO.md · README.md
└── src/
    ├── shared/
    │   ├── types.ts             # AppSettings, CaptureRecord, SessionSnapshot, BubblePhase, IPC payloads
    │   └── ipc.ts               # tên kênh IPC tập trung, tránh chuỗi magic
    ├── main/
    │   ├── index.ts             # bootstrap, single-instance, scheme, permission handler, wiring, --smoke
    │   ├── session.ts           # state machine điều phối bật/tắt, gọi capture + AI, ghi history
    │   ├── capture.ts           # screenshot + chọn display theo con trỏ
    │   ├── hotkeys.ts           # uiohook tap-detection + globalShortcut fallback
    │   ├── ai.ts                # OpenAI-compatible client: chat(SSE), transcription, fallback
    │   ├── overlay.ts           # tạo/di chuyển/ignore-mouse/focus overlay
    │   ├── dashboard.ts         # cửa sổ dashboard
    │   ├── store.ts             # settings.json + history.json + artifact dir + safeStorage key
    │   └── tray.ts              # tray optional (ẩn/hiện bubble, dashboard, quit)
    ├── preload/
    │   ├── index.ts             # contextBridge → window.bubble
    │   └── index.d.ts           # typing cho renderer
    └── renderer/
        ├── index.html · overlay.html
        └── src/
            ├── dashboard/{main.tsx,App.tsx,views/*.tsx,components/*.tsx}
            ├── overlay/{main.tsx,Bubble.tsx,useRecorder.ts}
            └── styles/{theme.css,dashboard.css,overlay.css}
└── scripts/smoke.mjs            # chạy end-to-end trong Xvfb: screenshot + WAV giả + gọi AI thật
```

## Thiết kế (aesthetic)

- **Design movement:** "Heads-up instrument" — borrowing từ HUD của phi công và thiết bị đo: một chấm sáng nhỏ luôn ngồi trên màn hình, im lặng cho tới khi được gọi.
- **Core principles:** một điểm nhấn duy nhất trên nền tối trong suốt; trạng thái = chuyển động (không phải chữ); không border cứng, mọi thứ là khối bo; overlay không bao giờ lấy focus khỏi app khác.
- **Color philosophy:** `--signal: #7C5CFF` (tím điện tử, màu nhận diện) cho trạng thái AI; `--live: #26E6A0` cho "đang nghe"; `--alert: #FF6B57` cho lỗi. Nền `#0B0D14 → #141826` (slate đen xanh) để bubble nổi trên cả nền trắng lẫn nền tối.
- **Layout paradigm:** Dashboard dùng trục đôi (sidebar điều hướng + nội dung lệch trái, cột health bên phải), không dùng grid căn giữa. Bubble là pill bo tròn `border-radius: 999px` co thành card `24px` khi có kết quả, neo góc dưới-phải, tự kéo về trong màn hình khi đổi resolution.
- **Signature elements:** vòng sóng audio phản ứng theo RMS khi đang nghe; đường viền "scanning" chạy quanh bubble khi `thinking`; dòng kết quả hiện dần kiểu typewriter; badge phím nóng (`⇧⇧` / `⌘⌘` / `fn fn`) trong suốt khi idle.
- **Interaction philosophy:** một thao tác cho luồng chính (bấm phím), mọi thứ còn lại là phím tắt (`⌘/Ctrl+Enter` gửi, `Esc` đóng, `⌘/Ctrl+C` copy kết quả).
- **Animation:** pill `scale 1 → 1.06` + glow `box-shadow` 240ms `cubic-bezier(.2,.8,.2,1)` khi arming; vòng sóng co giãn 90ms theo RMS; card fade+slide 12px khi có kết quả; respect `prefers-reduced-motion` (tắt scale/typewriter).
- **Typography system:** Inter/system-ui; Dashboard `22px/600` cho section, `13px/500` label uppercase letter-spacing `.08em`, `14px/1.6` body; Bubble `14px` answer, `11px` meta. Không dùng font decorative.
- **Brand essence:** "AI nhìn và nghe cùng bạn, ngay tại khoảnh khắc bạn cần" — cho người dùng power-user cần hỏi AI về chính màn hình đang làm mà không rời tay khỏi bàn phím. Personality: *lặng lẽ, tức thì, chính xác*.
- **Brand voice:** động từ ngắn, không hứa suông. Ví dụ: “Bấm ⇧⇧ để hỏi về màn hình này.” · “Đã nghe 12 giây · đã thấy 1 màn hình.”
- **Wordmark & logo:** chữ “bubble” được viết bằng một vòng tròn liền nét (dấu chấm của “i” tách thành chấm tín hiệu); icon app = vòng tròn gradient tím với một cung sáng đang “nghe”.
- **Signature brand color:** `#7C5CFF`.

## Ràng buộc & ghi chú nền tảng

- macOS: cần quyền **Microphone** và **Screen Recording**; lần chạy đầu hệ thống sẽ hỏi — app hiển thị health check đỏ kèm link mở `x-apple.systempreferences`. Fn trên macOS thường bị system nuốt (Mission Control/change input source); nếu không bắt được Fn, dùng Command hoặc phím fallback, và hướng dẫn người dùng đổi hành vi phím Fn trong System Settings.
- Wayland (Linux): global hook và screen capture có thể bị chặn → app phát hiện (`$XDG_SESSION_TYPE`) và tự chuyển sang fallback `globalShortcut` + cho phép người dùng biết lý do trong health check.
- Windows: Shift/Command(Win)/Fn — Win và Fn thường bị system giữ; mặc định trên Windows là Shift double-tap.
- uiohook-napi là native module: giữ trong `dependencies` để electron-vite externalize; không cho vào asar mà không `asarUnpack`.
- Trong sandbox của Manus không có thiết bị mic/display thật → verification gồm: typecheck, build, và `scripts/smoke.mjs` chạy pipeline screenshot + WAV + AI thật dưới Xvfb; hành vi cần phần cứng được kiểm bằng code inspection + log.

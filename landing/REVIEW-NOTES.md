# Ghi chú dựng landing (để lần sau không phải dò lại)

Ngày: 2026-11-15. Phạm vi: thư mục `landing/` + `.github/workflows/pages.yml`.

## Sự thật về môi trường và công cụ

- Sandbox là Linux, **không có Xcode** ⇒ không build/chạy app macOS ở đây được.
  Landing chỉ kiểm được bằng trình duyệt headless.
- `chromium` có sẵn. Cách chụp hữu ích nhất:
  `chromium --headless=new --disable-gpu --no-sandbox --hide-scrollbars --window-size=1280,9500 --screenshot=out.png "http://127.0.0.1:3005/?lang=vi"`
  ⇒ cửa sổ cao 9500px cho ảnh **toàn trang thật** (không bị nén như công cụ
  screenshot của nền tảng, vốn hạ xuống tối đa 7500px nên chữ mobile không đọc được).
  Sau đó cắt dải bằng PIL (`landing/` không chứa các ảnh cắt này).
- `--window-size=375,812` + `#anchor` **không cuộn**: headless screenshot luôn chụp
  từ đỉnh. Muốn soi section ở cỡ điện thoại thì chụp toàn trang 375×9600 rồi cắt 9 dải,
  phóng 2x. (Harness iframe file:// → http cũng không cuộn được.)
- Servơ tĩnh để test: `python3 -m http.server 3005 --bind 127.0.0.1 --directory landing`.
  MIME của `.js` là `text/javascript` ⇒ ES module chạy bình thường, không cần build.
- Font: chỉ dùng font có subset `vietnamese` trên Google Fonts, đã kiểm bằng
  `curl 'fonts.googleapis.com/css2?family=...' | grep -c vietnamese`:
  **Fraunces** (display) và **Be Vietnam Pro** (body) đều ✓, **IBM Plex Mono** ✓.
  `Space Grotesk`, `Manrope`, `DM Sans` không có ⇒ tránh.
- Ảnh mockup UI sinh bằng tool generate-image (1920×1280 / 1920×1080), đã re-encode
  webp 1440px, quality 82 → `assets/mock-*.webp` (tổng ~128KB).

## Quyết định thiết kế/nội dung

- Giữ đúng khung trang tham chiếu: manifesto chữ thường → ảnh sản phẩm → 3 việc nó làm →
  phòng hỏi → tường trích dẫn → pricing → FAQ → khu tải. **Không có nút CTA trước fold**
  (đặc trưng của trang tham chiếu).
- Khác biệt thương hiệu: palette olive `#5c6b34` / trắng ấm `#fbfaf4` / vàng pastel
  `#f6e7a1`; Fraunces + Be Vietnam Pro; motif bút highlight (`span.hl`), mẩu băng dính
  vàng dán ảnh (`.shot::after`), nền kẻ ô vở 32px (`body::before`).
- Tiếng Việt là bản viết tay trong `index.html`; `lib/i18n.js` cache markup gốc theo khoá
  rồi đổi sang `lib/dictionary.en.js`. Vậy nên JS tắt vẫn ra trang tiếng Việt hoàn chỉnh,
  và crawler thấy chữ thật. `scripts/check-i18n.mjs` = 178 khoá, fail khi lệch.
- Luật quan trọng: phần tử mang `data-i18n` **chỉ được chứa chữ**. Muốn lồng `<kbd>` hay
  `<span class="hl">` thì tách thành nhiều khoá (đã áp cho `does.h1..h3`, `room.h1/h2`,
  `dl.sub1/sub2`, `m.note1/2`, `does.1a/1b`).

## Trạng thái link tải (chính xác tại ngày trên)

- Repo `Julie22-yaerin/PRESENTATION` **chưa có Release nào** ⇒ `releases/latest/download/...`
  trả 404. Vì vậy `download-config.json` để `url` trống và cất địa chỉ hứa trong
  `plannedUrl`; nút hiện "sắp có · TheLyceum-arm64.dmg · báo cho tôi" trỏ vào Issues.
  Không có nút chết, cũng không có nút dẫn tới 404.
- Tên asset đã chốt: `TheLyceum-arm64.dmg`, `TheLyceum-intel.dmg`, `TheLyceum-win-x64.exe`.
  `scripts/release.sh` hiện vẫn đặt `APP_NAME="makesomething"` và
  `GITHUB_REPO="julianjear/makesomething-mac-app"` ⇒ khi phát hành bản Lyceum phải đặt
  lại tên asset theo trên (không đổi script trong đợt này).
- `bash landing/scripts/check-downloads.sh` in ra LIVE / READY / WAITING / BROKEN cho từng
  kênh. NOTE: script phải dùng token `NOTSET` cho ô trống, vì `IFS=$'\t' read` gộp ô rỗng
  làm lệch cột (đã gặp và đã sửa).

## Lỗi đã bắt được nhờ ảnh chụp và đã sửa tại nguồn

1. Nút CTA gói giữa: `label` màu vàng pastel nằm trên nền nút vàng ⇒ vô hình. Sửa thành
   `.plan--best a:not(.btn)`.
2. 10 nhãn thời gian trên tường trích dẫn là tiếng Việt cứng, không qua i18n ⇒ EN lẫn Việt.
   Thêm khoá `time.*`.
3. Khối ưu đãi học sinh: dòng nhỏ rơi xuống cột trái. Sửa lưới `0.72fr/1.6fr` + `.fine`
   `grid-column: 2`.
4. Ô tải chưa có file vẫn hover như nút sống ⇒ thêm border dashed, tắt transform.
5. `--olive-soft` ghi nhầm `#77875200` (8 chữ số, alpha 0) ⇒ sửa `#778752`.
6. `post__time` bị xuống hàng đôi ("2 / days") ⇒ `white-space: nowrap`.

## Đừng "sửa" những thứ sau

- `clicky-main/README.md` có câu `私の発表は以上です` trong danh sách cụm từ kết thúc bài nói:
  đó là **nội dung có chủ đích** (bộ dò kết thúc chạy đa ngôn ngữ), không phải ký tự lạc.
  Quét CJK tự động sẽ báo đúng dòng này — bỏ qua.
- `landing/download-config.json` có bốn key bắt đầu bằng `_` (`_how_to_use`,
  `_release_recipe`, `_check_command`): `lib/downloads.js` cố tình không đọc key nào có tên
  lạ, nên chúng là tài liệu sống ngay cạnh giá trị.

## Việc còn mở

- Thay 10 dòng trích dẫn bằng lời thật (hiện ghi rõ là "ghi chú từ nhóm thử nội bộ").
- Bật GitHub Pages: Settings → Pages → Source = **GitHub Actions**, rồi push `landing/**`.
- Khi đổi sang domain riêng: sửa `canonical`, 3 `hreflang`, `og:url`, `og:image`
  trong `index.html` (hiện trỏ `julie22-yaerin.github.io/PRESENTATION/`).
- Chưa test tương tác thật (bấm VI/EN, cuộn) trên thiết bị — mới kiểm bằng ảnh.

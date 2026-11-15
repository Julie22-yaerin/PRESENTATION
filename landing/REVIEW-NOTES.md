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

## Cách kiểm tra nhận diện máy (đã chạy, 7/7 PASS)

`--user-agent` **không đủ**: Chrome vẫn trả `navigator.platform` và `userAgentData` của máy
thật, nên lúc đầu mọi giả lập đều ra "khác". Cách đúng: chép `landing/` ra thư mục tạm, chèn
một `<script>` nhỏ **trước** `app.js` để `Object.defineProperty(Navigator.prototype, ...)`
cho `userAgent`, `platform`, `userAgentData`, rồi `chromium --dump-dom` và đọc `data-best`
của từng nút. Lưu ý cú pháp: giá trị object phải viết trong ngoặc
`() => ({'platform': 'macOS'})`, nếu không nó là một block và cả script chết — lỗi này đã
làm 2 case báo sai trước khi sửa.

Kết quả trên bản local (giống hệt bản live):

| Giả lập | Nút được tô ★ | Thứ tự | Dòng trạng thái |
| --- | --- | --- | --- |
| Chrome/macOS | Apple Silicon | mac-arm → mac-intel → win → repo | "Bạn đang dùng Mac… Cần macOS 14.2 trở lên." |
| Safari/macOS (không có userAgentData) | Apple Silicon | như trên | như trên |
| Chrome/Windows | Windows | win → mac-arm → mac-intel → repo | "Bạn đang dùng Windows…" |
| Firefox/Windows | Windows | như trên | như trên |
| iPadOS | mã nguồn & bản thử | repo trước | "Mở trang này trên chính máy bạn…" |
| Android (Pixel) | mã nguồn & bản thử | repo trước | như trên |
| Linux desktop | mã nguồn & bản thử | repo trước | như trên |

Ba lỗi bắt được từ bảng này và đã sửa: (1) nút ★ chỉ được chọn khi `url` đã có ⇒ người Mac
không thấy nút nào được gợi ý dù dòng trạng thái nói "nút đầu tiên là của bạn"; (2) bản
sắp-có không bao giờ được ★; (3) gộp chuỗi yêu cầu macOS in "14.2" hai lần. Thêm: iPhone/iPad
trước đây bị tính là macOS ⇒ nay xếp là `other`.

## Mặc định ngôn ngữ

`i18n.js` ưu tiên `?lang=` → lựa chọn đã lưu → `navigator.language`. Trình duyệt tiếng Anh
mở `/` sẽ thấy **bản Anh**, không phải bản Việt; `?lang=vi` luôn ra Việt. Đây là hành vi có
chủ đích (đã kiểm bằng `--dump-dom`: `<html lang>` và toàn bộ nhãn đổi theo).

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
- ~~Bật GitHub Pages~~ **đã bật** bằng `POST /repos/Julie22-yaerin/PRESENTATION/pages`
  `{"build_type":"workflow"}` (2026-11-15). Run đầu `43717370399` xanh, trang live ở
  `https://julie22-yaerin.github.io/PRESENTATION/`. Từ đây mỗi push chạm `landing/**` tự đăng.
- Điền `url` cho ba kênh khi Release có asset đúng tên (xem mục trạng thái link tải).
- Khi đổi sang domain riêng: sửa `canonical`, 3 `hreflang`, `og:url`, `og:image`
  trong `index.html` (hiện trỏ `julie22-yaerin.github.io/PRESENTATION/`).
- Chưa test tương tác thật (bấm VI/EN, cuộn, bấm nút tải) trên thiết bị — mới kiểm bằng
  ảnh và `--dump-dom`.
- Trang không có analytics hay SEO động: `sitemap.xml` để trống theo thoả thuận.

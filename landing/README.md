# Trang giới thiệu The Lyceum

Trang tĩnh, không build, không dependency. Serves nguyên vẹn từ thư mục này.

- Bố cục theo trang tham chiếu (`heyclicky.com`): manifesto → ảnh sản phẩm → ba việc nó
  làm → phòng hỏi → tường trích dẫn → bảng giá → FAQ → khu tải → footer. Không đặt nút
  tải ở màn hình đầu, đó là đặc trưng của trang gốc.
- Thương hiệu: olive `#5c6b34`, trắng ấm `#fbfaf4`, vàng pastel `#f6e7a1`; chữ
  Fraunces (display) + Be Vietnam Pro (body) + IBM Plex Mono (số); motif bút highlight,
  mẩu băng dính dán ảnh, nền kẻ ô vở.
- Hai ngôn ngữ: tiếng Việt viết tay trong HTML, tiếng Anh trong từ điển.

## Xem thử và đẩy lên mạng

```sh
python3 -m http.server 3005 --bind 127.0.0.1 --directory landing
# http://127.0.0.1:3005/            tiếng Việt
# http://127.0.0.1:3005/?lang=en    tiếng Anh

node landing/scripts/check-i18n.mjs      # hai thứ tiếng có đủ khoá chưa
bash   landing/scripts/check-downloads.sh  # kênh tải nào đang sống
```

Xuất bản bằng GitHub Actions (`.github/workflows/pages.yml`): mỗi push chạm `landing/**`
sẽ chạy kiểm tra i18n rồi đăng lên `https://julie22-yaerin.github.io/PRESENTATION/`.

**Thiết lập một lần** (mình không làm hộ được, cần quyền chủ repo):
Settings → Pages → Source → chọn **GitHub Actions**. Nếu vẫn để "Deploy from a branch"
thì workflow báo lỗi `Pages not enabled`.

## Sửa lời

| Muốn sửa | Sửa ở |
| --- | --- |
| Câu tiếng Việt | `index.html` (kèm `data-i18n="..."`) |
| Câu tiếng Anh | `lib/dictionary.en.js` |
| Nhãn nút tải / cảnh báo máy | `lib/dictionary.vi.js` + `dictionary.en.js` (khoá `gen.*`) |
| Màu, chữ, khoảng cách | `styles/tokens.css` |
| Bố cục section | `styles/page.css` |

Luật duy nhất: phần tử mang `data-i18n` **chỉ được chứa chữ**. Muốn lồng `<kbd>` hoặc
`<span class="hl">` thì tách thành nhiều khoá, nếu không engine sẽ ghi đè markup.
Sau khi sửa, chạy `node landing/scripts/check-i18n.mjs` — nó bắt cả khoá thiếu lẫn khoá
không ai dùng.

## Link tải macOS và Windows

File duy nhất: **`download-config.json`**. Mỗi kênh có hai địa chỉ:

- `plannedUrl` — tên file mà điều kiện release hứa sẽ upload. Trang dùng nó chỉ để in
  chú thích "sắp có · TheLyceum-arm64.dmg".
- `url` — địa chỉ thật. **Để trống thì nút tự hoá "sắp có · báo cho tôi"** trỏ vào
  `signupUrl`; không bao giờ thành nút chết hay nút dẫn tới 404.

Điều kiện để điền `url` (áp dụng từ ngày 2026-11-15): repo chưa có Release nào, nên
`releases/latest/download/...` đang trả 404.

```sh
cd clicky-main
GITHUB_TOKEN=... ./scripts/release.sh        # build + notarise + appcast
# rồi tạo Release tag v<version>, upload ba asset đúng tên:
#   TheLyceum-arm64.dmg   TheLyceum-intel.dmg   TheLyceum-win-x64.exe
```

Lưu ý: `scripts/release.sh` hiện đặt `APP_NAME="makesomething"` và
`GITHUB_REPO="julianjear/makesomething-mac-app"` — phải đặt lại theo repo này thì asset
mới mang tên như trên. Sau khi upload, copy từng `plannedUrl` sang `url`, chạy
`bash landing/scripts/check-downloads.sh` cho tới khi mọi kênh in `LIVE`, rồi commit.
Không phải sửa code hay template nào.

Máy người xem tự được nhận ra: `lib/downloads.js` đọc `userAgentData.platform`,
`navigator.platform` và `userAgent` (nên Safari trên Mac và Firefox trên Windows vẫn đúng),
tô dấu "hợp với máy bạn" lên đúng bản kể cả khi bản đó chưa phát hành, và in một dòng trạng
thái bằng ngôn ngữ đang hiện. iPhone/Android được xếp là `other`: app chỉ có bản desktop.

## Cấu trúc

```
landing/
  index.html              nội dung tiếng Việt + mọi khoá data-i18n
  app.js                  khởi tạo i18n, nút tải, hiệu ứng cuộn
  download-config.json    nơi duy nhất để đổi link tải
  styles/tokens.css       màu, chữ, thước 8pt, thời gian động
  styles/base.css         reset, chữ thường to, nút, bút highlight, reveal
  styles/page.css         bố cục từng section + breakpoint
  lib/i18n.js             cache markup Việt, đổi sang Anh, ghi nhớ, deep link
  lib/dictionary.en.js    toàn bộ câu tiếng Anh (178 khoá)
  lib/dictionary.vi.js    phần tiếng Việt sinh bằng JS (gen.*, meta.*)
  lib/downloads.js        dựng nút tải từ config, có bản mặc định nếu config lỗi
  assets/                 logo, favicon, ba mockup webp
  scripts/check-i18n.mjs  ca hai thứ tiếng lệch nhau
  scripts/check-downloads.sh  hiện trạng kênh tải
  .nojekyll               Pages không chạy Jekyll với thư mục có dấu chấm
  REVIEW-NOTES.md         sự thật đã kiểm chứng, lỗi đã bắt được, việc còn mở
```

## Đã kiểm và chưa kiểm

Đã kiểm bằng Chromium headless ở 1920×1080, 1280×800, 768×1024, 375×812 và ảnh toàn trang
cắt dải: không tràn ngang, nút ≥48px, tương phản đạt, chuyển VI/EN đúng ở mọi section,
tắt JS vẫn ra trang tiếng Việt đầy đủ, `?lang=en` không còn lẫn chữ Việt.

Chưa kiểm: tương tác thật trên điện thoại (vuốt, bấm), và đo Lighthouse. Trang dùng font
Google Fonts nên cần mạng để hiện đúng chữ; không có tracker hay analytics.

## Bản quyền

Dựng lại từ [Clicky (MIT)](https://github.com/farzaa/clicky-main) của @farzaa: đổi tên,
đổi mục đích, giữ nguyên giấy phép. Ảnh mockup là sản phẩm AI, mô phỏng giao diện thật của
app trong `clicky-main/`.

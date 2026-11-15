# PRESENTATION

Bản thu âm cho bài thuyết trình của bạn: app macOS/Swift biết nhìn slide, nghe bạn nói,
chấm từng slide, rồi mở một "phòng" gồm năm AI nhỏ để hỏi lại bạn như hội đồng thật.

| Thư mục | Là gì | Đọc trước khi sửa |
| --- | --- | --- |
| `clicky-main/` | app The Lyceum (SwiftUI + Cloudflare Worker proxy) | `clicky-main/README.md`, `clicky-main/CLAUDE.md` |
| `landing/` | trang giới thiệu công khai, HTML tĩnh, đẩy lên GitHub Pages | `landing/README.md` |
| `.github/workflows/pages.yml` | kiểm tra hai ngôn ngữ rồi đăng `landing/` | `landing/README.md` |

Cấu hình để người dùng tải bản macOS và Windows nằm ở `landing/download-config.json` —
đổi file đó, không đổi code. Tình trạng từng kênh tải: `bash landing/scripts/check-downloads.sh`.

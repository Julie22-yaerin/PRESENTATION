import { useApp } from '../context'
import { Card, Key } from '../components'

export function Guide() {
  const { bundle } = useApp()
  const platform = bundle?.runtime.platform ?? window.bubble.platform
  const isMac = platform === 'darwin'
  const isWindows = platform === 'win32'
  const wayland = bundle?.runtime.sessionType === 'wayland'

  return (
    <div className="guide">
      <Card title="Dùng trong 10 giây" subtitle="Một lần bấm để bật, một lần bấm để dừng và gửi">
        <ol className="guide-steps">
          <li>
            Nhìn vào thứ bạn đang làm việc, bấm <Key>{bundle?.runtime.hotkey.keyLabel ?? '⇧⇧'}</Key>. Bong bóng mở ra, mic bật và
            màn hình được chụp lại đúng khoảnh khắc đó.
          </li>
          <li>
            Nói câu hỏi của bạn — “mục này nghĩa là gì”, “viết lại email này trang trọng hơn”, “bug ở dòng nào”.
          </li>
          <li>
            Bấm lại <Key>{bundle?.runtime.hotkey.keyLabel ?? '⇧⇧'}</Key>. AI trả lời ngay trong bong bóng; bản ghi, ảnh và câu trả
            lời nằm trong Lịch sử.
          </li>
          <li>
            Không tiện nói? Gõ thẳng vào ô dưới bong bóng, ảnh màn hình vẫn được đính kèm.
          </li>
        </ol>
      </Card>

      <div className="guide-grid">
        <Card title={isMac ? 'Cấp quyền trên macOS' : isWindows ? 'Cấp quyền trên Windows' : 'Chạy trên Linux'}>
          {isMac ? (
            <ul className="guide-list">
              <li>
                <strong>Microphone:</strong> System Settings → Privacy &amp; Security → Microphone → bật AI Bubble. Lần bấm đầu tiên
                hệ thống sẽ hỏi, hãy chọn OK.
              </li>
              <li>
                <strong>Screen Recording:</strong> System Settings → Privacy &amp; Security → Screen Recording &amp; System Audio →
                thêm AI Bubble rồi khởi động lại app (macOS bắt buộc restart sau khi cấp).
              </li>
              <li>
                <strong>Fn:</strong> macOS thường giữ phím Fn cho Đổi bàn phím/Mission Control. Nếu “Học phím” không nhận Fn, hãy gán
                Command (⌘) hoặc dùng phím dự phòng. Bạn cũng có thể đặt hành vi phím Fn sang “Do nothing” trong Keyboard settings.
              </li>
            </ul>
          ) : isWindows ? (
            <ul className="guide-list">
              <li>
                <strong>Microphone:</strong> Settings → Privacy &amp; security → Microphone → bật cho app desktop.
              </li>
              <li>
                <strong>Phím:</strong> Shift an toàn nhất. Phím Win thường bị system chiếm; Fn trên laptop thường không gửi tín hiệu
                xuống app.
              </li>
              <li>
                <strong>Đóng gói:</strong> bản build Windows tạo bằng <code>npm run package</code> (electron-builder, target nsis).
              </li>
            </ul>
          ) : (
            <ul className="guide-list">
              <li>
                <strong>X11:</strong> mọi thứ hoạt động đầy đủ (hook bàn phím + chụp màn hình).
              </li>
              <li>
                <strong>Wayland:</strong> hook bàn phím toàn cục và cửa sổ always-on-top bị chặn ở tầng bảo mật. App tự chuyển sang
                phím dự phòng; để có trải nghiệm đầy đủ, đăng nhập lại bằng phiên “Xorg”.
              </li>
              <li>
                <strong>Tray:</strong> cần appindicator (libappindicator3). Không có thì app vẫn chạy, điều khiển bằng phím.
              </li>
            </ul>
          )}
        </Card>

        <Card title="Vì sao bấm đúp?" subtitle="Mặc định an toàn cho phím thuần">
          <p className="guide-text">
            Shift/Command/Fn là phím bạn bấm cả nghìn lần mỗi ngày khi gõ hoa hay tổ hợp tắt. Nên mặc định là <em>bấm đúp nhanh</em>{' '}
            (hai lần nhấn–nhả liên tiếp trong 0,6 giây, mỗi lần dưới 0,45 giây, không có phím khác xen giữa) — giống thói quen kích
            hoạt trợ lý trên điện thoại.
          </p>
          <p className="guide-text">
            Nếu bạn muốn bấm một lần, đổi “Kiểu bấm” sang <strong>Bấm một lần</strong> trong Cài đặt → Phím nóng, và cân nhắc gán
            một phím ít dùng bằng nút <strong>Học phím</strong>.
          </p>
        </Card>
      </div>

      <Card title="Xử lý sự cố">
        <table className="guide-table">
          <thead>
            <tr>
              <th>Hiện tượng</th>
              <th>Nguyên nhân phổ biến</th>
              <th>Cách xử lý</th>
            </tr>
          </thead>
          <tbody>
            <tr>
              <td>Bấm phím không thấy gì</td>
              <td>Hook bị chặn (Wayland) hoặc hệ thống giữ phím</td>
              <td>
                Dùng phím dự phòng <Key>{bundle?.runtime.hotkey.shortcut ?? 'Alt+Shift+Space'}</Key>; xem mục Phím nóng ở card Sức
                khỏe hệ thống
              </td>
            </tr>
            <tr>
              <td>“Không lấy được ghi âm từ overlay”</td>
              <td>Chưa cấp quyền mic</td>
              <td>Cấp quyền trong hệ điều hành rồi bấm lại; kiểm tra thiết bị trong Cài đặt → Nghe và nhìn</td>
            </tr>
            <tr>
              <td>Ảnh màn hình rỗng / đen</td>
              <td>Thiếu Screen Recording (macOS) hoặc cửa sổ được bảo vệ DRM</td>
              <td>Cấp quyền, khởi động lại app; nội dung ngân hàng/DRM cố ý bị chặn ở tầng hệ thống</td>
            </tr>
            <tr>
              <td>AI báo lỗi model</td>
              <td>Model không có vision hoặc đã bị nhà cung cấp gỡ</td>
              <td>Bấm “Tải danh sách model”, chọn model có badge 👁 rồi lưu</td>
            </tr>
            <tr>
              <td>Trả lời không có phần giọng nói</td>
              <td>Endpoint không nhận audio trong một lượt gọi</td>
              <td>Đổi “Cách gửi giọng nói” sang <em>Chữ hoá trước</em> (whisper-1)</td>
            </tr>
            <tr>
              <td>Bong bóng nằm sau cửa sổ toàn màn hình</td>
              <td>Chế độ full-screen独占 của một số app</td>
              <td>Dùng chế độ cửa sổ, hoặc bật “hiện trên mọi workspace” trong hệ điều hành</td>
            </tr>
          </tbody>
        </table>
        {wayland ? <p className="note">Bạn đang chạy phiên Wayland — hook bàn phím toàn cục có thể bị chặn hoàn toàn.</p> : null}
      </Card>

      <Card title="Quyền riêng tư">
        <ul className="guide-list">
          <li>Ảnh và âm thanh chỉ được gửi khi bạn bấm phím; không có ghi nền, không upload liên tục.</li>
          <li>API key lưu bằng kho mã hoá của hệ điều hành (safeStorage), không nằm trong tệp cấu hình.</li>
          <li>
            Ảnh chụp, bản ghi và kết quả lưu trong <code>{bundle?.runtime.userData ?? '~/.config/AI Bubble'}</code>; xóa phiên trong
            Lịch sử sẽ xoá cả tệp.
          </li>
          <li>Muốn dùng model nội bộ? Đổi Base URL sang endpoint của bạn — app không hardcode nhà cung cấp nào.</li>
        </ul>
      </Card>
    </div>
  )
}
              <td>Một số app chiếm toàn màn hình và đè lên lớp overlay</td>

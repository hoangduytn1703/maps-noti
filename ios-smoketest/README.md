# Smoke test — bắn notification

App ~200 dòng, không làm gì ngoài bắn local notification theo các kiểu khác nhau.

## Dựng project trong Xcode

Ba file `.swift` trong `sources/` chưa kèm `.xcodeproj` — tự tay tạo trong Xcode nhanh và
chắc hơn là mình sinh sẵn file project (định dạng `.pbxproj` rất dễ hỏng vặt).

1. Cài **Xcode** từ App Store (~15 GB, khá lâu). Mở lên, đồng ý cài thêm component.
2. `File → New → Project… → iOS → App → Next`
3. Điền:
   - Product Name: `NotiSmokeTest` — **đúng chính tả**, vì tên file `NotiSmokeTestApp.swift` sinh ra theo tên này
   - Organization Identifier: `com.<tênbạn>` (bất kỳ, miễn không trùng ai)
   - Interface: **SwiftUI** · Language: **Swift** · Storage: **None**
   - Phần test (`Include Tests` hoặc `Testing System`): bỏ tick / chọn **None**
4. `Next` → chọn chỗ lưu là thư mục **`ios-smoketest/`** trong repo → `Create`.
   (Xcode sẽ tạo `ios-smoketest/NotiSmokeTest/`, nằm cạnh `sources/`, không đè lên nhau.)
5. Xcode đẻ sẵn `NotiSmokeTestApp.swift` và `ContentView.swift`. Mở từng file,
   `⌘A` bôi đen hết, dán đè bằng nội dung file cùng tên trong `sources/`.
6. Tạo file thứ ba: chọn nhóm `NotiSmokeTest` ở cột trái → `File → New → File…`
   → **Swift File** → đặt tên `Notifier` → Create → dán nội dung `sources/Notifier.swift` vào.
7. Chọn project ở cột trái → tab **Signing & Capabilities**:
   - Tick **Automatically manage signing**
   - Team: `Add an Account…` → đăng nhập Apple ID thường (miễn phí, không cần
     tài khoản $99). Sau đó chọn team `<tên bạn> (Personal Team)`.
   - Nếu báo bundle id trùng, đổi Organization Identifier thành cái khác.
8. Cắm iPhone bằng cáp, mở khoá, bấm **Trust This Computer** khi máy hỏi.
9. **Bật Developer Mode trên iPhone** — iOS 16 trở lên bắt buộc:
   `Settings → Privacy & Security → Developer Mode` → bật → máy khởi động lại.
   Mục này chỉ xuất hiện sau khi iPhone đã cắm vào Xcode ít nhất một lần; chưa
   thấy thì bấm ⌘R một lần cho Xcode chạm tới máy rồi mở lại Settings.
10. Chọn iPhone ở thanh thiết bị trên cùng Xcode → bấm **⌘R**.
11. Lần đầu iPhone sẽ chặn không cho mở app:
    `Settings → General → VPN & Device Management` → chọn Apple ID của bạn →
    **Trust**. Rồi bấm ⌘R lại.

> Tài khoản Apple miễn phí: app **hết hạn sau 7 ngày**, và tối đa 3 app tự cài
> cùng lúc. Cắm máy chạy lại ⌘R là gia hạn. Nếu sau này thấy đáng thì mua Apple
> Developer $99/năm cho khỏi phiền.

## Trước khi test — bật app trong Huawei Health

Đây chính là câu hỏi số 1 cần trả lời:

`Huawei Health → Devices → Watch GT4 → Notifications` → bật tổng, rồi tìm
**NotiSmokeTest** trong danh sách app và bật nó.

- **Không thấy app trong danh sách** → bắn 1 noti trước rồi mở lại danh sách
  (nhiều app chỉ hiện sau khi đã gửi noti lần đầu).
- Vẫn không thấy sau khi đã bắn → ghi lại, đây là dấu hiệu chặn.

## Quy trình test

Làm đúng thứ tự, ghi kết quả từng bước:

| # | Thao tác | Cần quan sát |
|---|---|---|
| 1 | Mở app, bấm **Xin quyền thông báo**, chọn Allow | Trạng thái đổi thành "đã cấp" |
| 2 | Bấm **Bắn ngay 1 cái** | iPhone có banner không? Đồng hồ có rung không? |
| 3 | Vào Huawei Health bật app (mục trên) | App có xuất hiện trong danh sách không? |
| 4 | Bấm **Hẹn 30 giây**, khoá máy, bỏ vào túi quần | Đồng hồ rung sau ~30s? Trễ bao lâu? |
| 5 | Bấm cả 3 nút mục "Hiển thị trên màn GT4", khoá máy | Chữ có dấu đúng không? Mũi tên `↰` thành ô vuông? Chuỗi dài cắt ở đâu? |
| 6 | Bấm **5 lệnh rẽ cách nhau 20s**, khoá máy, đợi 2 phút | Rung đủ 5 lần hay bị gộp? |
| 7 | Lặp lại bước 4 nhưng bật **Do Not Disturb** trên iPhone | Còn nhận được không? |

Bước 7 quan trọng vì lúc chạy xe nhiều người bật Focus. Nếu DND chặn thì app
chính sẽ cần `interruptionLevel = .timeSensitive` — biết trước để tính.

## Báo kết quả

Cần đủ 3 câu trả lời để quyết bước tiếp:

- App **có** hiện trong danh sách Huawei Health không?
- Bước 4 độ trễ khoảng bao nhiêu giây?
- Bước 6 rung đủ 5 lần không?

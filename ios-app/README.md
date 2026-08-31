# Maps Noti — app chính

Chỉ đường bằng dữ liệu Google, bắn notification ở mỗi ngã rẽ để Huawei Watch GT4
rung khi iPhone nằm trong túi.

Luồng dùng: mở app → gõ tên điểm đến → chọn → **Bắt đầu** → khoá máy bỏ túi →
đồng hồ rung "⬅️ Rẽ trái · 300 m" rồi "⬅️ Rẽ trái · 80 m" ở từng ngã rẽ →
"🏁 Đã tới nơi".

## Phần 1 — Lấy Google API key (làm một lần, ~10 phút)

1. Vào [console.cloud.google.com](https://console.cloud.google.com), đăng nhập Google.
2. Tạo project mới (tên gì cũng được, ví dụ `maps-noti`).
3. Gắn thẻ thanh toán: menu **Billing**. Bắt buộc phải có thẻ nhưng dùng cá nhân
   nằm gọn trong hạn mức miễn phí hằng tháng — một chuyến đi tốn 1 lần tìm chỗ
   + 1 lần tính route (+ vài lần nếu lệch đường).
4. Bật 2 API: **APIs & Services → Library**, tìm và Enable từng cái:
   - **Places API (New)** — nhớ chọn đúng bản *(New)*
   - **Routes API**
5. Tạo key: **APIs & Services → Credentials → Create credentials → API key**.
   Copy chuỗi key.
6. Nên khoá key lại: bấm vào key vừa tạo → **API restrictions → Restrict key**
   → tick đúng 2 API trên → Save. Lỡ lộ key cũng không ai xài được vào việc khác.

Key này **dán thẳng vào app** (mục Cài đặt trong màn hình chính), lưu trong máy,
không nằm trong repo.

## Phần 2 — Dựng project Xcode (giống lần smoke test)

1. Xcode → `File → New → Project…` → iOS → App
2. Product Name: **`MapsNoti`** · Interface SwiftUI · Language Swift ·
   Storage None · phần test chọn None
3. Chỗ lưu: thư mục **`ios-app/`** trong repo. **BỎ TICK "Create Git repository"**.
4. Signing & Capabilities → Team → chọn Personal Team như cũ.
5. Chép code vào (chạy trong Terminal, sửa đường dẫn nếu repo nằm chỗ khác):

   ```bash
   cd ~/Projects/maps-noti/maps-noti
   cp ios-app/sources/*.swift ios-app/MapsNoti/MapsNoti/
   ```

   Xcode tự nạp lại. Xoá nội dung 2 file mặc định không cần thiết? Không —
   `ContentView.swift` và `MapsNotiApp.swift` bị `cp` đè trực tiếp luôn, các
   file còn lại (Models, GoogleAPI, NavigationEngine, Notifier) là file mới,
   Xcode 26 dùng buildable folder nên thấy trên đĩa là tự nhận. Nếu cột trái
   KHÔNG hiện đủ 6 file thì kéo từng file từ Finder thả vào nhóm MapsNoti.

## Phần 3 — Hai thiết lập bắt buộc, thiếu là crash/không chạy nền

### 3a. Quyền vị trí

Chọn project → TARGETS `MapsNoti` → tab **Info** → mục *Custom iOS Target
Properties* → chuột phải → **Add Row** → gõ:

- Key: `Privacy - Location When In Use Usage Description`
- Value: `Cần vị trí liên tục để đo khoảng cách tới ngã rẽ và báo lên đồng hồ.`

### 3b. Chạy nền

Tab **Signing & Capabilities** → nút **+ Capability** (góc trên trái) → gõ
`Background Modes` → thêm → tick **Location updates**.

> Thiếu 3b mà bấm Bắt đầu là app **crash ngay** — code có gọi
> `allowsBackgroundLocationUpdates = true`, iOS giết app nào gọi mà chưa khai.

## Phần 4 — Chạy

1. Cắm iPhone, chọn nó làm đích, `⌘R`.
2. Mở app: cho quyền **thông báo** và quyền **vị trí** (chọn *While Using*).
3. `Huawei Health → Watch GT4 → Notifications` → bật **MapsNoti**
   (app mới nên phải bật riêng, NotiSmokeTest bật rồi không tính).
4. Dán API key vào mục Cài đặt.
5. Gõ tên chỗ nào đó gần nhà → chọn → Bắt đầu → khoá máy → đi thử một vòng.

## Đã biết / chưa làm

- iPhone hiện chấm xanh/pill khi app đọc GPS nền — bình thường, là luật của iOS.
- Pin: GPS liên tục ở chế độ navigation ngốn kha khá, chấp nhận cho chuyến đi.
- Chưa có: giọng nói, bản đồ trên màn hình, lưu lịch sử, chọn trong nhiều route.
  Đủ xài đã rồi tính.

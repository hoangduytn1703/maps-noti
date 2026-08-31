# Maps Noti — app chính

Chỉ đường, bắn notification ở mỗi ngã rẽ để Huawei Watch GT4 rung khi iPhone
nằm trong túi.

Luồng dùng: mở app → gõ tên điểm đến → chọn → **Bắt đầu** → khoá máy bỏ túi →
đồng hồ rung "⬅️ Rẽ trái · 300 m" rồi "⬅️ Rẽ trái · 80 m" ở từng ngã rẽ →
"🏁 Đã tới nơi".

## Nguồn chỉ đường

Mặc định dùng **Apple Maps (MapKit)** — nằm sẵn trong iOS, không API key,
không thẻ, không giới hạn. `ContentView` gọi qua `AppleAPI`.

`GoogleAPI.swift` (Places New + Routes API) vẫn nằm trong repo, dùng được khi
có tài khoản Google Cloud sống + API key: đường xe máy VN tốt hơn. Muốn đổi
nguồn thì thay `AppleAPI` bằng `GoogleAPI(apiKey:)` ở các call site trong
`ContentView` — hai struct cùng hình dạng hàm.

## Phần 1 — Dựng project Xcode

1. Xcode → `File → New → Project…` → iOS → App
2. Product Name: **`MapsNoti`** · Interface SwiftUI · Language Swift ·
   Storage None · phần test chọn None
3. Chỗ lưu: thư mục **`ios-app/`** trong repo. **BỎ TICK "Create Git repository"**.
4. Signing & Capabilities → Team → chọn Personal Team như cũ.
5. Chép code vào (sửa đường dẫn nếu repo nằm chỗ khác):

   ```bash
   cd ~/Projects/maps-noti/maps-noti
   cp ios-app/sources/*.swift ios-app/MapsNoti/MapsNoti/
   ```

   Cột trái Xcode phải hiện đủ **7 file swift**: MapsNotiApp, ContentView,
   Models, AppleAPI, GoogleAPI, NavigationEngine, Notifier. Thiếu cái nào thì
   kéo từ Finder thả vào nhóm MapsNoti.

## Phần 2 — Hai thiết lập bắt buộc, thiếu là crash/không chạy nền

### 2a. Quyền vị trí

Chọn project → TARGETS `MapsNoti` → tab **Info** → mục *Custom iOS Target
Properties* → chuột phải → **Add Row** → gõ:

- Key: `Privacy - Location When In Use Usage Description`
- Value: `Cần vị trí liên tục để đo khoảng cách tới ngã rẽ và báo lên đồng hồ.`

### 2b. Chạy nền

Tab **Signing & Capabilities** → nút **+ Capability** (góc trên trái) → gõ
`Background Modes` → thêm → tick **Location updates**.

> Thiếu 2b mà bấm Bắt đầu là app **crash ngay** — code có gọi
> `allowsBackgroundLocationUpdates = true`, iOS giết app nào gọi mà chưa khai.

## Phần 3 — Chạy

1. Cắm iPhone, chọn nó làm đích, `⌘R`.
2. Mở app: cho quyền **thông báo** và quyền **vị trí** (chọn *While Using*).
3. `Huawei Health → Watch GT4 → Notifications` → bật **MapsNoti**
   (app mới nên phải bật riêng, NotiSmokeTest bật rồi không tính).
4. Gõ tên chỗ nào đó gần nhà → chọn → Bắt đầu → khoá máy → đi thử một vòng.

## Đã biết / chưa làm

- iPhone hiện chấm xanh/pill khi app đọc GPS nền — bình thường, luật của iOS.
- Pin: GPS liên tục ở chế độ navigation ngốn kha khá, chấp nhận cho chuyến đi.
- MapKit không có chế độ xe máy — đường tính theo ô tô, đôi khi đi vòng hơn
  đường xe máy quen chạy. Muốn chuẩn xe máy thì chờ cứu tài khoản Google.
- Chưa có: giọng nói, bản đồ trên màn hình, lưu lịch sử, chọn nhiều route.

## Chạy app mà không dính debugger

Mặc định `⌘R` gắn debugger vào app — rút cáp là app đứng, lỡ có breakpoint thì
app treo giữa chừng. Tắt đi:

`Product → Scheme → Edit Scheme…` (`⌘<`) → chọn **Run** → tab **Info**:

- Bỏ tick **Debug executable**
- Build Configuration: `Debug` → **Release** (nhanh hơn, đỡ tốn pin)

Thêm `⌘Y` để tắt toàn bộ breakpoint.

Sau khi app đã cài, **không cần `⌘R` nữa** — mở thẳng từ màn hình chính iPhone.
Chỉ cắm cáp lại khi có code mới, hoặc mỗi 7 ngày để gia hạn chữ ký (giới hạn
của tài khoản Apple miễn phí).

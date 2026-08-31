# Thêm Share Extension — chia sẻ thẳng từ Google Maps

Sau khi làm xong, luồng dùng rút còn:

```
Google Maps → Chia sẻ → bấm icon MapsNoti → app mở ra, đường đã vẽ sẵn
```

Không copy, không chuyển app tay, không bấm Dán.

Làm một lần, khoảng 10 phút. **Không bắt buộc** — nút Dán trong app vẫn chạy
bình thường nếu bạn bỏ qua phần này.

---

## Bước 1 — Khai URL scheme cho app chính

Extension gọi app chính qua địa chỉ `mapsnoti://`. Phải khai thì iOS mới cho.

Chọn project → TARGETS **MapsNoti** → tab **Info**.

Tab Info có nhiều mục xếp dọc. Trên cùng là bảng *Custom iOS Target Properties*
(chỗ thêm privacy key hôm trước). **Kéo xuống dưới bảng đó**, qua *Document
Types*, *Exported/Imported Type Identifiers*, tới mục **URL Types** — mục riêng,
không nằm trong bảng trên. Bung mũi tên ra, bấm `+`:

- **Identifier**: `com.hoangduy.MapsNoti` (hoặc bundle id của bạn)
- **URL Schemes**: `mapsnoti`   ← gõ chính xác, viết thường, không có `://`

Đây là bước duy nhất phải làm trên target **MapsNoti**; các bước sau đều thao
tác trên target extension.

## Bước 2 — Tạo target Share Extension

1. Menu **File → New → Target…**
2. Chọn iOS → **Share Extension** → Next
3. Product Name: **`ShareToMapsNoti`**
4. Language: **Swift**
5. Finish → hộp thoại hỏi *"Activate scheme?"* → bấm **Cancel**
   (bấm Activate thì Xcode chuyển sang chạy extension, lát Run sẽ khó hiểu)

Xcode đẻ ra thư mục `ShareToMapsNoti` gồm `ShareViewController.swift`,
`MainInterface.storyboard`, `Info.plist`.

## Bước 3 — Thay code extension

1. **Xoá `MainInterface.storyboard`** — chọn file → chuột phải → Delete →
   **Move to Trash**. (Bản mình viết không dùng storyboard.)
2. Mở `ShareToMapsNoti/ShareViewController.swift` → `⌘A` → dán đè bằng nội dung
   `ios-app/share-extension/ShareViewController.swift`.

## Bước 4 — Sửa Info.plist của extension

Mở `ShareToMapsNoti/Info.plist`. Cần khớp với file
`ios-app/share-extension/Info-share-extension.plist`, cụ thể trong khối
`NSExtension`:

| Sửa gì | Cũ | Mới |
|---|---|---|
| Xoá | `NSExtensionMainStoryboard` = `MainInterface` | *(xoá hẳn dòng này)* |
| Thêm | — | `NSExtensionPrincipalClass` = `$(PRODUCT_MODULE_NAME).ShareViewController` |

Và trong `NSExtensionAttributes → NSExtensionActivationRule`, đổi từ chuỗi
`TRUEPREDICATE` sang **Dictionary** chứa:

- `NSExtensionActivationSupportsWebURLWithMaxCount` = `1` (Number)
- `NSExtensionActivationSupportsText` = `YES` (Boolean)

> Xem plist dạng chữ cho dễ: chuột phải file Info.plist → **Open As → Source
> Code**, rồi chép thẳng khối `NSExtension` từ file mẫu của mình sang.

## Bước 5 — Ký extension

Chọn project → TARGETS **ShareToMapsNoti** → tab **Signing & Capabilities** →
tick *Automatically manage signing* → Team chọn **Personal Team** giống app chính.

## Bước 6 — Chạy

Chọn scheme **MapsNoti** (không phải ShareToMapsNoti) ở thanh trên → chọn iPhone
→ `⌘R`.

Thử: mở Google Maps → chọn một quán → **Chia sẻ** → tìm icon **MapsNoti** trong
bảng (lần đầu có thể phải kéo sang phải, bấm **Thêm/More** rồi bật nó lên) →
bấm → MapsNoti mở ra với đường đã vẽ.

---

## Hỏng thì soi mấy chỗ này

| Triệu chứng | Nguyên nhân thường gặp |
|---|---|
| Không thấy MapsNoti trong bảng Chia sẻ | Chưa cài lại app sau khi thêm target; hoặc `NSExtensionActivationRule` còn là `TRUEPREDICATE`. Thử khởi động lại iPhone. |
| Bấm vào thì bảng đóng nhưng app không mở | URL scheme `mapsnoti` ở Bước 1 gõ sai hoặc khai vào nhầm target |
| App mở nhưng báo "Không đọc được nội dung này" | Link không mang toạ độ — app sẽ tự lấy tên quán rồi nhờ Apple định vị; nếu vẫn trượt thì dùng nút Dán |
| Build lỗi `Cannot find 'ShareViewController'` | `NSExtensionPrincipalClass` sai tên module — giữ nguyên `$(PRODUCT_MODULE_NAME).ShareViewController` |

> Tài khoản Apple miễn phí: app + extension tính là **2 App ID**, mà mỗi tuần
> chỉ được cấp 3. Nếu Xcode báo hết quota App ID thì xoá bớt app thử nghiệm cũ
> (NotiSmokeTest chẳng hạn) rồi thử lại.

---

## Cách B — Phím tắt (Shortcuts): bấm là CHUYỂN APP LUÔN, không cần code

iOS chặn share extension tự mở app chính, nhưng **Phím tắt thì được phép mở
app**. Tạo một phím tắt nhận link từ bảng Chia sẻ rồi mở `mapsnoti://` —
2 phút, không đụng Xcode:

1. Mở app **Phím tắt** (Shortcuts) có sẵn trên iPhone → tab **Phím tắt** → **+**
2. Đặt tên: `Đi bằng MapsNoti`
3. Bấm nút **ⓘ** (thông tin) dưới đáy → bật **Hiện trong bảng chia sẻ**
   (*Show in Share Sheet*) → mục *Nhận* (Receive) chọn **URL** và **Văn bản** → Xong
4. Thêm hành động 1: tìm **"Mã hóa URL"** (*URL Encode*) → nó tự nhận
   đầu vào là *Đầu vào phím tắt* (Shortcut Input)
5. Thêm hành động 2: tìm **"Mở URL"** (*Open URLs*) → bấm vào ô URL, gõ:

   ```
   mapsnoti://route?link=
   ```

   rồi ngay sau dấu `=` chọn biến **Văn bản được mã hóa URL** (kết quả của
   hành động 1) từ thanh gợi ý biến phía trên bàn phím
6. Xong. Thử: Google Maps → **Chia sẻ** → kéo xuống danh sách hành động →
   bấm **Đi bằng MapsNoti** → MapsNoti bật lên với đường vẽ sẵn

> Lần đầu chạy iOS hỏi "Cho phép mở MapsNoti?" → Luôn cho phép.
>
> Có cách B rồi thì extension ShareToMapsNoti thành dự phòng (nó vẫn chép
> link vào clipboard để nút Dán sáng xanh) — giữ hay xoá target đều được.

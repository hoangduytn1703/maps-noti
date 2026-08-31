# maps-noti

App iOS tự chỉ đường, bắn local notification ở mỗi lệnh rẽ, để Huawei Watch GT4
mirror qua ANCS — thay cho Google Maps (đã chuyển sang Live Activity nên đồng hồ
không còn nhận được).

Thiết bị: iPhone 13 Pro Max + Huawei Watch GT4.

## Kết quả smoke test

Chạy trên máy thật ngày 31/08/2026. Chi tiết bài test ở [ios-smoketest/](ios-smoketest/README.md).

| Câu hỏi | Kết quả |
|---|---|
| Huawei Health có cho bật app tự cài không? | ✅ **Có** — NotiSmokeTest hiện trong danh sách và bật được |
| iPhone khoá, nằm trong túi, đồng hồ có rung? | ✅ **Có** |
| Độ trễ | ✅ **~1 giây** |
| Tiếng Việt có dấu | ✅ Hiển thị đúng |
| Nhiều noti liên tiếp có bị gộp? | ✅ **Không** — 5/5 lần rung, tới nhau ngay |
| Do Not Disturb có chặn? | ⏳ chưa đo |
| Emoji (🏁) | ✅ Hiển thị được |
| Ký tự mũi tên `↰ ↱ ↑` | ⏳ chưa xác nhận |
| Chuỗi dài cắt ở đâu | ⏳ chưa đo |

**Kết luận: hướng này chạy được.** Huawei không chặn app ngoài App Store, và độ
trễ 1 giây thì bắn noti ở 150 m trước ngã rẽ là thừa kịp (chạy 40 km/h chỉ lệch
khoảng 12 m).

## Bước tiếp theo

Viết app chính:

- **Routing** — Google Directions API (`language=vi`), lấy từng step kèm maneuver và toạ độ
- **Chạy nền** — `CLLocationManager` với `allowsBackgroundLocationUpdates`,
  `activityType = .automotiveNavigation`; background mode `location` cho app sống
  vô thời hạn khi bỏ túi
- **Bắn noti** — tính khoảng cách tới maneuver kế tiếp, bắn ở các mốc cố định
- **Lệch đường** — cách polyline quá xa trong vài update liên tiếp thì gọi lại route

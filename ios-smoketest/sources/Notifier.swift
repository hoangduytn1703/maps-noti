import Foundation
import UserNotifications

/// Toàn bộ phần bắn thông báo cho bài test.
/// Mục tiêu duy nhất: xác minh Huawei Watch GT4 có nhận noti từ một app tự cài hay không.
@MainActor
final class Notifier: NSObject, ObservableObject {

    @Published private(set) var authStatus = "chưa kiểm tra"
    @Published private(set) var log: [String] = []

    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        // Không có delegate này thì noti bắn lúc app đang mở sẽ bị iOS nuốt,
        // không vào Notification Center, và ANCS cũng không đẩy sang đồng hồ.
        center.delegate = self
    }

    // MARK: - Quyền

    func requestPermission() {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            Task { @MainActor in
                if let error {
                    self.append("❌ xin quyền lỗi: \(error.localizedDescription)")
                }
                self.append(granted ? "✅ đã cấp quyền" : "⛔️ bị từ chối quyền")
                self.refreshStatus()
            }
        }
    }

    func refreshStatus() {
        center.getNotificationSettings { settings in
            let text: String
            switch settings.authorizationStatus {
            case .authorized:    text = "đã cấp"
            case .denied:        text = "bị từ chối"
            case .notDetermined: text = "chưa hỏi"
            case .provisional:   text = "tạm thời (im lặng)"
            case .ephemeral:     text = "ephemeral"
            @unknown default:    text = "không rõ"
            }
            Task { @MainActor in self.authStatus = text }
        }
    }

    // MARK: - Bắn noti

    /// `delay == 0` gửi ngay; `delay > 0` hẹn giờ, đủ để khoá máy bỏ vào túi trước khi nó nổ.
    func fire(title: String, body: String, after delay: TimeInterval = 0) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        // Mỗi noti một id riêng. Dùng lại id thì iOS ghi đè cái cũ
        // và đồng hồ chỉ rung đúng một lần cho cả loạt.
        let trigger: UNNotificationTrigger? = delay > 0
            ? UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
            : nil
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content,
                                            trigger: trigger)

        center.add(request) { error in
            Task { @MainActor in
                if let error {
                    self.append("❌ \(title): \(error.localizedDescription)")
                } else if delay > 0 {
                    self.append("⏱ hẹn \(Int(delay))s — \(title)")
                } else {
                    self.append("📤 gửi ngay — \(title)")
                }
            }
        }
    }

    /// Mô phỏng nhịp của một lần chỉ đường thật: nhiều lệnh rẽ liên tiếp.
    /// Dùng để xem iOS hoặc Huawei Health có gộp / bóp bớt khi noti dồn dập không.
    func fireTurnSequence(startingAfter delay: TimeInterval = 20, gap: TimeInterval = 20) {
        let turns = [
            ("↰ Rẽ trái",    "500 m · Nguyễn Huệ"),
            ("↰ Rẽ trái",    "150 m · Nguyễn Huệ"),
            ("↱ Rẽ phải",    "300 m · Lê Lợi"),
            ("↑ Đi thẳng",   "1,2 km · qua vòng xoay"),
            ("🏁 Đã tới nơi", "Bên phải bạn"),
        ]
        for (i, turn) in turns.enumerated() {
            fire(title: turn.0, body: turn.1, after: delay + Double(i) * gap)
        }
    }

    func clearPending() {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
        append("🗑 đã xoá hàng chờ")
    }

    // MARK: - Nhật ký

    private func append(_ line: String) {
        log.insert("\(Self.clock.string(from: Date()))  \(line)", at: 0)
    }

    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}

extension Notifier: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }
}

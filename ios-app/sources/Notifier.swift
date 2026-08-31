import Combine
import Foundation
import UserNotifications

/// Bắn local notification — ANCS đẩy sang Huawei Watch GT4.
/// Kiến trúc đã xác minh bằng smoke test: trễ ~1s, không gộp, tiếng Việt chuẩn.
@MainActor
final class Notifier: NSObject, ObservableObject {

    @Published var authStatus = "chưa kiểm tra"

    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        // Cho noti hiện cả khi app đang mở — không có thì iOS nuốt,
        // đồng hồ cũng không thấy gì.
        center.delegate = self
    }

    func requestPermission() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        await refreshStatus()
    }

    func refreshStatus() async {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized:    authStatus = "đã cấp"
        case .denied:        authStatus = "bị từ chối"
        case .notDetermined: authStatus = "chưa hỏi"
        default:             authStatus = "khác"
        }
    }

    func fire(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        // Mỗi noti một id riêng — trùng id là iOS ghi đè, đồng hồ chỉ rung một lần.
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content,
                                            trigger: nil)
        Task { try? await center.add(request) }
    }
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

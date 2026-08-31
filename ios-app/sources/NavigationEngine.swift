import Combine
import CoreLocation
import Foundation

/// Trái tim của app: theo GPS chạy nền, đo khoảng cách tới ngã rẽ kế tiếp,
/// bắn thông báo ở hai mốc, phát hiện lệch đường và xin route mới.
@MainActor
final class NavigationEngine: NSObject, ObservableObject {

    // Mốc bắn noti, mét. Smoke test đo trễ ~1s nên hai mốc này thừa kịp với xe máy.
    private let farMark: Double = 300
    private let nearMark: Double = 80
    private let passMark: Double = 35      // coi như đã qua ngã rẽ
    private let offRouteMark: Double = 75  // cách tuyến bao xa thì tính là lệch

    struct Announcement {
        let coordinate: CLLocationCoordinate2D
        let glyph: String       // emoji cho notification
        let symbol: String      // SF Symbol cho banner trên màn hình
        let word: String        // "Rẽ trái" — luôn tự đủ nghĩa
        let instruction: String // câu đầy đủ
        let isArrival: Bool
    }

    @Published private(set) var isNavigating = false
    @Published private(set) var lastLocation: CLLocationCoordinate2D?
    @Published private(set) var log: [String] = []

    // Trạng thái cho banner kiểu Apple Maps
    @Published private(set) var nextSymbol = "arrow.up"
    @Published private(set) var nextWord = ""
    @Published private(set) var nextDistanceText = ""
    @Published private(set) var nextInstruction = ""
    /// Tuyến đang chạy — ContentView vẽ lên bản đồ, tự cập nhật khi reroute.
    @Published private(set) var activePolyline: [CLLocationCoordinate2D] = []

    /// ContentView gắn vào Notifier.
    var notify: (String, String) -> Void = { _, _ in }
    /// Gọi khi lệch đường: nhận vị trí hiện tại, trả route mới (hoặc nil nếu lỗi).
    var reroute: ((CLLocationCoordinate2D) async -> Route?)?

    private let manager = CLLocationManager()
    private var announcements: [Announcement] = []
    private var index = 0
    private var firedFar = false
    private var firedNear = false
    private var routePoints: [CLLocationCoordinate2D] = []
    private var offRouteCount = 0
    private var isRerouting = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = .automotiveNavigation
        manager.pausesLocationUpdatesAutomatically = false
    }

    // MARK: - Vòng đời

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    /// Bật GPS lúc app mở để lấy vị trí xuất phát. Chưa cho chạy nền.
    func startForegroundUpdates() {
        manager.startUpdatingLocation()
    }

    func start(route: Route) {
        buildAnnouncements(from: route)
        routePoints = route.polyline
        activePolyline = route.polyline
        index = 0
        firedFar = false
        firedNear = false
        offRouteCount = 0
        isNavigating = true

        // Hai dòng cho phép app sống khi khoá máy bỏ túi.
        // ĐÒI HỎI Background Modes → Location updates đã bật, thiếu là crash.
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()

        let km = formatDistance(Double(route.distanceMeters))
        let mins = max(1, route.durationSeconds / 60)
        let first = route.steps.first?.instruction ?? ""
        notify("🧭 Bắt đầu · \(km)", "Khoảng \(mins) phút. \(first)")
        append("▶️ bắt đầu: \(km), ~\(mins) phút, \(announcements.count) điểm báo")
    }

    func stop(silent: Bool = false) {
        isNavigating = false
        manager.allowsBackgroundLocationUpdates = false
        activePolyline = []
        nextWord = ""
        nextDistanceText = ""
        nextInstruction = ""
        nextSymbol = "arrow.up"
        if !silent {
            notify("⏹ Đã dừng chỉ đường", "Tắt theo yêu cầu")
            append("⏹ dừng")
        }
    }

    // MARK: - Dựng danh sách điểm báo

    /// Lệnh của step k+1 xảy ra tại điểm CUỐI của step k.
    private func buildAnnouncements(from route: Route) {
        var list: [Announcement] = []
        let steps = route.steps
        if steps.count >= 2 {
            for k in 0..<(steps.count - 1) {
                let next = steps[k + 1]
                list.append(Announcement(coordinate: steps[k].endCoordinate,
                                         glyph: Maneuver.glyph(next.maneuver),
                                         symbol: Maneuver.symbol(next.maneuver),
                                         word: Maneuver.word(next.maneuver),
                                         instruction: next.instruction,
                                         isArrival: false))
            }
        }
        if let last = steps.last {
            list.append(Announcement(coordinate: last.endCoordinate,
                                     glyph: "🏁",
                                     symbol: "flag.checkered",
                                     word: "Đã tới nơi",
                                     instruction: "Điểm đến ở gần đây",
                                     isArrival: true))
        }
        announcements = list
    }

    /// Route mới sau khi lệch đường.
    private func apply(route: Route) {
        buildAnnouncements(from: route)
        routePoints = route.polyline
        activePolyline = route.polyline
        index = 0
        firedFar = false
        firedNear = false
        offRouteCount = 0
        let km = formatDistance(Double(route.distanceMeters))
        notify("🔄 Đường mới · \(km)", route.steps.first?.instruction ?? "Đi tiếp")
        append("🔄 route mới: \(km), \(announcements.count) điểm báo")
    }

    // MARK: - Xử lý mỗi lần GPS nhích

    func process(_ location: CLLocation) {
        lastLocation = location.coordinate
        guard isNavigating, index < announcements.count else { return }

        let target = announcements[index]
        let d = location.coordinate.distance(to: target.coordinate)

        nextSymbol = target.symbol
        nextWord = target.word
        nextDistanceText = formatDistance(d)
        nextInstruction = target.instruction

        if target.isArrival {
            if d < 45 {
                notify("🏁 Đã tới nơi", target.instruction)
                append("🏁 tới nơi")
                stop(silent: true)
            }
        } else if d < passMark {
            // Qua ngã rẽ — đoạn quá ngắn chưa kịp báo thì báo bù ngay.
            if !firedNear {
                notify("\(target.glyph) \(target.word)", target.instruction)
            }
            advance()
        } else if d < nearMark + 10 {
            if !firedNear {
                firedNear = true
                notify("\(target.glyph) \(target.word) · \(formatDistance(d))", target.instruction)
                append("📤 gần: \(target.word) \(formatDistance(d))")
            }
        } else if d < farMark + 20 {
            if !firedFar {
                firedFar = true
                notify("\(target.glyph) Sắp: \(target.word.lowercased()) · \(formatDistance(d))",
                       target.instruction)
                append("📤 xa: \(target.word) \(formatDistance(d))")
            }
        }

        checkOffRoute(location)
    }

    private func advance() {
        index += 1
        firedFar = false
        firedNear = false
    }

    // MARK: - Lệch đường

    private func checkOffRoute(_ location: CLLocation) {
        guard !routePoints.isEmpty, !isRerouting else { return }
        // GPS nhiễu thì bỏ qua, khỏi reroute oan.
        guard location.horizontalAccuracy < 50 else { return }

        var minD = Double.greatestFiniteMagnitude
        for p in routePoints {
            let d = location.coordinate.distance(to: p)
            if d < minD { minD = d }
            if minD < offRouteMark { break }
        }

        if minD > offRouteMark {
            offRouteCount += 1
        } else {
            offRouteCount = 0
        }

        guard offRouteCount >= 3, let reroute else { return }
        offRouteCount = 0
        isRerouting = true
        append("⚠️ lệch đường \(Int(minD)) m, tính lại…")
        notify("🔄 Lệch đường", "Đang tính lại lộ trình…")
        let here = location.coordinate
        Task {
            if let newRoute = await reroute(here) {
                self.apply(route: newRoute)
            } else {
                self.append("❌ tính lại thất bại, giữ route cũ")
            }
            self.isRerouting = false
        }
    }

    // MARK: - Nhật ký

    private func append(_ line: String) {
        log.insert("\(Self.clock.string(from: Date()))  \(line)", at: 0)
        if log.count > 200 { log.removeLast() }
    }

    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}

extension NavigationEngine: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in self.process(loc) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didFailWithError error: Error) {
        let msg = error.localizedDescription
        Task { @MainActor in self.append("⚠️ GPS lỗi: \(msg)") }
    }
}

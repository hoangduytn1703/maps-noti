import Combine
import CoreLocation
import Foundation

/// Một địa điểm yêu thích. `label` là tên gợi nhớ do người dùng đặt
/// ("Nhà", "Công ty"…) — để trống cũng được, khi đó hiện tên gốc.
struct FavoritePlace: Codable, Identifiable, Equatable {
    var id = UUID()
    var label: String?
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double

    var place: Place {
        Place(name: name,
              address: address,
              coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
    }

    /// Tên hiện ra ngoài: ưu tiên label, không có thì tên gốc.
    var displayTitle: String {
        if let label, !label.isEmpty { return label }
        return name
    }

    /// Icon theo tên gợi nhớ: nhà ra hình nhà, công ty ra cặp táp, còn lại ngôi sao.
    var iconName: String {
        let t = (label ?? "").lowercased()
        if t.contains("nhà") || t.contains("home") { return "house.fill" }
        if t.contains("công ty") || t.contains("cty") || t.contains("văn phòng")
            || t.contains("làm") || t.contains("work") || t.contains("office") {
            return "briefcase.fill"
        }
        if t.contains("trường") || t.contains("school") { return "graduationcap.fill" }
        if t.contains("gym") || t.contains("tập") { return "dumbbell.fill" }
        return "star.fill"
    }
}

/// Danh sách yêu thích, lưu trên máy. Không server, không đồng bộ — đủ xài.
@MainActor
final class FavoritesStore: ObservableObject {

    @Published private(set) var items: [FavoritePlace] = []

    private static let storageKey = "favoritePlaces"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([FavoritePlace].self, from: data) {
            items = decoded
        }
    }

    func isSaved(_ place: Place) -> Bool {
        items.contains { same($0, place) }
    }

    func add(_ place: Place, label: String) {
        guard !isSaved(place) else { return }
        let trimmed = label.trimmingCharacters(in: .whitespaces)
        items.insert(FavoritePlace(label: trimmed.isEmpty ? nil : trimmed,
                                   name: place.name,
                                   address: place.address,
                                   latitude: place.coordinate.latitude,
                                   longitude: place.coordinate.longitude),
                     at: 0)
        save()
    }

    func remove(_ place: Place) {
        items.removeAll { same($0, place) }
        save()
    }

    func remove(id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }

    /// So bằng tên + toạ độ xấp xỉ (~50 m) — đủ để không lưu trùng.
    private func same(_ f: FavoritePlace, _ p: Place) -> Bool {
        f.name == p.name
            && abs(f.latitude - p.coordinate.latitude) < 0.0005
            && abs(f.longitude - p.coordinate.longitude) < 0.0005
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}

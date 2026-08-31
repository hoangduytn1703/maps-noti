import Combine
import SwiftUI
import CoreLocation
import Foundation

/// Một địa điểm yêu thích — bản Codable của Place để cất vào UserDefaults.
struct FavoritePlace: Codable, Identifiable, Equatable {
    var id = UUID()
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double

    var place: Place {
        Place(name: name,
              address: address,
              coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
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

    /// Chưa có thì thêm, có rồi thì bỏ.
    func toggle(_ place: Place) {
        if let i = items.firstIndex(where: { same($0, place) }) {
            items.remove(at: i)
        } else {
            items.insert(FavoritePlace(name: place.name,
                                       address: place.address,
                                       latitude: place.coordinate.latitude,
                                       longitude: place.coordinate.longitude),
                         at: 0)
        }
        save()
    }

    func remove(atOffsets offsets: IndexSet) {
        items.remove(atOffsets: offsets)
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

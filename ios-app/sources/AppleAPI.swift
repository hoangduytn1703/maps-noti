import CoreLocation
import Foundation
import MapKit

/// Nguồn dữ liệu chỉ đường: Apple Maps (MapKit) — nằm sẵn trong iOS,
/// không cần API key, không cần billing, không giới hạn lượt gọi.
/// Cùng hình dạng với GoogleAPI để sau này muốn đổi nguồn chỉ sửa call site.
struct AppleAPI {

    // MARK: - Tìm địa điểm

    /// `near` là vị trí hiện tại — có nó kết quả sẽ ưu tiên quanh mình
    /// thay vì trả về trùng tên ở tỉnh khác.
    func searchPlaces(_ query: String, near: CLLocationCoordinate2D?) async throws -> [Place] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        if let near {
            request.region = MKCoordinateRegion(center: near,
                                                latitudinalMeters: 50_000,
                                                longitudinalMeters: 50_000)
        }

        let response = try await MKLocalSearch(request: request).start()
        return response.mapItems.prefix(6).map { item in
            Place(name: item.name ?? query,
                  address: item.placemark.title ?? "",
                  coordinate: item.placemark.coordinate)
        }
    }

    // MARK: - Tính lộ trình

    func computeRoute(from origin: CLLocationCoordinate2D,
                      to destination: CLLocationCoordinate2D) async throws -> Route {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        // MapKit không có chế độ xe máy — automobile là gần nhất.
        request.transportType = .automobile

        let response = try await MKDirections(request: request).calculate()
        guard let route = response.routes.first else {
            throw AppleAPIError.noRoute
        }

        let steps: [RouteStep] = route.steps.compactMap { step in
            guard let end = step.polyline.coordinates.last else { return nil }
            let text = step.instructions.isEmpty ? "Xuất phát" : step.instructions
            return RouteStep(instruction: text,
                             maneuver: Self.maneuver(fromInstruction: text),
                             distanceMeters: Int(step.distance),
                             endCoordinate: end)
        }
        guard !steps.isEmpty else { throw AppleAPIError.noRoute }

        return Route(distanceMeters: Int(route.distance),
                     durationSeconds: Int(route.expectedTravelTime),
                     steps: steps,
                     polyline: route.polyline.coordinates)
    }

    // MARK: - Đoán maneuver từ câu chữ

    /// MapKit chỉ cho câu instruction, không cho mã rẽ trái/phải như Google,
    /// nên soi chữ để chọn emoji + từ ngắn. Instruction theo ngôn ngữ máy —
    /// bắt cả tiếng Việt lẫn tiếng Anh cho chắc.
    private static func maneuver(fromInstruction text: String) -> String {
        let t = text.lowercased()
        if t.contains("quay đầu") || t.contains("u-turn") || t.contains("u turn") {
            return "UTURN_LEFT"
        }
        if t.contains("vòng xuyến") || t.contains("vòng xoay") || t.contains("roundabout") {
            return "ROUNDABOUT_RIGHT"
        }
        if t.contains("giữ bên trái") || t.contains("keep left") {
            return "TURN_SLIGHT_LEFT"
        }
        if t.contains("giữ bên phải") || t.contains("keep right") {
            return "TURN_SLIGHT_RIGHT"
        }
        if t.contains("trái") || t.contains("left") {
            return "TURN_LEFT"
        }
        if t.contains("phải") || t.contains("right") {
            return "TURN_RIGHT"
        }
        if t.contains("nhập") || t.contains("merge") {
            return "MERGE"
        }
        return "STRAIGHT"
    }
}

enum AppleAPIError: LocalizedError {
    case noRoute
    var errorDescription: String? {
        "Apple Maps không tìm được đường tới đó"
    }
}

// MARK: - Rút toạ độ từ MKPolyline

extension MKPolyline {
    var coordinates: [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D](repeating: CLLocationCoordinate2D(),
                                              count: pointCount)
        getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
        return coords
    }
}

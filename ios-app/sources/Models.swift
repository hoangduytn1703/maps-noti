import CoreLocation
import Foundation

// MARK: - Địa điểm tìm được

struct Place: Identifiable {
    let id = UUID()
    let name: String
    let address: String
    let coordinate: CLLocationCoordinate2D
}

// MARK: - Lộ trình

struct RouteStep {
    /// Câu lệnh đầy đủ tiếng Việt, mô tả việc cần làm Ở ĐẦU đoạn này,
    /// ví dụ "Rẽ trái vào Nguyễn Đình Chiểu".
    let instruction: String
    /// Mã maneuver: TURN_LEFT, TURN_RIGHT, ROUNDABOUT_RIGHT, ...
    let maneuver: String
    let distanceMeters: Int
    /// Điểm cuối đoạn — nơi maneuver của đoạn KẾ TIẾP xảy ra.
    let endCoordinate: CLLocationCoordinate2D
}

struct Route {
    let distanceMeters: Int
    let durationSeconds: Int
    let steps: [RouteStep]
    /// Toàn tuyến, đã giải mã — vẽ lên bản đồ + phát hiện lệch đường.
    let polyline: [CLLocationCoordinate2D]
}

// MARK: - Maneuver → emoji / chữ / SF Symbol

enum Maneuver {
    /// Emoji cho notification — GT4 lúc hiện lúc nuốt, chữ phải luôn tự đủ nghĩa.
    static func glyph(_ m: String) -> String {
        switch m {
        case "TURN_LEFT", "TURN_SLIGHT_LEFT", "TURN_SHARP_LEFT", "RAMP_LEFT", "FORK_LEFT":
            return "⬅️"
        case "TURN_RIGHT", "TURN_SLIGHT_RIGHT", "TURN_SHARP_RIGHT", "RAMP_RIGHT", "FORK_RIGHT":
            return "➡️"
        case "UTURN_LEFT", "UTURN_RIGHT":
            return "↩️"
        case "ROUNDABOUT_LEFT", "ROUNDABOUT_RIGHT":
            return "🔄"
        case "STRAIGHT", "NAME_CHANGE", "MERGE", "DEPART":
            return "⬆️"
        default:
            return "🧭"
        }
    }

    static func word(_ m: String) -> String {
        switch m {
        case "TURN_LEFT":            return "Rẽ trái"
        case "TURN_SLIGHT_LEFT":     return "Chếch trái"
        case "TURN_SHARP_LEFT":      return "Rẽ gắt trái"
        case "TURN_RIGHT":           return "Rẽ phải"
        case "TURN_SLIGHT_RIGHT":    return "Chếch phải"
        case "TURN_SHARP_RIGHT":     return "Rẽ gắt phải"
        case "UTURN_LEFT", "UTURN_RIGHT": return "Quay đầu"
        case "ROUNDABOUT_LEFT", "ROUNDABOUT_RIGHT": return "Vòng xoay"
        case "RAMP_LEFT":            return "Nhánh trái"
        case "RAMP_RIGHT":           return "Nhánh phải"
        case "FORK_LEFT":            return "Nhánh trái"
        case "FORK_RIGHT":           return "Nhánh phải"
        case "MERGE":                return "Nhập làn"
        case "STRAIGHT", "NAME_CHANGE": return "Đi thẳng"
        default:                     return "Chú ý"
        }
    }

    /// SF Symbol cho banner trên màn hình (kiểu Apple Maps).
    static func symbol(_ m: String) -> String {
        switch m {
        case "TURN_LEFT", "TURN_SHARP_LEFT":
            return "arrow.turn.up.left"
        case "TURN_SLIGHT_LEFT", "FORK_LEFT", "RAMP_LEFT":
            return "arrow.up.left"
        case "TURN_RIGHT", "TURN_SHARP_RIGHT":
            return "arrow.turn.up.right"
        case "TURN_SLIGHT_RIGHT", "FORK_RIGHT", "RAMP_RIGHT":
            return "arrow.up.right"
        case "UTURN_LEFT", "UTURN_RIGHT":
            return "arrow.uturn.left"
        case "ROUNDABOUT_LEFT", "ROUNDABOUT_RIGHT":
            return "arrow.triangle.2.circlepath"
        case "MERGE":
            return "arrow.merge"
        default:
            return "arrow.up"
        }
    }
}

// MARK: - Tiện ích

extension CLLocationCoordinate2D {
    func distance(to other: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: other.latitude, longitude: other.longitude))
    }
}

func formatDistance(_ meters: Double) -> String {
    if meters < 950 {
        return "\(Int(meters / 10) * 10) m"
    }
    return String(format: "%.1f km", meters / 1000).replacingOccurrences(of: ".", with: ",")
}

// MARK: - Giải mã encoded polyline của Google (dùng cho phase 2)

enum Polyline {
    static func decode(_ encoded: String) -> [CLLocationCoordinate2D] {
        var coords: [CLLocationCoordinate2D] = []
        let bytes = Array(encoded.utf8)
        var i = 0
        var lat = 0
        var lng = 0

        func nextValue() -> Int? {
            var result = 0
            var shift = 0
            while i < bytes.count {
                let b = Int(bytes[i]) - 63
                i += 1
                result |= (b & 0x1F) << shift
                shift += 5
                if b < 0x20 {
                    return (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
                }
            }
            return nil
        }

        while i < bytes.count {
            guard let dLat = nextValue(), let dLng = nextValue() else { break }
            lat += dLat
            lng += dLng
            coords.append(CLLocationCoordinate2D(latitude: Double(lat) * 1e-5,
                                                 longitude: Double(lng) * 1e-5))
        }
        return coords
    }
}

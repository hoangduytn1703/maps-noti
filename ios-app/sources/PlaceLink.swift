import CoreLocation
import Foundation

/// Moi điểm đến ra từ link Google Maps (hoặc chuỗi toạ độ) dán vào app.
///
/// Đây là cách lấy dữ liệu địa điểm của Google mà không cần API key, không cần
/// billing: người dùng tìm quán trong app Google Maps như thường lệ, bấm Chia sẻ,
/// rồi dán link sang đây.
enum PlaceLink {

    enum LinkError: LocalizedError {
        case notRecognized
        case cannotResolve

        var errorDescription: String? {
            switch self {
            case .notRecognized:
                return "Không đọc được nội dung này. Trong Google Maps bấm Chia sẻ → Sao chép liên kết, rồi dán lại."
            case .cannotResolve:
                return "Không mở được link rút gọn — kiểm tra mạng rồi thử lại."
            }
        }
    }

    // MARK: - Cửa chính

    static func parse(_ raw: String) async throws -> Place {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Toạ độ dán trần: "10.8231, 106.6297"
        //    (Google Maps: giữ tay lên bản đồ → toạ độ hiện ra → bấm để copy)
        if let c = plainCoordinate(text) {
            return Place(name: "Điểm đã ghim", address: coordText(c), coordinate: c)
        }

        // 2. Nhặt URL trong chuỗi — Google hay kèm chữ mô tả quanh link.
        guard var url = firstURL(in: text) else { throw LinkError.notRecognized }

        // 3. Link rút gọn thì giãn ra: đi theo redirect để lộ URL đầy đủ.
        if isShortLink(url) {
            url = try await expand(url)
        }

        let full = url.absoluteString
        let name = placeName(from: url) ?? "Điểm từ Google Maps"

        // 4. Toạ độ CHÍNH XÁC của địa điểm nằm ở !3d<lat>!4d<lng>.
        if let c = match(full, #"!3d(-?\d+\.\d+)!4d(-?\d+\.\d+)"#) {
            return Place(name: name, address: coordText(c), coordinate: c)
        }
        // 5. Tâm khung nhìn: @lat,lng — kém chính xác hơn chút nhưng vẫn tốt.
        if let c = match(full, #"@(-?\d+\.\d+),(-?\d+\.\d+)"#) {
            return Place(name: name, address: coordText(c), coordinate: c)
        }
        // 6. Dạng tham số: ?q=lat,lng / ?query=lat,lng / ?daddr=lat,lng
        if let c = match(full, #"[?&](?:q|query|daddr|destination)=(-?\d+\.\d+),\s*(-?\d+\.\d+)"#) {
            return Place(name: name, address: coordText(c), coordinate: c)
        }

        // 7. Link không mang toạ độ (dạng place-id): lấy TÊN từ link rồi
        //    nhờ Apple định vị. Vẫn hưởng được khả năng tìm kiếm của Google.
        if let resolved = try? await AppleAPI().searchPlaces(name, near: nil).first {
            return resolved
        }
        throw LinkError.notRecognized
    }

    // MARK: - Giãn link rút gọn

    private static func isShortLink(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return host.contains("goo.gl") || host.contains("g.co") || host.contains("gg.gg")
    }

    private static func expand(_ url: URL) async throws -> URL {
        var request = URLRequest(url: url)
        // Google trả nội dung khác nhau tuỳ client — giả trình duyệt cho chắc.
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        // URLSession tự đi theo redirect; URL cuối nằm ở response.url.
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let final = response.url else {
            throw LinkError.cannotResolve
        }
        return final
    }

    // MARK: - Nhặt thông tin

    private static func firstURL(in text: String) -> URL? {
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let range = NSRange(text.startIndex..., in: text)
            if let m = detector.firstMatch(in: text, range: range), let url = m.url {
                return url
            }
        }
        return URL(string: text)
    }

    /// Tên địa điểm nằm giữa /place/ và đoạn tiếp theo: .../maps/place/Mị+Coffee/@...
    private static func placeName(from url: URL) -> String? {
        let parts = url.pathComponents
        guard let i = parts.firstIndex(of: "place"), i + 1 < parts.count else { return nil }
        let raw = parts[i + 1].replacingOccurrences(of: "+", with: " ")
        let decoded = raw.removingPercentEncoding ?? raw
        let clean = decoded.trimmingCharacters(in: .whitespaces)
        // Đoạn "place" đôi khi chính là toạ độ, khi đó không phải tên.
        if clean.isEmpty || plainCoordinate(clean) != nil { return nil }
        return clean
    }

    private static func plainCoordinate(_ text: String) -> CLLocationCoordinate2D? {
        match(text, #"^\s*(-?\d+\.\d+)\s*,\s*(-?\d+\.\d+)\s*$"#)
    }

    /// Regex có đúng 2 nhóm bắt: lat rồi lng.
    private static func match(_ text: String, _ pattern: String) -> CLLocationCoordinate2D? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let m = re.firstMatch(in: text, range: range), m.numberOfRanges >= 3,
              let latRange = Range(m.range(at: 1), in: text),
              let lngRange = Range(m.range(at: 2), in: text),
              let lat = Double(text[latRange]),
              let lng = Double(text[lngRange]),
              abs(lat) <= 90, abs(lng) <= 180 else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    private static func coordText(_ c: CLLocationCoordinate2D) -> String {
        String(format: "%.5f, %.5f", c.latitude, c.longitude)
    }
}

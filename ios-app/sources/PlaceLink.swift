import CoreLocation
import Foundation

/// Moi điểm đến ra từ link Google Maps (hoặc chuỗi toạ độ) dán vào app.
///
/// Link Google có nhiều đời định dạng; chiến thuật nhiều lớp:
/// 1. Toạ độ dán trần
/// 2. Toạ độ nằm ngay trong URL (@lat,lng · !3d!4d · ?q=)
/// 3. Không có thì TẢI TRANG mà link trỏ tới — HTML của Google Maps luôn
///    giấu toạ độ trong thẻ og:image (ảnh bản đồ tĩnh có center=lat,lng)
///    và tên chỗ trong og:title
/// 4. Bét nhất: lấy được mỗi cái tên → nhờ Apple định vị
enum PlaceLink {

    enum LinkError: LocalizedError {
        case notRecognized
        case cannotResolve

        var errorDescription: String? {
            switch self {
            case .notRecognized:
                return "Không moi được toạ độ từ link này. Trong Google Maps thử giữ tay lên điểm đó rồi copy toạ độ, dán sang đây."
            case .cannotResolve:
                return "Không mở được link — kiểm tra mạng rồi thử lại."
            }
        }
    }

    // MARK: - Cửa chính

    static func parse(_ raw: String) async throws -> Place {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Toạ độ dán trần: "10.8231, 106.6297"
        if let c = plainCoordinate(text) {
            return Place(name: "Điểm đã ghim", address: coordText(c), coordinate: c)
        }

        guard let url = firstURL(in: text) else { throw LinkError.notRecognized }

        // 2. Toạ độ nằm ngay trong URL gốc thì khỏi tốn mạng.
        if let place = placeFromURLString(url.absoluteString) {
            return place
        }

        // 3. Tải trang (link rút gọn sẽ tự đi theo redirect) rồi soi cả
        //    URL cuối lẫn nội dung HTML.
        let (finalURL, body) = try await fetch(url)

        if let place = placeFromURLString(finalURL.absoluteString) {
            return place
        }
        if let place = placeFromHTML(body, url: finalURL) {
            return place
        }

        // 4. Còn mỗi cái tên → nhờ Apple định vị.
        let name = placeName(fromPath: finalURL) ?? ogTitle(in: body)
        if let name, let resolved = try? await AppleAPI().searchPlaces(name, near: nil).first {
            return resolved
        }
        throw LinkError.notRecognized
    }

    // MARK: - Moi từ URL

    private static func placeFromURLString(_ s: String) -> Place? {
        let name = placeName(fromPath: URL(string: s)) ?? "Điểm từ Google Maps"

        // Toạ độ CHÍNH XÁC của địa điểm: !3d<lat>!4d<lng>
        if let c = match(s, #"!3d(-?\d+\.\d+)!4d(-?\d+\.\d+)"#) {
            return Place(name: name, address: coordText(c), coordinate: c)
        }
        // Dạng tham số: ?q= / ?query= / ?daddr= / ?destination=
        if let c = match(s, #"[?&](?:q|query|daddr|destination)=(-?\d+\.\d+)(?:,|%2C)\s*(-?\d+\.\d+)"#) {
            return Place(name: name, address: coordText(c), coordinate: c)
        }
        // Tâm khung nhìn: @lat,lng — kém chính xác hơn chút, để sau cùng.
        if let c = match(s, #"@(-?\d+\.\d+),(-?\d+\.\d+)"#) {
            return Place(name: name, address: coordText(c), coordinate: c)
        }
        return nil
    }

    // MARK: - Moi từ HTML của trang Google Maps

    private static func placeFromHTML(_ body: String, url: URL) -> Place? {
        guard !body.isEmpty else { return nil }
        let name = placeName(fromPath: url) ?? ogTitle(in: body) ?? "Điểm từ Google Maps"

        // og:image là ảnh bản đồ tĩnh, mang center=lat%2Clng — chính là toạ độ chỗ đó.
        if let c = match(body, #"center=(-?\d+\.\d+)%2C(-?\d+\.\d+)"#) {
            return Place(name: name, address: coordText(c), coordinate: c)
        }
        // Thẻ canonical / link nội bộ dạng @lat,lng
        if let c = match(body, #"@(-?\d+\.\d+),(-?\d+\.\d+)"#) {
            return Place(name: name, address: coordText(c), coordinate: c)
        }
        // Toạ độ dạng !3d!4d nằm rải trong HTML
        if let c = match(body, #"!3d(-?\d+\.\d+)!4d(-?\d+\.\d+)"#) {
            return Place(name: name, address: coordText(c), coordinate: c)
        }
        return nil
    }

    /// `<meta property="og:title" content="Tên chỗ">` — bỏ qua nếu chỉ là "Google Maps".
    private static func ogTitle(in body: String) -> String? {
        guard let re = try? NSRegularExpression(
            pattern: #"property="og:title"\s+content="([^"]+)""#) else { return nil }
        let range = NSRange(body.startIndex..., in: body)
        guard let m = re.firstMatch(in: body, range: range),
              let r = Range(m.range(at: 1), in: body) else { return nil }
        var title = String(body[r])
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#39;", with: "'")
        for suffix in [" - Google Maps", " – Google Maps", " · Google Maps"] {
            if title.hasSuffix(suffix) { title = String(title.dropLast(suffix.count)) }
        }
        let clean = title.trimmingCharacters(in: .whitespaces)
        if clean.isEmpty || clean.lowercased() == "google maps" { return nil }
        return clean
    }

    // MARK: - Tải trang

    private static func fetch(_ url: URL) async throws -> (URL, String) {
        var request = URLRequest(url: url)
        // Giả trình duyệt iPhone — Google trả trang khác nhau tuỳ client.
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent")
        request.setValue("vi-VN,vi;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.timeoutInterval = 15

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let final = response.url else {
            throw LinkError.cannotResolve
        }
        return (final, String(decoding: data, as: UTF8.self))
    }

    // MARK: - Nhặt thông tin

    private static func firstURL(in text: String) -> URL? {
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let range = NSRange(text.startIndex..., in: text)
            if let m = detector.firstMatch(in: text, range: range), let url = m.url {
                return url
            }
        }
        // Chuỗi trần chỉ được tính là link khi là URL web thật.
        if let url = URL(string: text),
           let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https",
           url.host != nil {
            return url
        }
        return nil
    }

    /// Tên địa điểm giữa /place/ và đoạn kế: .../maps/place/Mị+Coffee/@...
    private static func placeName(fromPath url: URL?) -> String? {
        guard let url else { return nil }
        let parts = url.pathComponents
        guard let i = parts.firstIndex(of: "place"), i + 1 < parts.count else { return nil }
        let raw = parts[i + 1].replacingOccurrences(of: "+", with: " ")
        let decoded = raw.removingPercentEncoding ?? raw
        let clean = decoded.trimmingCharacters(in: .whitespaces)
        if clean.isEmpty || plainCoordinate(clean) != nil { return nil }
        return clean
    }

    private static func plainCoordinate(_ text: String) -> CLLocationCoordinate2D? {
        match(text, #"^\s*(-?\d+\.\d+)\s*,\s*(-?\d+\.\d+)\s*$"#)
    }

    /// Regex có đúng 2 nhóm bắt. Nhóm nào trị tuyệt đối > 90 thì chắc chắn là
    /// kinh độ — tự hoán đổi nếu bị ngược thứ tự.
    private static func match(_ text: String, _ pattern: String) -> CLLocationCoordinate2D? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let m = re.firstMatch(in: text, range: range), m.numberOfRanges >= 3,
              let aRange = Range(m.range(at: 1), in: text),
              let bRange = Range(m.range(at: 2), in: text),
              let a = Double(text[aRange]),
              let b = Double(text[bRange]) else { return nil }

        var lat = a
        var lng = b
        if abs(lat) > 90, abs(lng) <= 90 { swap(&lat, &lng) }
        guard abs(lat) <= 90, abs(lng) <= 180 else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    private static func coordText(_ c: CLLocationCoordinate2D) -> String {
        String(format: "%.5f, %.5f", c.latitude, c.longitude)
    }
}

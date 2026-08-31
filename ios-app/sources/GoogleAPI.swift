import CoreLocation
import Foundation

enum GoogleAPIError: LocalizedError {
    case badStatus(Int, String)
    case emptyResult

    var errorDescription: String? {
        switch self {
        case .badStatus(let code, let message):
            return "Google trả lỗi \(code): \(message)"
        case .emptyResult:
            return "Google không trả kết quả nào"
        }
    }
}

/// Gọi hai API của Google Maps Platform: Places (New) để tìm điểm đến,
/// Routes để lấy lộ trình kèm lệnh rẽ tiếng Việt.
struct GoogleAPI {
    let apiKey: String

    // MARK: - Tìm địa điểm

    func searchPlaces(_ query: String) async throws -> [Place] {
        var request = URLRequest(url: URL(string: "https://places.googleapis.com/v1/places:searchText")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue("places.displayName,places.formattedAddress,places.location",
                         forHTTPHeaderField: "X-Goog-FieldMask")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "textQuery": query,
            "languageCode": "vi",
            "regionCode": "VN",
            "pageSize": 5,
        ])

        let data = try await send(request)
        let decoded = try JSONDecoder().decode(PlacesResponse.self, from: data)
        guard let places = decoded.places, !places.isEmpty else { throw GoogleAPIError.emptyResult }
        return places.map {
            Place(name: $0.displayName.text,
                  address: $0.formattedAddress ?? "",
                  coordinate: CLLocationCoordinate2D(latitude: $0.location.latitude,
                                                     longitude: $0.location.longitude))
        }
    }

    // MARK: - Tính lộ trình

    func computeRoute(from origin: CLLocationCoordinate2D,
                      to destination: CLLocationCoordinate2D) async throws -> Route {
        // Xe máy trước (Google hỗ trợ TWO_WHEELER ở Việt Nam), hỏng thì xe hơi.
        do {
            return try await computeRoute(from: origin, to: destination, mode: "TWO_WHEELER")
        } catch {
            return try await computeRoute(from: origin, to: destination, mode: "DRIVE")
        }
    }

    private func computeRoute(from origin: CLLocationCoordinate2D,
                              to destination: CLLocationCoordinate2D,
                              mode: String) async throws -> Route {
        var request = URLRequest(url: URL(string: "https://routes.googleapis.com/directions/v2:computeRoutes")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue([
            "routes.distanceMeters",
            "routes.duration",
            "routes.polyline.encodedPolyline",
            "routes.legs.steps.distanceMeters",
            "routes.legs.steps.navigationInstruction",
            "routes.legs.steps.endLocation",
        ].joined(separator: ","), forHTTPHeaderField: "X-Goog-FieldMask")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "origin": ["location": ["latLng": ["latitude": origin.latitude,
                                               "longitude": origin.longitude]]],
            "destination": ["location": ["latLng": ["latitude": destination.latitude,
                                                    "longitude": destination.longitude]]],
            "travelMode": mode,
            "languageCode": "vi",
            "units": "METRIC",
        ])

        let data = try await send(request)
        let decoded = try JSONDecoder().decode(RoutesResponse.self, from: data)
        guard let route = decoded.routes?.first,
              let steps = route.legs?.first?.steps, !steps.isEmpty else {
            throw GoogleAPIError.emptyResult
        }

        let routeSteps: [RouteStep] = steps.compactMap { step in
            guard let end = step.endLocation?.latLng else { return nil }
            return RouteStep(
                instruction: step.navigationInstruction?.instructions ?? "Đi tiếp",
                maneuver: step.navigationInstruction?.maneuver ?? "STRAIGHT",
                distanceMeters: step.distanceMeters ?? 0,
                endCoordinate: CLLocationCoordinate2D(latitude: end.latitude,
                                                      longitude: end.longitude))
        }

        // "1234s" → 1234
        let seconds = Int((route.duration ?? "0s").dropLast()) ?? 0

        return Route(distanceMeters: route.distanceMeters ?? 0,
                     durationSeconds: seconds,
                     steps: routeSteps,
                     polyline: Polyline.decode(route.polyline?.encodedPolyline ?? ""))
    }

    // MARK: - Chung

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(code) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw GoogleAPIError.badStatus(code, String(body.prefix(300)))
        }
        return data
    }
}

// MARK: - Cấu trúc phản hồi

private struct PlacesResponse: Decodable {
    struct P: Decodable {
        struct DisplayName: Decodable { let text: String }
        struct Location: Decodable { let latitude: Double; let longitude: Double }
        let displayName: DisplayName
        let formattedAddress: String?
        let location: Location
    }
    let places: [P]?
}

private struct RoutesResponse: Decodable {
    struct R: Decodable {
        struct Poly: Decodable { let encodedPolyline: String }
        struct LatLngBox: Decodable {
            struct LatLng: Decodable { let latitude: Double; let longitude: Double }
            let latLng: LatLng?
        }
        struct Leg: Decodable {
            struct Step: Decodable {
                struct NavIns: Decodable {
                    let maneuver: String?
                    let instructions: String?
                }
                let distanceMeters: Int?
                let navigationInstruction: NavIns?
                let endLocation: LatLngBox?
            }
            let steps: [Step]?
        }
        let distanceMeters: Int?
        let duration: String?
        let legs: [Leg]?
        let polyline: Poly?
    }
    let routes: [R]?
}

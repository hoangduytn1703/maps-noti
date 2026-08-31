import CoreLocation
import MapKit
import SwiftUI

struct ContentView: View {
    @StateObject private var engine = NavigationEngine()
    @StateObject private var notifier = Notifier()
    @StateObject private var favorites = FavoritesStore()

    @Namespace private var mapScope

    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var query = ""
    @State private var results: [Place] = []
    /// Điểm xuất phát tuỳ chọn — nil nghĩa là "vị trí của tôi".
    @State private var origin: Place?
    @State private var pickingOrigin = false
    @State private var selected: Place?
    @State private var route: Route?
    @State private var busy = false
    @State private var errorText: String?
    @State private var showSaveAlert = false
    @State private var labelInput = ""

    private let api = AppleAPI()

    var body: some View {
        ZStack(alignment: .bottom) {
            mapLayer
                .ignoresSafeArea()

            if !engine.isNavigating {
                mapControlsOverlay
            }

            if engine.isNavigating {
                navigationOverlay
            } else {
                bottomPanel
            }
        }
        .mapScope(mapScope)
        .task {
            await notifier.requestPermission()
            engine.requestPermission()
            engine.startForegroundUpdates()
            engine.notify = { [weak notifier] title, body in
                notifier?.fire(title: title, body: body)
            }
        }
        .onOpenURL { url in
            // Share Extension gọi sang: mapsnoti://route?link=<đã mã hoá>
            guard url.scheme == "mapsnoti",
                  let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let link = comps.queryItems?.first(where: { $0.name == "link" })?.value,
                  !link.isEmpty else { return }
            if engine.isNavigating { engine.stop(silent: true) }
            handlePasted(link)
        }
        .alert("Lưu địa điểm", isPresented: $showSaveAlert) {
            TextField("Tên gợi nhớ (Nhà, Công ty…)", text: $labelInput)
            Button("Lưu") {
                if let selected {
                    favorites.add(selected, label: labelInput)
                }
            }
            Button("Huỷ", role: .cancel) {}
        } message: {
            Text("Bỏ trống tên cũng được.")
        }
    }

    // MARK: - Bản đồ

    private var routeLine: [CLLocationCoordinate2D] {
        engine.isNavigating ? engine.activePolyline : (route?.polyline ?? [])
    }

    private var mapLayer: some View {
        Map(position: $camera, scope: mapScope) {
            UserAnnotation()
            if routeLine.count > 1 {
                MapPolyline(coordinates: routeLine)
                    .stroke(.blue, lineWidth: 6)
            }
            if let origin {
                Marker(origin.name, coordinate: origin.coordinate)
                    .tint(.green)
            }
            if let selected {
                Marker(selected.name, coordinate: selected.coordinate)
            }
        }
    }

    /// Nút vị trí + la bàn. Phải nằm TRONG cây view có .mapScope thì mới
    /// nối được với Map — treo ngoài overlay là SwiftUI hỏng render.
    private var mapControlsOverlay: some View {
        VStack {
            HStack {
                Spacer()
                VStack(spacing: 10) {
                    MapUserLocationButton(scope: mapScope)
                    MapCompass(scope: mapScope)
                }
                .padding(.top, 72)
                .padding(.trailing, 14)
            }
            Spacer()
        }
    }

    // MARK: - Overlay khi đang chỉ đường

    private var navigationOverlay: some View {
        VStack {
            HStack(spacing: 16) {
                Image(systemName: engine.nextSymbol)
                    .font(.system(size: 38, weight: .bold))
                VStack(alignment: .leading, spacing: 2) {
                    Text(engine.nextDistanceText.isEmpty ? "…" : engine.nextDistanceText)
                        .font(.system(size: 32, weight: .heavy))
                    Text(engine.nextInstruction.isEmpty ? engine.nextWord : engine.nextInstruction)
                        .font(.subheadline)
                        .lineLimit(2)
                }
                Spacer()
            }
            .foregroundStyle(.white)
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(red: 0.09, green: 0.47, blue: 0.29))
                    .shadow(radius: 6, y: 3)
            )
            .padding(.horizontal, 12)
            .padding(.top, 6)

            Spacer()

            Button {
                stopEverything()
            } label: {
                Text("Kết thúc")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 44)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(.red).shadow(radius: 5, y: 2))
            }
            .padding(.bottom, 24)
        }
    }

    // MARK: - Panel dưới khi chưa chạy

    private var bottomPanel: some View {
        VStack(spacing: 12) {
            if pickingOrigin {
                originPickerBar
            }

            searchBar

            if !pickingOrigin {
                pasteRow
            }

            if let errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !results.isEmpty {
                resultsList
            }

            if let selected, let route {
                routeCard(selected, route)
            }

            if !favorites.items.isEmpty && results.isEmpty && route == nil && !pickingOrigin {
                favoritesRow
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 26)
                .fill(.regularMaterial)
                .shadow(radius: 8, y: 4)
        )
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
    }

    private var originPickerBar: some View {
        HStack {
            Label("Đang chọn điểm xuất phát", systemImage: "smallcircle.filled.circle")
                .font(.caption)
                .foregroundStyle(.green)
            Spacer()
            Button("Vị trí của tôi") {
                origin = nil
                pickingOrigin = false
                query = ""
                results = []
                computeRoute()
            }
            .font(.caption)
            Button("Huỷ") {
                pickingOrigin = false
                query = ""
                results = []
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(pickingOrigin ? "Tìm điểm xuất phát…" : "Tìm điểm đến…", text: $query)
                .onSubmit(search)
                .autocorrectionDisabled()
            if busy {
                ProgressView()
            } else if !query.isEmpty {
                Button {
                    query = ""
                    results = []
                    errorText = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 13).fill(.gray.opacity(0.15)))
    }

    /// Dán link từ app Google Maps — mượn kho địa điểm của Google mà
    /// không cần API key hay billing.
    private var pasteRow: some View {
        HStack(spacing: 10) {
            PasteButton(payloadType: String.self) { items in
                guard let first = items.first else { return }
                Task { @MainActor in handlePasted(first) }
            }
            .labelStyle(.iconOnly)
            .buttonBorderShape(.capsule)

            VStack(alignment: .leading, spacing: 1) {
                Text("Dán link Google Maps")
                    .font(.caption)
                Text("Trong Google Maps: Chia sẻ → Sao chép liên kết")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var resultsList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(results) { place in
                    Button {
                        choose(place)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: pickingOrigin ? "smallcircle.filled.circle" : "mappin.circle.fill")
                                .font(.title3)
                                .foregroundStyle(pickingOrigin ? .green : .red)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(place.name)
                                    .foregroundStyle(.primary)
                                Text(place.address)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }
                    Divider()
                }
            }
        }
        .frame(maxHeight: 250)
    }

    private func routeCard(_ place: Place, _ route: Route) -> some View {
        VStack(spacing: 12) {
            // Điểm đi → điểm đến, bấm dòng đi để đổi
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "smallcircle.filled.circle")
                        .foregroundStyle(.green)
                    Button {
                        pickingOrigin = true
                        results = []
                        query = ""
                    } label: {
                        Text(origin?.name ?? "Vị trí của tôi")
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .underline(origin == nil, color: .clear)
                    }
                    if origin != nil {
                        Button {
                            origin = nil
                            computeRoute()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text("đổi")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
                HStack(spacing: 8) {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundStyle(.red)
                    Text(place.name)
                        .font(.subheadline.bold())
                    Spacer()
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12).fill(.gray.opacity(0.1)))

            HStack {
                Text("\(formatDistance(Double(route.distanceMeters))) · \(max(1, route.durationSeconds / 60)) phút · \(route.steps.count) đoạn")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    if favorites.isSaved(place) {
                        favorites.remove(place)
                    } else {
                        labelInput = ""
                        showSaveAlert = true
                    }
                } label: {
                    Image(systemName: favorites.isSaved(place) ? "star.fill" : "star")
                        .font(.title3)
                        .foregroundStyle(.yellow)
                }
                Button {
                    clearRoute()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                startNavigation(to: place, route: route)
            } label: {
                Label("Bắt đầu", systemImage: "location.north.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Capsule().fill(.blue))
            }
        }
    }

    private var favoritesRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 18) {
                ForEach(favorites.items) { fav in
                    Button {
                        choose(fav.place)
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: fav.iconName)
                                .font(.title3)
                                .foregroundStyle(.blue)
                                .frame(width: 54, height: 54)
                                .background(Circle().fill(.blue.opacity(0.14)))
                            Text(fav.displayTitle)
                                .font(.caption2)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .frame(width: 66)
                        }
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            favorites.remove(id: fav.id)
                        } label: {
                            Label("Xoá", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Hành động

    private func search() {
        errorText = nil
        results = []
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                results = try await api.searchPlaces(text, near: engine.lastLocation)
                if results.isEmpty { errorText = "Không tìm thấy chỗ nào tên vậy." }
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    private func handlePasted(_ text: String) {
        errorText = nil
        results = []
        query = ""
        busy = true
        Task {
            do {
                let place = try await PlaceLink.parse(text)
                busy = false
                choose(place)
            } catch {
                busy = false
                errorText = error.localizedDescription
            }
        }
    }

    private func choose(_ place: Place) {
        results = []
        errorText = nil
        query = ""
        if pickingOrigin {
            origin = place
            pickingOrigin = false
        } else {
            selected = place
        }
        computeRoute()
    }

    /// Tính đường từ điểm xuất phát (mặc định: vị trí hiện tại) tới điểm đến.
    private func computeRoute() {
        guard let dest = selected else { return }
        route = nil
        let from = origin?.coordinate ?? engine.lastLocation
        guard let from else {
            errorText = "Chưa bắt được GPS — ra chỗ thoáng, đợi vài giây rồi chọn lại."
            selected = nil
            return
        }
        busy = true
        Task {
            defer { busy = false }
            do {
                route = try await api.computeRoute(from: from, to: dest.coordinate)
                camera = .automatic // khung nhìn ôm trọn tuyến
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    private func startNavigation(to place: Place, route: Route) {
        let dest = place.coordinate
        engine.reroute = { [api] here in
            try? await api.computeRoute(from: here, to: dest)
        }
        camera = .userLocation(fallback: .automatic) // bám theo mình khi chạy
        engine.start(route: route)
    }

    private func clearRoute() {
        route = nil
        selected = nil
        origin = nil
        pickingOrigin = false
    }

    private func stopEverything() {
        engine.stop()
        clearRoute()
    }
}

#Preview {
    ContentView()
}

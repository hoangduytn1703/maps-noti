import CoreLocation
import MapKit
import SwiftUI

struct ContentView: View {
    @StateObject private var engine = NavigationEngine()
    @StateObject private var notifier = Notifier()
    @StateObject private var favorites = FavoritesStore()

    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var query = ""
    @State private var results: [Place] = []
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

            if engine.isNavigating {
                navigationOverlay
            } else {
                bottomPanel
            }
        }
        .task {
            await notifier.requestPermission()
            engine.requestPermission()
            engine.startForegroundUpdates()
            engine.notify = { [weak notifier] title, body in
                notifier?.fire(title: title, body: body)
            }
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
        Map(position: $camera) {
            UserAnnotation()
            if routeLine.count > 1 {
                MapPolyline(coordinates: routeLine)
                    .stroke(.blue, lineWidth: 6)
            }
            if let selected {
                Marker(selected.name, coordinate: selected.coordinate)
            }
        }
        .mapControls {
            MapUserLocationButton()
            MapCompass()
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
                engine.stop()
                route = nil
                selected = nil
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
            searchBar

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

            if !favorites.items.isEmpty && results.isEmpty && route == nil {
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

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Tìm địa điểm…", text: $query)
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

    private var resultsList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(results) { place in
                    Button {
                        choose(place)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.red)
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
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.name).font(.headline)
                    Text("\(formatDistance(Double(route.distanceMeters))) · \(max(1, route.durationSeconds / 60)) phút · \(route.steps.count) đoạn")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
                        .font(.title2)
                        .foregroundStyle(.yellow)
                }
                Button {
                    self.route = nil
                    self.selected = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
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
        selected = nil
        route = nil
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

    private func choose(_ place: Place) {
        selected = place
        results = []
        errorText = nil
        guard let here = engine.lastLocation else {
            errorText = "Chưa bắt được GPS — ra chỗ thoáng, đợi vài giây rồi chọn lại."
            selected = nil
            return
        }
        busy = true
        Task {
            defer { busy = false }
            do {
                route = try await api.computeRoute(from: here, to: place.coordinate)
                camera = .automatic // khung nhìn ôm trọn tuyến vừa vẽ
            } catch {
                errorText = error.localizedDescription
                selected = nil
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
}

#Preview {
    ContentView()
}

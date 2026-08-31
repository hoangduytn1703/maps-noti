import CoreLocation
import SwiftUI

struct ContentView: View {
    @AppStorage("googleAPIKey") private var apiKey = ""

    @StateObject private var engine = NavigationEngine()
    @StateObject private var notifier = Notifier()

    @State private var query = ""
    @State private var results: [Place] = []
    @State private var selected: Place?
    @State private var route: Route?
    @State private var busy = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            List {
                if engine.isNavigating {
                    navigatingSection
                } else {
                    searchSection
                    if let selected, let route {
                        routeSection(selected, route)
                    }
                    keySection
                }

                if let errorText {
                    Section {
                        Text(errorText).foregroundStyle(.red).font(.caption)
                    }
                }

                logSection
            }
            .navigationTitle("Maps Noti")
        }
        .task {
            await notifier.requestPermission()
            engine.requestPermission()
            engine.startForegroundUpdates()
            engine.notify = { [weak notifier] title, body in
                notifier?.fire(title: title, body: body)
            }
        }
    }

    // MARK: - Đang chạy

    private var navigatingSection: some View {
        Section("Đang chỉ đường") {
            Text(engine.statusLine)
                .font(.title3.bold())
            Button("Dừng", role: .destructive) {
                engine.stop()
                route = nil
                selected = nil
            }
        }
    }

    // MARK: - Tìm điểm đến

    private var searchSection: some View {
        Section("Đi đâu?") {
            HStack {
                TextField("Tên địa điểm…", text: $query)
                    .onSubmit(search)
                Button("Tìm", action: search)
                    .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || busy)
            }
            if busy {
                HStack { ProgressView(); Text("Đang hỏi Google…").foregroundStyle(.secondary) }
            }
            ForEach(results) { place in
                Button {
                    choose(place)
                } label: {
                    VStack(alignment: .leading) {
                        Text(place.name)
                        Text(place.address).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func search() {
        errorText = nil
        results = []
        selected = nil
        route = nil
        guard !apiKey.isEmpty else {
            errorText = "Chưa có API key — kéo xuống mục Cài đặt dán vào."
            return
        }
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                results = try await GoogleAPI(apiKey: apiKey).searchPlaces(text)
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
                route = try await GoogleAPI(apiKey: apiKey)
                    .computeRoute(from: here, to: place.coordinate)
            } catch {
                errorText = error.localizedDescription
                selected = nil
            }
        }
    }

    // MARK: - Route tìm được

    private func routeSection(_ place: Place, _ route: Route) -> some View {
        Section("Lộ trình") {
            VStack(alignment: .leading) {
                Text(place.name).bold()
                Text("\(formatDistance(Double(route.distanceMeters))) · khoảng \(max(1, route.durationSeconds / 60)) phút · \(route.steps.count) đoạn")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button {
                startNavigation(to: place, route: route)
            } label: {
                Text("Bắt đầu — rồi khoá máy bỏ túi")
                    .bold()
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func startNavigation(to place: Place, route: Route) {
        let key = apiKey
        let dest = place.coordinate
        engine.reroute = { here in
            try? await GoogleAPI(apiKey: key).computeRoute(from: here, to: dest)
        }
        engine.start(route: route)
    }

    // MARK: - API key

    private var keySection: some View {
        Section {
            SecureField("Dán Google API key vào đây", text: $apiKey)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        } header: {
            Text("Cài đặt")
        } footer: {
            Text(apiKey.isEmpty
                 ? "Cần API key của Google Maps Platform (bật Places API (New) và Routes API). Key lưu trên máy, chỉ gửi tới Google."
                 : "Đã có key (\(apiKey.count) ký tự). Quyền thông báo: \(notifier.authStatus).")
        }
    }

    // MARK: - Nhật ký

    private var logSection: some View {
        Section("Nhật ký") {
            if engine.log.isEmpty {
                Text("chưa có gì").foregroundStyle(.secondary)
            }
            ForEach(engine.log, id: \.self) { line in
                Text(line).font(.system(.caption2, design: .monospaced))
            }
        }
    }
}

#Preview {
    ContentView()
}

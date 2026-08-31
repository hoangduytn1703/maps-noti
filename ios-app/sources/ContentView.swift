import CoreLocation
import SwiftUI

struct ContentView: View {
    @StateObject private var engine = NavigationEngine()
    @StateObject private var notifier = Notifier()

    @State private var query = ""
    @State private var results: [Place] = []
    @State private var selected: Place?
    @State private var route: Route?
    @State private var busy = false
    @State private var errorText: String?

    private let api = AppleAPI()

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
        Section {
            HStack {
                TextField("Tên địa điểm…", text: $query)
                    .onSubmit(search)
                Button("Tìm", action: search)
                    .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || busy)
            }
            if busy {
                HStack { ProgressView(); Text("Đang tìm…").foregroundStyle(.secondary) }
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
        } header: {
            Text("Đi đâu?")
        } footer: {
            Text("Quyền thông báo: \(notifier.authStatus) · GPS: \(engine.lastLocation == nil ? "đang bắt…" : "sẵn sàng")")
        }
    }

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
        let dest = place.coordinate
        engine.reroute = { [api] here in
            try? await api.computeRoute(from: here, to: dest)
        }
        engine.start(route: route)
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

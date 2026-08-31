import SwiftUI

struct ContentView: View {
    @StateObject private var notifier = Notifier()

    var body: some View {
        NavigationStack {
            List {
                Section("Quyền thông báo") {
                    HStack {
                        Text("Trạng thái")
                        Spacer()
                        Text(notifier.authStatus).foregroundStyle(.secondary)
                    }
                    Button("Xin quyền thông báo") {
                        notifier.requestPermission()
                    }
                }

                Section {
                    Button("Bắn ngay 1 cái") {
                        notifier.fire(title: "↰ Rẽ trái", body: "150 m · Lê Lợi")
                    }
                    Button("Hẹn 30 giây — bấm rồi khoá máy bỏ túi") {
                        notifier.fire(title: "↱ Rẽ phải",
                                      body: "200 m · Nguyễn Thị Minh Khai",
                                      after: 30)
                    }
                } header: {
                    Text("Test cơ bản")
                } footer: {
                    Text("Cái quan trọng là nút hẹn 30 giây: nhiều đồng hồ BLE không hiện noti khi màn hình iPhone đang bật.")
                }

                Section("Hiển thị trên màn GT4") {
                    Button("Có dấu + mũi tên") {
                        notifier.fire(title: "↰ Rẽ trái",
                                      body: "150 m · Nguyễn Đình Chiểu", after: 15)
                    }
                    Button("Không dấu, không icon") {
                        notifier.fire(title: "Re trai",
                                      body: "150m - Nguyen Dinh Chieu", after: 20)
                    }
                    Button("Chuỗi dài (xem bị cắt ở đâu)") {
                        notifier.fire(title: "↰ Rẽ trái rồi đi thẳng 400 m",
                                      body: "Rẽ trái vào Cách Mạng Tháng Tám, đi thẳng 400 m rồi rẽ phải vào hẻm 123",
                                      after: 25)
                    }
                }

                Section {
                    Button("5 lệnh rẽ cách nhau 20s") {
                        notifier.fireTurnSequence()
                    }
                    Button("Xoá hàng chờ", role: .destructive) {
                        notifier.clearPending()
                    }
                } header: {
                    Text("Nhịp giống chỉ đường thật")
                } footer: {
                    Text("Bắt đầu sau 20 giây. Xem đồng hồ có rung đủ 5 lần hay bị gộp lại.")
                }

                Section("Nhật ký") {
                    if notifier.log.isEmpty {
                        Text("chưa có gì").foregroundStyle(.secondary)
                    }
                    ForEach(notifier.log, id: \.self) { line in
                        Text(line).font(.system(.caption, design: .monospaced))
                    }
                }
            }
            .navigationTitle("Noti Smoke Test")
        }
        .task { await notifier.refreshStatus() }
    }
}

#Preview {
    ContentView()
}

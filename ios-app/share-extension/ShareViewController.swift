import UIKit
import UniformTypeIdentifiers

/// Share Extension: nhận link từ bảng Chia sẻ của Google Maps rồi chuyển cho
/// app chính MapsNoti.
///
/// Kế hoạch A: nhờ hệ thống mở app chính qua `mapsnoti://` — thử API chính
/// thức trước, rồi tới trò responder chain (hack cũ, iOS mới hay chặn).
/// Kế hoạch B (luôn chạy): chép link vào clipboard. App chính mỗi lần mở lên
/// sẽ tự phát hiện clipboard có link và mời bấm một nút để đi.
final class ShareViewController: UIViewController {

    private var handled = false
    private let statusLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        statusLabel.text = "Đang chuyển sang MapsNoti…"
        statusLabel.font = .preferredFont(forTextStyle: .headline)
        statusLabel.textColor = .secondaryLabel
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
        ])
    }

    // Chạy từ viewDidAppear — lúc viewDidLoad view chưa gắn vào window,
    // responder chain cụt.
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !handled else { return }
        handled = true
        readInput()
    }

    // MARK: - Đọc thứ được chia sẻ sang

    private func readInput() {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem])?
            .compactMap(\.attachments)
            .flatMap { $0 } ?? []

        if let p = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) }) {
            p.loadItem(forTypeIdentifier: UTType.url.identifier) { [weak self] item, _ in
                self?.finish(with: (item as? URL)?.absoluteString ?? (item as? String))
            }
            return
        }
        if let p = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) }) {
            p.loadItem(forTypeIdentifier: UTType.plainText.identifier) { [weak self] item, _ in
                self?.finish(with: item as? String)
            }
            return
        }
        finish(with: nil)
    }

    // MARK: - Chuyển giao

    private func finish(with text: String?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard let text, !text.isEmpty else {
                self.close()
                return
            }

            // Kế hoạch B — làm TRƯỚC cho chắc: link luôn nằm sẵn trong
            // clipboard, app chính mở lên là tự thấy.
            UIPasteboard.general.string = text

            guard let encoded = text.addingPercentEncoding(withAllowedCharacters: .alphanumerics),
                  let url = URL(string: "mapsnoti://route?link=\(encoded)") else {
                self.close()
                return
            }

            // Kế hoạch A: nhờ mở app chính.
            self.openHostApp(url) { opened in
                DispatchQueue.main.async {
                    if opened {
                        self.close(after: 0.3)
                    } else {
                        // Không mở hộ được — nói thật cho người dùng biết bước tiếp.
                        self.statusLabel.textColor = .label
                        self.statusLabel.text = "✓ Đã nhận link\nMở MapsNoti và bấm nút Dán màu xanh"
                        self.close(after: 1.6)
                    }
                }
            }
        }
    }

    private func close(after delay: TimeInterval = 0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }

    // MARK: - Các đường mở app chính, từ đàng hoàng tới lách

    private func openHostApp(_ url: URL, completion: @escaping (Bool) -> Void) {
        // Đường 1: API chính thức. Tài liệu nói chỉ dành cho widget,
        // nhưng nhiều bản iOS vẫn cho share extension dùng — thử trước.
        if let ctx = extensionContext {
            ctx.open(url) { [weak self] success in
                if success {
                    completion(true)
                } else {
                    DispatchQueue.main.async {
                        completion(self?.responderChainOpen(url) ?? false)
                    }
                }
            }
            return
        }
        completion(responderChainOpen(url))
    }

    /// Đường 2: hack cổ điển — lần responder chain tìm ai đó chịu "openURL:".
    /// iOS mới có thể đã bịt; trả false thì rơi về kế hoạch B.
    private func responderChainOpen(_ url: URL) -> Bool {
        let selector = sel_registerName("openURL:")
        var responder: UIResponder? = self
        while let current = responder {
            if current is UIApplication || (current !== self && current.responds(to: selector)) {
                if current.responds(to: selector) {
                    current.perform(selector, with: url)
                    return true
                }
            }
            responder = current.next
        }
        return false
    }
}

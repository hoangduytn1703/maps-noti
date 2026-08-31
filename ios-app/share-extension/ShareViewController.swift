import UIKit
import UniformTypeIdentifiers

/// Share Extension: nhận link từ bảng Chia sẻ của Google Maps (hoặc app bất kỳ),
/// rồi mở thẳng MapsNoti kèm link đó qua custom URL scheme `mapsnoti://`.
///
/// Hai cái bẫy đã dính và cách né:
/// - Phải chạy từ viewDidAppear, KHÔNG phải viewDidLoad: lúc viewDidLoad view
///   chưa gắn vào window, responder chain cụt, không lần ra UIApplication
///   để nhờ mở app → bấm icon xong im re.
/// - Phải chờ một nhịp rồi mới completeRequest, không thì extension bị đóng
///   trước khi lệnh mở app kịp đi.
final class ShareViewController: UIViewController {

    private var handled = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
    }

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

        // Ưu tiên URL; không có thì lấy text (một số app chia sẻ link dạng chữ).
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

    // MARK: - Chuyển sang app chính

    private func finish(with text: String?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard let text, !text.isEmpty,
                  let encoded = text.addingPercentEncoding(withAllowedCharacters: .alphanumerics),
                  let url = URL(string: "mapsnoti://route?link=\(encoded)") else {
                self.close()
                return
            }
            self.openHostApp(url)
            // Cho lệnh mở app một nhịp để đi, rồi mới đóng extension.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.close()
            }
        }
    }

    private func close() {
        extensionContext?.completeRequest(returningItems: nil)
    }

    /// Extension không được gọi thẳng `UIApplication.shared.open`. Cách đi vòng
    /// quen thuộc: lần responder chain tới UIApplication rồi nhờ nó "openURL:".
    private func openHostApp(_ url: URL) {
        let selector = sel_registerName("openURL:")
        var responder: UIResponder? = self

        // Vòng 1: tìm đích danh UIApplication.
        while let current = responder {
            if current is UIApplication, current.responds(to: selector) {
                current.perform(selector, with: url)
                return
            }
            responder = current.next
        }

        // Vòng 2: bất kỳ ai trong chain chịu trả lời openURL: cũng được.
        responder = self
        while let current = responder {
            if current !== self, current.responds(to: selector) {
                current.perform(selector, with: url)
                return
            }
            responder = current.next
        }
    }
}

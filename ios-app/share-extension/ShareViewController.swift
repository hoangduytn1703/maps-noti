import UIKit
import UniformTypeIdentifiers

/// Share Extension: nhận link từ bảng Chia sẻ của Google Maps (hoặc app bất kỳ),
/// rồi mở thẳng MapsNoti kèm link đó. Không có giao diện — nhận xong là chuyển
/// app ngay, người dùng không phải bấm thêm gì.
///
/// Không dùng App Group (tài khoản Apple miễn phí không được cấp), mà truyền
/// dữ liệu qua custom URL scheme `mapsnoti://`.
final class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
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
            if let text, !text.isEmpty,
               let encoded = text.addingPercentEncoding(withAllowedCharacters: .alphanumerics),
               let url = URL(string: "mapsnoti://route?link=\(encoded)") {
                self.openHostApp(url)
            }
            self.extensionContext?.completeRequest(returningItems: nil)
        }
    }

    /// Extension không được gọi thẳng `UIApplication.shared.open`. Cách đi vòng
    /// quen thuộc: lần theo responder chain tìm đối tượng nào chịu mở URL.
    private func openHostApp(_ url: URL) {
        let selector = sel_registerName("openURL:")
        var responder: UIResponder? = self
        while let current = responder {
            if current !== self, current.responds(to: selector) {
                current.perform(selector, with: url)
                return
            }
            responder = current.next
        }
    }
}

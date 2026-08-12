import MobileCoreServices
import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        captureSharedLink()
    }

    private func captureSharedLink() {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachments = item.attachments,
              let provider = attachments.first(where: supportsLink) else {
            complete()
            return
        }

        let title = item.attributedTitle?.string ?? item.attributedContentText?.string
        let typeIdentifier = preferredTypeIdentifier(for: provider)
        provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { [weak self] item, _ in
            guard let self else { return }

            let url: URL?
            if let sharedURL = item as? URL {
                url = sharedURL
            } else if let text = item as? String {
                url = URL(string: text)
            } else {
                url = nil
            }

            if let url, url.scheme?.hasPrefix("http") == true {
                try? PendingSharedLinkStore.save(PendingSharedLink(url: url, title: title))
            }

            DispatchQueue.main.async {
                self.openContainingApp()
            }
        }
    }

    private func supportsLink(_ provider: NSItemProvider) -> Bool {
        provider.hasItemConformingToTypeIdentifier(UTType.url.identifier)
            || provider.hasItemConformingToTypeIdentifier(kUTTypeURL as String)
            || provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
            || provider.hasItemConformingToTypeIdentifier(UTType.text.identifier)
    }

    private func preferredTypeIdentifier(for provider: NSItemProvider) -> String {
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            return UTType.url.identifier
        }
        if provider.hasItemConformingToTypeIdentifier(kUTTypeURL as String) {
            return kUTTypeURL as String
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            return UTType.plainText.identifier
        }
        return UTType.text.identifier
    }

    private func openContainingApp() {
        extensionContext?.open(SharedImportConfiguration.callbackURL) { [weak self] _ in
            self?.complete()
        }
    }

    private func complete() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}

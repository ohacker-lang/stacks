import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private var sharedProviders: [NSItemProvider] = []
    private var didResolvePagePreview = false
    private var didPresentDestinationPicker = false
    private var didQueueLink = false
    private var activeProviderRequest: UUID?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        captureSharedLink()
    }

    private func captureSharedLink() {
        let items = (extensionContext?.inputItems ?? []).compactMap { $0 as? NSExtensionItem }
        let attachments = items.flatMap { $0.attachments ?? [] }
        let providers = attachments.filter(supportsLink)
        let pageProvider = attachments.first { $0.hasItemConformingToTypeIdentifier(UTType.propertyList.identifier) }
        guard !providers.isEmpty || pageProvider != nil else {
            showUnsupportedShare()
            return
        }

        let title = items.first?.attributedTitle?.string ?? items.first?.attributedContentText?.string
        sharedProviders = providers
        guard let pageProvider else {
            loadSharedURL(at: 0, title: title, pagePreview: nil)
            return
        }

        // Safari can supply metadata from the page the person actually has
        // open, even when Grailed or another shop rejects server-side fetches.
        // A short deadline keeps the share sheet responsive for other apps.
        pageProvider.loadItem(forTypeIdentifier: UTType.propertyList.identifier, options: nil) { item, _ in
            let dictionary = Self.propertyListDictionary(from: item)
            let results = dictionary?[NSExtensionJavaScriptPreprocessingResultsKey] as? [String: Any]
            let preview = (results ?? dictionary).flatMap(SharedPagePreview.init(dictionary:))
            DispatchQueue.main.async { [weak self] in
                self?.continueCapture(title: title, pagePreview: preview)
            }
        }
        // Safari's page is the only source of the link when it is the sole
        // attachment, so wait longer for it than when a plain URL is also shared.
        let deadline: TimeInterval = providers.isEmpty ? 6 : 1.5
        DispatchQueue.main.asyncAfter(deadline: .now() + deadline) { [weak self] in
            self?.continueCapture(title: title, pagePreview: nil)
        }
    }

    private func continueCapture(title: String?, pagePreview: SharedPagePreview?) {
        guard !didResolvePagePreview else { return }
        didResolvePagePreview = true
        if sharedProviders.isEmpty, let url = pagePreview?.pageURL {
            presentDestinationPicker(for: url, title: title, pagePreview: pagePreview)
        } else {
            loadSharedURL(at: 0, title: title, pagePreview: pagePreview)
        }
    }

    private func loadSharedURL(at index: Int, title: String?, pagePreview: SharedPagePreview?) {
        guard !didPresentDestinationPicker else { return }
        guard sharedProviders.indices.contains(index) else {
            if let url = pagePreview?.pageURL {
                presentDestinationPicker(for: url, title: title, pagePreview: pagePreview)
            } else {
                showUnsupportedShare()
            }
            return
        }
        let provider = sharedProviders[index]
        let typeIdentifier = preferredTypeIdentifier(for: provider)
        let requestID = UUID()
        activeProviderRequest = requestID
        provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { [weak self] item, _ in
            guard let self else { return }
            let url = Self.sharedURL(from: item)
            DispatchQueue.main.async {
                guard self.activeProviderRequest == requestID else { return }
                self.activeProviderRequest = nil
                guard let url, ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
                    self.loadSharedURL(at: index + 1, title: title, pagePreview: pagePreview)
                    return
                }
                self.presentDestinationPicker(for: url, title: title, pagePreview: pagePreview)
            }
        }
        // Some host apps never call the item-provider completion handler. Do
        // not strand the person in a blank extension when that happens.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, self.activeProviderRequest == requestID else { return }
            self.activeProviderRequest = nil
            self.loadSharedURL(at: index + 1, title: title, pagePreview: pagePreview)
        }
    }

    // Safari delivers the page results either as a dictionary or as archived
    // property-list data, depending on the OS version.
    nonisolated private static func propertyListDictionary(from item: NSSecureCoding?) -> [String: Any]? {
        if let dictionary = item as? [String: Any] { return dictionary }
        guard let data = item as? Data else { return nil }
        if let archived = try? NSKeyedUnarchiver.unarchivedObject(
            ofClasses: [NSDictionary.self, NSString.self, NSNumber.self, NSArray.self, NSNull.self],
            from: data
        ) as? [String: Any] {
            return archived
        }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
    }

    nonisolated private static func sharedURL(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL { return url }
        let text: String?
        if let string = item as? String {
            text = string
        } else if let attributed = item as? NSAttributedString {
            text = attributed.string
        } else if let data = item as? Data {
            text = String(data: data, encoding: .utf8)
        } else {
            text = nil
        }
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            return url
        }
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        return detector.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap(\.url)
            .first { ["http", "https"].contains($0.scheme?.lowercased() ?? "") }
    }

    private func presentDestinationPicker(for url: URL, title: String?, pagePreview: SharedPagePreview?) {
        guard !didPresentDestinationPicker else { return }
        didPresentDestinationPicker = true
        let destinations = SharedStackDestinationStore.load()
        let canAccessSharedStacks = SharedStackDestinationStore.isAvailable
        preferredContentSize = CGSize(
            width: 0,
            height: canAccessSharedStacks
                ? CGFloat(min(620, max(310, 245 + destinations.count * 80)))
                : 310
        )
        let picker = ShareDestinationPickerViewController(
            destinations: destinations,
            canAccessSharedStacks: canAccessSharedStacks
        ) { [weak self] selection in
            guard let self else { return }
            switch selection {
            case .existing(let destination):
                self.queue(url: url, title: title, pagePreview: pagePreview, destination: destination)
            case .newStack(let stackTitle):
                self.queue(url: url, title: title, pagePreview: pagePreview, newStackTitle: stackTitle)
            case .copyLink:
                UIPasteboard.general.url = url
                self.showCopiedLinkConfirmation()
            case .cancel:
                self.complete()
            }
        }

        // A share extension is already hosted in a system sheet. Embed the
        // picker directly so UIKit does not create a second blank sheet behind it.
        addChild(picker)
        picker.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(picker.view)
        NSLayoutConstraint.activate([
            picker.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            picker.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            picker.view.topAnchor.constraint(equalTo: view.topAnchor),
            picker.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        picker.didMove(toParent: self)
    }

    private func queue(url: URL, title: String?, pagePreview: SharedPagePreview?, destination: SharedStackDestination) {
        guard !didQueueLink else { return }
        didQueueLink = true
        do {
            try PendingSharedLinkStore.save(
                PendingSharedLink(
                    url: url,
                    title: title,
                    pagePreview: pagePreview,
                    destinationStackID: destination.id,
                    destinationStackTitle: destination.title
                )
            )
            showQueuedConfirmation(for: destination.title)
        } catch {
            didQueueLink = false
            showSaveError(error)
        }
    }

    private func queue(url: URL, title: String?, pagePreview: SharedPagePreview?, newStackTitle: String) {
        guard !didQueueLink else { return }
        didQueueLink = true
        do {
            try PendingSharedLinkStore.save(
                PendingSharedLink(
                    url: url,
                    title: title,
                    pagePreview: pagePreview,
                    destinationStackTitle: newStackTitle,
                    newStackTitle: newStackTitle
                )
            )
            showQueuedConfirmation(for: newStackTitle)
        } catch {
            didQueueLink = false
            showSaveError(error)
        }
    }

    private func showQueuedConfirmation(for stackTitle: String) {
        children.compactMap { $0 as? ShareDestinationPickerViewController }.first?
            .showQueuedConfirmation(for: stackTitle)
    }

    private func showCopiedLinkConfirmation() {
        children.compactMap { $0 as? ShareDestinationPickerViewController }.first?
            .showCopiedLinkConfirmation()
    }

    private func showSaveError(_ error: Error) {
        let alert = UIAlertController(
            title: "Couldn’t save link",
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func supportsLink(_ provider: NSItemProvider) -> Bool {
        provider.hasItemConformingToTypeIdentifier(UTType.url.identifier)
            || provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
            || provider.hasItemConformingToTypeIdentifier(UTType.text.identifier)
    }

    private func preferredTypeIdentifier(for provider: NSItemProvider) -> String {
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            return UTType.url.identifier
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            return UTType.plainText.identifier
        }
        return UTType.text.identifier
    }

    private func complete() {
        extensionContext?.completeRequest(returningItems: nil)
    }

    private func showUnsupportedShare() {
        guard !didPresentDestinationPicker else { return }
        didPresentDestinationPicker = true
        preferredContentSize = CGSize(width: 0, height: 230)
        let message = UILabel()
        message.text = "This share didn’t include a product link. Copy the link and use Paste Link in Stacks."
        message.font = .systemFont(ofSize: 16)
        message.textColor = .secondaryLabel
        message.textAlignment = .center
        message.numberOfLines = 0
        let done = UIButton(type: .system)
        done.setTitle("Done", for: .normal)
        done.addTarget(self, action: #selector(closeUnsupportedShare), for: .touchUpInside)
        let content = UIStackView(arrangedSubviews: [message, done])
        content.axis = .vertical
        content.spacing = 18
        content.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor, constant: 12),
            content.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor, constant: -12),
            content.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    @objc private func closeUnsupportedShare() { complete() }
}

private enum ShareDestinationSelection {
    case existing(SharedStackDestination)
    case newStack(String)
    case copyLink
    case cancel
}

private final class ShareDestinationPickerViewController: UIViewController {
    private let destinations: [SharedStackDestination]
    private let canAccessSharedStacks: Bool
    private let onSelection: (ShareDestinationSelection) -> Void
    private let list = UIStackView()
    private let root = UIStackView()
    private let newStackForm = UIStackView()
    private let newStackField = UITextField()
    private let queueNewStackButton = UIButton(type: .system)

    init(
        destinations: [SharedStackDestination],
        canAccessSharedStacks: Bool,
        onSelection: @escaping (ShareDestinationSelection) -> Void
    ) {
        self.destinations = destinations
        self.canAccessSharedStacks = canAccessSharedStacks
        self.onSelection = onSelection
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let header = UILabel()
        header.text = "Save to Stacks"
        header.font = .systemFont(ofSize: 22, weight: .semibold)
        header.textColor = .label

        let hint = UILabel()
        hint.text = canAccessSharedStacks
            ? "Choose where to save it. Stacks will finish the import when you open the app."
            : "This build can’t read your Stacks in the share sheet. Copy the link, then paste it in Stacks."
        hint.font = .systemFont(ofSize: 14)
        hint.textColor = .secondaryLabel
        hint.numberOfLines = 2

        let close = UIButton(type: .system)
        close.setImage(UIImage(systemName: "xmark"), for: .normal)
        close.tintColor = .secondaryLabel
        close.backgroundColor = .secondarySystemBackground
        close.layer.cornerRadius = 17
        close.addTarget(self, action: #selector(cancel), for: .touchUpInside)

        let headerRow = UIStackView(arrangedSubviews: [header, UIView(), close])
        headerRow.alignment = .center
        headerRow.spacing = 12
        close.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            close.widthAnchor.constraint(equalToConstant: 34),
            close.heightAnchor.constraint(equalToConstant: 34)
        ])

        list.axis = .vertical
        list.spacing = 10

        let createButton = UIButton(type: .system)
        var createConfiguration = UIButton.Configuration.filled()
        createConfiguration.title = canAccessSharedStacks ? "Create a new Stack" : "Copy link for Stacks"
        createConfiguration.image = UIImage(systemName: canAccessSharedStacks ? "plus" : "link")
        createConfiguration.imagePadding = 8
        createConfiguration.cornerStyle = .capsule
        createConfiguration.baseBackgroundColor = .label
        createConfiguration.baseForegroundColor = .systemBackground
        createConfiguration.contentInsets = .init(top: 12, leading: 18, bottom: 12, trailing: 18)
        createButton.configuration = createConfiguration
        createButton.contentHorizontalAlignment = .center
        createButton.addTarget(
            self,
            action: canAccessSharedStacks ? #selector(showNewStackForm) : #selector(copyLink),
            for: .touchUpInside
        )
        createButton.heightAnchor.constraint(equalToConstant: 48).isActive = true

        newStackField.placeholder = "Name your new Stack"
        newStackField.font = .systemFont(ofSize: 16)
        newStackField.autocapitalizationType = .words
        newStackField.returnKeyType = .done
        newStackField.backgroundColor = .secondarySystemBackground
        newStackField.layer.cornerRadius = 14
        newStackField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 14, height: 1))
        newStackField.leftViewMode = .always
        newStackField.addTarget(self, action: #selector(newStackTitleChanged), for: .editingChanged)
        newStackField.addTarget(self, action: #selector(queueNewStack), for: .editingDidEndOnExit)
        newStackField.heightAnchor.constraint(equalToConstant: 48).isActive = true

        queueNewStackButton.setTitle("Create", for: .normal)
        queueNewStackButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        queueNewStackButton.isEnabled = false
        queueNewStackButton.addTarget(self, action: #selector(queueNewStack), for: .touchUpInside)
        queueNewStackButton.widthAnchor.constraint(equalToConstant: 70).isActive = true

        newStackForm.axis = .horizontal
        newStackForm.spacing = 8
        newStackForm.addArrangedSubview(newStackField)
        newStackForm.addArrangedSubview(queueNewStackButton)
        newStackForm.isHidden = true

        let scrollView = UIScrollView()
        scrollView.alwaysBounceVertical = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.addSubview(list)
        list.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            list.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            list.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            list.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            list.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])

        root.axis = .vertical
        root.spacing = 12
        [headerRow, hint, scrollView, divider(), createButton, newStackForm].forEach(root.addArrangedSubview)
        root.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor, constant: 8),
            root.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor, constant: -8),
            root.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 18),
            root.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -16)
        ])

        if destinations.isEmpty {
            let empty = UILabel()
            empty.text = canAccessSharedStacks
                ? "No Stacks synced yet. Open Stacks once to refresh, or create a new one below."
                : "Your owned Stacks are still in the app. This build cannot display them here."
            empty.font = .systemFont(ofSize: 16, weight: .regular)
            empty.textColor = .secondaryLabel
            empty.numberOfLines = 2
            list.addArrangedSubview(empty)
        } else {
            destinations.forEach { list.addArrangedSubview(destinationRow(for: $0)) }
        }
    }

    private func destinationRow(for destination: SharedStackDestination) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.contentInsets = .init(top: 8, leading: 0, bottom: 8, trailing: 0)
        let button = UIButton(configuration: configuration)
        button.contentHorizontalAlignment = .leading
        button.accessibilityLabel = "Add to \(destination.title)"
        button.backgroundColor = .secondarySystemBackground
        button.layer.cornerRadius = 16
        button.addAction(UIAction { [weak self] _ in self?.onSelection(.existing(destination)) }, for: .touchUpInside)

        let avatar = AvatarImageView(
            data: destination.avatarData,
            url: destination.avatarURL,
            name: destination.ownerName
        )
        let title = UILabel()
        title.text = destination.title
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        title.textColor = .label
        title.numberOfLines = 2
        title.lineBreakMode = .byWordWrapping
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let updated = UILabel()
        updated.text = Self.lastUpdatedText(destination.updatedAt)
        updated.font = .systemFont(ofSize: 14, weight: .regular)
        updated.textColor = .secondaryLabel
        let text = UIStackView(arrangedSubviews: [title, updated])
        text.axis = .vertical
        text.spacing = 2
        let arrow = UIImageView(image: UIImage(systemName: "chevron.right"))
        arrow.tintColor = .tertiaryLabel
        arrow.setContentHuggingPriority(.required, for: .horizontal)
        let row = UIStackView(arrangedSubviews: [avatar, text, arrow])
        row.alignment = .center
        row.spacing = 12
        row.isUserInteractionEnabled = false
        row.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -14),
            row.topAnchor.constraint(equalTo: button.topAnchor, constant: 10),
            row.bottomAnchor.constraint(equalTo: button.bottomAnchor, constant: -10),
            avatar.widthAnchor.constraint(equalToConstant: 44),
            avatar.heightAnchor.constraint(equalToConstant: 44),
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 70)
        ])
        return button
    }

    private static func lastUpdatedText(_ date: Date?) -> String {
        guard let date else { return "Recently updated" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return "Updated \(formatter.localizedString(for: date, relativeTo: Date()))"
    }

    private func divider() -> UIView {
        let divider = UIView()
        divider.backgroundColor = .separator
        divider.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale).isActive = true
        return divider
    }

    @objc private func showNewStackForm() {
        newStackForm.isHidden = false
        newStackField.becomeFirstResponder()
    }

    @objc private func copyLink() { onSelection(.copyLink) }

    @objc private func newStackTitleChanged() {
        queueNewStackButton.isEnabled = !(newStackField.text ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @objc private func queueNewStack() {
        let title = (newStackField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        onSelection(.newStack(title))
    }

    func showQueuedConfirmation(for stackTitle: String) {
        showConfirmation(
            titleText: "Saved for \(stackTitle)",
            detailText: "Open Stacks to finish adding this link."
        )
    }

    func showCopiedLinkConfirmation() {
        showConfirmation(
            titleText: "Link copied",
            detailText: "Open Stacks, choose Paste Link, and pick your Stack there."
        )
    }

    private func showConfirmation(titleText: String, detailText: String) {
        view.endEditing(true)
        parent?.preferredContentSize = CGSize(width: 0, height: 265)
        root.arrangedSubviews.forEach { $0.isHidden = true }

        let symbol = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))
        symbol.tintColor = .label
        symbol.contentMode = .scaleAspectFit
        symbol.heightAnchor.constraint(equalToConstant: 46).isActive = true

        let title = UILabel()
        title.text = titleText
        title.font = .systemFont(ofSize: 21, weight: .semibold)
        title.textAlignment = .center
        title.numberOfLines = 2

        let detail = UILabel()
        detail.text = detailText
        detail.font = .systemFont(ofSize: 15)
        detail.textColor = .secondaryLabel
        detail.textAlignment = .center
        detail.numberOfLines = 2

        let done = UIButton(type: .system)
        var configuration = UIButton.Configuration.filled()
        configuration.title = "Done"
        configuration.cornerStyle = .capsule
        configuration.baseBackgroundColor = .label
        configuration.baseForegroundColor = .systemBackground
        done.configuration = configuration
        done.heightAnchor.constraint(equalToConstant: 48).isActive = true
        done.addTarget(self, action: #selector(cancel), for: .touchUpInside)

        [symbol, title, detail, done].forEach(root.addArrangedSubview)
        root.setCustomSpacing(18, after: detail)
    }

    @objc private func cancel() { onSelection(.cancel) }
}

private final class AvatarImageView: UIImageView {
    init(data: Data?, url: URL?, name: String) {
        super.init(frame: .zero)
        contentMode = .scaleAspectFill
        clipsToBounds = true
        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 22
        image = data.flatMap(UIImage.init(data:)) ?? Self.initialsImage(for: name)
        guard data == nil else { return }
        guard let url else { return }
        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        request.setValue("image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            guard let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode) else { return }
            guard let image = data.flatMap(UIImage.init(data:)) else { return }
            DispatchQueue.main.async { self?.image = image }
        }.resume()
    }

    required init?(coder: NSCoder) { nil }

    private static func initialsImage(for name: String) -> UIImage? {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 44, height: 44))
        return renderer.image { context in
            UIColor.systemGray5.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 44, height: 44))
            let initials = name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 15, weight: .semibold),
                .foregroundColor: UIColor.secondaryLabel
            ]
            let size = (initials as NSString).size(withAttributes: attributes)
            (initials as NSString).draw(
                at: CGPoint(x: (44 - size.width) / 2, y: (44 - size.height) / 2),
                withAttributes: attributes
            )
        }
    }
}

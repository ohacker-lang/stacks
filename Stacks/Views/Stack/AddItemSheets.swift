import PhotosUI
import SwiftUI
import UIKit

struct AddItemOptionsSheet: View {
    let onSelect: (AddItemSource) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Add item to Stack") {
                    Button {
                        onSelect(.search)
                    } label: {
                        Label("Search", systemImage: "magnifyingglass")
                    }

                    Button {
                        onSelect(.pastedLink)
                    } label: {
                        Label("Paste Link", systemImage: "link")
                    }

                    Button {
                        onSelect(.camera)
                    } label: {
                        Label("Take Picture", systemImage: "camera")
                    }

                    Button {
                        onSelect(.photoLibrary)
                    } label: {
                        Label("Camera Roll", systemImage: "photo.on.rectangle")
                    }
                }
            }
            .navigationTitle("Add Item")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct SearchAddItemSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appServices) private var services
    @State private var viewModel = AddItemViewModel()

    let onSelect: (ProductSearchResult) -> Void

    var body: some View {
        NavigationStack {
            List {
                if viewModel.isLoading {
                    Section {
                        ProgressView("Searching")
                    }
                }

                Section {
                    ForEach(viewModel.results) { result in
                        Button {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                onSelect(result)
                            }
                        } label: {
                            HStack(spacing: 14) {
                                ProductResultThumbnail(result: result)

                                VStack(alignment: .leading, spacing: 5) {
                                    Text(result.title)
                                        .font(.headline)
                                    Text("\(result.brand) • \(formattedPrice(result.price))")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $viewModel.query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search products")
            .onSubmit(of: .search) {
                Task { await viewModel.search(services: services) }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .overlay {
                if viewModel.results.isEmpty && !viewModel.isLoading {
                    ContentUnavailableView("Search products", systemImage: "magnifyingglass", description: Text("Find a product, then add it to the canvas."))
                }
            }
        }
    }

    private func formattedPrice(_ price: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: price as NSDecimalNumber) ?? "$\(price)"
    }
}

private struct ProductResultThumbnail: View {
    let result: ProductSearchResult

    var body: some View {
        AsyncImage(url: result.imageURL ?? DemoProductImageCatalog.url(for: result.title)) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFit()
            case .empty:
                ProgressView()
                    .tint(Color.stacksInk)
            default:
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Color.stacksInk.opacity(0.7))
            }
        }
        .frame(width: 52, height: 52)
        .padding(6)
        .background(Color.stacksCream, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private enum ProductImportDestination: String, CaseIterable, Identifiable {
    case current
    case existing
    case new

    var id: String { rawValue }

    var title: String {
        switch self {
        case .current: "This Stack"
        case .existing: "Another Stack"
        case .new: "New Stack"
        }
    }
}

private struct MinimalLinkPasteStage: View {
    @Binding var link: String
    let isLoading: Bool
    let onSubmit: () -> Void
    let onCancel: () -> Void

    @FocusState private var isFocused: Bool

    private var hasLink: Bool {
        !link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.stacksInk.opacity(0.18))
                .frame(width: 38, height: 5)
                .padding(.top, 10)

            HStack {
                Button("Cancel", action: onCancel)
                    .font(.stacksText(size: 16, weight: .regular))
                    .foregroundStyle(Color.stacksMutedInk)

                Spacer()
            }
            .padding(.horizontal, 28)
            .padding(.top, 16)

            Spacer(minLength: 20)

            VStack(spacing: 12) {
                Image(systemName: "link")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(Color.stacksInk)

                Text("Paste your link here")
                    .font(.stacksText(size: 31, weight: .semibold))
                    .tracking(-0.9)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.stacksInk)

                Text("We’ll pull in the product image and the details we can find.")
                    .font(.stacksText(size: 16, weight: .regular))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.stacksMutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 34)

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "link")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(Color.stacksMutedInk)

                    TextField("Paste product link", text: $link)
                        .font(.stacksText(size: 16, weight: .regular))
                        .foregroundStyle(Color.stacksInk)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .submitLabel(.go)
                        .focused($isFocused)
                        .disabled(isLoading)
                        .onSubmit(onSubmit)
                }
                .padding(.horizontal, 17)
                .frame(height: 56)

                Divider().padding(.leading, 48)

                Button(action: onSubmit) {
                    HStack(spacing: 9) {
                        if isLoading {
                            ProgressView().tint(Color.stacksInk)
                        } else {
                            Image(systemName: "arrow.right")
                        }
                        Text(isLoading ? "Finding product" : "Find product")
                    }
                    .font(.stacksText(size: 16, weight: .semibold))
                    .foregroundStyle(hasLink ? Color.stacksInk : Color.stacksMutedInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 17)
                    .frame(height: 56)
                }
                .buttonStyle(.plain)
                .disabled(!hasLink || isLoading)
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.72), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.08), radius: 22, y: 10)
            .padding(.horizontal, 24)
            .padding(.top, 30)

            if isLoading {
                Text("Finding the best product image")
                    .font(.stacksText(size: 14, weight: .regular))
                    .foregroundStyle(Color.stacksMutedInk)
                    .padding(.top, 12)
            }

            Spacer(minLength: 28)
        }
        .background(.thinMaterial)
        .task {
            isFocused = true
        }
        .onChange(of: isLoading) { _, loading in
            if loading { isFocused = false }
        }
    }
}

enum PhotoProductImportStartingSource {
    case editor
    case camera
    case photoLibrary
}

struct ProductLinkImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appServices) private var services
    @State private var link: String
    @State private var buyLink = ""
    @State private var imageLink = ""
    @State private var priceText = ""
    @State private var selectedReplacementImage: PhotosPickerItem?
    @State private var replacementImageData: Data?
    @State private var replacementImageURL: URL?
    @State private var removedBackgroundImageURL: URL?
    @State private var isRemovingBackground = false
    @State private var isPresentingRemovalMoment = false
    @State private var isResolvingRemovalMoment = false
    @State private var removalMomentStartedAt: Date?
    @State private var draft: ProductImportDraft?
    @State private var stacks: [Stack] = []
    @State private var selectedStackID: UUID?
    @State private var destination: ProductImportDestination
    @State private var newStackTitle = ""
    @State private var newStackWishlistMode = false
    @State private var isLoadingStacks = true
    @State private var isPreviewing = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var visibleDetails: Set<ProductReviewOptionalField> = [.brand, .price, .description]

    let user: UserProfile
    let preferredStack: Stack?
    let locksDestination: Bool
    let initialNewStackTitle: String?
    let initialPreview: ProductLinkPreview?
    let onSaved: (Stack) -> Void

    init(
        initialURL: URL? = nil,
        initialPreview: ProductLinkPreview? = nil,
        user: UserProfile,
        preferredStack: Stack? = nil,
        locksDestination: Bool = false,
        initialNewStackTitle: String? = nil,
        onSaved: @escaping (Stack) -> Void
    ) {
        let resolvedInitialPreview = initialPreview.map { preview in
            var resolvedPreview = preview
            if resolvedPreview.imageURL == nil {
                resolvedPreview.imageURL = DemoProductImageCatalog.url(for: resolvedPreview.title)
            }
            return resolvedPreview
        }
        self.user = user
        self.preferredStack = preferredStack
        self.locksDestination = locksDestination
        self.initialNewStackTitle = initialNewStackTitle
        self.initialPreview = resolvedInitialPreview
        self.onSaved = onSaved
        _link = State(initialValue: resolvedInitialPreview?.sourceURL.absoluteString ?? initialURL?.absoluteString ?? "")
        _buyLink = State(initialValue: resolvedInitialPreview?.sourceURL.absoluteString ?? "")
        _imageLink = State(initialValue: resolvedInitialPreview?.imageURL?.absoluteString ?? "")
        _priceText = State(initialValue: resolvedInitialPreview?.price.map { NSDecimalNumber(decimal: $0).stringValue } ?? "")
        _draft = State(initialValue: resolvedInitialPreview.map(ProductImportDraft.init))
        _destination = State(initialValue: preferredStack == nil ? (initialNewStackTitle == nil ? .existing : .new) : .current)
        _newStackTitle = State(initialValue: initialNewStackTitle ?? "")
    }

    var body: some View {
        linkEditor
            .fullScreenCover(isPresented: $isPresentingRemovalMoment) {
                ProductImportRemovalMoment(
                    originalData: replacementImageData,
                    originalURL: replacementImageURL ?? validURL(imageLink),
                    removedBackgroundURL: removedBackgroundImageURL,
                    showsCutout: isResolvingRemovalMoment
                )
                .interactiveDismissDisabled(isRemovingBackground || isResolvingRemovalMoment)
            }
    }

    private var linkEditor: some View {
        Group {
            if draft == nil {
                MinimalLinkPasteStage(
                    link: $link,
                    isLoading: isPreviewing,
                    onSubmit: previewLink,
                    onCancel: { dismiss() }
                )
            } else {
                ProductImportDetailScreen(
                    originalData: replacementImageData,
                    originalURL: replacementImageURL ?? validURL(imageLink),
                    removedBackgroundURL: removedBackgroundImageURL,
                    title: draftBinding(\.title, default: ""),
                    brand: draftBinding(\.brand, default: ""),
                    price: $priceText,
                    currencyCode: draftBinding(\.currencyCode, default: "USD"),
                    description: draftBinding(\.shortDescription, default: ""),
                    sourceLink: $link,
                    buyLink: $buyLink,
                    stackName: destinationName,
                    stackOptions: selectableStackNames,
                    onSelectStack: locksDestination ? nil : { name in
                        selectStack(named: name)
                    },
                    isSaving: isSaving,
                    canSave: isDraftValid,
                    onCancel: { dismiss() },
                    onSave: save
                )
            }
        }
        // Link paste is intentionally a focused, nearly full-height moment. The
        // importer then owns the background-removal transition before showing any
        // product fields.
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.thinMaterial)
        .task {
            await loadStacks()
            if let initialPreview, let imageURL = initialPreview.imageURL {
                await preparePreviewRemoval(for: imageURL)
            } else if validURL(link) != nil, draft == nil {
                previewLink()
            }
        }
        .task(id: selectedReplacementImage) {
            guard let selectedReplacementImage else { return }
            replacementImageData = try? await selectedReplacementImage.loadTransferable(type: Data.self)
            if let replacementImageData {
                await prepareReplacementImage(replacementImageData)
            }
        }
        .alert("Could not import product", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var productPreviewSection: some View {
        Section {
            EditorialProductPreview(
                originalData: replacementImageData,
                originalURL: replacementImageURL ?? validURL(imageLink),
                removedBackgroundURL: removedBackgroundImageURL,
                isRemoving: isRemovingBackground
            )
            .listRowInsets(.init())
            .listRowBackground(Color.white)
        }
    }

    private var productDetailsSection: some View {
        let replacementImageLabel = replacementImageData == nil ? "Use another photo" : "Replacement photo selected"
        return Section {
            VStack(spacing: 0) {
                EditorialProductField(label: "Name", placeholder: "Product name", text: draftBinding(\.title, default: ""))

                if visibleDetails.contains(.brand) {
                    EditorialProductField(label: "Brand", placeholder: "Brand or maker", text: draftBinding(\.brand, default: "")) {
                        updateDraft(\.brand, value: "")
                        visibleDetails.remove(.brand)
                    }
                }

                if visibleDetails.contains(.price) {
                    EditorialPriceField(price: $priceText, currencyCode: draftBinding(\.currencyCode, default: "USD")) {
                        priceText = ""
                        visibleDetails.remove(.price)
                    }
                }

                if visibleDetails.contains(.description) {
                    EditorialProductField(label: "Details", placeholder: "A short note about it", text: draftBinding(\.shortDescription, default: ""), multiline: true) {
                        updateDraft(\.shortDescription, value: "")
                        visibleDetails.remove(.description)
                    }
                }

                EditorialProductField(label: "Product link", placeholder: "Paste the original link", text: $link, keyboardType: .URL)
                EditorialProductField(label: "Buy link", placeholder: "Paste a checkout link", text: $buyLink, keyboardType: .URL)

                PhotosPicker(selection: $selectedReplacementImage, matching: .images) {
                    Label(replacementImageLabel, systemImage: "photo.badge.plus")
                        .font(.system(size: 15, weight: .regular, design: .default))
                        .foregroundStyle(Color.stacksMutedInk)
                        .padding(.top, 14)
                }

                Menu {
                    ForEach(ProductReviewOptionalField.allCases.filter { !visibleDetails.contains($0) }, id: \.self) { field in
                        Button("Add \(field.title)") {
                            visibleDetails.insert(field)
                        }
                    }
                } label: {
                    Label("Add a detail", systemImage: "plus")
                        .font(.system(size: 15, weight: .regular, design: .default))
                        .foregroundStyle(Color.stacksMutedInk)
                        .padding(.top, 14)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .listRowInsets(.init(top: 4, leading: 20, bottom: 14, trailing: 20))
            .listRowBackground(Color.white)
        }
    }

    private var destinationSection: some View {
        Section {
            Picker("Destination", selection: $destination) {
                ForEach(availableDestinations) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.menu)

            switch destination {
            case .current:
                if let preferredStack {
                    LabeledContent("Stack", value: preferredStack.displayTitle)
                }
            case .existing:
                if isLoadingStacks {
                    ProgressView("Loading Stacks")
                } else if stacks.isEmpty {
                    Text("No Stack yet. Choose New Stack below.")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Stack", selection: $selectedStackID) {
                        ForEach(stacks) { stack in
                            Text(stack.displayTitle).tag(Optional(stack.id))
                        }
                    }
                }
            case .new:
                TextField("New Stack title", text: $newStackTitle)
                    .textInputAutocapitalization(.words)
                    .textContentType(.name)
                Toggle("Wishlist mode", isOn: $newStackWishlistMode)
            }
        }
    }

    private var availableDestinations: [ProductImportDestination] {
        preferredStack == nil ? [.existing, .new] : [.current, .existing, .new]
    }

    private var destinationName: String {
        if locksDestination { return preferredStack?.displayTitle ?? newStackTitle }
        switch destination {
        case .current:
            return preferredStack?.displayTitle ?? "Current Stack"
        case .existing:
            return stacks.first(where: { $0.id == selectedStackID })?.displayTitle ?? "Choose Stack"
        case .new:
            return newStackTitle.isEmpty ? "New Stack" : newStackTitle
        }
    }

    private var selectableStackNames: [String] {
        guard !locksDestination else { return [destinationName] }
        var names = stacks.map(\.displayTitle)
        if let preferredStack, !names.contains(preferredStack.displayTitle) {
            names.insert(preferredStack.displayTitle, at: 0)
        }
        if !names.contains(destinationName) {
            names.insert(destinationName, at: 0)
        }
        return names.reduce(into: []) { uniqueNames, name in
            if !uniqueNames.contains(name) { uniqueNames.append(name) }
        }
    }

    private func selectStack(named name: String) {
        if preferredStack?.displayTitle == name {
            destination = .current
        } else if let stack = stacks.first(where: { $0.displayTitle == name }) {
            selectedStackID = stack.id
            destination = .existing
        }
    }

    private var isDraftValid: Bool {
        guard var draft,
              let sourceURL = validURL(link),
              let buyURL = validURL(buyLink) else { return false }
        draft.sourceURL = sourceURL
        draft.buyURL = buyURL
        if destination == .new {
            return !newStackTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && draft.isValid
        }
        if destination == .existing {
            return selectedStackID != nil && draft.isValid
        }
        return preferredStack != nil && draft.isValid
    }

    private func draftBinding<Value>(_ keyPath: WritableKeyPath<ProductImportDraft, Value>, default defaultValue: Value) -> Binding<Value> {
        Binding(
            get: { draft?[keyPath: keyPath] ?? defaultValue },
            set: { value in
                guard var updated = draft else { return }
                updated[keyPath: keyPath] = value
                draft = updated
            }
        )
    }

    private func updateDraft<Value>(_ keyPath: WritableKeyPath<ProductImportDraft, Value>, value: Value) {
        guard var updated = draft else { return }
        updated[keyPath: keyPath] = value
        draft = updated
    }

    private func loadStacks() async {
        isLoadingStacks = true
        defer { isLoadingStacks = false }
        do {
            stacks = try await services.stacks.fetchMyStacks(for: user.id)
            selectedStackID = stacks.first?.id
            if stacks.isEmpty && preferredStack == nil && !locksDestination {
                destination = .new
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func previewLink() {
        guard !isPreviewing else { return }
        guard let url = normalizedProductURL(from: link) else {
            errorMessage = AppError.invalidURL.localizedDescription
            return
        }
        link = url.absoluteString
        isPreviewing = true
        Task {
            do {
                var preview = try await services.productSearch.previewProductLink(url)
                var candidates: [URL] = []
                if let previewImageURL = preview.imageURL {
                    candidates.append(previewImageURL)
                }
                candidates += await ProductPageImageExtractor.productImageURLs(for: preview.sourceURL)

                var seenCandidates = Set<URL>()
                candidates = candidates.filter { seenCandidates.insert($0).inserted }
                guard let resolvedImage = await firstDownloadableImage(from: candidates) else {
                    throw AppError.unavailable("We found the product, but couldn't download a usable image. Try another link or add a photo.")
                }

                // Do not enter the product editor until we have an actual image to
                // show and isolate. This prevents a title-only detail page after a
                // retailer returns metadata but its first image request fails.
                beginRemovalMoment()
                removedBackgroundImageURL = nil
                replacementImageURL = resolvedImage.url
                replacementImageData = resolvedImage.data

                preview.imageURL = resolvedImage.url
                draft = ProductImportDraft(preview: preview)
                link = preview.sourceURL.absoluteString
                buyLink = preview.sourceURL.absoluteString
                imageLink = resolvedImage.url.absoluteString
                priceText = preview.price.map(decimalText) ?? ""

                do {
                    let uploadedURL = try await services.storage.uploadImageData(
                        resolvedImage.data,
                        preferredName: preview.title
                    )
                    replacementImageURL = uploadedURL
                    await preparePreviewRemoval(for: uploadedURL, managesLoadingState: false)
                } catch {
                    // Background removal can work directly against a retailer CDN
                    // when local storage is unavailable in the current environment.
                    replacementImageURL = resolvedImage.url
                    await preparePreviewRemoval(for: resolvedImage.url, managesLoadingState: false)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isPreviewing = false
        }
    }

    private func downloadedImageData(from url: URL) async -> Data? {
        if url.isFileURL {
            return try? Data(contentsOf: url)
        }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Safari/604.1", forHTTPHeaderField: "User-Agent")
            request.setValue("image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
            request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  UIImage(data: data) != nil else {
                return nil
            }
            return data
        } catch {
            return nil
        }
    }

    private func firstDownloadableImage(from candidates: [URL]) async -> (url: URL, data: Data)? {
        for candidate in candidates.prefix(12) {
            if let data = await downloadedImageData(from: candidate) {
                return (candidate, data)
            }
        }
        return nil
    }

    private func save() {
        guard !isSaving,
              var importedDraft = draft,
              let sourceURL = validURL(link),
              let buyURL = validURL(buyLink) else {
            errorMessage = AppError.invalidURL.localizedDescription
            return
        }
        importedDraft.sourceURL = sourceURL
        importedDraft.buyURL = buyURL
        importedDraft.price = decimalPrice(priceText)
        guard importedDraft.isValid else {
            errorMessage = AppError.missingRequiredField("Title and valid links").localizedDescription
            return
        }

        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                if let replacementImageURL {
                    importedDraft.imageURL = replacementImageURL
                } else {
                    importedDraft.imageURL = validURL(imageLink)
                }
                let target = try await targetStack()
                let item = StackItem(
                    id: UUID(), stackID: target.id,
                    title: importedDraft.title.trimmingCharacters(in: .whitespacesAndNewlines),
                    brand: importedDraft.brand.trimmingCharacters(in: .whitespacesAndNewlines),
                    shortDescription: importedDraft.shortDescription.trimmingCharacters(in: .whitespacesAndNewlines),
                    price: importedDraft.price ?? 0, currencyCode: importedDraft.currencyCode,
                    sourceURL: sourceURL, buyURL: buyURL,
                    affiliateURL: try? await services.affiliate.affiliateURL(for: buyURL),
                    originalImageURL: importedDraft.imageURL,
                    removedBackgroundImageURL: removedBackgroundImageURL,
                    removalStatus: removedBackgroundImageURL != nil ? .complete : (importedDraft.imageURL == nil ? .complete : .processing),
                    placement: placement(for: target.items.count), addSource: .pastedLink,
                    claimStatus: nil, demoGlyph: nil
                )
                let savedStack = try await services.stacks.addItem(item, to: target.id)
                services.haptics.notification(.success)
                onSaved(savedStack)
                if item.removedBackgroundImageURL == nil {
                    completeBackgroundRemoval(for: item, in: savedStack)
                }
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                services.haptics.notification(.error)
            }
        }
    }

    private func prepareReplacementImage(_ data: Data) async {
        beginRemovalMoment()
        removedBackgroundImageURL = nil
        do {
            let uploadedURL = try await services.storage.uploadImageData(data, preferredName: draft?.title ?? "product")
            replacementImageURL = uploadedURL
            await preparePreviewRemoval(for: uploadedURL, managesLoadingState: false)
        } catch {
            errorMessage = error.localizedDescription
            finishRemovalMoment()
        }
    }

    private func preparePreviewRemoval(for imageURL: URL, managesLoadingState: Bool = true) async {
        if managesLoadingState {
            beginRemovalMoment()
            removedBackgroundImageURL = nil
        }

        let previewItem = StackItem(
            id: UUID(), stackID: UUID(), title: draft?.title ?? "Product",
            brand: draft?.brand ?? "", shortDescription: draft?.shortDescription ?? "",
            price: draft?.price ?? 0, currencyCode: draft?.currencyCode ?? "USD",
            sourceURL: validURL(link) ?? imageURL, buyURL: validURL(buyLink) ?? imageURL,
            affiliateURL: nil, originalImageURL: imageURL, removedBackgroundImageURL: nil,
            removalStatus: .processing, placement: .centered, addSource: .pastedLink,
            claimStatus: nil, demoGlyph: nil
        )

        var didRemoveBackground = false
        do {
            removedBackgroundImageURL = try await services.backgroundRemoval.removeBackground(for: previewItem)
            didRemoveBackground = removedBackgroundImageURL != nil
        } catch {
            // Keep the scraped product usable when a retailer image cannot be isolated.
            removedBackgroundImageURL = nil
        }
        finishRemovalMoment(didRemoveBackground: didRemoveBackground)
    }

    private func beginRemovalMoment() {
        removalMomentStartedAt = Date()
        isResolvingRemovalMoment = false
        isPresentingRemovalMoment = true
        isRemovingBackground = true
        services.haptics.impact(.soft)
    }

    private func finishRemovalMoment(didRemoveBackground: Bool = false) {
        let elapsed = Date().timeIntervalSince(removalMomentStartedAt ?? .distantPast)
        // Every import gets a legible processing moment, but never cuts off a
        // real Vision pass that needs longer than the minimum.
        let delay = max(0, 3 - elapsed)

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            isRemovingBackground = false
            if didRemoveBackground {
                services.haptics.notification(.success)
                withAnimation(.smooth(duration: 0.42)) {
                    isResolvingRemovalMoment = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.48) {
                    isPresentingRemovalMoment = false
                    isResolvingRemovalMoment = false
                    removalMomentStartedAt = nil
                }
                return
            }
            isPresentingRemovalMoment = false
            removalMomentStartedAt = nil
        }
    }

    private func targetStack() async throws -> Stack {
        switch destination {
        case .current:
            guard let preferredStack else { throw AppError.notFound }
            return preferredStack
        case .existing:
            guard let id = selectedStackID,
                  let stack = stacks.first(where: { $0.id == id }) else { throw AppError.notFound }
            return stack
        case .new:
            return try await services.stacks.createStack(
                title: newStackTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                wishlistMode: newStackWishlistMode,
                owner: user
            )
        }
    }

    private func completeBackgroundRemoval(for item: StackItem, in stack: Stack) {
        guard item.originalImageURL != nil else { return }
        Task {
            do {
                var updatedItem = item
                updatedItem.removedBackgroundImageURL = try await services.backgroundRemoval.removeBackground(for: item)
                updatedItem.removalStatus = .complete
                onSaved(try await services.stacks.updateItem(updatedItem, in: stack.id))
            } catch {
                var failedItem = item
                failedItem.removalStatus = .failed
                if let updated = try? await services.stacks.updateItem(failedItem, in: stack.id) {
                    onSaved(updated)
                }
            }
        }
    }

    private func placement(for itemCount: Int) -> StickerPlacement {
        let positions: [StickerPlacement] = [
            StickerPlacement(xRatio: 0.23, yRatio: 0.24, scale: 1, rotationDegrees: -5),
            StickerPlacement(xRatio: 0.72, yRatio: 0.28, scale: 1.05, rotationDegrees: 4),
            StickerPlacement(xRatio: 0.34, yRatio: 0.56, scale: 0.92, rotationDegrees: -4),
            StickerPlacement(xRatio: 0.72, yRatio: 0.68, scale: 1.02, rotationDegrees: 6),
            StickerPlacement(xRatio: 0.48, yRatio: 0.84, scale: 0.96, rotationDegrees: -2)
        ]
        return positions[itemCount % positions.count]
    }

    private func validURL(_ value: String) -> URL? {
        normalizedProductURL(from: value)
    }

    private func normalizedProductURL(from value: String) -> URL? {
        var cleanValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanValue.isEmpty else { return nil }
        if !cleanValue.lowercased().hasPrefix("http://"), !cleanValue.lowercased().hasPrefix("https://") {
            cleanValue = "https://\(cleanValue)"
        }
        guard let encoded = cleanValue.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed),
              let url = URL(string: encoded),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else { return nil }
        return url
    }

    private func decimalPrice(_ value: String) -> Decimal? {
        let clean = value.filter { $0.isNumber || $0 == "." || $0 == "," }
            .replacingOccurrences(of: ",", with: ".")
        return clean.isEmpty ? nil : Decimal(string: clean)
    }

    private func decimalText(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }
}

private struct ProductImportImage: View {
    let url: URL?
    let data: Data?

    var body: some View {
        Group {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else if let url {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFit()
                    } else if case .failure = phase {
                        Image(systemName: "photo").font(.title2).foregroundStyle(.secondary)
                    } else {
                        ProgressView()
                    }
                }
            } else {
                Image(systemName: "photo").font(.title2).foregroundStyle(.secondary)
            }
        }
        .frame(width: 76, height: 76)
        .background(Color.stacksCream, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private enum ProductReviewOptionalField: CaseIterable, Hashable {
    case brand
    case price
    case description

    var title: String {
        switch self {
        case .brand: "Brand"
        case .price: "Price"
        case .description: "Description"
        }
    }
}

private struct EditorialProductField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var multiline = false
    var onRemove: (() -> Void)?

    var body: some View {
        HStack(alignment: multiline ? .top : .center, spacing: 12) {
            Text(label)
                .font(.system(size: 16, weight: .regular, design: .default))
                .tracking(-0.25)
                .foregroundStyle(Color.stacksMutedInk)
                .frame(width: 104, alignment: .leading)

            if multiline {
                TextField(placeholder, text: $text, axis: .vertical)
                    .lineLimit(2...5)
                    .multilineTextAlignment(.trailing)
                    .font(.system(size: 17, weight: .regular, design: .default))
                    .tracking(-0.25)
                    .foregroundStyle(Color.stacksInk)
            } else {
                TextField(placeholder, text: $text)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(keyboardType)
                    .font(.system(size: 17, weight: .regular, design: .default))
                    .tracking(-0.25)
                    .foregroundStyle(Color.stacksInk)
            }

            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(Color.stacksMutedInk.opacity(0.55))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(label) field")
            }
        }
        .padding(.vertical, multiline ? 11 : 9)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.stacksInk.opacity(0.09))
                .frame(height: 1)
        }
    }
}

private struct EditorialPriceField: View {
    @Binding var price: String
    @Binding var currencyCode: String
    var onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text("Price")
                .font(.system(size: 16, weight: .regular, design: .default))
                .tracking(-0.25)
                .foregroundStyle(Color.stacksMutedInk)
                .frame(width: 104, alignment: .leading)

            TextField("0.00", text: $price)
                .multilineTextAlignment(.trailing)
                .keyboardType(.decimalPad)
                .font(.system(size: 17, weight: .regular, design: .default))
                .tracking(-0.25)

            Menu {
                ForEach(["USD", "EUR", "GBP", "CAD", "AUD"], id: \.self) { currency in
                    Button(currency) { currencyCode = currency }
                }
            } label: {
                Text(currencyCode)
                    .font(.system(size: 14, weight: .regular, design: .default))
                    .foregroundStyle(Color.stacksMutedInk)
            }

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Color.stacksMutedInk.opacity(0.55))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove Price field")
        }
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.stacksInk.opacity(0.09))
                .frame(height: 1)
        }
    }
}

private struct EditorialProductPreview: View {
    let originalData: Data?
    let originalURL: URL?
    let removedBackgroundURL: URL?
    let isRemoving: Bool

    var body: some View {
        ZStack {
            Color.white

            if let removedBackgroundURL {
                productImage(url: removedBackgroundURL)
                    .padding(24)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else if let originalData, let image = UIImage(data: originalData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(18)
                    .transition(.opacity)
            } else if let originalURL {
                productImage(url: originalURL)
                    .padding(18)
                    .transition(.opacity)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(Color.stacksMutedInk.opacity(0.55))
            }

            if isRemoving {
                RemovalShimmerView()
                    .clipShape(Rectangle())
                    .padding(.horizontal, 12)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 300)
        .background(Color.white)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.stacksInk.opacity(0.08))
                .frame(height: 1)
        }
        .animation(.snappy(duration: 0.38), value: removedBackgroundURL)
        .animation(.easeInOut(duration: 0.22), value: isRemoving)
    }

    @ViewBuilder
    private func productImage(url: URL) -> some View {
        if url.isFileURL, let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } else {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFit()
                case .empty:
                    ProgressView().tint(Color.stacksInk)
                default:
                    Image(systemName: "photo")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(Color.stacksMutedInk.opacity(0.55))
                }
            }
        }
    }
}

/// The post-import editor deliberately mirrors a saved product page. Imported
/// values are editable in place while unknown values stay visible as prompts.
private struct ProductImportDetailScreen: View {
    let originalData: Data?
    let originalURL: URL?
    let removedBackgroundURL: URL?
    @Binding var title: String
    @Binding var brand: String
    @Binding var price: String
    @Binding var currencyCode: String
    @Binding var description: String
    @Binding var sourceLink: String
    @Binding var buyLink: String
    let stackName: String
    let stackOptions: [String]
    let onSelectStack: ((String) -> Void)?
    let isSaving: Bool
    let canSave: Bool
    let onCancel: () -> Void
    let onSave: () -> Void

    // Links are part of the product record, not an advanced setting. Keeping
    // them visible makes the post-processing screen a complete editor whether
    // the product came from a photo, a pasted URL, or the share extension.
    @State private var showsLinks = true
    @State private var showsEditableShimmer = false

    var body: some View {
        ZStack(alignment: .top) {
            Color.white.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    ImportCutoutStage(
                        originalData: originalData,
                        originalURL: originalURL,
                        removedBackgroundURL: removedBackgroundURL
                    )
                    .padding(.top, 60)

                    VStack(spacing: 18) {
                        ImportTitleField(title: $title, showsEditableShimmer: showsEditableShimmer)

                        ImportDescriptionField(description: $description, showsEditableShimmer: showsEditableShimmer)

                        ImportMetadataCard(
                            brand: $brand,
                            price: $price,
                            currencyCode: $currencyCode,
                            stackName: stackName,
                            stackOptions: stackOptions,
                            onSelectStack: onSelectStack,
                            showsEditableShimmer: showsEditableShimmer
                        )

                        if showsLinks {
                            VStack(spacing: 0) {
                                ImportDetailRow(
                                    label: "Product link",
                                    placeholder: "Paste the original link",
                                    text: $sourceLink,
                                    keyboardType: .URL,
                                    showsEditableShimmer: showsEditableShimmer
                                )
                                ImportDetailRow(
                                    label: "Buy link",
                                    placeholder: "Paste a checkout link",
                                    text: $buyLink,
                                    keyboardType: .URL,
                                    showsEditableShimmer: showsEditableShimmer
                                )
                            }
                            .padding(.horizontal, 24)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .padding(.bottom, 112)
                }
            }

            HStack {
                Button(action: onCancel) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")

                Spacer()

                Menu {
                    Button(showsLinks ? "Hide links" : "Show links", systemImage: "link") {
                        withAnimation(.snappy(duration: 0.24)) {
                            showsLinks.toggle()
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityLabel("Product options")
            }
            .foregroundStyle(Color.stacksInk)
            .padding(.horizontal, 22)
            .padding(.top, 8)
        }
        .task {
            showsEditableShimmer = true
            try? await Task.sleep(for: .seconds(3))
            showsEditableShimmer = false
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button(action: onSave) {
                HStack {
                    Text(isSaving ? "Saving" : "Save to Stack")
                    Spacer()
                    if isSaving {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "arrow.right")
                    }
                }
                .font(.stacksText(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .frame(height: 62)
                .background(canSave ? Color.stacksInk : Color.stacksInk.opacity(0.32), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
            .padding(.horizontal, 22)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
    }
}

private struct ImportCutoutStage: View {
    let originalData: Data?
    let originalURL: URL?
    let removedBackgroundURL: URL?

    var body: some View {
        Group {
            if let removedBackgroundURL {
                image(from: removedBackgroundURL)
            } else if let originalData, let image = UIImage(data: originalData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else if let originalURL {
                image(from: originalURL)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(Color.stacksMutedInk.opacity(0.45))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 390)
        .padding(.horizontal, 26)
    }

    @ViewBuilder
    private func image(from url: URL) -> some View {
        if url.isFileURL, let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } else {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFit()
                case .empty:
                    ProgressView().tint(Color.stacksInk)
                default:
                    Image(systemName: "photo")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(Color.stacksMutedInk.opacity(0.45))
                }
            }
        }
    }
}

private struct ImportTitleField: View {
    @Binding var title: String
    let showsEditableShimmer: Bool

    var body: some View {
        ZStack {
            TextField("", text: $title, axis: .vertical)
                .font(.system(size: 48, weight: .semibold, design: .default))
                .tracking(-1.8)
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.words)
                .textContentType(.name)
                .autocorrectionDisabled(false)
                .foregroundStyle(Color.stacksInk)
                .lineLimit(1...2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 62)

            if title.isEmpty {
                ImportShimmerPlaceholder(text: "Type product title", font: .system(size: 36, weight: .semibold, design: .default))
                    .allowsHitTesting(false)
            } else if showsEditableShimmer {
                ImportShimmerPlaceholder(text: title, font: .system(size: 48, weight: .semibold, design: .default))
                    .tracking(-1.8)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .opacity(0.62)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityLabel("Product title")
    }
}

private struct ImportDescriptionField: View {
    @Binding var description: String
    let showsEditableShimmer: Bool

    var body: some View {
        ZStack(alignment: .top) {
            TextField("", text: $description, axis: .vertical)
                .font(.stacksText(size: 17, weight: .regular))
                .tracking(-0.25)
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.sentences)
                .lineLimit(1...4)
                .foregroundStyle(Color.stacksInk.opacity(0.72))
                .frame(maxWidth: .infinity, minHeight: 26)

            if description.isEmpty {
                ImportShimmerPlaceholder(text: "Type a short description", font: .stacksText(size: 17, weight: .regular))
                    .allowsHitTesting(false)
            } else if showsEditableShimmer {
                ImportShimmerPlaceholder(text: description, font: .stacksText(size: 17, weight: .regular))
                    .opacity(0.52)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityLabel("Product details")
    }
}

private struct ImportMetadataCard: View {
    @Binding var brand: String
    @Binding var price: String
    @Binding var currencyCode: String
    let stackName: String
    let stackOptions: [String]
    let onSelectStack: ((String) -> Void)?
    let showsEditableShimmer: Bool

    var body: some View {
        HStack(spacing: 0) {
            ImportMetadataInput(
                label: "Brand",
                placeholder: "Add brand",
                text: $brand,
                showsEditableShimmer: showsEditableShimmer
            )
            Divider().frame(height: 42)
            ImportPriceInput(
                price: $price,
                currencyCode: $currencyCode,
                showsEditableShimmer: showsEditableShimmer
            )
            Divider().frame(height: 42)
            ImportStackInput(
                stackName: stackName,
                stackOptions: stackOptions,
                onSelectStack: onSelectStack,
                showsEditableShimmer: showsEditableShimmer
            )
        }
        .padding(.vertical, 14)
        .stacksGlass(cornerRadius: 22)
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.68), lineWidth: 1)
        }
    }
}

private struct ImportStackInput: View {
    let stackName: String
    let stackOptions: [String]
    let onSelectStack: ((String) -> Void)?
    let showsEditableShimmer: Bool

    var body: some View {
        VStack(spacing: 5) {
            ImportMetadataLabel(text: "Stack")
            if let onSelectStack, stackOptions.count > 1 {
                Menu {
                    ForEach(stackOptions, id: \.self) { option in
                        Button(option) { onSelectStack(option) }
                    }
                } label: {
                    stackValue
                }
                .buttonStyle(.plain)
            } else {
                stackValue
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Stack")
    }

    @ViewBuilder
    private var stackValue: some View {
        ZStack {
            Text(stackName)
                .font(.stacksText(size: 14, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(Color.stacksInk)
            if showsEditableShimmer {
                ImportShimmerPlaceholder(text: stackName, font: .stacksText(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .opacity(0.52)
                    .allowsHitTesting(false)
            }
        }
    }
}

private struct ImportMetadataInput: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    let showsEditableShimmer: Bool

    var body: some View {
        VStack(spacing: 5) {
            ImportMetadataLabel(text: label)
            ZStack {
                TextField("", text: $text)
                    .font(.stacksText(size: 14, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .textInputAutocapitalization(.words)
                    .textContentType(.name)
                    .foregroundStyle(Color.stacksInk)
                if text.isEmpty {
                    ImportShimmerPlaceholder(text: placeholder, font: .stacksText(size: 14, weight: .semibold))
                        .allowsHitTesting(false)
                } else if showsEditableShimmer {
                    ImportShimmerPlaceholder(text: text, font: .stacksText(size: 14, weight: .semibold))
                        .opacity(0.52)
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ImportPriceInput: View {
    @Binding var price: String
    @Binding var currencyCode: String
    let showsEditableShimmer: Bool

    var body: some View {
        VStack(spacing: 5) {
            ImportMetadataLabel(text: "Price")
            HStack(spacing: 2) {
                ZStack {
                    TextField("", text: $price)
                        .font(.stacksText(size: 14, weight: .semibold))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                    if price.isEmpty {
                        ImportShimmerPlaceholder(text: "Add price", font: .stacksText(size: 14, weight: .semibold))
                            .allowsHitTesting(false)
                    } else if showsEditableShimmer {
                        ImportShimmerPlaceholder(text: price, font: .stacksText(size: 14, weight: .semibold))
                            .opacity(0.52)
                            .allowsHitTesting(false)
                    }
                }
                Menu(currencyCode) {
                    ForEach(["USD", "EUR", "GBP", "CAD", "AUD"], id: \.self) { code in
                        Button(code) { currencyCode = code }
                    }
                }
                .font(.stacksText(size: 11, weight: .regular))
                .foregroundStyle(Color.stacksMutedInk)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ImportMetadataValue: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 5) {
            ImportMetadataLabel(text: label)
            Text(value)
                .font(.stacksText(size: 14, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(Color.stacksInk)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ImportMetadataLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .medium, design: .default))
            .tracking(0.7)
            .foregroundStyle(Color.stacksMutedInk)
    }
}

private struct ImportDetailRow: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    let keyboardType: UIKeyboardType
    let showsEditableShimmer: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.stacksText(size: 15, weight: .regular))
                .foregroundStyle(Color.stacksMutedInk)
                .frame(width: 88, alignment: .leading)
            ZStack(alignment: .trailing) {
                TextField("", text: $text)
                    .font(.stacksText(size: 15, weight: .regular))
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(keyboardType)
                if text.isEmpty {
                    ImportShimmerPlaceholder(text: placeholder, font: .stacksText(size: 15, weight: .regular))
                        .allowsHitTesting(false)
                } else if showsEditableShimmer {
                    ImportShimmerPlaceholder(text: text, font: .stacksText(size: 15, weight: .regular))
                        .opacity(0.52)
                        .allowsHitTesting(false)
                }
            }
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.stacksInk.opacity(0.09)).frame(height: 1)
        }
    }
}

private struct ImportShimmerPlaceholder: View {
    let text: String
    let font: Font
    @State private var glows = false

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(
                LinearGradient(
                    colors: [Color.stacksMutedInk.opacity(glows ? 0.22 : 0.46), .white.opacity(0.9), Color.stacksMutedInk.opacity(glows ? 0.46 : 0.22)],
                    startPoint: glows ? .leading : .trailing,
                    endPoint: glows ? .trailing : .leading
                )
            )
            .onAppear {
                withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) {
                    glows = true
                }
            }
    }
}

private struct ProductImportRemovalMoment: View {
    let originalData: Data?
    let originalURL: URL?
    let removedBackgroundURL: URL?
    let showsCutout: Bool

    var body: some View {
        GeometryReader { proxy in
            let imageSize = min(proxy.size.width - 48, 360)

            ZStack {
                Color.white
                    .ignoresSafeArea()

                ZStack {
                    if showsCutout, let removedBackgroundURL {
                        image(from: removedBackgroundURL)
                            .frame(width: imageSize, height: imageSize)
                            .transition(.scale(scale: 0.92).combined(with: .opacity))
                    } else {
                        productImage
                            .frame(width: imageSize, height: imageSize)

                        RemovalShimmerView()
                            .frame(width: imageSize, height: imageSize)
                            .blendMode(.screen)
                            .opacity(0.82)
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Removing product background")
        .animation(.smooth(duration: 0.42), value: showsCutout)
    }

    @ViewBuilder
    private var productImage: some View {
        if let originalData, let image = UIImage(data: originalData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } else if let originalURL {
            if originalURL.isFileURL, let image = UIImage(contentsOfFile: originalURL.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                AsyncImage(url: originalURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                    case .empty:
                        ProgressView()
                            .tint(Color.stacksInk)
                    default:
                        Image(systemName: "photo")
                            .font(.system(size: 30, weight: .light))
                            .foregroundStyle(Color.stacksMutedInk.opacity(0.45))
                    }
                }
            }
        } else {
            Image(systemName: "photo")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Color.stacksMutedInk.opacity(0.45))
        }
    }

    @ViewBuilder
    private func image(from url: URL) -> some View {
        if url.isFileURL, let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } else {
            AsyncImage(url: url) { phase in
                if case .success(let image) = phase {
                    image
                        .resizable()
                        .scaledToFit()
                } else {
                    ProgressView()
                        .tint(Color.stacksInk)
                }
            }
        }
    }
}

struct PhotoProductImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appServices) private var services
    @State private var isShowingCamera = false
    @State private var isShowingPhotoLibrary = false
    @State private var imageData: Data?
    @State private var originalImageURL: URL?
    @State private var removedBackgroundImageURL: URL?
    @State private var isRemovingBackground = false
    @State private var isPresentingRemovalMoment = false
    @State private var isResolvingRemovalMoment = false
    @State private var removalMomentStartedAt: Date?
    @State private var removalError: String?
    @State private var title = ""
    @State private var brand = ""
    @State private var priceText = ""
    @State private var currencyCode = "USD"
    @State private var description = ""
    @State private var sourceLink = ""
    @State private var buyLink = ""
    @State private var stacks: [Stack] = []
    @State private var selectedStackID: UUID?
    @State private var destination: ProductImportDestination
    @State private var newStackTitle = ""
    @State private var newStackWishlistMode = false
    @State private var isLoadingStacks = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var visibleDetails: Set<ProductReviewOptionalField> = [.brand, .price, .description]

    let user: UserProfile
    let preferredStack: Stack?
    let navigationTitle: String
    let startingSource: PhotoProductImportStartingSource
    let locksDestination: Bool
    let initialNewStackTitle: String?
    let onSaved: (Stack) -> Void

    init(
        initialImageData: Data? = nil,
        navigationTitle: String = "Add From Photo",
        startingSource: PhotoProductImportStartingSource = .editor,
        user: UserProfile,
        preferredStack: Stack? = nil,
        locksDestination: Bool = false,
        initialNewStackTitle: String? = nil,
        onSaved: @escaping (Stack) -> Void
    ) {
        self.user = user
        self.preferredStack = preferredStack
        self.navigationTitle = navigationTitle
        self.startingSource = startingSource
        self.locksDestination = locksDestination
        self.initialNewStackTitle = initialNewStackTitle
        self.onSaved = onSaved
        _imageData = State(initialValue: initialImageData)
        _destination = State(initialValue: preferredStack == nil ? (initialNewStackTitle == nil ? .existing : .new) : .current)
        _newStackTitle = State(initialValue: initialNewStackTitle ?? "")
    }

    var body: some View {
        photoEditor
            .fullScreenCover(isPresented: $isPresentingRemovalMoment) {
                ProductImportRemovalMoment(
                    originalData: imageData,
                    originalURL: originalImageURL,
                    removedBackgroundURL: removedBackgroundImageURL,
                    showsCutout: isResolvingRemovalMoment
                )
                .interactiveDismissDisabled(isRemovingBackground || isResolvingRemovalMoment)
            }
    }

    private var photoEditor: some View {
        ProductImportDetailScreen(
            originalData: imageData,
            originalURL: originalImageURL,
            removedBackgroundURL: removedBackgroundImageURL,
            title: $title,
            brand: $brand,
            price: $priceText,
            currencyCode: $currencyCode,
            description: $description,
            sourceLink: $sourceLink,
            buyLink: $buyLink,
            stackName: destinationName,
            stackOptions: selectableStackNames,
            onSelectStack: locksDestination ? nil : { name in
                selectStack(named: name)
            },
            isSaving: isSaving,
            canSave: canSave,
            onCancel: { dismiss() },
            onSave: save
        )
        .task {
            await loadStacks()
            if let imageData, originalImageURL == nil {
                await preparePhoto(imageData)
            }
            presentStartingSourceIfNeeded()
        }
        .onChange(of: imageData) { _, newData in
            guard let newData else { return }
            Task { await preparePhoto(newData) }
        }
        .sheet(isPresented: $isShowingCamera) {
            CameraCaptureView(imageData: $imageData)
                .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $isShowingPhotoLibrary) {
            ProductPhotoLibraryPicker(
                onCapture: { data in
                    imageData = data
                    isShowingPhotoLibrary = false
                },
                onCancel: {
                    isShowingPhotoLibrary = false
                }
            )
            .ignoresSafeArea()
        }
        .alert("Could not add photo", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var photoSection: some View {
        let photoLabel = imageData == nil ? "Choose from Library" : "Choose Another Photo"
        return Section {
            EditorialProductPreview(
                originalData: imageData,
                originalURL: originalImageURL,
                removedBackgroundURL: removedBackgroundImageURL,
                isRemoving: isRemovingBackground
            )
            .listRowInsets(.init())
            .listRowBackground(Color.white)

            if let removalError, let imageData {
                Button("Try Background Removal Again") {
                    Task { await preparePhoto(imageData) }
                }
                .font(.system(size: 15, weight: .regular, design: .default))
                .foregroundStyle(Color.stacksMutedInk)
            }

            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button {
                    isShowingCamera = true
                } label: {
                    Label("Replace photo", systemImage: "camera")
                        .font(.system(size: 16, weight: .regular, design: .default))
                }
            }

            Button {
                isShowingPhotoLibrary = true
            } label: {
                Label(photoLabel, systemImage: "photo.on.rectangle")
                    .font(.system(size: 16, weight: .regular, design: .default))
            }
        }
    }

    private var detailsSection: some View {
        Section {
            VStack(spacing: 0) {
                EditorialProductField(label: "Name", placeholder: "Product name", text: $title)

                if visibleDetails.contains(.brand) {
                    EditorialProductField(label: "Brand", placeholder: "Brand or maker", text: $brand) {
                        brand = ""
                        visibleDetails.remove(.brand)
                    }
                }

                if visibleDetails.contains(.price) {
                    EditorialPriceField(price: $priceText, currencyCode: $currencyCode) {
                        priceText = ""
                        visibleDetails.remove(.price)
                    }
                }

                if visibleDetails.contains(.description) {
                    EditorialProductField(label: "Details", placeholder: "A short note about it", text: $description, multiline: true) {
                        description = ""
                        visibleDetails.remove(.description)
                    }
                }

                EditorialProductField(label: "Product link", placeholder: "Paste the original link", text: $sourceLink, keyboardType: .URL)
                EditorialProductField(label: "Buy link", placeholder: "Paste a checkout link", text: $buyLink, keyboardType: .URL)

                Menu {
                    ForEach(ProductReviewOptionalField.allCases.filter { !visibleDetails.contains($0) }, id: \.self) { field in
                        Button("Add \(field.title)") {
                            visibleDetails.insert(field)
                        }
                    }
                } label: {
                    Label("Add a detail", systemImage: "plus")
                        .font(.system(size: 15, weight: .regular, design: .default))
                        .foregroundStyle(Color.stacksMutedInk)
                        .padding(.top, 14)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .listRowInsets(.init(top: 4, leading: 20, bottom: 14, trailing: 20))
            .listRowBackground(Color.white)
        }
    }

    private var destinationSection: some View {
        Section("Add to") {
            Picker("Destination", selection: $destination) {
                ForEach(availableDestinations) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.menu)

            switch destination {
            case .current:
                if let preferredStack {
                    LabeledContent("Stack", value: preferredStack.displayTitle)
                }
            case .existing:
                if isLoadingStacks {
                    ProgressView("Loading Stacks")
                } else if stacks.isEmpty {
                    Text("No Stack yet. Choose New Stack below.")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Stack", selection: $selectedStackID) {
                        ForEach(stacks) { stack in
                            Text(stack.displayTitle).tag(Optional(stack.id))
                        }
                    }
                }
            case .new:
                TextField("New Stack title", text: $newStackTitle)
                    .textInputAutocapitalization(.words)
                    .textContentType(.name)
                Toggle("Wishlist mode", isOn: $newStackWishlistMode)
            }
        }
    }

    private var lockedDestinationSection: some View {
        Section("Adding to") {
            LabeledContent("Stack", value: preferredStack?.displayTitle ?? newStackTitle)
        }
    }

    private var availableDestinations: [ProductImportDestination] {
        preferredStack == nil ? [.existing, .new] : [.current, .existing, .new]
    }

    private var destinationName: String {
        if locksDestination { return preferredStack?.displayTitle ?? newStackTitle }
        switch destination {
        case .current:
            return preferredStack?.displayTitle ?? "Current Stack"
        case .existing:
            return stacks.first(where: { $0.id == selectedStackID })?.displayTitle ?? "Choose Stack"
        case .new:
            return newStackTitle.isEmpty ? "New Stack" : newStackTitle
        }
    }

    private var selectableStackNames: [String] {
        guard !locksDestination else { return [destinationName] }
        var names = stacks.map(\.displayTitle)
        if let preferredStack, !names.contains(preferredStack.displayTitle) {
            names.insert(preferredStack.displayTitle, at: 0)
        }
        if !names.contains(destinationName) {
            names.insert(destinationName, at: 0)
        }
        return names.reduce(into: []) { uniqueNames, name in
            if !uniqueNames.contains(name) { uniqueNames.append(name) }
        }
    }

    private func selectStack(named name: String) {
        if preferredStack?.displayTitle == name {
            destination = .current
        } else if let stack = stacks.first(where: { $0.displayTitle == name }) {
            selectedStackID = stack.id
            destination = .existing
        }
    }

    private var canSave: Bool {
        guard !isSaving,
              !isRemovingBackground,
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }

        if destination == .new {
            return !newStackTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if destination == .existing {
            return selectedStackID != nil
        }
        return preferredStack != nil
    }

    private func preparePhoto(_ data: Data) async {
        guard !isRemovingBackground else { return }
        isPresentingRemovalMoment = true
        isRemovingBackground = true
        isResolvingRemovalMoment = false
        removalMomentStartedAt = Date()
        services.haptics.impact(.soft)
        removalError = nil
        removedBackgroundImageURL = nil
        var didRemoveBackground = false
        do {
            let originalURL = try await services.storage.uploadImageData(data, preferredName: title.isEmpty ? "photo-item" : title)
            originalImageURL = originalURL
            let previewItem = StackItem(
                id: UUID(), stackID: UUID(), title: title.isEmpty ? "Photo Item" : title,
                brand: brand, shortDescription: description, price: 0, currencyCode: currencyCode,
                sourceURL: URL(string: "https://stacks.app/photo-import")!,
                buyURL: URL(string: "https://stacks.app/photo-import")!, affiliateURL: nil,
                originalImageURL: originalURL, removedBackgroundImageURL: nil,
                removalStatus: .processing, placement: .centered, addSource: .manualPhoto,
                claimStatus: nil, demoGlyph: nil
            )
            removedBackgroundImageURL = try await services.backgroundRemoval.removeBackground(for: previewItem)
            didRemoveBackground = removedBackgroundImageURL != nil
        } catch {
            removalError = error.localizedDescription
            services.haptics.notification(.error)
        }
        finishRemovalMoment(didRemoveBackground: didRemoveBackground)
    }

    private func finishRemovalMoment(didRemoveBackground: Bool) {
        let elapsed = Date().timeIntervalSince(removalMomentStartedAt ?? .distantPast)
        let delay = max(0, 3 - elapsed)

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            isRemovingBackground = false
            if didRemoveBackground {
                services.haptics.notification(.success)
                withAnimation(.smooth(duration: 0.42)) {
                    isResolvingRemovalMoment = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.48) {
                    isPresentingRemovalMoment = false
                    isResolvingRemovalMoment = false
                    removalMomentStartedAt = nil
                }
                return
            }
            isPresentingRemovalMoment = false
            removalMomentStartedAt = nil
        }
    }

    private func presentStartingSourceIfNeeded() {
        guard imageData == nil else { return }
        switch startingSource {
        case .editor:
            break
        case .camera:
            guard UIImagePickerController.isSourceTypeAvailable(.camera) else { return }
            isShowingCamera = true
        case .photoLibrary:
            isShowingPhotoLibrary = true
        }
    }

    private func loadStacks() async {
        isLoadingStacks = true
        defer { isLoadingStacks = false }
        do {
            stacks = try await services.stacks.fetchMyStacks(for: user.id)
            selectedStackID = stacks.first?.id
            if stacks.isEmpty && preferredStack == nil && !locksDestination {
                destination = .new
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() {
        guard canSave else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                let target = try await targetStack()
                let itemID = UUID()
                let internalFindURL = URL(string: "https://stacks.app/finds/\(itemID.uuidString)")!
                let sourceURL = validURL(sourceLink) ?? validURL(buyLink) ?? internalFindURL
                let buyURL = validURL(buyLink) ?? validURL(sourceLink) ?? internalFindURL
                let item = StackItem(
                    id: itemID, stackID: target.id,
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    brand: brand.trimmingCharacters(in: .whitespacesAndNewlines),
                    shortDescription: description.trimmingCharacters(in: .whitespacesAndNewlines),
                    price: decimalPrice(priceText) ?? 0, currencyCode: currencyCode,
                    sourceURL: sourceURL, buyURL: buyURL,
                    affiliateURL: try? await services.affiliate.affiliateURL(for: buyURL),
                    originalImageURL: originalImageURL,
                    removedBackgroundImageURL: removedBackgroundImageURL,
                    removalStatus: removedBackgroundImageURL != nil ? .complete : (originalImageURL == nil ? .complete : .failed),
                    placement: placement(for: target.items.count), addSource: .manualPhoto,
                    claimStatus: nil, demoGlyph: nil
                )
                let savedStack = try await services.stacks.addItem(item, to: target.id)
                services.haptics.notification(.success)
                onSaved(savedStack)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                services.haptics.notification(.error)
            }
        }
    }

    private func targetStack() async throws -> Stack {
        switch destination {
        case .current:
            guard let preferredStack else { throw AppError.notFound }
            return preferredStack
        case .existing:
            guard let id = selectedStackID,
                  let stack = stacks.first(where: { $0.id == id }) else { throw AppError.notFound }
            return stack
        case .new:
            return try await services.stacks.createStack(
                title: newStackTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                wishlistMode: newStackWishlistMode,
                owner: user
            )
        }
    }

    private func placement(for itemCount: Int) -> StickerPlacement {
        let positions: [StickerPlacement] = [
            StickerPlacement(xRatio: 0.23, yRatio: 0.24, scale: 1, rotationDegrees: -5),
            StickerPlacement(xRatio: 0.72, yRatio: 0.28, scale: 1.05, rotationDegrees: 4),
            StickerPlacement(xRatio: 0.34, yRatio: 0.56, scale: 0.92, rotationDegrees: -4),
            StickerPlacement(xRatio: 0.72, yRatio: 0.68, scale: 1.02, rotationDegrees: 6),
            StickerPlacement(xRatio: 0.48, yRatio: 0.84, scale: 0.96, rotationDegrees: -2)
        ]
        return positions[itemCount % positions.count]
    }

    private func validURL(_ value: String) -> URL? {
        guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.hasPrefix("http") == true else { return nil }
        return url
    }

    private func decimalPrice(_ value: String) -> Decimal? {
        let clean = value.filter { $0.isNumber || $0 == "." || $0 == "," }
            .replacingOccurrences(of: ",", with: ".")
        return clean.isEmpty ? nil : Decimal(string: clean)
    }
}

private struct PhotoRemovalPreview: View {
    let originalData: Data
    let removedBackgroundURL: URL?
    let isRemoving: Bool

    var body: some View {
        ZStack {
            Color.white
            if let removedBackgroundURL,
               let image = UIImage(contentsOfFile: removedBackgroundURL.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(18)
            } else if let image = UIImage(data: originalData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            }

            if isRemoving {
                RemovalShimmerView()
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .padding(14)
            }
        }
        .frame(height: 240)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        }
    }
}
private struct CameraCaptureView: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    @Binding var imageData: Data?

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(imageData: $imageData, dismiss: dismiss)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        @Binding private var imageData: Data?
        private let dismiss: DismissAction

        init(imageData: Binding<Data?>, dismiss: DismissAction) {
            _imageData = imageData
            self.dismiss = dismiss
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                imageData = image.jpegData(compressionQuality: 0.9)
            }
            dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}

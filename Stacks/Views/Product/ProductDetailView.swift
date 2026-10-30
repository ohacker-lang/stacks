import PhotosUI
import SwiftUI
import UIKit

/// An editorial product page for a single saved sticker. The source Stack is
/// carried through navigation so saving to another Stack is a real copy action.
struct ProductDetailView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.appServices) private var services
    @Environment(PriceAlertCenter.self) private var priceAlerts
    @Environment(\.dismiss) private var dismiss

    let item: StackItem
    let sourceStack: Stack
    let productTransition: Namespace.ID
    let onBack: (() -> Void)?

    @State private var isShowingDestinationPicker = false
    @State private var didCopyLink = false
    @State private var saveMessage: String?
    @State private var claimStatus: GiftClaimStatus?
    @State private var isClaiming = false
    @State private var affiliateResolution: AffiliateLinkResolution?
    @State private var isConfirmingDelete = false
    @State private var deleteError: String?
    @State private var currentItem: StackItem
    @State private var isShowingEditor = false
    @State private var replacementPhoto: PhotosPickerItem?
    @State private var actionError: String?
    @State private var isUpdatingProduct = false
    @State private var didClaimThisSession = false
    @State private var priceAlertItem: StackItem?

    init(
        item: StackItem,
        sourceStack: Stack,
        productTransition: Namespace.ID,
        onBack: (() -> Void)? = nil
    ) {
        self.item = item
        self.sourceStack = sourceStack
        self.productTransition = productTransition
        self.onBack = onBack
        _claimStatus = State(initialValue: item.claimStatus)
        _currentItem = State(initialValue: item)
    }

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    ProductStickerStage(item: currentItem)
                        .padding(.top, 76)

                    VStack(spacing: 10) {
                        ProductPageTitle(text: currentItem.title)

                        if !currentItem.shortDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            ProductDescription(item: currentItem)
                        }
                    }
                    .padding(.horizontal, 26)
                    .padding(.top, 25)

                    ProductInformation(item: currentItem)
                        .padding(.horizontal, 24)
                        .padding(.top, 26)
                        .padding(.bottom, 26)
                }
            }

            ProductNavigationBar(
                onBack: goBack,
                hasPriceAlert: priceAlerts.alert(for: currentItem.id) != nil,
                onPriceAlert: { priceAlertItem = currentItem },
                shareURL: currentItem.buyURL,
                onAddToAnotherStack: { isShowingDestinationPicker = true },
                onCopyLink: copyLink,
                canEdit: sourceStack.canEdit(userID: session.currentUser?.id),
                canDelete: sourceStack.ownerID == session.currentUser?.id,
                isWishlist: sourceStack.wishlistMode,
                claimStatus: claimStatus,
                canUnclaim: didClaimThisSession,
                originalImageAvailable: currentItem.originalImageURL != nil,
                replacementPhoto: $replacementPhoto,
                onEdit: { isShowingEditor = true },
                onRetryBackgroundRemoval: retryBackgroundRemoval,
                onMarkPurchased: { updateClaimStatus(.purchased) },
                onMakeAvailable: { updateClaimStatus(nil) },
                onDelete: { isConfirmingDelete = true }
            )
        }
        .background(Color.white.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar, .tabBar)
        .navigationTransition(.zoom(sourceID: item.id, in: productTransition))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 10) {
                if sourceStack.wishlistMode, sourceStack.ownerID != session.currentUser?.id {
                    Button(action: claimGift) {
                        Text(claimStatus == nil ? (isClaiming ? "Claiming…" : "Claim this gift") : "Already claimed")
                        .font(.stacksText(size: 16, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.stacksInk.opacity(claimStatus == nil ? 1 : 0.45), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(isClaiming || claimStatus != nil)
                }

                Group {
                    if currentItem.hasExternalPurchaseLink {
                        Link(destination: affiliateResolution?.url ?? currentItem.buyURL) {
                            ProductBuyButton(title: buyButtonTitle, price: currentItem.price > 0 ? currentItem.formattedPrice : "")
                        }
                        .simultaneousGesture(TapGesture().onEnded {
                            Analytics.capture("buy_tapped", [
                                "retailer_host": Analytics.host(of: currentItem.buyURL),
                                "commissionable": affiliateResolution?.isCommissionable == true,
                            ])
                        })
                    } else {
                        ProductBuyButton(title: buyButtonTitle, price: "Add a link", isEnabled: false)
                            .accessibilityLabel("No purchase link available")
                    }
                }

            }
            .padding(.horizontal, 22)
            .padding(.top, 12)
            .padding(.bottom, 10)
        }
        .sheet(isPresented: $isShowingDestinationPicker) {
            if let user = session.currentUser {
                ProductDestinationPicker(
                    item: currentItem,
                    sourceStack: sourceStack,
                    user: user,
                    onSaved: { destination in
                        saveMessage = "Saved to \(destination.displayTitle)"
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            } else {
                ContentUnavailableView("Sign in required", systemImage: "person.crop.circle")
                    .presentationDetents([.medium])
            }
        }
        .sheet(item: $priceAlertItem) { selectedItem in
            PriceAlertEditorSheet(item: selectedItem, stack: sourceStack)
                .presentationDetents([.medium, .large])
                .presentationBackground(.ultraThinMaterial)
        }
        .task { await priceAlerts.refresh() }
        .sheet(isPresented: $isShowingEditor) {
            ProductDetailsEditorSheet(item: currentItem, stackID: sourceStack.id) { updatedItem in
                currentItem = updatedItem
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .alert("Link Copied", isPresented: $didCopyLink) {
            Button("Done", role: .cancel) {}
        } message: {
            Text("The product link is ready to paste.")
        }
        .alert("Saved", isPresented: Binding(
            get: { saveMessage != nil },
            set: { if !$0 { saveMessage = nil } }
        )) {
            Button("Done", role: .cancel) {}
        } message: {
            Text(saveMessage ?? "")
        }
        .confirmationDialog(
            "Delete \(currentItem.title)?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Product", role: .destructive) {
                deleteProduct()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the product from \(sourceStack.displayTitle). This cannot be undone.")
        }
        .alert("Could not delete product", isPresented: Binding(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteError ?? "Please try again.")
        }
        .alert("Could not update product", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "Please try again.")
        }
        .task(id: replacementPhoto) {
            guard let replacementPhoto else { return }
            defer { self.replacementPhoto = nil }
            do {
                guard let data = try await replacementPhoto.loadTransferable(type: Data.self) else {
                    throw AppError.unavailable("That photo could not be loaded.")
                }
                await replacePhoto(with: data)
            } catch is CancellationError {
                return
            } catch {
                actionError = error.localizedDescription
            }
        }
        .task(id: currentItem.buyURL) {
            affiliateResolution = nil
            guard currentItem.hasExternalPurchaseLink else { return }
            affiliateResolution = try? await services.affiliate.resolveLink(
                for: currentItem.buyURL,
                countryCode: Locale.current.region?.identifier
            )
        }
        .task(id: item.id) {
            if sourceStack.ownerID == session.currentUser?.id {
                claimStatus = nil
                currentItem.claimStatus = nil
                return
            }
            guard sourceStack.wishlistMode else { return }
            if let ownStatus = try? await services.claims.myClaimStatus(for: item) {
                didClaimThisSession = true
                claimStatus = ownStatus
                currentItem.claimStatus = ownStatus
            }
        }
    }

    private func copyLink() {
        UIPasteboard.general.url = currentItem.buyURL
        services.haptics.notification(.success)
        didCopyLink = true
    }

    private func deleteProduct() {
        guard sourceStack.ownerID == session.currentUser?.id else { return }
        Task {
            do {
                _ = try await services.stacks.removeItem(id: currentItem.id, from: sourceStack.id)
                services.haptics.notification(.success)
                goBack()
            } catch is CancellationError {
                return
            } catch {
                deleteError = error.localizedDescription
                services.haptics.notification(.error)
            }
        }
    }

    private func claimGift() {
        guard let claimer = session.currentUser, !isClaiming, claimStatus == nil else { return }
        isClaiming = true
        Task {
            defer { isClaiming = false }
            do {
                let claim = try await services.claims.claim(
                    item: currentItem,
                    in: sourceStack,
                    claimerName: claimer.displayName
                )
                claimStatus = claim.status
                currentItem.claimStatus = claim.status
                didClaimThisSession = true
                services.haptics.notification(.success)
            } catch {
                services.haptics.notification(.error)
            }
        }
    }

    private func goBack() {
        services.haptics.impact(.light)
        if let onBack {
            onBack()
        } else {
            dismiss()
        }
    }

    private var buyButtonTitle: String {
        if let host = currentItem.buyURL.host?.lowercased(),
           host == "dickssportinggoods.com" || host.hasSuffix(".dickssportinggoods.com") {
            return "Buy from DICK’S"
        }
        let brand = currentItem.brand.trimmingCharacters(in: .whitespacesAndNewlines)
        return brand.isEmpty ? "Buy" : "Buy from \(brand)"
    }

    private func replacePhoto(with data: Data) async {
        guard !isUpdatingProduct else { return }
        isUpdatingProduct = true
        defer { isUpdatingProduct = false }
        do {
            let originalURL = try await services.storage.uploadImageData(data, preferredName: currentItem.title)
            var updated = currentItem
            updated.originalImageURL = originalURL
            updated.removedBackgroundImageURL = nil
            updated.removalStatus = .processing
            currentItem = try await persisted(updated)
            isUpdatingProduct = false
            await retryBackgroundRemoval()
        } catch is CancellationError {
            return
        } catch {
            actionError = error.localizedDescription
            services.haptics.notification(.error)
        }
    }

    private func retryBackgroundRemoval() {
        Task { await retryBackgroundRemoval() }
    }

    private func retryBackgroundRemoval() async {
        guard !isUpdatingProduct, currentItem.originalImageURL != nil else { return }
        isUpdatingProduct = true
        defer { isUpdatingProduct = false }
        do {
            var updated = currentItem
            updated.removalStatus = .processing
            updated.removedBackgroundImageURL = nil
            currentItem = try await persisted(updated)
            updated = currentItem
            updated.removedBackgroundImageURL = try await services.backgroundRemoval.removeBackground(for: updated)
            updated.removalStatus = updated.removedBackgroundImageURL == nil ? .failed : .complete
            currentItem = try await persisted(updated)
            services.haptics.notification(.success)
        } catch is CancellationError {
            return
        } catch {
            var failed = currentItem
            failed.removalStatus = .failed
            currentItem = (try? await persisted(failed)) ?? failed
            actionError = error.localizedDescription
            services.haptics.notification(.error)
        }
    }

    private func persisted(_ updated: StackItem) async throws -> StackItem {
        let stack = try await services.stacks.updateItem(updated, in: sourceStack.id)
        return stack.items.first(where: { $0.id == updated.id }) ?? updated
    }

    private func updateClaimStatus(_ status: GiftClaimStatus?) {
        Task {
            do {
                claimStatus = try await services.claims.updateStatus(
                    for: currentItem,
                    in: sourceStack,
                    status: status
                )
                currentItem.claimStatus = claimStatus
                if status == nil { didClaimThisSession = false }
                services.haptics.notification(.success)
            } catch is CancellationError {
                return
            } catch {
                actionError = error.localizedDescription
                services.haptics.notification(.error)
            }
        }
    }
}

private struct ProductPageTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.stacksMasthead(size: 56))
            .tracking(-1.8)
            // Reserve only one line when possible. The former 2...4 range
            // kept a blank title line even for short product names.
            .lineLimit(1...2)
            .minimumScaleFactor(0.78)
            .multilineTextAlignment(.center)
            .foregroundStyle(Color.stacksInk)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

private struct ProductStickerStage: View {
    let item: StackItem

    var body: some View {
        StickerImageView(item: item, size: 350)
            .rotationEffect(.degrees(item.placement.rotationDegrees))
            .frame(maxWidth: .infinity)
            .frame(height: 390)
            .padding(.horizontal, 12)
    }
}

private struct ProductNavigationBar: View {
    let onBack: () -> Void
    let hasPriceAlert: Bool
    let onPriceAlert: () -> Void
    let shareURL: URL
    let onAddToAnotherStack: () -> Void
    let onCopyLink: () -> Void
    let canEdit: Bool
    let canDelete: Bool
    let isWishlist: Bool
    let claimStatus: GiftClaimStatus?
    let canUnclaim: Bool
    let originalImageAvailable: Bool
    @Binding var replacementPhoto: PhotosPickerItem?
    let onEdit: () -> Void
    let onRetryBackgroundRemoval: () -> Void
    let onMarkPurchased: () -> Void
    let onMakeAvailable: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.stacksInk)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay {
                        Circle()
                            .stroke(Color.stacksInk.opacity(0.08), lineWidth: 1)
                    }
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")
            .accessibilityIdentifier("product-detail-back")

            Spacer()

            Button(action: onPriceAlert) {
                Image(systemName: hasPriceAlert ? "bell.fill" : "bell")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.stacksInk)
                    .frame(width: 40, height: 40)
                    .stacksGlass(cornerRadius: 20, interactive: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(hasPriceAlert ? "Edit price alert" : "Create price alert")

            Menu {
                ShareLink(item: shareURL) {
                    Label("Share Product", systemImage: "square.and.arrow.up")
                }
                .simultaneousGesture(TapGesture().onEnded { Analytics.capture("product_shared") })

                Button(action: onAddToAnotherStack) {
                    Label("Add to Another Stack", systemImage: "square.stack.3d.up")
                }

                Button(action: onCopyLink) {
                    Label("Copy Product Link", systemImage: "link")
                }

                if canEdit {
                    Divider()
                    Button(action: onEdit) {
                        Label("Edit Details", systemImage: "pencil")
                    }
                    PhotosPicker(selection: $replacementPhoto, matching: .images) {
                        Label("Replace Photo", systemImage: "photo.on.rectangle")
                    }
                    Button(action: onRetryBackgroundRemoval) {
                        Label("Re-run Background Removal", systemImage: "wand.and.stars")
                    }
                    .disabled(!originalImageAvailable)
                }

                if isWishlist, claimStatus == .claimed, canUnclaim {
                    Button(action: onMarkPurchased) {
                        Label("Mark Purchased", systemImage: "checkmark.seal")
                    }
                }

                if isWishlist, claimStatus != nil, canUnclaim {
                    Button(action: onMakeAvailable) {
                        Label("Make Available", systemImage: "arrow.uturn.backward")
                    }
                }

                if canDelete {
                    Divider()
                    Button(role: .destructive, action: onDelete) {
                        Label("Delete Product", systemImage: "trash")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Color.stacksInk)
                    .frame(width: 40, height: 40)
                    .stacksGlass(cornerRadius: 20, interactive: true)
            }
            .accessibilityLabel("Product options")
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .zIndex(2)
    }
}

private struct ProductDescription: View {
    let item: StackItem

    var body: some View {
        Text(item.shortDescription.trimmingCharacters(in: .whitespacesAndNewlines))
            .font(.stacksText(size: 17, weight: .regular))
            .tracking(-0.1)
            .foregroundStyle(Color.stacksInk.opacity(0.72))
            .multilineTextAlignment(.center)
            .lineSpacing(2)
    }
}

private struct ProductInformation: View {
    let item: StackItem

    var body: some View {
        VStack(spacing: 0) {
            ProductInfoCell(label: "Brand", value: item.brand.isEmpty ? "—" : item.brand)
            if item.price > 0 || !CuratedStackCatalog.isCuratedStack(item.stackID) {
                infoDivider
                ProductInfoCell(label: "Price", value: item.formattedPrice)
            }
        }
        .stacksGlass(cornerRadius: 22)
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.64), lineWidth: 1)
        }
    }

    private var infoDivider: some View {
        Divider()
            .overlay(Color.stacksInk.opacity(0.08))
            .padding(.horizontal, 16)
    }
}

private struct ProductDetailsEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appServices) private var services

    let item: StackItem
    let stackID: UUID
    let onSaved: (StackItem) -> Void

    @State private var title: String
    @State private var brand: String
    @State private var price: String
    @State private var currencyCode: String
    @State private var details: String
    @State private var sourceLink: String
    @State private var buyLink: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(item: StackItem, stackID: UUID, onSaved: @escaping (StackItem) -> Void) {
        self.item = item
        self.stackID = stackID
        self.onSaved = onSaved
        _title = State(initialValue: item.title)
        _brand = State(initialValue: item.brand)
        _price = State(initialValue: item.price > 0 ? NSDecimalNumber(decimal: item.price).stringValue : "")
        _currencyCode = State(initialValue: item.currencyCode)
        _details = State(initialValue: item.shortDescription)
        _sourceLink = State(initialValue: item.sourceURL.absoluteString)
        _buyLink = State(initialValue: item.buyURL.absoluteString)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Product") {
                    TextField("Title", text: $title)
                    TextField("Brand", text: $brand)
                    HStack {
                        TextField("Price", text: $price)
                            .keyboardType(.decimalPad)
                        TextField("USD", text: $currencyCode)
                            .textInputAutocapitalization(.characters)
                            .frame(width: 64)
                    }
                    TextField("Your notes", text: $details, axis: .vertical)
                        .lineLimit(2...5)
                }

                Section("Links") {
                    TextField("Product link", text: $sourceLink)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Buy link", text: $buyLink)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle("Edit product")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") {
                        save()
                    }
                    .disabled(isSaving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .alert("Could not save product", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
    }

    private func save() {
        guard !isSaving else { return }
        guard let sourceURL = normalizedURL(sourceLink),
              let buyURL = normalizedURL(buyLink) else {
            errorMessage = "Enter valid product and Buy links."
            return
        }

        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                var updated = item
                updated.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
                updated.brand = brand.trimmingCharacters(in: .whitespacesAndNewlines)
                updated.price = parsedPrice
                updated.currencyCode = currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                updated.shortDescription = details.trimmingCharacters(in: .whitespacesAndNewlines)
                updated.isDescriptionUserAuthored = !updated.shortDescription.isEmpty
                updated.sourceURL = sourceURL
                updated.buyURL = buyURL
                let savedStack = try await services.stacks.updateItem(updated, in: stackID)
                onSaved(savedStack.items.first(where: { $0.id == updated.id }) ?? updated)
                services.haptics.notification(.success)
                dismiss()
            } catch is CancellationError {
                return
            } catch {
                errorMessage = error.localizedDescription
                services.haptics.notification(.error)
            }
        }
    }

    private var parsedPrice: Decimal {
        let clean = price.filter { $0.isNumber || $0 == "." || $0 == "," }
            .replacingOccurrences(of: ",", with: ".")
        return Decimal(string: clean) ?? 0
    }

    private func normalizedURL(_ value: String) -> URL? {
        var value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if !value.lowercased().hasPrefix("http://"), !value.lowercased().hasPrefix("https://") {
            value = "https://\(value)"
        }
        guard let url = URL(string: value), url.host != nil else { return nil }
        return url
    }
}

private struct ProductInfoCell: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 16) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .medium, design: .default))
                .tracking(0.7)
                .foregroundStyle(Color.stacksMutedInk)
                .frame(width: 58, alignment: .leading)
            Spacer(minLength: 0)
            Text(value)
                .font(.stacksText(size: 14, weight: .semibold))
                .foregroundStyle(Color.stacksInk)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .allowsTightening(true)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, minHeight: 62)
    }
}

private struct ProductBuyButton: View {
    let title: String
    let price: String
    var isEnabled = true

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer()
            if !price.isEmpty { Text(price) }
        }
        .font(.stacksText(size: 18, weight: .semibold))
        .tracking(-0.25)
        .foregroundStyle(Color.stacksInk.opacity(isEnabled ? 1 : 0.48))
        .padding(.horizontal, 24)
        .frame(height: 62)
        .stacksGlass(cornerRadius: 31, interactive: isEnabled)
        .overlay {
            Capsule()
                .strokeBorder(Color.white.opacity(0.72), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.10), radius: 15, y: 8)
        .contentShape(Capsule())
    }
}

private struct ProductDestinationPicker: View {
    @Environment(\.appServices) private var services
    @Environment(StacksPro.self) private var pro
    @Environment(\.dismiss) private var dismiss

    let item: StackItem
    let sourceStack: Stack
    let user: UserProfile
    let onSaved: (Stack) -> Void

    @State private var stacks: [Stack] = []
    @State private var errorMessage: String?
    @State private var savingID: UUID?

    private var destinations: [Stack] {
        stacks.filter { $0.id != sourceStack.id }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let errorMessage {
                    ContentUnavailableView(
                        "Couldn’t load your Stacks",
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorMessage)
                    )
                } else if stacks.isEmpty {
                    ProgressView()
                } else if destinations.isEmpty {
                    ContentUnavailableView(
                        "Create another Stack first",
                        systemImage: "square.stack.3d.up",
                        description: Text("You can save (item.title) there once it exists.")
                    )
                } else {
                    List(destinations) { destination in
                        Button {
                            Task { await save(item, to: destination) }
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "square.stack.3d.up.fill")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundStyle(Color.stacksInk)
                                    .frame(width: 32, height: 32)
                                    .background(Color.stacksInk.opacity(0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(destination.displayTitle)
                                        .font(.stacksText(size: 17, weight: .semibold))
                                        .foregroundStyle(Color.stacksInk)
                                    Text("\(destination.items.count) \(destination.items.count == 1 ? "find" : "finds")")
                                        .font(.stacksText(size: 13, weight: .regular))
                                        .foregroundStyle(Color.stacksMutedInk)
                                }

                                Spacer()
                                if savingID == destination.id {
                                    ProgressView()
                                } else {
                                    Image(systemName: "plus")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(Color.stacksInk.opacity(0.54))
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(savingID != nil)
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Color.white.ignoresSafeArea())
            .navigationTitle("Add to Stack")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                do {
                    stacks = try await services.stacks.fetchMyStacks(for: user.id)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func save(_ item: StackItem, to destination: Stack) async {
        guard pro.requireItemSlot(in: destination, resume: {
            Task { await save(item, to: destination) }
        }) else { return }
        savingID = destination.id
        let copiedItem = StackItem(
            id: UUID(),
            stackID: destination.id,
            title: item.title,
            brand: item.brand,
            shortDescription: item.shortDescription,
            price: item.price,
            currencyCode: item.currencyCode,
            sourceURL: item.sourceURL,
            buyURL: item.buyURL,
            affiliateURL: nil,
            originalImageURL: item.originalImageURL,
            removedBackgroundImageURL: item.removedBackgroundImageURL,
            removalStatus: item.removalStatus,
            placement: item.placement,
            hasCustomPlacement: item.hasCustomPlacement,
            addSource: item.addSource,
            claimStatus: item.claimStatus,
            demoGlyph: item.demoGlyph,
            isBookmarked: item.isBookmarked
        )

        do {
            _ = try await services.stacks.addItem(copiedItem, to: destination.id)
            services.haptics.notification(.success)
            onSaved(destination)
            dismiss()
        } catch {
            if StacksPro.isItemLimitError(error) {
                pro.present(.itemLimit) { Task { await save(item, to: destination) } }
                savingID = nil
                return
            }
            errorMessage = error.localizedDescription
        }

        savingID = nil
    }
}

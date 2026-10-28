import SwiftUI
import UIKit

/// Runs after a destination was chosen from the system share sheet. Keeping
/// the network and Vision work in the containing app avoids the strict time
/// limits iOS places on extensions, while making the import feel automatic.
struct SharedLinkImportProgressView: View {
    @Environment(\.appServices) private var services
    @Environment(StacksPro.self) private var pro

    @State private var status = "Getting the product"
    @State private var errorMessage: String?
    @State private var hasStarted = false
    @State private var createdDestination: Stack?

    let link: PendingSharedLink
    let user: UserProfile
    let onSaved: (Stack, StackItem) -> Void
    let onFallback: () -> Void

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(spacing: 18) {
                ProgressView()
                    .controlSize(.large)
                    .tint(Color.stacksInk)

                Text(status)
                    .font(.stacksHeader(size: 25))
                    .foregroundStyle(Color.stacksInk)

                Text(destinationLabel)
                    .font(.stacksText(size: 16, weight: .regular))
                    .foregroundStyle(Color.stacksMutedInk)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
            }
        }
        .task {
            guard !hasStarted else { return }
            hasStarted = true
            await importSharedLink()
        }
        .alert("Couldn’t add this yet", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Try Again") {
                Task {
                    hasStarted = false
                    await importSharedLink()
                }
            }
            Button("Choose Another Stack") {
                onFallback()
            }
        } message: {
            Text(errorMessage ?? "Your link is safely queued and can be retried.")
        }
    }

    @MainActor
    private func importSharedLink() async {
        do {
            status = "Finding your Stack"
            let destination: Stack
            if let createdDestination {
                destination = createdDestination
            } else if let requestedTitle = link.newStackTitle {
                status = "Creating \(requestedTitle)"
                let created = try await services.stacks.createStack(
                    title: requestedTitle,
                    wishlistMode: true,
                    visibility: .private,
                    owner: user
                )
                createdDestination = created
                PendingSharedLinkStore.setDestination(
                    id: created.id,
                    title: created.displayTitle,
                    for: link
                )
                destination = created
            } else {
                let stacks = try await services.stacks.fetchMyStacks(for: user.id)
                guard let destinationID = link.destinationStackID,
                      let existing = stacks.first(where: { $0.id == destinationID }) else {
                    onFallback()
                    return
                }
                destination = existing
            }

            // The queue ID is also the item ID. A restart after a successful
            // server insert can therefore finish without creating a duplicate.
            if let alreadyAdded = destination.items.first(where: { $0.id == link.id }) {
                PendingSharedLinkStore.remove(link)
                onSaved(destination, alreadyAdded)
                return
            }

            guard pro.requireItemSlot(in: destination, resume: {
                Task { await importSharedLink() }
            }) else {
                status = "Stacks Pro is needed to add another item"
                return
            }

            status = "Getting the product"
            var preview = try await services.productSearch.previewProductLink(link.url)
            let shouldRepairTitle = ProductImportedCopy.isGenericTitle(
                preview.title,
                brand: preview.brand,
                sourceURL: link.url
            )
            if preview.importWarning != nil || preview.imageURL == nil || shouldRepairTitle,
               let sharedPage = link.pagePreview,
               let sharedHost = sharedPage.pageURL?.host?.lowercased().replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression),
               let linkHost = link.url.host?.lowercased().replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression),
               sharedHost == linkHost {
                if let title = sharedPage.title,
                   title.count <= 160,
                   (shouldRepairTitle || preview.title.count > 80) {
                    preview.title = title
                } else if let title = link.title, title.count <= 160 {
                    preview.title = title
                }
                if let brand = sharedPage.brand, !brand.isEmpty { preview.brand = brand }
                if preview.price == nil { preview.price = sharedPage.price }
                if let currency = sharedPage.currencyCode { preview.currencyCode = currency }
                if preview.imageURL == nil { preview.imageURL = sharedPage.imageURL }
            }
            preview.title = ProductImportedCopy.conciseTitle(preview.title, brand: preview.brand)
            preview.shortDescription = ""
            var candidates = await ProductPageImageExtractor.productImageURLs(for: preview.sourceURL)
            if let previewImageURL = preview.imageURL { candidates.append(previewImageURL) }

            var seenCandidates = Set<URL>()
            candidates = candidates.filter { seenCandidates.insert($0).inserted }
            var resolvedImage = await ProductPageImageExtractor.firstDownloadableImage(from: candidates)
            if resolvedImage == nil,
               let metadataImageURL = await ProductPageImageExtractor.linkPresentationImageURL(for: preview.sourceURL),
               let metadataImageData = await downloadableImageData(from: metadataImageURL),
               ProductPageImageExtractor.isUsableProductImage(metadataImageData, sourceURL: metadataImageURL) {
                resolvedImage = (metadataImageURL, metadataImageData)
            }

            // A valid shared link should always be saved. Some stores block
            // image hotlinking entirely; retain their product details as a link
            // card rather than showing an error after the share extension did
            // its job.
            let originalImageURL: URL?
            if let resolvedImage {
                do {
                    originalImageURL = try await services.storage.uploadImageData(
                        resolvedImage.data,
                        preferredName: preview.title
                    )
                } catch {
                    originalImageURL = resolvedImage.url
                }
                status = "Removing the background"
            } else {
                originalImageURL = nil
                status = "Saving product details"
            }
            let itemID = link.id
            let pendingItem = StackItem(
                id: itemID,
                stackID: destination.id,
                title: preview.title,
                brand: preview.brand,
                shortDescription: preview.shortDescription,
                price: preview.price ?? 0,
                currencyCode: preview.currencyCode,
                sourceURL: preview.sourceURL,
                buyURL: preview.sourceURL,
                affiliateURL: nil,
                originalImageURL: originalImageURL,
                removedBackgroundImageURL: nil,
                removalStatus: originalImageURL == nil ? .complete : .processing,
                placement: suggestedPlacement(for: destination.items.count),
                addSource: .pastedLink,
                claimStatus: nil,
                demoGlyph: originalImageURL == nil ? "link" : nil
            )
            let cutoutURL = originalImageURL == nil ? nil : try? await services.backgroundRemoval.removeBackground(for: pendingItem)

            status = "Adding to \(destination.displayTitle)"
            var item = pendingItem
            item.removedBackgroundImageURL = cutoutURL
            item.removalStatus = originalImageURL == nil ? .complete : (cutoutURL == nil ? .failed : .complete)
            let savedStack = try await services.stacks.addItem(item, to: destination.id)
            PendingSharedLinkStore.remove(link)
            services.haptics.notification(.success)
            onSaved(savedStack, savedStack.items.first(where: { $0.id == itemID }) ?? item)
        } catch {
            if StacksPro.isItemLimitError(error) {
                pro.present(.itemLimit) { Task { await importSharedLink() } }
                return
            }
            if let stacks = try? await services.stacks.fetchMyStacks(for: user.id),
               let saved = stacks.first(where: { $0.id == (createdDestination?.id ?? link.destinationStackID) }),
               let item = saved.items.first(where: { $0.id == link.id }) {
                PendingSharedLinkStore.remove(link)
                onSaved(saved, item)
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    private var destinationLabel: String {
        let title = link.destinationStackTitle ?? link.newStackTitle
        return title.map { "Adding it to \($0)." } ?? "Preparing your saved link."
    }

    private func suggestedPlacement(for count: Int) -> StickerPlacement {
        let placements = [
            StickerPlacement(xRatio: 0.5, yRatio: 0.46, scale: 0.94, rotationDegrees: 0),
            StickerPlacement(xRatio: 0.31, yRatio: 0.37, scale: 0.72, rotationDegrees: -8),
            StickerPlacement(xRatio: 0.68, yRatio: 0.34, scale: 0.70, rotationDegrees: 7),
            StickerPlacement(xRatio: 0.42, yRatio: 0.66, scale: 0.68, rotationDegrees: 5),
            StickerPlacement(xRatio: 0.70, yRatio: 0.64, scale: 0.66, rotationDegrees: -6)
        ]
        return placements[count % placements.count]
    }

    private func downloadableImageData(from url: URL) async -> Data? {
        if url.isFileURL {
            guard let data = try? Data(contentsOf: url), UIImage(data: data) != nil else { return nil }
            return data
        }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Safari/604.1", forHTTPHeaderField: "User-Agent")
            request.setValue("image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode),
                  UIImage(data: data) != nil else { return nil }
            return data
        } catch {
            return nil
        }
    }
}

struct PendingSharedLinkSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appServices) private var services

    @State private var stacks: [Stack] = []
    @State private var selectedStack: Stack?
    @State private var newStackTitle = ""
    @State private var newStackWishlistMode = true
    @State private var isLoadingStacks = true
    @State private var isCreatingStack = false
    @State private var isPresentingNewStack = false
    @State private var isPresentingDiscardConfirmation = false
    @State private var errorMessage: String?

    let link: PendingSharedLink
    let user: UserProfile
    let onSaved: (Stack, StackItem) -> Void
    let onDeferred: () -> Void
    let onDiscarded: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("What do you want to do with this link?")
                            .font(.stacksHeader(size: 22))
                            .tracking(-0.4)
                            .foregroundStyle(Color.stacksInk)

                        Text("Choose where to put it before continuing.")
                            .font(.stacksText(size: 15, weight: .regular))
                            .foregroundStyle(Color.stacksMutedInk)
                            .padding(.bottom, 8)

                        Text(link.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? link.title! : link.url.host ?? "Shared link")
                            .font(.stacksText(size: 17))
                            .foregroundStyle(Color.stacksInk)
                            .lineLimit(2)
                        Text(link.url.host ?? link.url.absoluteString)
                            .font(.stacksText(size: 14))
                            .foregroundStyle(Color.stacksMutedInk)
                            .lineLimit(1)
                    }
                    .padding(.vertical, 4)
                }

                Section("Add to a Stack") {
                    if isLoadingStacks {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Loading your Stacks")
                                .font(.stacksText(size: 16))
                        }
                    } else {
                        ForEach(stacks) { stack in
                            Button {
                                selectedStack = stack
                            } label: {
                                HStack {
                                    Text(stack.displayTitle)
                                        .font(.stacksText(size: 18))
                                        .foregroundStyle(Color.stacksInk)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14, weight: .regular))
                                        .foregroundStyle(Color.stacksMutedInk)
                                }
                            }
                        }

                        Button {
                            isPresentingNewStack = true
                        } label: {
                            Label("New Stack", systemImage: "plus")
                                .font(.stacksText(size: 17))
                        }
                    }
                }
            }
            .navigationTitle("Shared Link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        isPresentingDiscardConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel("Discard shared link")
                }
            }
            .task {
                await loadStacks()
            }
            .sheet(isPresented: $isPresentingNewStack) {
                newStackSheet
            }
            .confirmationDialog("Discard this shared link?", isPresented: $isPresentingDiscardConfirmation, titleVisibility: .visible) {
                Button("Discard Link", role: .destructive) {
                    PendingSharedLinkStore.remove(link)
                    onDiscarded()
                    dismiss()
                }
            } message: {
                Text("This removes the link from your pending Stacks imports.")
            }
            .alert("Could not create Stack", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .fullScreenCover(item: $selectedStack) { stack in
            ProductLinkImportSheet(
                initialURL: link.url,
                user: user,
                preferredStack: stack,
                locksDestination: true,
                importID: link.id
            ) { savedStack in
                if let savedItem = savedStack.items.first(where: { $0.id == link.id }) {
                    PendingSharedLinkStore.remove(link)
                    onSaved(savedStack, savedItem)
                    dismiss()
                } else {
                    errorMessage = "The product was saved, but Stacks could not confirm it yet. Please try again."
                }
            }
        }
    }

    private var newStackSheet: some View {
        NavigationStack {
            Form {
                Section("Stack") {
                    TextField("Title", text: $newStackTitle)
                        .textInputAutocapitalization(.words)
                        .textContentType(.name)
                    Toggle("Wishlist mode", isOn: $newStackWishlistMode)
                }
            }
            .navigationTitle("New Stack")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresentingNewStack = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createStack()
                    }
                    .disabled(isCreatingStack || newStackTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func loadStacks() async {
        isLoadingStacks = true
        defer { isLoadingStacks = false }
        do {
            let loadedStacks = try await services.stacks.fetchMyStacks(for: user.id)
            stacks = loadedStacks.sorted { $0.updatedAt > $1.updatedAt }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func createStack() {
        guard !isCreatingStack else { return }
        isCreatingStack = true
        let title = newStackTitle.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            defer { isCreatingStack = false }
            do {
                let stack = try await services.stacks.createStack(
                    title: title,
                    wishlistMode: newStackWishlistMode,
                    visibility: .private,
                    owner: user
                )
                services.haptics.notification(.success)
                isPresentingNewStack = false
                selectedStack = stack
            } catch {
                errorMessage = error.localizedDescription
                services.haptics.notification(.error)
            }
        }
    }
}

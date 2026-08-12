import Foundation
import Observation

@MainActor
@Observable
final class StackDetailViewModel {
    var stack: Stack
    var isSaving = false
    var errorMessage: String?

    init(stack: Stack) {
        self.stack = stack
    }

    func addSearchResult(_ result: ProductSearchResult, services: AppServices) async {
        let placement = nextPlacement()
        let item = result.makeStackItem(stackID: stack.id, placement: placement)
        await addItem(item, services: services)
    }

    func addPastedLink(_ link: String, services: AppServices) async {
        guard let url = URL(string: link), url.scheme?.hasPrefix("http") == true else {
            errorMessage = AppError.invalidURL.localizedDescription
            services.haptics.notification(.error)
            return
        }

        do {
            let item = try await services.productSearch.productFromPastedLink(
                url,
                stackID: stack.id,
                placement: nextPlacement()
            )
            await addItem(item, services: services)
        } catch {
            errorMessage = error.localizedDescription
            services.haptics.notification(.error)
        }
    }

    func addManualPhoto(title: String, link: String, imageData: Data?, services: AppServices) async {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else {
            errorMessage = AppError.missingRequiredField("Title").localizedDescription
            services.haptics.notification(.error)
            return
        }
        guard let url = URL(string: link), url.scheme?.hasPrefix("http") == true else {
            errorMessage = AppError.invalidURL.localizedDescription
            services.haptics.notification(.error)
            return
        }

        do {
            let uploadedURL: URL?
            if let imageData {
                uploadedURL = try await services.storage.uploadImageData(imageData, preferredName: cleanTitle)
            } else {
                uploadedURL = nil
            }

            let item = StackItem(
                id: UUID(),
                stackID: stack.id,
                title: cleanTitle,
                brand: "Manual Find",
                shortDescription: "A personal find added by photo, link, and title.",
                price: 0,
                currencyCode: "USD",
                sourceURL: url,
                buyURL: url,
                affiliateURL: try? await services.affiliate.affiliateURL(for: url),
                originalImageURL: uploadedURL,
                removedBackgroundImageURL: nil,
                removalStatus: .processing,
                placement: nextPlacement(),
                addSource: .manualPhoto,
                claimStatus: nil,
                demoGlyph: "📸"
            )
            await addItem(item, services: services)
        } catch {
            errorMessage = error.localizedDescription
            services.haptics.notification(.error)
        }
    }

    private func addItem(_ item: StackItem, services: AppServices) async {
        isSaving = true
        defer { isSaving = false }

        do {
            stack = try await services.stacks.addItem(item, to: stack.id)
            services.haptics.impact(.medium)
            Task { await completeBackgroundRemoval(for: item, services: services) }
        } catch {
            errorMessage = error.localizedDescription
            services.haptics.notification(.error)
        }
    }

    func completeVisibleProcessingItems(services: AppServices) async {
        let items = stack.items.filter { $0.removalStatus.isWorking }
        for item in items {
            await completeBackgroundRemoval(for: item, services: services)
        }
    }

    func copyStack(to owner: UserProfile, services: AppServices) async -> Stack? {
        isSaving = true
        defer { isSaving = false }

        do {
            let copiedStack = try await services.stacks.copyStack(stack, to: owner)

            services.haptics.notification(.success)
            return copiedStack
        } catch {
            errorMessage = error.localizedDescription
            services.haptics.notification(.error)
            return nil
        }
    }

    func updatePlacement(
        for itemID: UUID,
        placement: StickerPlacement,
        services: AppServices
    ) async {
        guard let index = stack.items.firstIndex(where: { $0.id == itemID }) else { return }

        stack.items[index].placement = placement
        stack.items[index].hasCustomPlacement = true

        do {
            stack = try await services.stacks.updateItem(stack.items[index], in: stack.id)
            services.haptics.impact(.light)
        } catch {
            errorMessage = error.localizedDescription
            services.haptics.notification(.error)
        }
    }

    func toggleProductBookmark(for itemID: UUID, services: AppServices) async {
        guard let index = stack.items.firstIndex(where: { $0.id == itemID }) else { return }

        stack.items[index].isBookmarked = !(stack.items[index].isBookmarked ?? false)

        do {
            stack = try await services.stacks.updateItem(stack.items[index], in: stack.id)
            services.haptics.impact(.light)
        } catch {
            errorMessage = error.localizedDescription
            services.haptics.notification(.error)
        }
    }

    func transfer(
        itemID: UUID,
        to destination: Stack,
        removingOriginal: Bool,
        services: AppServices
    ) async {
        guard let item = stack.items.first(where: { $0.id == itemID }) else { return }

        var transferredItem = item
        transferredItem.stackID = destination.id

        do {
            _ = try await services.stacks.addItem(transferredItem, to: destination.id)
            if removingOriginal {
                stack = try await services.stacks.removeItem(id: itemID, from: stack.id)
            }
            services.haptics.notification(.success)
        } catch {
            errorMessage = error.localizedDescription
            services.haptics.notification(.error)
        }
    }

    private func completeBackgroundRemoval(for item: StackItem, services: AppServices) async {
        do {
            let removedURL = try await services.backgroundRemoval.removeBackground(for: item)
            guard let index = stack.items.firstIndex(where: { $0.id == item.id }) else { return }
            stack.items[index].removedBackgroundImageURL = removedURL
            stack.items[index].removalStatus = .complete
            stack = try await services.stacks.updateItem(stack.items[index], in: stack.id)
            services.haptics.impact(.light)
        } catch {
            guard let index = stack.items.firstIndex(where: { $0.id == item.id }) else { return }
            stack.items[index].removalStatus = .failed
            errorMessage = error.localizedDescription
        }
    }

    private func nextPlacement() -> StickerPlacement {
        let count = stack.items.count
        let positions: [StickerPlacement] = [
            StickerPlacement(xRatio: 0.28, yRatio: 0.2, scale: 0.95, rotationDegrees: -6),
            StickerPlacement(xRatio: 0.68, yRatio: 0.28, scale: 1.1, rotationDegrees: 7),
            StickerPlacement(xRatio: 0.4, yRatio: 0.52, scale: 1.0, rotationDegrees: -3),
            StickerPlacement(xRatio: 0.73, yRatio: 0.66, scale: 0.9, rotationDegrees: 5),
            StickerPlacement(xRatio: 0.34, yRatio: 0.82, scale: 1.08, rotationDegrees: -8)
        ]
        return positions[count % positions.count]
    }
}

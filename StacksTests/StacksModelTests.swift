import XCTest
@testable import Stacks
import UIKit

final class StacksModelTests: XCTestCase {
    func testWishlistTitleAddsMarker() {
        let seed = MockSeedData()
        var stack = seed.myStacks[0]
        stack.wishlistMode = true

        XCTAssertEqual(stack.displayTitle, "Summer • Wishlist")
    }

    func testStackTitleUsesMaximumSizeWhenItFits() {
        let resolved = StackTitleMetrics.resolvedFontSize(for: "Hi", availableWidth: 390)

        XCTAssertEqual(resolved, StackTitleTokens.stackTitleMaximumFontSize)
    }

    func testStackTitleReducesSizeForLongNamesWithoutDroppingBelowMinimum() {
        let resolved = StackTitleMetrics.resolvedFontSize(
            for: "A Very Long Stack Name That Still Needs One Line",
            availableWidth: 390
        )

        XCTAssertLessThan(resolved, StackTitleTokens.stackTitleMaximumFontSize)
        XCTAssertGreaterThanOrEqual(resolved, StackTitleTokens.stackTitleMinimumFontSize)
    }

    func testBackgroundRemovalWorkingStates() {
        XCTAssertTrue(BackgroundRemovalStatus.queued.isWorking)
        XCTAssertTrue(BackgroundRemovalStatus.processing.isWorking)
        XCTAssertFalse(BackgroundRemovalStatus.complete.isWorking)
        XCTAssertFalse(BackgroundRemovalStatus.failed.isWorking)
    }

    func testProductSearchResultCreatesProcessingStackItem() {
        let stackID = UUID()
        let result = ProductSearchResult(
            id: UUID(),
            title: "Lamp",
            brand: "Studio",
            price: 48,
            currencyCode: "USD",
            sourceURL: URL(string: "https://example.com/lamp")!,
            imageURL: nil,
            shortDescription: "A test lamp.",
            demoGlyph: "💡"
        )

        let item = result.makeStackItem(stackID: stackID, placement: .centered)

        XCTAssertEqual(item.stackID, stackID)
        XCTAssertEqual(item.title, "Lamp")
        XCTAssertEqual(item.removalStatus, .processing)
        XCTAssertEqual(item.addSource, .search)
        XCTAssertEqual(item.purchaseURL, item.buyURL)
    }

    func testMockRepositoryCreatesStack() async throws {
        let seed = MockSeedData()
        let repository = MockStackRepository(seed: seed)

        let stack = try await repository.createStack(
            title: "Birthday Ideas",
            wishlistMode: true,
            owner: seed.currentUser
        )

        XCTAssertEqual(stack.title, "Birthday Ideas")
        XCTAssertTrue(stack.wishlistMode)
        XCTAssertEqual(stack.ownerID, seed.currentUserID)
    }

    func testMockAuthPersistsCompletedOnboarding() async throws {
        let seed = MockSeedData()
        let auth = MockAuthService(seed: seed)
        let signedIn = try await auth.signInWithApple()

        XCTAssertFalse(signedIn.hasCompletedOnboarding)
        try await auth.completeOnboarding(for: signedIn.userID)

        let restored = try await auth.restoreSession()
        XCTAssertTrue(restored?.hasCompletedOnboarding == true)
    }

    @MainActor
    func testCopyStackCreatesAnOwnedItemPreservingDuplicate() async throws {
        let services = AppServices.mock()
        let currentUser = MockSeedData().currentUser
        let publicStack = try await services.stacks.fetchDiscoverStacks(query: nil)[0]
        let viewModel = StackDetailViewModel(stack: publicStack)

        let copiedStack = await viewModel.copyStack(to: currentUser, services: services)
        let myStacks = try await services.stacks.fetchMyStacks(for: currentUser.id)

        XCTAssertEqual(copiedStack?.ownerID, currentUser.id)
        XCTAssertEqual(copiedStack?.items.count, publicStack.items.count)
        XCTAssertTrue(myStacks.contains { $0.id == copiedStack?.id })
    }

    func testPendingSharedLinkStoreRoundTrips() throws {
        PendingSharedLinkStore.clearAll()
        let link = PendingSharedLink(url: URL(string: "https://example.com/jacket")!, title: "Jacket")

        try PendingSharedLinkStore.save(link)

        XCTAssertEqual(PendingSharedLinkStore.load(), link)
        PendingSharedLinkStore.clear()
        XCTAssertNil(PendingSharedLinkStore.load())
    }

    func testPendingSharedLinkStoreQueuesLinksInOrder() throws {
        PendingSharedLinkStore.clearAll()
        let first = PendingSharedLink(url: URL(string: "https://example.com/first")!)
        let second = PendingSharedLink(url: URL(string: "https://example.com/second")!)

        try PendingSharedLinkStore.save(first)
        try PendingSharedLinkStore.save(second)

        XCTAssertEqual(PendingSharedLinkStore.load(), first)
        PendingSharedLinkStore.remove(first)
        XCTAssertEqual(PendingSharedLinkStore.load(), second)
        PendingSharedLinkStore.clearAll()
    }

    func testDiscoverSeedDataDoesNotStartWithProcessingSavedItems() {
        let seed = MockSeedData()
        let savedItems = seed.discoverStacks
            .filter(\.isBookmarked)
            .flatMap(\.items)

        XCTAssertFalse(savedItems.contains { $0.removalStatus.isWorking })
    }

    func testProductPageImageExtractorPrefersFrontWhiteProductImage() {
        let html = """
        <meta property="og:image" content="http://example.com/cdn/shop/files/lifestyle-scene.jpg">
        <img alt="Model wearing oven" src="https://example.com/cdn/shop/files/model-side.jpg">
        <img alt="Arc XL front facing product white background" src="https://example.com/cdn/shop/files/arc-xl-front-white-1200x1200.png">
        <img alt="Logo" src="https://example.com/logo.png">
        <img src="sizeImage(item.image, 800)">
        """

        let imageURL = ProductPageImageExtractor.bestImageURL(
            in: html,
            baseURL: URL(string: "https://example.com/products/arc-xl")!
        )

        XCTAssertEqual(
            imageURL?.absoluteString,
            "https://example.com/cdn/shop/files/arc-xl-front-white-1200x1200.png"
        )
    }

    func testProductPagePreviewReadsJSONLDProductFields() {
        let html = """
        <script type="application/ld+json">
        {
          "@context": "https://schema.org",
          "@type": "Product",
          "name": "Arc XL Pizza Oven",
          "brand": { "@type": "Brand", "name": "Gozney" },
          "description": "A <b>live-fire</b> pizza oven.",
          "image": "https://cdn.example.com/products/arc-xl-front-white.png",
          "offers": { "@type": "Offer", "price": "1999.00", "priceCurrency": "USD" }
        }
        </script>
        <meta property="og:image" content="https://cdn.example.com/products/arc-xl-front-white.png">
        """

        let preview = ProductPageImageExtractor.preview(
            in: html,
            sourceURL: URL(string: "https://example.com/products/arc-xl")!
        )

        XCTAssertEqual(preview.title, "Arc XL Pizza Oven")
        XCTAssertEqual(preview.brand, "Gozney")
        XCTAssertEqual(preview.shortDescription, "A live-fire pizza oven.")
        XCTAssertEqual(preview.price, Decimal(string: "1999.00"))
        XCTAssertEqual(preview.currencyCode, "USD")
        XCTAssertEqual(preview.imageURL?.absoluteString, "https://cdn.example.com/products/arc-xl-front-white.png")
    }

    func testProductPagePreviewUsesEmbeddedShopifyProductMedia() {
        let html = #"""
        <script>
        let product_data = {
          "title": "Arc XL",
          "vendor": "Gozney",
          "description": "A compact live-fire oven.",
          "price": 99999,
          "images": [
            "//cdn.example.com/cdn/shop/files/arc-cinemagraph-frame.png",
            "//cdn.example.com/cdn/shop/files/arc-xl-front-white-1600.png"
          ]
        };
        </script>
        <meta property="og:image" content="https://cdn.example.com/cdn/shop/files/arc-cinemagraph-frame.png">
        """#

        let preview = ProductPageImageExtractor.preview(
            in: html,
            sourceURL: URL(string: "https://example.com/products/arc-xl")!
        )

        XCTAssertEqual(preview.title, "Arc XL")
        XCTAssertEqual(preview.brand, "Gozney")
        XCTAssertEqual(preview.shortDescription, "A compact live-fire oven.")
        XCTAssertEqual(preview.price, Decimal(string: "999.99"))
        XCTAssertEqual(preview.imageURL?.absoluteString, "https://cdn.example.com/cdn/shop/files/arc-xl-front-white-1600.png")
    }

    func testProductPagePreviewUsesOpenGraphAndCreatesEditableDraft() {
        let sourceURL = URL(string: "https://shop.example.com/products/linen-shirt")!
        let html = """
        <meta property="og:title" content="Linen Shirt">
        <meta property="og:description" content="Easy &amp; light.">
        <meta property="og:image" content="/images/linen-shirt-front-white.jpg">
        <meta property="product:price:amount" content="$80.00">
        <meta property="product:price:currency" content="USD">
        """

        let preview = ProductPageImageExtractor.preview(in: html, sourceURL: sourceURL)
        var draft = ProductImportDraft(preview: preview)

        XCTAssertEqual(preview.title, "Linen Shirt")
        XCTAssertEqual(preview.shortDescription, "Easy & light.")
        XCTAssertEqual(preview.price, Decimal(string: "80.00"))
        XCTAssertEqual(preview.imageURL?.absoluteString, "https://shop.example.com/images/linen-shirt-front-white.jpg")
        XCTAssertTrue(draft.isValid)

        draft.title = ""
        XCTAssertFalse(draft.isValid)
    }

    func testAppleVisionBackgroundRemovalWritesTransparentPNG() async throws {
        guard let image = UIImage(named: "OnboardingTShirt") else {
            return XCTFail("Bundled product image is unavailable")
        }
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = 1
        let whiteBackgroundImage = UIGraphicsImageRenderer(
            size: CGSize(width: 640, height: 640),
            format: format
        ).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 640, height: 640))
            image.draw(in: CGRect(x: 72, y: 120, width: 496, height: 400))
        }
        guard let data = whiteBackgroundImage.pngData() else {
            return XCTFail("Could not create white-background product image")
        }
        let inputURL = FileManager.default.temporaryDirectory.appendingPathComponent("vision-input.png")
        try data.write(to: inputURL, options: .atomic)
        let item = StackItem(
            id: UUID(), stackID: UUID(), title: "T-Shirt", brand: "Test",
            shortDescription: "", price: 0, currencyCode: "USD",
            sourceURL: URL(string: "https://example.com/t-shirt")!,
            buyURL: URL(string: "https://example.com/t-shirt")!, affiliateURL: nil,
            originalImageURL: inputURL, removedBackgroundImageURL: nil,
            removalStatus: .processing, placement: .centered, addSource: .pastedLink,
            claimStatus: nil, demoGlyph: nil
        )

        do {
            let outputURL = try await AppleVisionBackgroundRemovalService().removeBackground(for: item)
            XCTAssertTrue(outputURL?.isFileURL == true)
            XCTAssertNotNil(outputURL.flatMap { UIImage(contentsOfFile: $0.path) })
            XCTAssertNotEqual(try Data(contentsOf: outputURL!), data)
        } catch {
            XCTFail(error.localizedDescription)
        }
    }
}

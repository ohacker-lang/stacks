import XCTest
@testable import Stacks
import UIKit

final class StacksModelTests: XCTestCase {
    @MainActor
    func testRevenueCatIdentifiersMatchStacksProConfiguration() {
        XCTAssertEqual(StacksPro.entitlementID, "stacks_pro")
        XCTAssertEqual(StacksPro.offeringID, "Stacks Pro")
        XCTAssertEqual(StacksPro.monthlyID, "stacks.pro.monthly")
        XCTAssertEqual(StacksPro.annualID, "stacks.pro.annual")
    }

    func testSafariPageMetadataSurvivesShareQueueAndOldLinksStillDecode() throws {
        let productURL = URL(string: "https://www.grailed.com/listings/88747318-kapital-surf-hoodie")!
        let preview = try XCTUnwrap(SharedPagePreview(dictionary: [
            "url": productURL.absoluteString,
            "title": "Kapital Surf Hoodie",
            "brand": "Kapital",
            "imageURL": "https://cdn.example.com/surf-1200.jpg",
            "price": "325",
            "currencyCode": "usd"
        ]))
        let queued = PendingSharedLink(url: productURL, pagePreview: preview)
        let data = try JSONEncoder().encode(queued)
        let restored = try JSONDecoder().decode(PendingSharedLink.self, from: data)
        XCTAssertEqual(restored.pagePreview?.brand, "Kapital")
        XCTAssertEqual(restored.pagePreview?.price, 325)
        XCTAssertEqual(restored.pagePreview?.currencyCode, "USD")

        var oldPayload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        oldPayload.removeValue(forKey: "pagePreview")
        let oldData = try JSONSerialization.data(withJSONObject: oldPayload)
        XCTAssertNil(try JSONDecoder().decode(PendingSharedLink.self, from: oldData).pagePreview)
    }

    func testBlockedDicksTokyoLinkKeepsMakerAndDoesNotInventPhotoOrPrice() {
        let url = URL(string: "https://www.dickssportinggoods.com/p/adidas-womens-tokyo-shoes-25adiwcasutkyblkffzfu/25adiwcasutkyblkffzfu?sku=27778878")!
        let preview = ProductPageImageExtractor.knownProductPreview(for: url)
        XCTAssertEqual(preview?.title, "adidas Tokyo Shoes")
        XCTAssertEqual(preview?.brand, "adidas")
        XCTAssertNil(preview?.imageURL)
        XCTAssertNil(preview?.price)
    }

    func testTinyPreviewAndLogoCannotBecomeProductSticker() {
        let small = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 120)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 120, height: 120))
        }.pngData()!
        XCTAssertFalse(ProductPageImageExtractor.isUsableProductImage(small, sourceURL: URL(string: "https://example.com/product.jpg")!))
        let large = UIGraphicsImageRenderer(size: CGSize(width: 900, height: 900)).image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 900, height: 900))
        }.pngData()!
        XCTAssertTrue(ProductPageImageExtractor.isUsableProductImage(large, sourceURL: URL(string: "https://example.com/product.jpg")!))
        XCTAssertFalse(ProductPageImageExtractor.isUsableProductImage(large, sourceURL: URL(string: "https://example.com/logo.png")!))
        XCTAssertTrue(ProductPageImageExtractor.isUsableProductImage(large, sourceURL: URL(string: "https://example.com/products/logo-hoodie.jpg")!))
    }
    func testWishlistTitleDoesNotAddMarker() {
        let seed = MockSeedData()
        var stack = seed.myStacks[0]
        stack.wishlistMode = true

        XCTAssertEqual(stack.displayTitle, stack.title)
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

    func testAutomaticCollageFillsTwoByTwoBeforeStartingAnotherPage() {
        let items = Array(MockSeedData().myStacks[0].items.prefix(5))
        let width: CGFloat = 360

        let one = EditorialCollageLayout(items: Array(items.prefix(1)), canvasSize: CGSize(width: width, height: 520))
        XCTAssertEqual(one.placement(for: 0).position.x, width / 2)

        let two = EditorialCollageLayout(items: Array(items.prefix(2)), canvasSize: CGSize(width: width, height: 520))
        XCTAssertEqual(two.placement(for: 0).position.x, 90)
        XCTAssertEqual(two.placement(for: 1).position.x, 270)
        XCTAssertEqual(two.placement(for: 0).position.y, two.placement(for: 1).position.y)

        let three = EditorialCollageLayout(items: Array(items.prefix(3)), canvasSize: CGSize(width: width, height: 520))
        XCTAssertEqual(three.placement(for: 0).position.x, 90)
        XCTAssertEqual(three.placement(for: 1).position.x, 270)
        XCTAssertEqual(three.placement(for: 2).position.x, width / 2)
        XCTAssertEqual(three.placement(for: 0).position.y, three.placement(for: 1).position.y)
        XCTAssertGreaterThan(three.placement(for: 2).position.y, three.placement(for: 0).position.y)

        let four = EditorialCollageLayout(items: Array(items.prefix(4)), canvasSize: CGSize(width: width, height: 520))
        XCTAssertEqual(four.placement(for: 3).position.x, 270)
        XCTAssertEqual(four.placement(for: 3).position.y, four.placement(for: 2).position.y)

        let five = EditorialCollageLayout(items: items, canvasSize: CGSize(width: width, height: EditorialCollageLayout.canvasHeight(for: 5)))
        XCTAssertEqual(five.placement(for: 4).position.x, width / 2)
        XCTAssertGreaterThan(five.placement(for: 4).position.y, five.placement(for: 3).position.y)
    }

    func testAutomaticCollageKeepsDeliberatelyMovedItemInPlace() {
        var items = Array(MockSeedData().myStacks[0].items.prefix(4))
        items[1].hasCustomPlacement = true
        items[1].placement = StickerPlacement(xRatio: 0.62, yRatio: 0.42, scale: 1, rotationDegrees: 8)

        let layout = EditorialCollageLayout(items: items, canvasSize: CGSize(width: 360, height: 520))
        XCTAssertEqual(layout.placement(for: 1).position.x, 223.2, accuracy: 0.01)
        XCTAssertEqual(layout.placement(for: 1).position.y, 218.4, accuracy: 0.01)
        XCTAssertEqual(layout.placement(for: 1).rotation, 8)
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
            visibility: .publicLink,
            owner: seed.currentUser
        )

        XCTAssertEqual(stack.title, "Birthday Ideas")
        XCTAssertTrue(stack.wishlistMode)
        XCTAssertEqual(stack.ownerID, seed.currentUserID)
    }

    func testShareLinksOpenBrowserAndKeepLinkTokenForLinkOnlyStacks() {
        let seed = MockSeedData()
        var stack = seed.myStacks[0]
        let token = UUID()
        stack.visibility = .publicLink
        stack.publicLinkToken = token

        let url = stack.shareURL
        let components = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
        XCTAssertEqual(components?.scheme, "https")
        XCTAssertEqual(components?.host, "stacks.spot")
        XCTAssertEqual(components?.path, "/s/\(stack.id.uuidString)")
        XCTAssertEqual(components?.queryItems?.first(where: { $0.name == "token" })?.value, token.uuidString)

        stack.visibility = .private
        XCTAssertNil(stack.shareURL)
        stack.visibility = .publicDiscover
        XCTAssertNotNil(stack.shareURL)
        XCTAssertNil(URLComponents(url: stack.shareURL!, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "token" }))
    }

    func testUniversalStackLinksParseOnlyCanonicalSharedPaths() {
        let stackID = UUID()
        let token = UUID()
        let link = SharedStackUniversalLink(
            url: URL(string: "https://stacks.spot/s/\(stackID.uuidString)?token=\(token.uuidString)")!
        )
        XCTAssertEqual(link?.stackID, stackID)
        XCTAssertEqual(link?.token, token)
        XCTAssertNil(SharedStackUniversalLink(url: URL(string: "https://example.com/s/\(stackID.uuidString)")!))
        XCTAssertNil(SharedStackUniversalLink(url: URL(string: "https://stacks.spot/s/\(stackID.uuidString)?token=bad")!))
    }

    func testCollaboratorCanEditOnlyWhileCollaborationIsEnabled() {
        let seed = MockSeedData()
        let collaborator = seed.isabella
        var stack = seed.myStacks[0]
        stack.collaborators = [
            Collaborator(
                id: collaborator.id,
                user: collaborator,
                permission: .edit,
                invitedAt: Date()
            )
        ]

        stack.collaborationEnabled = false
        XCTAssertFalse(stack.canEdit(userID: collaborator.id))

        stack.collaborationEnabled = true
        XCTAssertTrue(stack.canEdit(userID: collaborator.id))
        XCTAssertTrue(stack.canEdit(userID: stack.ownerID))
    }

    func testEachCollabContactGetsAUniqueOneUseInvite() async throws {
        let seed = MockSeedData()
        let collaboration = MockCollaborationService(seed: seed)
        var stack = seed.myStacks[0]
        stack.collaborationEnabled = true

        let first = try await collaboration.createInvite(to: stack, permission: .edit)
        let second = try await collaboration.createInvite(to: stack, permission: .edit)

        XCTAssertNotEqual(first.token, second.token)
        let acceptedFirstStackID = try await collaboration.acceptInvite(token: first.token)
        XCTAssertEqual(acceptedFirstStackID, stack.id)

        do {
            _ = try await collaboration.acceptInvite(token: first.token)
            XCTFail("A Collab invite must only be accepted once.")
        } catch {
            XCTAssertEqual(error as? AppError, .notFound)
        }

        let acceptedSecondStackID = try await collaboration.acceptInvite(token: second.token)
        XCTAssertEqual(acceptedSecondStackID, stack.id)
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

    func testPendingSharedLinkStoreKeepsSameURLForDifferentStacks() throws {
        PendingSharedLinkStore.clearAll()
        let url = URL(string: "https://example.com/shoes")!
        let first = PendingSharedLink(url: url, destinationStackID: UUID(), destinationStackTitle: "Shoes")
        let second = PendingSharedLink(url: url, destinationStackID: UUID(), destinationStackTitle: "Wishlist")

        try PendingSharedLinkStore.save(first)
        try PendingSharedLinkStore.save(second)

        XCTAssertEqual(PendingSharedLinkStore.load(), first)
        PendingSharedLinkStore.remove(first)
        XCTAssertEqual(PendingSharedLinkStore.load(), second)
        PendingSharedLinkStore.clearAll()
    }

    func testShareDestinationsContainOnlyTheSignedInUsersOwnedStacks() async throws {
        let seed = MockSeedData()
        let repository = MockStackRepository(seed: seed)
        let destinations = try await repository.fetchOwnedStackDestinations(for: seed.currentUser)
        let ownedStacks = seed.myStacks.filter { $0.ownerID == seed.currentUser.id }

        XCTAssertEqual(Set(destinations.map(\.id)), Set(ownedStacks.map(\.id)))
        XCTAssertEqual(destinations.map(\.id), destinations.sorted {
            ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast)
        }.map(\.id))
        XCTAssertTrue(destinations.allSatisfy { !$0.title.isEmpty })
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

    func testBlockedListingFallbackKeepsDescriptiveSlug() {
        let grailed = URL(string: "https://www.grailed.com/listings/88747318-kapital-surf-hoodie")!
        let target = URL(string: "https://www.target.com/p/solid-striped-women-s-mid-rise-poplin-drawstring-pull-on-pants-blue-white-striped/-/A-95074331")!
        XCTAssertEqual(ProductPageImageExtractor.fallbackTitle(for: grailed), "Kapital Surf Hoodie")
        XCTAssertEqual(
            ProductPageImageExtractor.fallbackTitle(for: target),
            "Solid Striped Women S Mid Rise Poplin Drawstring Pull On Pants Blue White Striped"
        )
    }

    func testAbercrombieChallengeFallsBackToProductSlugWithoutArtwork() {
        let source = URL(string: "https://www.abercrombie.com/shop/us/kids/p/long-sleeve-vintage-inspired-tee-61005367?pp=0")!
        let challenge = """
        <!doctype html>
        <html>
          <head>
            <title>Client Challenge</title>
            <meta property="og:title" content="Abercrombie &amp; Fitch">
            <meta property="og:image" content="https://example.com/random-campaign.jpg">
          </head>
        </html>
        """

        let preview = ProductPageImageExtractor.preview(in: challenge, sourceURL: source)

        XCTAssertEqual(preview.title, "Long Sleeve Vintage Inspired Tee")
        XCTAssertEqual(preview.brand, "Abercrombie & Fitch")
        XCTAssertNil(preview.imageURL)
    }

    func testStructuredProductPhotoBeatsSocialIconAndLowResolutionThumbnail() {
        let source = URL(string: "https://www.chanel.com/us/fragrance/p/107930/bleu-de-chanel-deodorant-spray/")!
        let html = """
        <title>BLEU DE CHANEL Deodorant Spray | CHANEL</title>
        <meta property="og:title" content="BLEU DE CHANEL Deodorant Spray | CHANEL">
        <meta property="og:image" content="https://www.chanel.com/favicon-192.png">
        <script type="application/ld+json">
        {"@type":"Product","name":"BLEU DE CHANEL","brand":{"name":"CHANEL"},
         "image":["https://www.chanel.com/product-107930-384x384.jpg",
                  "https://www.chanel.com/product-107930-1024x1024.jpg"]}
        </script>
        """
        let preview = ProductPageImageExtractor.preview(in: html, sourceURL: source)
        XCTAssertEqual(preview.title, "BLEU DE CHANEL Deodorant Spray")
        XCTAssertEqual(preview.brand, "CHANEL")
        XCTAssertEqual(preview.imageURL?.lastPathComponent, "product-107930-1024x1024.jpg")
    }

    func testImageExtractorRequestsLargerRetailerRenditionWhenAvailable() {
        let source = URL(string: "https://www.chanel.com/us/fragrance/p/107930/bleu-de-chanel-deodorant-spray/")!
        let html = """
        <script type="application/ld+json">
        {"@type":"Product","name":"BLEU DE CHANEL Deodorant Spray",
         "image":"https://www.chanel.com/images/t_one/w_620/product-107930-packshot.jpg"}
        </script>
        """
        XCTAssertEqual(
            ProductPageImageExtractor.bestImageURL(in: html, baseURL: source)?.absoluteString,
            "https://www.chanel.com/images/t_one/w_1200/product-107930-packshot.jpg"
        )
    }

    func testProductPagePreviewUsesSharedVariantInsteadOfDefaultOpenGraphImage() {
        let sourceURL = URL(string: "https://example.com/products/pan?variant=vanilla")!
        let html = """
        <script type="application/ld+json">
        {
          "@context": "https://schema.org",
          "@type": "ProductGroup",
          "hasVariant": [
            {
              "@type": "Product",
              "name": "Always Pan - Spice",
              "image": "https://cdn.example.com/spice-1200.jpg",
              "offers": { "url": "https://example.com/products/pan?variant=spice", "price": "89", "priceCurrency": "USD" }
            },
            {
              "@type": "Product",
              "name": "Always Pan - Vanilla Bean",
              "image": "https://cdn.example.com/vanilla-1200.jpg",
              "offers": { "url": "https://example.com/products/pan?variant=vanilla", "price": "89", "priceCurrency": "USD" }
            }
          ]
        }
        </script>
        <meta property="og:image" content="https://cdn.example.com/spice-1200.jpg">
        """

        let preview = ProductPageImageExtractor.preview(in: html, sourceURL: sourceURL)

        XCTAssertEqual(preview.title, "Always Pan - Vanilla Bean")
        XCTAssertEqual(preview.imageURL?.absoluteString, "https://cdn.example.com/vanilla-1200.jpg")
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

    func testMarketplaceSEOTitleBecomesHumanReadable() {
        let title = ProductImportedCopy.conciseTitle(
            "Retro Vintage Oakley Straight Jacket 99 Muzm Sunglasses Silver Frames/Blue Lenses Black Flame",
            brand: "Etsy"
        )

        XCTAssertEqual(title, "Oakley Straight Jacket Sunglasses")
        XCTAssertEqual(
            ProductImportedCopy.conciseTitle(
                "Retro Vintage Oakley Straight Jacket 99 Muzm Sunglasses Silver Frames/Blue Lenses Black Flame",
                brand: "NarongchaiCrafts"
            ),
            "Oakley Straight Jacket Sunglasses"
        )
    }

    func testRetailTitlesDropVariantsButKeepMeaningfulModelNames() {
        XCTAssertEqual(
            ProductImportedCopy.conciseTitle("peptide eye prep rhode logo", brand: "rhode"),
            "peptide eye prep"
        )
        XCTAssertEqual(
            ProductImportedCopy.conciseTitle(
                "Rhode Lip Balm - Toast | Shop Rhode",
                brand: "Rhode"
            ),
            "Rhode Lip Balm"
        )
        XCTAssertEqual(
            ProductImportedCopy.conciseTitle(
                "Rhode Lip Balm Toast 10ml",
                brand: "Rhode"
            ),
            "Rhode Lip Balm"
        )
        XCTAssertEqual(
            ProductImportedCopy.conciseTitle(
                "Rhode Peptide Lip Tint Toast 10ml | Rhode Skin",
                brand: "Rhode"
            ),
            "Rhode Peptide Lip Tint"
        )
        XCTAssertEqual(
            ProductImportedCopy.conciseTitle(
                "Nike Air Max 90 Shoes | Nike",
                brand: "Nike"
            ),
            "Nike Air Max 90 Shoes"
        )
        XCTAssertEqual(
            ProductImportedCopy.conciseTitle(
                "Nike Women's Air Max 90 Shoes in White | Nike",
                brand: "Nike"
            ),
            "Nike Air Max 90 Shoes"
        )
    }

    func testBarcodeImportUsesShortTitleAndNoCatalogDescription() {
        let catalogImage = URL(string: "https://catalog.example.com/ring-front.jpg")!
        let preview = ProductLinkPreview(
            sourceURL: URL(string: "https://shop.example.com/ring")!,
            title: "Aura ring Gen 3 - Horizon - size B - Silver",
            brand: "Aura",
            shortDescription: "Catalog marketing copy",
            price: 299,
            currencyCode: "USD",
            imageURL: catalogImage
        )
        let draft = ProductImportDraft(preview: preview)

        XCTAssertEqual(draft.title, "Aura ring")
        XCTAssertEqual(draft.shortDescription, "")
        XCTAssertEqual(draft.price, 299)
        XCTAssertEqual(draft.imageURL, catalogImage)
        XCTAssertEqual(
            ProductImportedCopy.conciseTitle(
                "Aura ring Gen 3 - Horizon - size B - Silver", brand: "Aura"
            ),
            "Aura ring"
        )
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

    func testWhiteProductOnGrayStudioBackgroundBecomesARealCutout() async throws {
        let size = CGSize(width: 400, height: 500)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = 1
        let studioPhoto = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor(white: 0.82, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.white.setFill()
            UIBezierPath(roundedRect: CGRect(x: 130, y: 60, width: 140, height: 380), cornerRadius: 42).fill()
            UIColor.black.setFill()
            context.fill(CGRect(x: 142, y: 95, width: 116, height: 12))
        }
        let inputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("gray-studio-\(UUID().uuidString).png")
        try XCTUnwrap(studioPhoto.pngData()).write(to: inputURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: inputURL) }

        let item = StackItem(
            id: UUID(), stackID: UUID(), title: "White socks", brand: "Test",
            shortDescription: "", price: 0, currencyCode: "USD",
            sourceURL: URL(string: "https://example.com/socks")!,
            buyURL: URL(string: "https://example.com/socks")!, affiliateURL: nil,
            originalImageURL: inputURL, removedBackgroundImageURL: nil,
            removalStatus: .processing, placement: .centered, addSource: .pastedLink,
            claimStatus: nil, demoGlyph: nil
        )
        let removedURL = try await AppleVisionBackgroundRemovalService().removeBackground(for: item)
        let outputURL = try XCTUnwrap(removedURL)
        let cutout = try XCTUnwrap(UIImage(contentsOfFile: outputURL.path)?.cgImage)
        XCTAssertLessThan(cutout.width, Int(size.width), "The gray photo canvas should be trimmed away")

        var pixels = [UInt8](repeating: 0, count: cutout.width * cutout.height * 4)
        let context = try XCTUnwrap(CGContext(
            data: &pixels, width: cutout.width, height: cutout.height,
            bitsPerComponent: 8, bytesPerRow: cutout.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(cutout, in: CGRect(x: 0, y: 0, width: cutout.width, height: cutout.height))
        XCTAssertEqual(pixels[3], 0, "The background must be transparent")
        let center = ((cutout.height / 2) * cutout.width + cutout.width / 2) * 4
        XCTAssertGreaterThan(pixels[center + 3], 240, "The white product must remain visible")
    }
}

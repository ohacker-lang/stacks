import Foundation

struct ProductLinkPreview: Identifiable, Hashable, Sendable {
    let id: UUID
    var sourceURL: URL
    var title: String
    var brand: String
    var shortDescription: String
    var price: Decimal?
    var currencyCode: String
    var imageURL: URL?

    init(
        id: UUID = UUID(),
        sourceURL: URL,
        title: String,
        brand: String = "",
        shortDescription: String = "",
        price: Decimal? = nil,
        currencyCode: String = "USD",
        imageURL: URL? = nil
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.title = title
        self.brand = brand
        self.shortDescription = shortDescription
        self.price = price
        self.currencyCode = currencyCode
        self.imageURL = imageURL
    }
}

struct ProductImportDraft: Hashable, Sendable {
    var sourceURL: URL
    var buyURL: URL
    var title: String
    var brand: String
    var shortDescription: String
    var price: Decimal?
    var currencyCode: String
    var imageURL: URL?

    init(preview: ProductLinkPreview) {
        sourceURL = preview.sourceURL
        buyURL = preview.sourceURL
        title = preview.title
        brand = preview.brand
        shortDescription = preview.shortDescription
        price = preview.price
        currencyCode = preview.currencyCode
        imageURL = preview.imageURL
    }

    var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && sourceURL.scheme?.hasPrefix("http") == true
            && buyURL.scheme?.hasPrefix("http") == true
    }
}

struct ProductSearchResult: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var title: String
    var brand: String
    var price: Decimal
    var currencyCode: String
    var sourceURL: URL
    var imageURL: URL?
    var shortDescription: String
    var demoGlyph: String?

    func makeStackItem(stackID: UUID, placement: StickerPlacement) -> StackItem {
        StackItem(
            id: UUID(),
            stackID: stackID,
            title: title,
            brand: brand,
            shortDescription: shortDescription,
            price: price,
            currencyCode: currencyCode,
            sourceURL: sourceURL,
            buyURL: sourceURL,
            affiliateURL: nil,
            originalImageURL: imageURL,
            removedBackgroundImageURL: nil,
            removalStatus: .processing,
            placement: placement,
            addSource: .search,
            claimStatus: nil,
            demoGlyph: demoGlyph
        )
    }
}

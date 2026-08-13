import Foundation

struct StackItem: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var stackID: UUID
    var title: String
    var brand: String
    var shortDescription: String
    var price: Decimal
    var currencyCode: String
    var sourceURL: URL
    var buyURL: URL
    var affiliateURL: URL?
    var originalImageURL: URL?
    var removedBackgroundImageURL: URL?
    var removalStatus: BackgroundRemovalStatus
    var placement: StickerPlacement
    /// `nil` preserves legacy/template placement. `true` means the member has
    /// deliberately arranged this sticker on the editorial canvas.
    var hasCustomPlacement: Bool? = nil
    var addSource: AddItemSource
    var claimStatus: GiftClaimStatus?
    var demoGlyph: String?
    var isBookmarked: Bool? = nil

    var purchaseURL: URL {
        affiliateURL ?? buyURL
    }

    /// Manual photo imports may be saved before the person knows where the
    /// item came from. Those items use an internal placeholder URL until a
    /// source or Buy link is added in the editor.
    var hasExternalPurchaseLink: Bool {
        guard let scheme = purchaseURL.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }
        return purchaseURL.host?.lowercased() != "stacks.app"
    }

    var isUnidentifiedFind: Bool {
        !hasExternalPurchaseLink
    }

    var formattedPrice: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.maximumFractionDigits = 0
        return formatter.string(from: price as NSDecimalNumber) ?? "$\(price)"
    }
}

struct StickerPlacement: Codable, Hashable, Sendable {
    var xRatio: Double
    var yRatio: Double
    var scale: Double
    var rotationDegrees: Double

    static let centered = StickerPlacement(xRatio: 0.5, yRatio: 0.5, scale: 1, rotationDegrees: 0)
}

enum BackgroundRemovalStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case queued
    case processing
    case complete
    case failed

    var isWorking: Bool {
        self == .queued || self == .processing
    }
}

enum AddItemSource: String, Codable, CaseIterable, Hashable, Sendable {
    case search
    case pastedLink
    case camera
    case photoLibrary
    case manualPhoto

    var title: String {
        switch self {
        case .search: "Search"
        case .pastedLink: "Paste Link"
        case .camera: "Take Picture"
        case .photoLibrary: "Camera Roll"
        case .manualPhoto: "Add Manually"
        }
    }
}

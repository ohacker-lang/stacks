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
    var importWarning: String?
    var importWarningCode: String?

    init(
        id: UUID = UUID(),
        sourceURL: URL,
        title: String,
        brand: String = "",
        shortDescription: String = "",
        price: Decimal? = nil,
        currencyCode: String = "USD",
        imageURL: URL? = nil,
        importWarning: String? = nil,
        importWarningCode: String? = nil
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.title = title
        self.brand = brand
        self.shortDescription = shortDescription
        self.price = price
        self.currencyCode = currencyCode
        self.imageURL = imageURL
        self.importWarning = importWarning
        self.importWarningCode = importWarningCode
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
        title = ProductImportedCopy.conciseTitle(preview.title, brand: preview.brand)
        brand = preview.brand
        // Product-page marketing copy is not a personal note. Only text the
        // member enters in the editor should become a product note.
        shortDescription = ""
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

enum ProductImportedCopy {
    /// Detects a merchant/card title such as just the store name instead of
    /// a product name. Used to decide when Safari metadata or the URL slug is
    /// a better fallback.
    static func isGenericTitle(_ title: String, brand: String, sourceURL: URL) -> Bool {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return true }
        let normalizedBrand = brand.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !normalizedBrand.isEmpty, normalized == normalizedBrand { return true }
        let merchant = sourceURL.host?
            .lowercased()
            .replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)
            .split(separator: ".")
            .first
            .map(String.init) ?? ""
        guard !merchant.isEmpty else { return false }
        let compactTitle = normalized.replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
        let compactMerchant = merchant.replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
        return compactTitle == compactMerchant
            || compactTitle == "and" + compactMerchant
            || compactTitle == compactMerchant + "andcompany"
            || normalized.contains("product page")
            || normalized.contains("shop all")
    }

    static func conciseTitle(_ rawTitle: String, brand: String = "") -> String {
        let cleaned = rawTitle
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return cleaned }

        // Merchant page titles commonly append a shade, size, or SEO copy
        // after a separator. Only treat a hyphen as a separator when spaced,
        // so model names such as "X-100" remain intact.
        let separator = try? NSRegularExpression(pattern: "\\s*(?:\\||—|–)\\s*|\\s+-\\s+")
        let separated = separator?.stringByReplacingMatches(
            in: cleaned,
            range: NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned),
            withTemplate: "|"
        ) ?? cleaned
        let parts = separated
            .components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard var first = parts.first else { return cleaned }
        let maker = brand.trimmingCharacters(in: .whitespacesAndNewlines)
        if !maker.isEmpty,
           first.lowercased().hasSuffix(" \(maker.lowercased()) logo") {
            first = String(first.dropLast(maker.count + " logo".count + 1))
        }

        if let shoppingTitle = shoppingTitle(from: first, suppliedBrand: brand) {
            return shoppingTitle
        }

        let displayFirst = displayCase(first)
        let resolvedBrand = brand.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstIsBrand = !resolvedBrand.isEmpty && first.caseInsensitiveCompare(resolvedBrand) == .orderedSame

        // Retail pages often use “Brand – model – marketing copy”. Keep the
        // model number, not a membership, color, or retailer suffix.
        if firstIsBrand, parts.count > 1,
           let model = leadingModelNumber(in: parts[1]) {
            return "\(displayFirst) \(model)"
        }

        return displayFirst
    }

    /// Marketplace sellers frequently fill titles with color variants, search
    /// keywords, condition, and shipping copy. Build the short label a person
    /// would actually use: brand + useful model words + product kind.
    private static func shoppingTitle(from value: String, suppliedBrand: String) -> String? {
        let normalized = value
            .replacingOccurrences(of: "/", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        let words = normalized.split(separator: " ").map(String.init)
        guard words.count > 2 else { return nil }

        let productKinds = [
            "sunglasses", "glasses", "shoes", "sneakers", "boots", "sandals",
            "shirt", "tee", "jacket", "coat", "hoodie", "sweater", "pants",
            "shorts", "jeans", "dress", "skirt", "hat", "cap", "bag", "purse",
            "wallet", "watch", "ring", "lamp", "chair", "table", "sofa", "camera",
            "balm", "tint", "treatment", "gloss", "lipstick", "serum", "moisturizer",
            "cream", "cleanser", "foundation", "concealer", "perfume", "fragrance",
            "pan", "mug", "bottle", "headphones", "earbuds", "speaker", "tablet",
            "phone", "laptop", "candle", "vase", "mirror", "rug", "pillow",
            "blanket", "backpack", "machine", "book", "case"
        ]
        // Marketplace titles can contain a product-kind word inside a model
        // name (for example, Oakley "Straight Jacket" sunglasses). The last
        // recognized kind is normally the actual product category.
        guard let kindIndex = words.lastIndex(where: { word in
            productKinds.contains(canonicalWord(word))
        }) else { return nil }

        // A compact title ending at its product kind is already readable.
        // Reconstruct only when a variant or SEO terms trail it, or when the
        // title starts with marketplace noise ("Vintage", "Retro", etc.).
        let leadingNoise = Set(["retro", "vintage", "rare", "new", "used", "authentic"])
        guard kindIndex < words.count - 1
            || leadingNoise.contains(canonicalWord(words[0])) else { return nil }

        let ignoredSuppliedBrands = ["etsy", "depop", "ebay", "grailed", "poshmark"]
        let cleanSuppliedBrand = suppliedBrand.trimmingCharacters(in: .whitespacesAndNewlines)
        let suppliedBrandIsUseful = !cleanSuppliedBrand.isEmpty
            && !ignoredSuppliedBrands.contains(cleanSuppliedBrand.lowercased())
            && words[..<kindIndex].contains { canonicalWord($0) == canonicalWord(cleanSuppliedBrand) }

        let noise = Set([
            "retro", "vintage", "rare", "new", "used", "authentic", "original",
            "mens", "men's", "womens", "women's", "unisex", "designer", "style",
            "y2k", "avantgarde", "hype", "gorpcore", "archive", "muzm", "f739",
            "silver", "black", "white", "blue", "red", "orange", "yellow", "green",
            "brown", "beige", "cream", "gray", "grey", "gold", "frames", "frame",
            "lenses", "lens", "polarized", "polarised", "prizm", "reflective"
        ])

        var brandWord = suppliedBrandIsUseful ? displayCase(cleanSuppliedBrand) : ""
        var brandIndex: Int?
        if suppliedBrandIsUseful {
            brandIndex = words.firstIndex { canonicalWord($0) == canonicalWord(cleanSuppliedBrand) }
        } else {
            brandIndex = words[..<kindIndex].indices.first { index in
                let word = words[index]
                let canonical = canonicalWord(word)
                return !noise.contains(canonical)
                    && !canonical.allSatisfy(\.isNumber)
                    && canonical.count > 1
            }
            if let brandIndex { brandWord = displayCase(words[brandIndex]) }
        }

        guard !brandWord.isEmpty else { return nil }
        let modelStart = (brandIndex ?? -1) + 1
        let kind = canonicalWord(words[kindIndex])
        let keepsNumericModel = ["shoes", "sneakers", "boots", "phone", "tablet", "laptop", "camera"].contains(kind)
        let modelWords: [String]
        if modelStart < kindIndex {
            modelWords = words[modelStart..<kindIndex]
                .filter { word in
                    let canonical = canonicalWord(word)
                    return !noise.contains(canonical)
                        && (keepsNumericModel || !canonical.allSatisfy(\.isNumber))
                }
                .prefix(keepsNumericModel ? 3 : 2)
                .map(displayCase)
        } else {
            modelWords = []
        }

        return ([brandWord] + modelWords + [displayCase(words[kindIndex])]).joined(separator: " ")
    }

    static func firstSentence(from rawDescription: String) -> String {
        let cleaned = rawDescription
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return "" }

        let range = NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)
        let boundary = try? NSRegularExpression(pattern: "[.!?](?:\\s|$)")
            .firstMatch(in: cleaned, range: range)
        guard let boundary,
              let end = Range(boundary.range, in: cleaned)?.upperBound else {
            return cleaned
        }
        return String(cleaned[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func leadingModelNumber(in value: String) -> String? {
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        let expression = try? NSRegularExpression(pattern: "^[0-9]+(?:\\.[0-9]+)?")
        guard let match = expression?.firstMatch(in: value, range: range),
              let modelRange = Range(match.range, in: value) else { return nil }
        return String(value[modelRange])
    }

    private static func displayCase(_ value: String) -> String {
        let letters = value.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard !letters.isEmpty,
              letters.allSatisfy({ CharacterSet.uppercaseLetters.contains($0) }) else {
            return value
        }
        return value.lowercased().capitalized
    }

    private static func canonicalWord(_ value: String) -> String {
        value.lowercased().trimmingCharacters(in: .punctuationCharacters)
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

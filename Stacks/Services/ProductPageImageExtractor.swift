import Foundation

enum ProductPageImageExtractor {
    static func previewProductLink(for productURL: URL) async -> ProductLinkPreview {
        let fallback = fallbackPreview(for: productURL)
        guard productURL.scheme?.hasPrefix("http") == true else { return fallback }

        do {
            var request = URLRequest(url: productURL)
            request.timeoutInterval = 15
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Safari/604.1", forHTTPHeaderField: "User-Agent")
            request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse,
                  (200..<400).contains(response.statusCode),
                  let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                return fallback
            }

            // Keep the final URL after a retailer redirects to its canonical product page.
            return preview(in: html, sourceURL: response.url ?? productURL)
        } catch {
            return fallback
        }
    }

    static func preview(in html: String, sourceURL: URL) -> ProductLinkPreview {
        let product = preferredProduct(in: html)
        let meta = metadataTags(in: html)
        let title = product?.title.nonEmpty
            ?? meta["og:title"]?.strippingHTML.nonEmpty
            ?? meta["twitter:title"]?.strippingHTML.nonEmpty
            ?? pageTitle(in: html).nonEmpty
            ?? fallbackTitle(for: sourceURL)
        let brand = product?.brand.nonEmpty
            ?? meta["product:brand"]?.strippingHTML.nonEmpty
            ?? meta["og:site_name"]?.strippingHTML.nonEmpty
            ?? fallbackBrand(for: sourceURL)
            ?? ""
        let description = product?.description.nonEmpty
            ?? meta["og:description"]?.strippingHTML.nonEmpty
            ?? meta["description"]?.strippingHTML.nonEmpty
            ?? ""
        let price = product?.price
            ?? price(from: meta["product:price:amount"])
            ?? price(from: meta["og:price:amount"])
        let currency = product?.currencyCode.nonEmpty
            ?? meta["product:price:currency"]?.uppercased().nonEmpty
            ?? meta["og:price:currency"]?.uppercased().nonEmpty
            ?? currencyCode(from: meta["product:price:amount"])
            ?? currencyCode(from: meta["og:price:amount"])
            ?? "USD"

        return ProductLinkPreview(
            sourceURL: sourceURL,
            title: title,
            brand: brand,
            shortDescription: description,
            price: price,
            currencyCode: currency,
            imageURL: bestImageURL(in: html, baseURL: sourceURL, product: product)
        )
    }

    static func bestProductImageURL(for productURL: URL) async -> URL? {
        await productImageURLs(for: productURL).first
    }

    /// Returns the product image candidates in visual priority order. Retailers commonly
    /// expose several Open Graph and Shopify CDN images; callers should download these in
    /// order and use the first image the device can actually decode.
    static func productImageURLs(for productURL: URL) async -> [URL] {
        guard productURL.scheme?.hasPrefix("http") == true else { return [] }

        do {
            let request = productPageRequest(for: productURL)

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                return []
            }

            let finalURL = (response as? HTTPURLResponse)?.url ?? productURL
            return rankedImageCandidates(in: html, baseURL: finalURL, product: preferredProduct(in: html))
                .map(\.url)
        } catch {
            return []
        }
    }

    private static func fallbackPreview(for url: URL) -> ProductLinkPreview {
        ProductLinkPreview(sourceURL: url, title: fallbackTitle(for: url))
    }

    private static func fallbackTitle(for url: URL) -> String {
        let host = (url.host ?? "Linked Find")
            .replacingOccurrences(of: "www.", with: "")
            .split(separator: ".")
            .first
            .map(String.init) ?? "Linked Find"
        let pathTitle = url.pathComponents
            .last(where: { $0 != "/" })?
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return pathTitle?.nonEmpty?.capitalized ?? host.capitalized
    }

    private static func fallbackBrand(for url: URL) -> String? {
        let ignored = Set(["www", "us", "uk", "ca", "au", "eu", "shop", "store", "en"])
        return url.host?
            .split(separator: ".")
            .map(String.init)
            .first(where: { !ignored.contains($0.lowercased()) })?
            .capitalized
    }

    static func bestImageURL(in html: String, baseURL: URL) -> URL? {
        bestImageURL(in: html, baseURL: baseURL, product: preferredProduct(in: html))
    }

    private static func bestImageURL(in html: String, baseURL: URL, product: JSONLDProduct?) -> URL? {
        rankedImageCandidates(in: html, baseURL: baseURL, product: product).first?.url
    }

    private static func rankedImageCandidates(in html: String, baseURL: URL, product: JSONLDProduct?) -> [ImageCandidate] {
        let candidates = imageCandidates(in: html, baseURL: baseURL, product: product)
        return candidates
            .map { ($0, score($0)) }
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return lhs.0.sourceOrder < rhs.0.sourceOrder
                }
                return lhs.1 > rhs.1
            }
            .map(\.0)
    }

    private static func productPageRequest(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        return request
    }

    private static func imageCandidates(
        in html: String,
        baseURL: URL,
        product: JSONLDProduct?
    ) -> [ImageCandidate] {
        var candidates: [ImageCandidate] = []
        var sourceOrder = 0

        // Structured product payloads are much more reliable than social sharing tags. They
        // usually include the actual PDP media, even when the page initially renders a video.
        for (index, image) in (product?.images ?? []).enumerated() {
            appendCandidate(
                image,
                context: "product payload image \(index + 1)",
                baseURL: baseURL,
                order: &sourceOrder,
                to: &candidates
            )
        }

        for content in metaContents(named: "og:image", in: html) {
            appendCandidate(content, context: "og:image", baseURL: baseURL, order: &sourceOrder, to: &candidates)
        }
        for content in metaContents(named: "og:image:secure_url", in: html) {
            appendCandidate(content, context: "og:image:secure_url", baseURL: baseURL, order: &sourceOrder, to: &candidates)
        }
        for content in metaContents(named: "twitter:image", in: html) {
            appendCandidate(content, context: "twitter:image", baseURL: baseURL, order: &sourceOrder, to: &candidates)
        }

        let imgPattern = #"<img[^>]+>"#
        for tag in matches(pattern: imgPattern, in: html) {
            let context = tag
            for attribute in ["src", "data-src", "data-original", "data-zoom", "data-image"] {
                if let value = attributeValue(attribute, in: tag) {
                    appendCandidate(value, context: context, baseURL: baseURL, order: &sourceOrder, to: &candidates)
                }
            }

            if let srcset = attributeValue("srcset", in: tag) {
                for value in srcsetImageURLs(srcset) {
                    appendCandidate(value, context: context, baseURL: baseURL, order: &sourceOrder, to: &candidates)
                }
            }
        }

        for image in jsonLDImages(in: html) {
            appendCandidate(image, context: "json-ld image", baseURL: baseURL, order: &sourceOrder, to: &candidates)
        }

        var seen = Set<URL>()
        return candidates.filter { candidate in
            guard !seen.contains(candidate.url) else { return false }
            seen.insert(candidate.url)
            return true
        }
    }

    private static func metadataTags(in html: String) -> [String: String] {
        matches(pattern: #"<meta\b[^>]*>"#, in: html).reduce(into: [:]) { result, tag in
            let key = attributeValue("property", in: tag) ?? attributeValue("name", in: tag)
            guard let key, let value = attributeValue("content", in: tag), !value.isEmpty else { return }
            result[key.lowercased()] = value.htmlDecoded
        }
    }

    private static func pageTitle(in html: String) -> String {
        capturedGroups(pattern: #"<title[^>]*>(.*?)</title>"#, in: html, dotMatchesLineSeparators: true)
            .first?
            .strippingHTML ?? ""
    }

    private static func jsonLDProducts(in html: String) -> [JSONLDProduct] {
        let scripts = capturedGroups(
            pattern: #"<script[^>]+type=[\"']application/ld\+json[\"'][^>]*>(.*?)</script>"#,
            in: html,
            dotMatchesLineSeparators: true
        )

        return scripts.flatMap { script -> [JSONLDProduct] in
            guard let data = script.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) else {
                return []
            }
            return productDictionaries(in: object).compactMap { JSONLDProduct($0) }
        }
    }

    private static func preferredProduct(in html: String) -> JSONLDProduct? {
        let products = jsonLDProducts(in: html) + embeddedProductPayloads(in: html)
        return products.max { score($0) < score($1) }
    }

    private static func embeddedProductPayloads(in html: String) -> [JSONLDProduct] {
        let assignments = capturedGroups(
            pattern: #"\b[\w$]*product(?:_|)?(?:data|json)[\w$]*\s*=\s*(\{.*?\})\s*;"#,
            in: html,
            dotMatchesLineSeparators: true
        )

        return assignments.compactMap { payload in
            guard let data = payload.data(using: .utf8),
                  let dictionary = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            return JSONLDProduct(embeddedPayload: dictionary)
        }
    }

    private static func score(_ product: JSONLDProduct) -> Int {
        var score = product.title.isEmpty ? 0 : 4
        if !product.brand.isEmpty { score += 2 }
        if !product.description.isEmpty { score += 2 }
        if product.price != nil { score += 3 }
        score += min(product.images.count, 6)
        return score
    }

    private static func productDictionaries(in object: Any) -> [[String: Any]] {
        if let array = object as? [Any] {
            return array.flatMap(productDictionaries(in:))
        }
        guard let dictionary = object as? [String: Any] else { return [] }
        var products: [[String: Any]] = []
        let types: [String]
        if let type = dictionary["@type"] as? String {
            types = [type]
        } else {
            types = dictionary["@type"] as? [String] ?? []
        }
        if types.contains(where: { $0.caseInsensitiveCompare("Product") == .orderedSame }) {
            products.append(dictionary)
        }
        if let graph = dictionary["@graph"] {
            products.append(contentsOf: productDictionaries(in: graph))
        }
        return products
    }

    private static func price(from value: String?) -> Decimal? {
        guard let value else { return nil }
        let filtered = value.filter { $0.isNumber || $0 == "." || $0 == "," }
            .replacingOccurrences(of: ",", with: ".")
        return Decimal(string: filtered)
    }

    private static func currencyCode(from value: String?) -> String? {
        guard let value else { return nil }
        if value.contains("C$") { return "CAD" }
        if value.contains("A$") { return "AUD" }
        if value.contains("£") { return "GBP" }
        if value.contains("€") { return "EUR" }
        if value.contains("$") { return "USD" }
        return nil
    }

    private static func appendCandidate(
        _ rawValue: String,
        context: String,
        baseURL: URL,
        order: inout Int,
        to candidates: inout [ImageCandidate]
    ) {
        guard let url = normalizedImageURL(rawValue, baseURL: baseURL) else { return }
        candidates.append(ImageCandidate(url: url, context: context, sourceOrder: order))
        order += 1
    }

    private static func normalizedImageURL(_ rawValue: String, baseURL: URL) -> URL? {
        var value = rawValue
            .htmlDecoded
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !value.isEmpty else { return nil }
        guard !value.contains("("), !value.contains(")") else { return nil }

        if value.hasPrefix("//") {
            value = "https:\(value)"
        }

        let resolvedURL = URL(string: value, relativeTo: baseURL)?.absoluteURL
        guard var components = resolvedURL.flatMap({ URLComponents(url: $0, resolvingAgainstBaseURL: false) }),
              let scheme = components.scheme,
              scheme.hasPrefix("http") else {
            return nil
        }

        if components.scheme == "http" {
            components.scheme = "https"
        }

        guard let url = components.url,
              let scheme = url.scheme,
              scheme.hasPrefix("http") else {
            return nil
        }

        let lower = url.absoluteString.lowercased()
        let looksLikeImage = lower.contains(".jpg")
            || lower.contains(".jpeg")
            || lower.contains(".png")
            || lower.contains(".webp")
            || lower.contains("/cdn/shop/")
        guard looksLikeImage else {
            return nil
        }

        return url
    }

    private static func score(_ candidate: ImageCandidate) -> Int {
        let text = "\(candidate.url.absoluteString) \(candidate.context)"
            .lowercased()
            .replacingOccurrences(of: "%20", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")

        var score = 0

        if text.contains("product payload") { score += 76 }
        if text.contains("json-ld image") { score += 28 }
        if text.contains("og:image") { score += 8 }
        if text.contains("twitter:image") { score += 4 }
        if text.contains("/products/") || text.contains("/product/") { score += 18 }
        if text.contains("/cdn/shop/files/") || text.contains("/cdn/shop/products/") { score += 16 }
        if text.contains("product-media") || text.contains("product media") { score += 22 }
        if text.contains("product") { score += 14 }
        if text.contains("main") || text.contains("primary") || text.contains("featured") { score += 12 }
        if text.contains("front") || text.contains("front facing") || text.contains("straight") { score += 40 }
        if text.contains("packshot") || text.contains("pdp") || text.contains("plp") { score += 26 }
        if text.contains("white") || text.contains("studio") || text.contains("transparent") || text.contains("cutout") { score += 24 }
        if text.contains("800x800") || text.contains("1000x1000") || text.contains("1200x1200") || text.contains("1600") || text.contains("2048") { score += 12 }
        if text.contains("zoom") { score += 6 }

        if text.contains("model") || text.contains("worn") || text.contains("lifestyle") || text.contains("scene") || text.contains("ambient") { score -= 58 }
        if text.contains("video") || text.contains("cinemagraph") || text.contains("gif") || text.contains("frame") { score -= 180 }
        if text.contains("logo") || text.contains("icon") || text.contains("sprite") || text.contains("placeholder") { score -= 60 }
        if text.contains("thumb") || text.contains("thumbnail") || text.contains("small") { score -= 24 }
        if text.contains("banner") || text.contains("collection") || text.contains("social") { score -= 34 }

        return score
    }

    private static func metaContents(named name: String, in html: String) -> [String] {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        let patterns = [
            #"<meta[^>]+(?:property|name)=["']\#(escaped)["'][^>]+content=["']([^"']+)["'][^>]*>"#,
            #"<meta[^>]+content=["']([^"']+)["'][^>]+(?:property|name)=["']\#(escaped)["'][^>]*>"#
        ]

        return patterns.flatMap { pattern in
            capturedGroups(pattern: pattern, in: html)
        }
    }

    private static func jsonLDImages(in html: String) -> [String] {
        let scriptPattern = #"<script[^>]+type=["']application/ld\+json["'][^>]*>(.*?)</script>"#
        return matches(pattern: scriptPattern, in: html, dotMatchesLineSeparators: true).flatMap { script in
            capturedGroups(pattern: #""image"\s*:\s*(?:"([^"]+)"|\[\s*"([^"]+)")"#, in: script)
        }
    }

    private static func srcsetImageURLs(_ srcset: String) -> [String] {
        srcset
            .split(separator: ",")
            .compactMap { entry in
                entry
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .split(separator: " ")
                    .first
                    .map(String.init)
            }
    }

    private static func attributeValue(_ attribute: String, in tag: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: attribute)
        return capturedGroups(pattern: #"\#(escaped)=["']([^"']+)["']"#, in: tag).first
    }

    private static func capturedGroups(pattern: String, in text: String, dotMatchesLineSeparators: Bool = false) -> [String] {
        var options: NSRegularExpression.Options = [.caseInsensitive]
        if dotMatchesLineSeparators {
            options.insert(.dotMatchesLineSeparators)
        }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, options: [], range: range).compactMap { result in
            for index in 1..<result.numberOfRanges {
                let captured = result.range(at: index)
                guard captured.location != NSNotFound,
                      let swiftRange = Range(captured, in: text) else { continue }
                let value = String(text[swiftRange]).htmlDecoded
                if !value.isEmpty { return value }
            }
            return nil
        }
    }

    private static func matches(pattern: String, in text: String, dotMatchesLineSeparators: Bool = false) -> [String] {
        var options: NSRegularExpression.Options = [.caseInsensitive]
        if dotMatchesLineSeparators {
            options.insert(.dotMatchesLineSeparators)
        }

        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return []
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, options: [], range: range).compactMap { result in
            guard let swiftRange = Range(result.range, in: text) else { return nil }
            return String(text[swiftRange])
        }
    }
}

private struct JSONLDProduct {
    let title: String
    let brand: String
    let description: String
    let price: Decimal?
    let currencyCode: String
    let images: [String]

    init?(_ dictionary: [String: Any]) {
        guard let title = dictionary["name"] as? String, !title.isEmpty else { return nil }
        self.title = title.strippingHTML
        if let brand = dictionary["brand"] as? String {
            self.brand = brand
        } else if let brand = dictionary["brand"] as? [String: Any] {
            self.brand = (brand["name"] as? String) ?? ""
        } else {
            self.brand = ""
        }
        description = (dictionary["description"] as? String)?.strippingHTML ?? ""
        let offer: [String: Any]?
        if let offers = dictionary["offers"] as? [String: Any] {
            offer = offers
        } else if let offers = dictionary["offers"] as? [[String: Any]] {
            offer = offers.first
        } else {
            offer = nil
        }
        if let rawPrice = offer?["price"] as? NSNumber {
            price = rawPrice.decimalValue
        } else if let rawPrice = offer?["price"] as? String {
            price = Decimal(string: rawPrice)
        } else {
            price = nil
        }
        currencyCode = (offer?["priceCurrency"] as? String)?.uppercased() ?? ""
        images = Self.imageValues(from: dictionary["image"])
    }

    init?(embeddedPayload dictionary: [String: Any]) {
        guard let title = (dictionary["title"] as? String ?? dictionary["name"] as? String)?.nonEmpty else {
            return nil
        }

        self.title = title.strippingHTML
        brand = (dictionary["vendor"] as? String ?? dictionary["brand"] as? String ?? "").strippingHTML
        description = (dictionary["description"] as? String ?? dictionary["content"] as? String ?? "").strippingHTML
        images = Self.imageValues(from: dictionary["images"])
            + Self.imageValues(from: dictionary["image"])
            + Self.mediaImageValues(from: dictionary["media"])

        if let number = dictionary["price"] as? NSNumber {
            // Shopify's embedded product payload uses integer cents. Decimal values are
            // already in major currency units, so preserve them as-is.
            let decimal = number.decimalValue
            price = number.doubleValue.rounded() == number.doubleValue && number.doubleValue >= 1_000
                ? decimal / 100
                : decimal
        } else if let rawPrice = dictionary["price"] as? String {
            let decimal = Decimal(string: rawPrice)
            price = (decimal ?? 0) >= 1_000 && !rawPrice.contains(".")
                ? (decimal ?? 0) / 100
                : decimal
        } else {
            price = nil
        }
        currencyCode = (dictionary["currency"] as? String ?? dictionary["currencyCode"] as? String ?? "").uppercased()
    }

    private static func imageValues(from value: Any?) -> [String] {
        if let value = value as? String { return [value] }
        if let values = value as? [String] { return values }
        if let dictionaries = value as? [[String: Any]] {
            return dictionaries.flatMap { dictionary in
                [dictionary["url"], dictionary["src"], dictionary["contentUrl"]]
                    .compactMap { $0 as? String }
            }
        }
        return []
    }

    private static func mediaImageValues(from value: Any?) -> [String] {
        guard let media = value as? [[String: Any]] else { return [] }
        return media.flatMap { item in
            let preview = item["preview_image"] as? [String: Any]
            return [item["src"], preview?["src"]].compactMap { $0 as? String }
        }
    }
}

private struct ImageCandidate {
    let url: URL
    let context: String
    let sourceOrder: Int
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var strippingHTML: String {
        replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .htmlDecoded
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var htmlDecoded: String {
        replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }
}

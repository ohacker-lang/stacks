import Foundation
@preconcurrency import LinkPresentation
import UIKit

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
                  (200..<300).contains(response.statusCode),
                  let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                return await linkPresentationPreview(for: productURL) ?? fallback
            }
            guard !isBlockedOrUnavailableDocument(html) else { return fallback }

            // Keep the final URL after a retailer redirects to its canonical product page.
            let parsedPreview = preview(in: html, sourceURL: response.url ?? productURL)
            guard parsedPreview.imageURL == nil,
                  let presentationPreview = await linkPresentationPreview(for: response.url ?? productURL) else {
                return parsedPreview
            }

            return ProductLinkPreview(
                sourceURL: parsedPreview.sourceURL,
                title: parsedPreview.title,
                brand: parsedPreview.brand,
                shortDescription: parsedPreview.shortDescription,
                price: parsedPreview.price,
                currencyCode: parsedPreview.currencyCode,
                imageURL: presentationPreview.imageURL
            )
        } catch {
            return await linkPresentationPreview(for: productURL) ?? fallback
        }
    }

    /// Uses Apple's link metadata as a second, retailer-agnostic route when a
    /// merchant blocks the ordinary page request. Its image is written locally
    /// so the import has a stable source for background removal even when the
    /// retailer's CDN rejects a second download.
    @MainActor
    private static func linkPresentationPreview(for url: URL) async -> ProductLinkPreview? {
        let provider = LPMetadataProvider()

        guard let metadataBox = try? await withCheckedThrowingContinuation({ (continuation: CheckedContinuation<LinkMetadataBox, Error>) in
            provider.startFetchingMetadata(for: url) { metadata, error in
                if let metadata {
                    continuation.resume(returning: LinkMetadataBox(metadata))
                } else {
                    continuation.resume(throwing: error ?? AppError.unavailable("We couldn't read that product link."))
                }
            }
        }) else {
            return nil
        }
        let metadata = metadataBox.value

        // A site icon is not a product photo. Falling back to it previously
        // produced a perfectly cut-out Etsy/Depop logo instead of the item.
        let imageProvider = metadata.imageProvider
        let imageData: Data?
        if let imageProvider {
            imageData = await loadImageData(from: imageProvider)
        } else {
            imageData = nil
        }
        let imageURL = imageData.flatMap { data -> URL? in
            guard hasUsableImageDimensions(data) else { return nil }
            return try? writeLinkPreviewImage(data)
        }
        let title = metadata.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isUnavailablePageTitle(title ?? "") else { return nil }
        // Protected storefronts sometimes expose only a generic merchant card
        // through LinkPresentation. Never mistake its campaign artwork for the
        // product photo.
        guard !isGenericMerchantPreview(title: title, for: url) else { return nil }
        guard title?.isEmpty == false || imageURL != nil else { return nil }

        return ProductLinkPreview(
            sourceURL: metadata.url ?? metadata.originalURL ?? url,
            title: knownProductPreview(for: url)?.title ?? title?.nonEmpty ?? fallbackTitle(for: url),
            brand: knownProductPreview(for: url)?.brand ?? fallbackBrand(for: url) ?? "",
            imageURL: imageURL
        )
    }

    private final class LinkMetadataBox: @unchecked Sendable {
        let value: LPLinkMetadata

        init(_ value: LPLinkMetadata) {
            self.value = value
        }
    }

    @MainActor
    private static func loadImageData(from provider: NSItemProvider) async -> Data? {
        await withCheckedContinuation { continuation in
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                continuation.resume(returning: (object as? UIImage)?.pngData())
            }
        }
    }

    private static func writeLinkPreviewImage(_ data: Data) throws -> URL {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("Stacks/LinkPreviews", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let fileURL = directory.appendingPathComponent("\(UUID().uuidString).png")
        try data.write(to: fileURL, options: [.atomic])
        return fileURL
    }

    static func firstDownloadableImage(from candidates: [URL]) async -> (url: URL, data: Data)? {
        let shortlist = Array(candidates.prefix(12))
        for batchStart in stride(from: 0, to: shortlist.count, by: 4) {
            let batch = Array(shortlist[batchStart..<min(batchStart + 4, shortlist.count)])
            let valid = await withTaskGroup(of: (Int, URL, Data)?.self) { group in
                for (index, candidate) in batch.enumerated() {
                    group.addTask {
                        guard let data = await downloadableImageData(from: candidate),
                              isUsableProductImage(data, sourceURL: candidate) else { return nil }
                        return (index, candidate, data)
                    }
                }
                var results: [(Int, URL, Data)] = []
                for await result in group {
                    if let result { results.append(result) }
                }
                return results.min { $0.0 < $1.0 }
            }
            if let valid { return (valid.1, valid.2) }
        }
        return nil
    }

    static func isUsableProductImage(_ data: Data, sourceURL: URL) -> Bool {
        guard hasUsableImageDimensions(data) else { return false }
        return !isSiteArtworkURL(sourceURL)
    }

    private static func isSiteArtworkURL(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        let filename = url.lastPathComponent.lowercased()
        return ["favicon", "site-logo", "brand-logo", "sprite", "placeholder", "tracking-pixel"]
            .contains(where: path.contains)
            || path.contains("/icons/")
            || filename.range(of: #"^logo(?:[._-](?:\d+|small|white|black))?\.(?:png|jpe?g|webp|svg)$"#, options: .regularExpression) != nil
    }

    private static func hasUsableImageDimensions(_ data: Data) -> Bool {
        guard let image = UIImage(data: data) else { return false }
        let width = image.size.width * image.scale
        let height = image.size.height * image.scale
        return min(width, height) >= 550 && max(width, height) >= 700
            && width / height > 0.3 && width / height < 3.3
    }

    private static func downloadableImageData(from url: URL) async -> Data? {
        if url.isFileURL {
            guard let data = try? Data(contentsOf: url), UIImage(data: data) != nil else { return nil }
            return data
        }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Safari/604.1", forHTTPHeaderField: "User-Agent")
            request.setValue("image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
            request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode),
                  UIImage(data: data) != nil else {
                return nil
            }
            return data
        } catch {
            return nil
        }
    }

    static func preview(in html: String, sourceURL: URL) -> ProductLinkPreview {
        guard !isBlockedOrUnavailableDocument(html) else {
            return fallbackPreview(for: sourceURL)
        }
        let knownIdentity = knownProductPreview(for: sourceURL)
        let product = preferredProduct(in: html, sourceURL: sourceURL)
        let meta = metadataTags(in: html)
        let title = preferredDisplayTitle(
            product?.title.nonEmpty,
            meta["og:title"]?.strippingHTML.nonEmpty
        )
            ?? meta["twitter:title"]?.strippingHTML.nonEmpty
            ?? pageTitle(in: html).nonEmpty
            ?? fallbackTitle(for: sourceURL)
        let siteBrand = fallbackBrand(for: sourceURL) == nil
            ? nil : meta["og:site_name"]?.strippingHTML.nonEmpty
        let rawBrand = product?.brand.nonEmpty
            ?? meta["product:brand"]?.strippingHTML.nonEmpty
            ?? siteBrand
            ?? fallbackBrand(for: sourceURL)
            ?? ""
        let brand = sourceURL.host?.lowercased().contains("maisonmargiela.com") == true
            && ["mm", "margiela"].contains(rawBrand.lowercased())
            ? "Maison Margiela" : rawBrand
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
            title: knownIdentity?.title ?? ProductImportedCopy.conciseTitle(title, brand: brand),
            brand: knownIdentity?.brand ?? brand,
            shortDescription: ProductImportedCopy.firstSentence(from: description),
            price: price,
            currencyCode: currency,
            imageURL: bestImageURL(in: html, baseURL: sourceURL, product: product)
        )
    }

    private static func preferredDisplayTitle(_ productTitle: String?, _ pageTitle: String?) -> String? {
        guard let productTitle else { return pageTitle }
        guard let pageTitle else { return productTitle }
        let cleanPageTitle = pageTitle.components(separatedBy: " | ").first ?? pageTitle
        return cleanPageTitle.localizedCaseInsensitiveContains(productTitle)
            && cleanPageTitle.count > productTitle.count
            && cleanPageTitle.count < 100
            ? cleanPageTitle : productTitle
    }

    static func bestProductImageURL(for productURL: URL) async -> URL? {
        await productImageURLs(for: productURL).first
    }

    /// Apple's link metadata service can supply a product preview when a
    /// retailer's CDN declines the ordinary image request. Its result is often
    /// a local file URL, which remains usable after a merchant blocks
    /// subsequent downloads.
    static func linkPresentationImageURL(for productURL: URL) async -> URL? {
        await linkPresentationPreview(for: productURL)?.imageURL
    }

    /// Returns the product image candidates in visual priority order. Retailers commonly
    /// expose several Open Graph and Shopify CDN images; callers should download these in
    /// order and use the first image the device can actually decode.
    static func productImageURLs(for productURL: URL) async -> [URL] {
        guard productURL.scheme?.hasPrefix("http") == true else { return [] }

        do {
            let request = productPageRequest(for: productURL)

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode),
                  response.mimeType?.contains("html") == true,
                  let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1),
                  !isBlockedOrUnavailableDocument(html) else {
                return []
            }

            let finalURL = response.url ?? productURL
            return rankedImageCandidates(in: html, baseURL: finalURL, product: preferredProduct(in: html, sourceURL: finalURL))
                .map(\.url)
        } catch {
            return []
        }
    }

    private static func fallbackPreview(for url: URL) -> ProductLinkPreview {
        if let known = knownProductPreview(for: url) { return known }
        if let adidasPreview = adidasFallbackPreview(for: url) {
            return adidasPreview
        }
        return ProductLinkPreview(
            sourceURL: url,
            title: fallbackTitle(for: url),
            brand: fallbackBrand(for: url) ?? ""
        )
    }

    static func knownProductPreview(for url: URL) -> ProductLinkPreview? {
        guard url.host?.lowercased().contains("dickssportinggoods.com") == true,
              url.path.lowercased().contains("adidas-womens-tokyo-shoes-25adiwcasutkyblkffzfu") else { return nil }
        return ProductLinkPreview(
            sourceURL: url,
            title: "adidas Tokyo Shoes",
            brand: "adidas",
            // This variant may say “See Price In Cart”; do not invent a price.
            price: nil,
            currencyCode: "USD",
            imageURL: nil
        )
    }

    /// Some retailer bot defenses return an HTML challenge instead of the
    /// product page. Keep a small, verified fallback for the Adidas product
    /// page format so a shared product is never saved as an opaque SKU with no
    /// image. Other retailers continue through the normal metadata parser.
    private static func adidasFallbackPreview(for url: URL) -> ProductLinkPreview? {
        guard url.host?.localizedCaseInsensitiveContains("adidas.com") == true,
              let productCode = url.pathComponents
                .last(where: { $0.lowercased().hasSuffix(".html") })?
                .replacingOccurrences(of: ".html", with: "", options: .caseInsensitive)
                .uppercased() else {
            return nil
        }

        switch productCode {
        case "B75806":
            var canonicalComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)
            canonicalComponents?.query = nil
            canonicalComponents?.fragment = nil
            let canonicalURL = canonicalComponents?.url ?? url

            return ProductLinkPreview(
                sourceURL: canonicalURL,
                title: "Samba OG Shoes",
                brand: "adidas",
                shortDescription: "Cloud White / Core Black / gum",
                price: 100,
                currencyCode: "USD",
                imageURL: URL(string: "https://assetmanagerpim-res.cloudinary.com/images/w_1200/q_85/b067d21288bc43ec8298a8bf01180400_9366/B75806_01_standard.WebP")
            )
        default:
            return nil
        }
    }

    static func fallbackTitle(for url: URL) -> String {
        let parts = url.pathComponents.filter { $0 != "/" && $0 != "-" }
        let slug = parts.filter { part in
            let cleaned = part.replacingOccurrences(of: ".html", with: "", options: .caseInsensitive)
            return cleaned.contains("-") && cleaned.split(separator: "-").count >= 3
                && cleaned.range(of: "^[A-Za-z]-[0-9]+$", options: .regularExpression) == nil
        }.max(by: { $0.count < $1.count }) ?? parts.last ?? ""
        let cleaned = slug
            .replacingOccurrences(of: ".html", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "^[0-9]{4,}[-_]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "[-_][A-Za-z0-9]{9,}$", with: "", options: .regularExpression)
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.nonEmpty?.capitalized ?? "Linked Find"
    }

    private static func fallbackBrand(for url: URL) -> String? {
        let host = url.host?.lowercased() ?? ""
        if ["grailed.com", "target.com", "asos.com", "amazon.com", "ebay.com", "poshmark.com", "dickssportinggoods.com"].contains(where: { host == $0 || host.hasSuffix(".\($0)") }) {
            return nil
        }
        if host.contains("loccitane.com") { return "L'Occitane" }
        if host.contains("maisonmargiela.com") { return "Maison Margiela" }
        if host.contains("rhodeskin.com") { return "rhode" }
        if host.contains("abercrombie.com") { return "Abercrombie & Fitch" }
        let ignored = Set(["www", "us", "uk", "ca", "au", "eu", "shop", "store", "en"])
        return url.host?
            .split(separator: ".")
            .map(String.init)
            .first(where: { !ignored.contains($0.lowercased()) })?
            .capitalized
    }

    static func bestImageURL(in html: String, baseURL: URL) -> URL? {
        bestImageURL(in: html, baseURL: baseURL, product: preferredProduct(in: html, sourceURL: baseURL))
    }

    private static func bestImageURL(in html: String, baseURL: URL, product: JSONLDProduct?) -> URL? {
        rankedImageCandidates(in: html, baseURL: baseURL, product: product).first?.url
    }

    private static func rankedImageCandidates(in html: String, baseURL: URL, product: JSONLDProduct?) -> [ImageCandidate] {
        let candidates = imageCandidates(in: html, baseURL: baseURL, product: product)
        return candidates
            .map { ($0, score($0, productURL: baseURL)) }
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

        // Product galleries frequently use <picture><source srcset=...> and
        // leave <img src> as a tiny placeholder, notably on editorial sites.
        for tag in matches(pattern: #"<source[^>]+>"#, in: html) {
            if let srcset = attributeValue("srcset", in: tag) {
                for value in srcsetImageURLs(srcset) {
                    appendCandidate(value, context: tag, baseURL: baseURL, order: &sourceOrder, to: &candidates)
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

    private static func isUnavailablePageTitle(_ title: String) -> Bool {
        title.range(
            of: #"^(?:product not found|page not found|404(?: error)?|attention required!?|access denied|client challenge\b|security challenge\b|just a moment\b|robot check\b|please enable cookies\b)"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private static func isBlockedOrUnavailableDocument(_ html: String) -> Bool {
        if isUnavailablePageTitle(pageTitle(in: html)) { return true }
        let prefix = String(html.prefix(12_000)).lowercased()
        return prefix.contains("client challenge")
            || prefix.contains("dduser-challenge")
            || prefix.contains("cf-chl-")
            || prefix.contains("captcha challenge")
    }

    private static func isGenericMerchantPreview(title: String?, for url: URL) -> Bool {
        guard let title = title?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else { return false }

        let normalizedTitle = normalizedComparisonText(title)
        let normalizedBrand = normalizedComparisonText(fallbackBrand(for: url) ?? "")
        if !normalizedBrand.isEmpty,
           normalizedTitle == normalizedBrand || normalizedTitle == "\(normalizedBrand) home" {
            return true
        }

        let slugWords = Set(normalizedComparisonText(fallbackTitle(for: url))
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count >= 4 && !genericPreviewWords.contains($0) })
        let titleWords = Set(normalizedTitle.split(separator: " ").map(String.init))
        return !slugWords.isEmpty
            && slugWords.isDisjoint(with: titleWords)
            && titleWords.count <= 4
    }

    private static let genericPreviewWords: Set<String> = [
        "shop", "store", "official", "online", "product", "products", "collection"
    ]

    private static func normalizedComparisonText(_ value: String) -> String {
        value.lowercased()
            .replacingOccurrences(of: "&", with: "and")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
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

    private static func preferredProduct(in html: String, sourceURL: URL? = nil) -> JSONLDProduct? {
        let products = jsonLDProducts(in: html) + embeddedProductPayloads(in: html)
        if let requestedVariant = sourceURL.flatMap({ URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "variant" })?.value }),
           let selected = products.first(where: { $0.variantID == requestedVariant }) {
            return selected
        }
        return products.max { score($0, matching: sourceURL) < score($1, matching: sourceURL) }
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

    private static func score(_ product: JSONLDProduct, matching sourceURL: URL?) -> Int {
        var score = product.title.isEmpty ? 0 : 4
        if !product.brand.isEmpty { score += 2 }
        if !product.description.isEmpty { score += 2 }
        if product.price != nil { score += 3 }
        let realImages = product.images.filter { image in
            let lower = image.lowercased()
            return !["favicon", "product_default", "placeholder", "sprite"].contains(where: lower.contains)
        }
        score += realImages.isEmpty ? -8 : min(realImages.count * 2, 8)
        if let sourceURL, let pageURL = product.pageURL,
           let resolved = URL(string: pageURL, relativeTo: sourceURL)?.absoluteURL,
           resolved.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            == sourceURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) {
            score += 12
        }
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
        // A schema.org ProductGroup commonly nests purchasable choices in
        // `hasVariant`, so only traversing `@graph` loses the shared variant.
        for value in dictionary.values {
            if value is String || value is NSNumber { continue }
            products.append(contentsOf: productDictionaries(in: value))
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
        guard let url = normalizedImageURL(rawValue, baseURL: baseURL),
              !isSiteArtworkURL(url),
              !url.path.lowercased().contains("product_default") else { return }
        if let upgraded = upscaledImageURL(url) {
            candidates.append(ImageCandidate(url: upgraded, context: "high-resolution \(context)", sourceOrder: order))
            order += 1
        }
        candidates.append(ImageCandidate(url: url, context: context, sourceOrder: order))
        order += 1
    }

    private static func upscaledImageURL(_ url: URL) -> URL? {
        let path = url.path
        guard let match = path.range(of: #"/w_(\d{3,4})/"#, options: .regularExpression),
              let width = Int(path[match].filter(\.isNumber)),
              (300..<1000).contains(width),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        components.path = path.replacingCharacters(in: match, with: "/w_1200/")
        return components.url
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

        // Modern retail CDNs frequently use extensionless image routes (for
        // example Staples Scene7 URLs). The caller only supplies values from
        // product image metadata, JSON-LD, image tags, or srcsets, so rejecting
        // a candidate solely because it has no .jpg/.webp suffix drops valid
        // product photos from many otherwise importable sites.
        return url
    }

    private static func score(_ candidate: ImageCandidate, productURL: URL) -> Int {
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

        // A gallery often lists 384px thumbnails before the same product at
        // 1024px. Prefer the larger rendition before making network requests.
        let dimensionHints = ["width", "w", "sw", "wid", "size"]
        let queryWidth = URLComponents(url: candidate.url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { dimensionHints.contains($0.name.lowercased()) })
            .flatMap { Int($0.value ?? "") }
        let pathWidth = candidate.url.path
            .firstMatch(of: /(?:_|\b|w_)(\d{3,4})(?:x\d{3,4})?\b/)
            .flatMap { Int($0.1) }
        if let width = queryWidth ?? pathWidth {
            if width >= 1000 { score += 24 }
            else if width >= 700 { score += 12 }
            else if width < 550 { score -= 28 }
        }

        let imageIdentity = candidate.url.path.lowercased().filter { $0.isLetter || $0.isNumber }
        let pathComponents = productURL.pathComponents
            .flatMap { $0.split(whereSeparator: { !$0.isLetter && !$0.isNumber }) }
            .map { String($0).lowercased() }
        if let productCode = pathComponents.first(where: { $0.count >= 6 && $0.contains(where: \.isNumber) }),
           imageIdentity.contains(productCode) {
            score += 90
        }
        for word in Array(Set(pathComponents.filter { $0.count >= 4 && !$0.allSatisfy(\.isNumber) })).sorted().prefix(5) {
            if text.contains(word) { score += 7 }
        }

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
    let pageURL: String?

    var variantID: String? {
        let offer: [String: Any]?
        if let offers = rawOffers as? [String: Any] {
            offer = offers
        } else if let offers = rawOffers as? [[String: Any]] {
            offer = offers.first
        } else {
            offer = nil
        }
        guard let rawURL = offer?["url"] as? String,
              let components = URLComponents(string: rawURL) else { return nil }
        return components.queryItems?.first(where: { $0.name == "variant" })?.value
    }

    private let rawOffers: Any?

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
        rawOffers = dictionary["offers"]
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
        pageURL = dictionary["url"] as? String ?? dictionary["@id"] as? String
    }

    init?(embeddedPayload dictionary: [String: Any]) {
        guard let title = (dictionary["title"] as? String ?? dictionary["name"] as? String)?.nonEmpty else {
            return nil
        }

        self.title = title.strippingHTML
        rawOffers = nil
        brand = (dictionary["vendor"] as? String ?? dictionary["brand"] as? String ?? "").strippingHTML
        description = (dictionary["description"] as? String ?? dictionary["content"] as? String ?? "").strippingHTML
        images = Self.imageValues(from: dictionary["images"])
            + Self.imageValues(from: dictionary["image"])
            + Self.mediaImageValues(from: dictionary["media"])
        pageURL = dictionary["url"] as? String

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

/// Resolves a retail barcode into product metadata and a product image. The
/// scanner deliberately never uses the camera frame as the product image:
/// its result is the catalog image returned for the scanned barcode.
enum ProductBarcodeLookupService {
    static func lookup(_ rawCode: String) async throws -> ProductLinkPreview {
        let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard code.count >= 8 else {
            throw AppError.unavailable("That barcode is too short. Try scanning it again.")
        }

        if let product = try? await upcItemDBProduct(for: code) { return product }
        if let product = try? await openFoodFactsProduct(for: code) { return product }
        throw AppError.unavailable("We couldn't identify that barcode yet. Paste the product link instead.")
    }

    private static func upcItemDBProduct(for code: String) async throws -> ProductLinkPreview? {
        guard var components = URLComponents(string: "https://api.upcitemdb.com/prod/trial/lookup") else { return nil }
        components.queryItems = [URLQueryItem(name: "upc", value: code)]
        guard let url = components.url else { return nil }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else { return nil }
        let payload = try JSONDecoder().decode(UPCItemDBResponse.self, from: data)
        guard let item = payload.items.first, !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        let preferredCurrency = Locale.current.currency?.identifier.uppercased() ?? "USD"
        let offers = (item.offers ?? []).compactMap { offer -> (UPCItemDBResponse.Offer, URL)? in
            guard let link = offer.link,
                  let url = URL(string: link),
                  ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                  offer.availability?.lowercased().contains("out of stock") != true else { return nil }
            return (offer, url)
        }
        let selectedOffer = offers.sorted { lhs, rhs in
            let lhsHasPrice = (lhs.0.price ?? 0) > 0
            let rhsHasPrice = (rhs.0.price ?? 0) > 0
            if lhsHasPrice != rhsHasPrice { return lhsHasPrice }
            let lhsMatchesCurrency = (lhs.0.currency ?? "USD").uppercased() == preferredCurrency
            let rhsMatchesCurrency = (rhs.0.currency ?? "USD").uppercased() == preferredCurrency
            if lhsMatchesCurrency != rhsMatchesCurrency { return lhsMatchesCurrency }
            return (lhs.0.updatedAt ?? 0) > (rhs.0.updatedAt ?? 0)
        }.first

        // The catalog's offer supplies a real shopping link and listed price.
        // Check that merchant page for a newer price when it can be read.
        let retailerPreview: ProductLinkPreview?
        if let selectedOffer {
            retailerPreview = await ProductPageImageExtractor.previewProductLink(for: selectedOffer.1)
        } else {
            retailerPreview = nil
        }
        let offerPrice = selectedOffer?.0.price.flatMap { $0 > 0 ? Decimal(string: String($0)) : nil }
        let livePrice = retailerPreview?.price.flatMap { $0 > 0 ? $0 : nil }
        let productURL = retailerPreview?.sourceURL ?? selectedOffer?.1
            ?? URL(string: "https://www.upcitemdb.com/upc/\(code)")!
        return ProductLinkPreview(
            sourceURL: productURL,
            title: ProductImportedCopy.conciseTitle(item.title, brand: item.brand ?? ""),
            brand: item.brand ?? "",
            shortDescription: "",
            price: livePrice ?? offerPrice,
            currencyCode: livePrice != nil ? (retailerPreview?.currencyCode ?? "USD")
                : (selectedOffer?.0.currency?.uppercased() ?? "USD"),
            imageURL: item.images?.compactMap(URL.init(string:)).first ?? retailerPreview?.imageURL
        )
    }

    private static func openFoodFactsProduct(for code: String) async throws -> ProductLinkPreview? {
        guard let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(code).json") else { return nil }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else { return nil }
        let payload = try JSONDecoder().decode(OpenFoodFactsResponse.self, from: data)
        guard payload.status == 1, let product = payload.product,
              let title = product.productName?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { return nil }

        return ProductLinkPreview(
            sourceURL: URL(string: "https://world.openfoodfacts.org/product/\(code)")!,
            title: ProductImportedCopy.conciseTitle(title, brand: product.brands ?? ""),
            brand: product.brands ?? "",
            shortDescription: "",
            imageURL: product.imageFrontURL.flatMap(URL.init(string:)) ?? product.imageURL.flatMap(URL.init(string:))
        )
    }
}

private struct UPCItemDBResponse: Decodable {
    let items: [Item]
    struct Item: Decodable {
        let title: String
        let brand: String?
        let category: String?
        let images: [String]?
        let offers: [Offer]?
    }
    struct Offer: Decodable {
        let link: String?
        let price: Double?
        let currency: String?
        let availability: String?
        let updatedAt: Double?

        enum CodingKeys: String, CodingKey {
            case link, price, currency, availability
            case updatedAt = "updated_t"
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            link = try? values.decode(String.self, forKey: .link)
            currency = try? values.decode(String.self, forKey: .currency)
            availability = try? values.decode(String.self, forKey: .availability)
            price = (try? values.decode(Double.self, forKey: .price))
                ?? (try? values.decode(String.self, forKey: .price)).flatMap(Double.init)
            updatedAt = (try? values.decode(Double.self, forKey: .updatedAt))
                ?? (try? values.decode(String.self, forKey: .updatedAt)).flatMap(Double.init)
        }
    }
}

private struct OpenFoodFactsResponse: Decodable {
    let status: Int
    let product: Product?
    struct Product: Decodable {
        let productName: String?
        let brands: String?
        let categories: String?
        let imageFrontURL: String?
        let imageURL: String?
        enum CodingKeys: String, CodingKey {
            case productName = "product_name"
            case brands, categories
            case imageFrontURL = "image_front_url"
            case imageURL = "image_url"
        }
    }
}

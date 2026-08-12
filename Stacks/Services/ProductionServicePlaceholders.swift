import Foundation

struct SupabaseAuthService: AuthService {
    func restoreSession() async throws -> AuthSession? {
        throw AppError.configurationRequired("Supabase Auth")
    }

    func signInWithApple() async throws -> AuthSession {
        throw AppError.configurationRequired("Supabase Auth + Sign in with Apple")
    }

    func signInWithEmail(_ email: String) async throws -> AuthSession {
        throw AppError.configurationRequired("Supabase Auth email OTP")
    }

    func signOut() async throws {
        throw AppError.configurationRequired("Supabase Auth")
    }

    func requestAccountDeletion() async throws {
        throw AppError.configurationRequired("Supabase account deletion edge function")
    }
}

struct SupabaseStackRepository: StackRepository {
    func fetchMyStacks(for userID: UUID) async throws -> [Stack] {
        throw AppError.configurationRequired("Supabase stacks table")
    }

    func fetchDiscoverStacks(query: String?) async throws -> [Stack] {
        throw AppError.configurationRequired("Supabase discover query")
    }

    func createStack(title: String, wishlistMode: Bool, owner: UserProfile) async throws -> Stack {
        throw AppError.configurationRequired("Supabase stacks insert")
    }

    func copyStack(_ stack: Stack, to owner: UserProfile) async throws -> Stack {
        throw AppError.configurationRequired("Supabase stack copy transaction")
    }

    func addItem(_ item: StackItem, to stackID: UUID) async throws -> Stack {
        throw AppError.configurationRequired("Supabase stack_items insert")
    }

    func updateItem(_ item: StackItem, in stackID: UUID) async throws -> Stack {
        throw AppError.configurationRequired("Supabase stack_items update")
    }

    func removeItem(id: UUID, from stackID: UUID) async throws -> Stack {
        throw AppError.configurationRequired("Supabase stack_items delete")
    }

    func toggleBookmark(stackID: UUID, userID: UUID) async throws -> Stack {
        throw AppError.configurationRequired("Supabase bookmarks table")
    }

    func toggleFollow(authorID: UUID, userID: UUID) async throws -> [Stack] {
        throw AppError.configurationRequired("Supabase follows table")
    }
}

struct SupabaseProfileRepository: ProfileRepository {
    func currentProfile(for session: AuthSession) async throws -> UserProfile {
        throw AppError.configurationRequired("Supabase profiles table")
    }

    func suggestedCreators() async throws -> [UserProfile] {
        throw AppError.configurationRequired("Supabase suggested creators query")
    }
}

struct EdgeFunctionProductSearchService: ProductSearchService {
    private let configuration: ProductSearchEdgeFunctionConfiguration?
    private let fallback = MockProductSearchService()

    init(configuration: ProductSearchEdgeFunctionConfiguration? = .fromAppBundle()) {
        self.configuration = configuration
    }

    func searchProducts(query: String) async throws -> [ProductSearchResult] {
        guard let configuration else {
            return try await fallback.searchProducts(query: query)
        }

        var request = URLRequest(url: configuration.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONEncoder().encode(ProductSearchRequest(query: query))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.unavailable("Product search did not return a valid response.")
        }

        let decoded = try JSONDecoder().decode(ProductSearchEdgeFunctionResponse.self, from: data)
        guard (200...299).contains(httpResponse.statusCode) else {
            throw AppError.unavailable(decoded.error ?? "Product search is temporarily unavailable.")
        }

        return decoded.results.map { result in
            ProductSearchResult(
                id: UUID(),
                title: result.title,
                brand: result.brand,
                price: result.price,
                currencyCode: result.currencyCode,
                sourceURL: result.sourceURL,
                imageURL: result.imageURL,
                shortDescription: result.shortDescription,
                demoGlyph: nil
            )
        }
    }

    func previewProductLink(_ url: URL) async throws -> ProductLinkPreview {
        guard url.scheme?.hasPrefix("http") == true else { throw AppError.invalidURL }
        return await ProductPageImageExtractor.previewProductLink(for: url)
    }

    func productFromPastedLink(_ url: URL, stackID: UUID, placement: StickerPlacement) async throws -> StackItem {
        guard url.scheme?.hasPrefix("http") == true else {
            throw AppError.invalidURL
        }

        let preview = await ProductPageImageExtractor.previewProductLink(for: url)

        return StackItem(
            id: UUID(),
            stackID: stackID,
            title: preview.title,
            brand: preview.brand,
            shortDescription: preview.shortDescription,
            price: preview.price ?? 0,
            currencyCode: preview.currencyCode,
            sourceURL: url,
            buyURL: url,
            affiliateURL: nil,
            originalImageURL: preview.imageURL,
            removedBackgroundImageURL: nil,
            removalStatus: .processing,
            placement: placement,
            addSource: .pastedLink,
            claimStatus: nil,
            demoGlyph: nil
        )
    }
}

struct ProductSearchEdgeFunctionConfiguration: Sendable {
    let endpoint: URL
    let anonKey: String

    static func fromAppBundle() -> Self? {
        guard let endpointString = configuredString(for: "STACKS_PRODUCT_SEARCH_URL"),
              let endpoint = URL(string: endpointString),
              endpoint.scheme == "https",
              let anonKey = configuredString(for: "STACKS_SUPABASE_ANON_KEY") else {
            return nil
        }
        return Self(endpoint: endpoint, anonKey: anonKey)
    }

    private static func configuredString(for key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("$(") else { return nil }
        return trimmed
    }
}

private struct ProductSearchRequest: Encodable {
    let query: String
    let country = "us"
    let language = "en"
    let limit = 12
}

private struct ProductSearchEdgeFunctionResponse: Decodable {
    let results: [ProductSearchEdgeFunctionResult]
    let error: String?

    private enum CodingKeys: String, CodingKey {
        case results
        case error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        results = try container.decodeIfPresent([ProductSearchEdgeFunctionResult].self, forKey: .results) ?? []
        error = try container.decodeIfPresent(String.self, forKey: .error)
    }
}

private struct ProductSearchEdgeFunctionResult: Decodable {
    let title: String
    let brand: String
    let price: Decimal
    let currencyCode: String
    let sourceURL: URL
    let imageURL: URL?
    let shortDescription: String
}

struct EdgeFunctionBackgroundRemovalService: BackgroundRemovalService {
    func removeBackground(for item: StackItem) async throws -> URL? {
        throw AppError.configurationRequired("Replicate rembg edge function")
    }
}

struct EdgeFunctionAffiliateService: AffiliateService {
    func affiliateURL(for url: URL) async throws -> URL {
        throw AppError.configurationRequired("Sovrn affiliate edge function")
    }
}

struct EdgeFunctionClaimService: ClaimService {
    func claim(item: StackItem, claimerName: String) async throws -> GiftClaim {
        throw AppError.configurationRequired("gift-claim edge function")
    }
}

struct SupabaseCollaborationService: CollaborationService {
    func invite(email: String, to stack: Stack) async throws -> Collaborator {
        throw AppError.configurationRequired("Supabase collaborators table")
    }
}

struct SupabaseStorageService: StorageService {
    func uploadImageData(_ data: Data, preferredName: String) async throws -> URL {
        throw AppError.configurationRequired("Supabase Storage")
    }
}

struct SupabaseRealtimeService: RealtimeService {
    func watchStack(id: UUID) async {}
    func stopWatchingStack(id: UUID) async {}
}

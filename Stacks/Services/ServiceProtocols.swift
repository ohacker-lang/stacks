import Foundation

protocol AuthService: Sendable {
    func restoreSession() async throws -> AuthSession?
    func signInWithApple() async throws -> AuthSession
    func signInWithEmail(_ email: String) async throws -> AuthSession
    func signOut() async throws
    func requestAccountDeletion() async throws
}

protocol StackRepository: Sendable {
    func fetchMyStacks(for userID: UUID) async throws -> [Stack]
    func fetchDiscoverStacks(query: String?) async throws -> [Stack]
    func createStack(title: String, wishlistMode: Bool, owner: UserProfile) async throws -> Stack
    func copyStack(_ stack: Stack, to owner: UserProfile) async throws -> Stack
    func addItem(_ item: StackItem, to stackID: UUID) async throws -> Stack
    func updateItem(_ item: StackItem, in stackID: UUID) async throws -> Stack
    func removeItem(id: UUID, from stackID: UUID) async throws -> Stack
    func toggleBookmark(stackID: UUID, userID: UUID) async throws -> Stack
    func toggleFollow(authorID: UUID, userID: UUID) async throws -> [Stack]
}

protocol ProfileRepository: Sendable {
    func currentProfile(for session: AuthSession) async throws -> UserProfile
    func suggestedCreators() async throws -> [UserProfile]
}

protocol ProductSearchService: Sendable {
    func searchProducts(query: String) async throws -> [ProductSearchResult]
    func previewProductLink(_ url: URL) async throws -> ProductLinkPreview
    func productFromPastedLink(_ url: URL, stackID: UUID, placement: StickerPlacement) async throws -> StackItem
}

protocol BackgroundRemovalService: Sendable {
    func removeBackground(for item: StackItem) async throws -> URL?
}

protocol AffiliateService: Sendable {
    func affiliateURL(for url: URL) async throws -> URL
}

protocol ClaimService: Sendable {
    func claim(item: StackItem, claimerName: String) async throws -> GiftClaim
}

protocol CollaborationService: Sendable {
    func invite(email: String, to stack: Stack) async throws -> Collaborator
}

protocol StorageService: Sendable {
    func uploadImageData(_ data: Data, preferredName: String) async throws -> URL
}

protocol RealtimeService: Sendable {
    func watchStack(id: UUID) async
    func stopWatchingStack(id: UUID) async
}

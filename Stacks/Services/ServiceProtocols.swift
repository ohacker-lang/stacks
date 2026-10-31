import Foundation

enum StacksLegalAgreement {
    static let version = "2026-09-21"
    static let termsURL = URL(string: "https://stacks.spot/terms")!
    static let privacyURL = URL(string: "https://stacks.spot/privacy")!
    static let affiliateURL = URL(string: "https://stacks.spot/affiliate")!
}

protocol AuthService: Sendable {
    func restoreSession() async throws -> AuthSession?
    func signInWithApple() async throws -> AuthSession
    func signInWithGoogle() async throws -> AuthSession
    func signInWithEmail(_ email: String) async throws -> EmailAuthenticationResult
    func handleAuthCallback(_ url: URL) async throws -> AuthSession?
    func verifyEmailCode(_ code: String, email: String) async throws -> AuthSession
    func recordLegalAcceptance(for userID: UUID, version: String) async throws
    func completeOnboarding(for userID: UUID) async throws
    func signOut() async throws
    func requestAccountDeletion() async throws
}

protocol StackRepository: Sendable {
    func fetchMyStacks(for userID: UUID) async throws -> [Stack]
    func fetchOwnedStackDestinations(for user: UserProfile) async throws -> [SharedStackDestination]
    func fetchStack(id: UUID, for userID: UUID) async throws -> Stack
    /// The Stacks shown on someone's public profile at stacks.spot/username.
    func fetchPublicStacks(ownerID: UUID, for viewerID: UUID) async throws -> [Stack]
    func fetchDiscoverStacks(query: String?) async throws -> [Stack]
    func createStack(title: String, wishlistMode: Bool, visibility: StackVisibility, owner: UserProfile) async throws -> Stack
    func fetchSharedStack(token: UUID) async throws -> Stack
    func copyStack(_ stack: Stack, to owner: UserProfile) async throws -> Stack
    func updateStack(_ stack: Stack) async throws -> Stack
    func rotateWishlistLink(stackID: UUID, revoke: Bool) async throws -> Stack
    func deleteStack(id: UUID) async throws
    func addItem(_ item: StackItem, to stackID: UUID) async throws -> Stack
    func updateItem(_ item: StackItem, in stackID: UUID) async throws -> Stack
    func removeItem(id: UUID, from stackID: UUID) async throws -> Stack
    func toggleBookmark(stackID: UUID, userID: UUID) async throws -> Stack
    func toggleFollow(authorID: UUID, userID: UUID) async throws -> [Stack]
}

protocol ProfileRepository: Sendable {
    func currentProfile(for session: AuthSession) async throws -> UserProfile
    func updateProfile(_ profile: UserProfile, avatarData: Data?) async throws -> UserProfile
    func enableProfileSharing() async throws
    /// Resolves a stacks.spot/username link. Returns nil for unknown or blocked accounts.
    func publicProfile(username: String) async throws -> UserProfile?
    func disableProfileSharing() async throws
    func suggestedCreators() async throws -> [UserProfile]
    func searchCreators(query: String) async throws -> [UserProfile]
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
    func resolveLink(for url: URL, countryCode: String?) async throws -> AffiliateLinkResolution
}

struct AffiliateLinkResolution: Sendable {
    let url: URL
    let isCommissionable: Bool
}

extension AffiliateService {
    func affiliateURL(for url: URL) async throws -> URL {
        let resolution = try await resolveLink(for: url, countryCode: Locale.current.region?.identifier)
        return resolution.url
    }
}

protocol ClaimService: Sendable {
    func claim(item: StackItem, in stack: Stack, claimerName: String) async throws -> GiftClaim
    func myClaimStatus(for item: StackItem) async throws -> GiftClaimStatus?
    func updateStatus(for item: StackItem, in stack: Stack, status: GiftClaimStatus?) async throws -> GiftClaimStatus?
}

protocol CollaborationService: Sendable {
    func createInvite(to stack: Stack, permission: CollaboratorPermission) async throws -> CollaborationInvite
    func previewInvite(token: UUID) async throws -> CollaborationInvitePreview
    func acceptInvite(token: UUID) async throws -> UUID
    func setCollaborationEnabled(stackID: UUID, enabled: Bool) async throws
    func removeCollaborator(stackID: UUID, userID: UUID) async throws
    func leaveStack(stackID: UUID) async throws
}

protocol StorageService: Sendable {
    func uploadImageData(_ data: Data, preferredName: String) async throws -> URL
}

protocol RealtimeService: Sendable {
    func watchStack(id: UUID) async
    func stopWatchingStack(id: UUID) async
}

protocol SafetyService: Sendable {
    func reportStack(id: UUID, reason: String) async throws
    func reportProfile(id: UUID, reason: String) async throws
    func blockUser(id: UUID) async throws
}

protocol PriceAlertService: Sendable {
    func list() async throws -> PriceAlertListing
    func save(itemID: UUID, mode: PriceAlertMode, targetPrice: Decimal?, linkToken: UUID?) async throws
    func delete(alertID: UUID) async throws
    func setPaused(_ paused: Bool, alertID: UUID) async throws
    func setNotificationsEnabled(_ enabled: Bool) async throws
    func markRead(eventID: UUID) async throws
}

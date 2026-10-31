import Foundation

actor MockAuthService: AuthService {
    private let seed: MockSeedData
    private var session: AuthSession?

    init(seed: MockSeedData) {
        self.seed = seed
    }

    func restoreSession() async throws -> AuthSession? {
        try await Task.sleep(for: .milliseconds(250))
        return session
    }

    func signInWithApple() async throws -> AuthSession {
        try await Task.sleep(for: .milliseconds(450))
        let session = AuthSession(
            userID: seed.currentUserID,
            email: "owen@example.com",
            displayName: seed.currentUser.displayName,
            hasCompletedOnboarding: false
        )
        self.session = session
        return session
    }

    func signInWithGoogle() async throws -> AuthSession {
        // Keep local builds and previews on the same onboarding path as the
        // production OAuth flow without opening an external browser.
        try await signInWithApple()
    }

    func signInWithEmail(_ email: String) async throws -> EmailAuthenticationResult {
        guard email.contains("@"), email.contains(".") else {
            throw AppError.invalidEmail
        }
        try await Task.sleep(for: .milliseconds(450))
        // Addresses starting with "code" exercise the emailed-code step.
        if email.lowercased().hasPrefix("code") { return .linkSent }
        let session = AuthSession(
            userID: seed.currentUserID,
            email: email,
            displayName: seed.currentUser.displayName,
            hasCompletedOnboarding: false
        )
        self.session = session
        return .authenticated(session)
    }

    func verifyEmailCode(_ code: String, email: String) async throws -> AuthSession {
        try await Task.sleep(for: .milliseconds(450))
        guard code == "123456" else { throw AppError.unavailable("Invalid code.") }
        let session = AuthSession(
            userID: seed.currentUserID,
            email: email,
            displayName: seed.currentUser.displayName,
            hasCompletedOnboarding: false
        )
        self.session = session
        return session
    }

    func handleAuthCallback(_ url: URL) async throws -> AuthSession? {
        // The mock sign-in never opens an external browser, but keeping this
        // route lets the app exercise the same callback plumbing as Supabase.
        session
    }

    func recordLegalAcceptance(for userID: UUID, version: String) async throws {
        guard session?.userID == userID, !version.isEmpty else { throw AppError.notFound }
    }

    func completeOnboarding(for userID: UUID) async throws {
        guard var session, session.userID == userID else {
            throw AppError.notFound
        }
        session.hasCompletedOnboarding = true
        self.session = session
    }

    func signOut() async throws {
        session = nil
    }

    func requestAccountDeletion() async throws {
        // The demo service has no remote data, so deleting the mock account
        // simply invalidates the local session.
        session = nil
    }
}

actor MockStackRepository: StackRepository {
    private let seed: MockSeedData
    private var myStacks: [Stack]
    private var discoverStacks: [Stack]

    init(seed: MockSeedData) {
        self.seed = seed
        self.myStacks = seed.myStacks
        self.discoverStacks = seed.discoverStacks
    }

    func fetchMyStacks(for userID: UUID) async throws -> [Stack] {
        try await Task.sleep(for: .milliseconds(250))
        return myStacks.filter {
            $0.ownerID == userID || $0.collaborators.contains(where: { $0.user.id == userID })
        }
    }

    func fetchOwnedStackDestinations(for user: UserProfile) async throws -> [SharedStackDestination] {
        myStacks.filter { $0.ownerID == user.id }
            .sorted { $0.updatedAt > $1.updatedAt }
            .map {
                SharedStackDestination(
                    id: $0.id,
                    title: $0.displayTitle,
                    ownerName: user.displayName,
                    avatarURL: user.avatarURL,
                    updatedAt: $0.updatedAt
                )
            }
    }

    func fetchPublicStacks(ownerID: UUID, for viewerID: UUID) async throws -> [Stack] {
        (myStacks + discoverStacks)
            .filter { $0.ownerID == ownerID && $0.visibility == .publicDiscover }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func fetchStack(id: UUID, for userID: UUID) async throws -> Stack {
        guard let stack = (myStacks + discoverStacks).first(where: { $0.id == id }),
              stack.ownerID == userID || stack.visibility == .publicDiscover || stack.visibility == .publicLink
                || stack.collaborators.contains(where: { $0.user.id == userID }) else {
            throw AppError.notFound
        }
        return stack
    }

    func fetchDiscoverStacks(query: String?) async throws -> [Stack] {
        try await Task.sleep(for: .milliseconds(250))
        let stacks = discoverStacks.sorted {
            if $0.isFollowingAuthor != $1.isFollowingAuthor {
                return $0.isFollowingAuthor
            }
            return $0.updatedAt > $1.updatedAt
        }
        guard let query, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return stacks
        }
        return stacks.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.author.displayName.localizedCaseInsensitiveContains(query)
                || $0.author.username.localizedCaseInsensitiveContains(query)
        }
    }

    func createStack(title: String, wishlistMode: Bool, visibility: StackVisibility, owner: UserProfile) async throws -> Stack {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else {
            throw AppError.missingRequiredField("Title")
        }
        let stack = Stack(
            id: UUID(),
            ownerID: owner.id,
            author: owner,
            title: cleanTitle,
            visibility: visibility,
            wishlistMode: wishlistMode,
            collaborators: [],
            items: [],
            publicLinkToken: visibility == .publicLink ? UUID() : nil,
            createdAt: Date(),
            updatedAt: Date(),
            isBookmarked: false,
            isFollowingAuthor: false
        )
        myStacks.insert(stack, at: 0)
        return stack
    }

    func fetchSharedStack(token: UUID) async throws -> Stack {
        guard let stack = (myStacks + discoverStacks).first(where: {
            $0.visibility == .publicLink && $0.publicLinkToken == token
        }) else {
            throw AppError.notFound
        }
        return stack
    }

    func copyStack(_ stack: Stack, to owner: UserProfile) async throws -> Stack {
        let copiedStackID = UUID()
        let copiedItems = stack.items.map { item in
            StackItem(
                id: UUID(),
                stackID: copiedStackID,
                title: item.title,
                brand: item.brand,
                shortDescription: item.shortDescription,
                price: item.price,
                currencyCode: item.currencyCode,
                sourceURL: item.sourceURL,
                buyURL: item.buyURL,
                affiliateURL: item.affiliateURL,
                originalImageURL: item.originalImageURL,
                removedBackgroundImageURL: item.removedBackgroundImageURL,
                removalStatus: item.removalStatus,
                placement: item.placement,
                addSource: item.addSource,
                claimStatus: nil,
                demoGlyph: item.demoGlyph
            )
        }
        let copy = Stack(
            id: copiedStackID,
            ownerID: owner.id,
            author: owner,
            title: stack.title,
            visibility: .private,
            wishlistMode: stack.wishlistMode,
            collaborators: [],
            items: copiedItems,
            createdAt: Date(),
            updatedAt: Date(),
            isBookmarked: false,
            isFollowingAuthor: false
        )
        myStacks.insert(copy, at: 0)
        return copy
    }

    func updateStack(_ stack: Stack) async throws -> Stack {
        guard let index = myStacks.firstIndex(where: { $0.id == stack.id }) else {
            throw AppError.notFound
        }
        var updated = stack
        updated.updatedAt = Date()
        myStacks[index] = updated
        return updated
    }

    func rotateWishlistLink(stackID: UUID, revoke: Bool) async throws -> Stack {
        guard let index = myStacks.firstIndex(where: { $0.id == stackID }), myStacks[index].wishlistMode else {
            throw AppError.notFound
        }
        myStacks[index].publicLinkToken = UUID()
        myStacks[index].visibility = revoke ? .private : .publicLink
        myStacks[index].updatedAt = Date()
        return myStacks[index]
    }

    func deleteStack(id: UUID) async throws {
        guard let index = myStacks.firstIndex(where: { $0.id == id }) else {
            throw AppError.notFound
        }
        myStacks.remove(at: index)
    }

    func addItem(_ item: StackItem, to stackID: UUID) async throws -> Stack {
        guard let index = myStacks.firstIndex(where: { $0.id == stackID }) else {
            throw AppError.notFound
        }
        myStacks[index].items.append(item)
        myStacks[index].updatedAt = Date()
        return myStacks[index]
    }

    func updateItem(_ item: StackItem, in stackID: UUID) async throws -> Stack {
        if let index = myStacks.firstIndex(where: { $0.id == stackID }),
           let itemIndex = myStacks[index].items.firstIndex(where: { $0.id == item.id }) {
            myStacks[index].items[itemIndex] = item
            myStacks[index].updatedAt = Date()
            return myStacks[index]
        }

        if let index = discoverStacks.firstIndex(where: { $0.id == stackID }),
           let itemIndex = discoverStacks[index].items.firstIndex(where: { $0.id == item.id }) {
            discoverStacks[index].items[itemIndex] = item
            discoverStacks[index].updatedAt = Date()
            return discoverStacks[index]
        }

        throw AppError.notFound
    }

    func removeItem(id: UUID, from stackID: UUID) async throws -> Stack {
        guard let stackIndex = myStacks.firstIndex(where: { $0.id == stackID }),
              let itemIndex = myStacks[stackIndex].items.firstIndex(where: { $0.id == id }) else {
            throw AppError.notFound
        }

        myStacks[stackIndex].items.remove(at: itemIndex)
        myStacks[stackIndex].updatedAt = Date()
        return myStacks[stackIndex]
    }

    func toggleBookmark(stackID: UUID, userID: UUID) async throws -> Stack {
        if let index = discoverStacks.firstIndex(where: { $0.id == stackID }) {
            discoverStacks[index].isBookmarked.toggle()
            return discoverStacks[index]
        }
        if let index = myStacks.firstIndex(where: { $0.id == stackID }) {
            myStacks[index].isBookmarked.toggle()
            return myStacks[index]
        }
        throw AppError.notFound
    }

    func toggleFollow(authorID: UUID, userID: UUID) async throws -> [Stack] {
        for index in discoverStacks.indices where discoverStacks[index].author.id == authorID {
            discoverStacks[index].isFollowingAuthor.toggle()
            discoverStacks[index].author.isFollowing = discoverStacks[index].isFollowingAuthor
        }
        for index in myStacks.indices where myStacks[index].author.id == authorID {
            myStacks[index].isFollowingAuthor.toggle()
            myStacks[index].author.isFollowing = myStacks[index].isFollowingAuthor
        }
        return discoverStacks.sorted {
            if $0.isFollowingAuthor != $1.isFollowingAuthor {
                return $0.isFollowingAuthor
            }
            return $0.updatedAt > $1.updatedAt
        }
    }
}

actor MockProfileRepository: ProfileRepository {
    private let seed: MockSeedData
    private var currentProfile: UserProfile

    init(seed: MockSeedData) {
        self.seed = seed
        currentProfile = seed.currentUser
    }

    func currentProfile(for session: AuthSession) async throws -> UserProfile {
        try await Task.sleep(for: .milliseconds(150))
        return currentProfile
    }

    func updateProfile(_ profile: UserProfile, avatarData: Data?) async throws -> UserProfile {
        guard profile.id == currentProfile.id else { throw AppError.notFound }
        currentProfile = profile
        return profile
    }

    func enableProfileSharing() async throws {}

    func publicProfile(username: String) async throws -> UserProfile? {
        ([currentProfile] + (try await suggestedCreators()))
            .first { $0.username.caseInsensitiveCompare(username) == .orderedSame }
    }

    func disableProfileSharing() async throws {}

    func suggestedCreators() async throws -> [UserProfile] {
        try await Task.sleep(for: .milliseconds(150))
        return [
            seed.isabella,
            UserProfile(
                id: UUID(uuidString: "43986D8E-0F80-4D5B-A188-6102E9A6330A")!,
                displayName: "Mina Park",
                username: "mina",
                avatarURL: nil,
                bio: "Design objects, small rituals, better gifts.",
                linkInBioURL: URL(string: "https://stacks.example/mina"),
                isFollowing: false
            )
        ]
    }

    func searchCreators(query: String) async throws -> [UserProfile] {
        let creators = try await suggestedCreators()
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanQuery.isEmpty else { return creators }
        return creators.filter {
            $0.displayName.localizedCaseInsensitiveContains(cleanQuery)
                || $0.username.localizedCaseInsensitiveContains(cleanQuery)
        }
    }
}

actor MockProductSearchService: ProductSearchService {
    func searchProducts(query: String) async throws -> [ProductSearchResult] {
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanQuery.isEmpty else { return [] }
        try await Task.sleep(for: .milliseconds(350))

        return [
            ProductSearchResult(
                id: UUID(),
                title: "\(cleanQuery) Studio Edition",
                brand: "Stacks Market",
                price: 64,
                currencyCode: "USD",
                sourceURL: URL(string: "https://example.com/products/\(cleanQuery.linkSlug)-studio")!,
                imageURL: DemoProductImageCatalog.url(for: cleanQuery),
                shortDescription: "A clean, collectible take on \(cleanQuery.lowercased()), ready to float on a Stack.",
                demoGlyph: nil
            ),
            ProductSearchResult(
                id: UUID(),
                title: "\(cleanQuery) Mini",
                brand: "Small Goods",
                price: 28,
                currencyCode: "USD",
                sourceURL: URL(string: "https://example.com/products/\(cleanQuery.linkSlug)-mini")!,
                imageURL: DemoProductImageCatalog.url(for: "\(cleanQuery) mini"),
                shortDescription: "Tiny, graphic, and exactly the kind of thing people ask about.",
                demoGlyph: nil
            )
        ]
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

actor MockBackgroundRemovalService: BackgroundRemovalService {
    func removeBackground(for item: StackItem) async throws -> URL? {
        try await Task.sleep(for: .seconds(1))
        return item.originalImageURL
    }
}

actor MockAffiliateService: AffiliateService {
    func resolveLink(for url: URL, countryCode: String?) async throws -> AffiliateLinkResolution {
        AffiliateLinkResolution(url: url, isCommissionable: false)
    }
}

actor MockSafetyService: SafetyService {
    func reportStack(id: UUID, reason: String) async throws {}
    func reportProfile(id: UUID, reason: String) async throws {}
    func blockUser(id: UUID) async throws {}
}

actor MockClaimService: ClaimService {
    func myClaimStatus(for item: StackItem) async throws -> GiftClaimStatus? { nil }
    func claim(item: StackItem, in stack: Stack, claimerName: String) async throws -> GiftClaim {
        GiftClaim(
            id: UUID(),
            itemID: item.id,
            stackID: item.stackID,
            claimerName: claimerName,
            privateMessage: nil,
            status: .claimed,
            createdAt: Date()
        )
    }

    func updateStatus(for item: StackItem, in stack: Stack, status: GiftClaimStatus?) async throws -> GiftClaimStatus? {
        status
    }
}

actor MockCollaborationService: CollaborationService {
    private let seed: MockSeedData
    private var invites: [UUID: CollaborationInvitePreview] = [:]

    init(seed: MockSeedData) {
        self.seed = seed
    }

    func createInvite(to stack: Stack, permission: CollaboratorPermission) async throws -> CollaborationInvite {
        let invite = CollaborationInvite(
            id: UUID(),
            stackID: stack.id,
            token: UUID(),
            permission: permission,
            expiresAt: Calendar.current.date(byAdding: .day, value: 7, to: Date())!
        )
        invites[invite.token] = CollaborationInvitePreview(
            token: invite.token,
            stackID: stack.id,
            stackTitle: stack.displayTitle,
            owner: stack.author,
            permission: permission,
            expiresAt: invite.expiresAt
        )
        return invite
    }

    func previewInvite(token: UUID) async throws -> CollaborationInvitePreview {
        guard let preview = invites[token] else { throw AppError.notFound }
        return preview
    }

    func acceptInvite(token: UUID) async throws -> UUID {
        guard let preview = invites.removeValue(forKey: token) else { throw AppError.notFound }
        return preview.stackID
    }

    func setCollaborationEnabled(stackID: UUID, enabled: Bool) async throws {}
    func removeCollaborator(stackID: UUID, userID: UUID) async throws {}
    func leaveStack(stackID: UUID) async throws {}
}

actor MockStorageService: StorageService {
    func uploadImageData(_ data: Data, preferredName: String) async throws -> URL {
        guard !data.isEmpty else {
            throw AppError.missingRequiredField("Image")
        }

        // Application Support survives ordinary cache eviction. This keeps a
        // saved imported item visually intact in the demo/local path until
        // Supabase Storage is configured for the signed-in production user.
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("Stacks/OriginalUploads", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let fileName = "\(preferredName.linkSlug)-\(UUID().uuidString).jpg"
        let url = directory.appendingPathComponent(fileName)
        try data.write(to: url, options: [.atomic])
        return url
    }
}

actor MockRealtimeService: RealtimeService {
    func watchStack(id: UUID) async {}
    func stopWatchingStack(id: UUID) async {}
}

private extension String {
    var linkSlug: String {
        lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
    }

    var bestDemoGlyph: String {
        let lower = lowercased()
        if lower.contains("ball") { return "🏀" }
        if lower.contains("lamp") { return "💡" }
        if lower.contains("book") { return "📚" }
        if lower.contains("shoe") { return "👟" }
        if lower.contains("banana") { return "🍌" }
        if lower.contains("camera") { return "📷" }
        return "🧩"
    }
}

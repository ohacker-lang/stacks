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

    func signInWithEmail(_ email: String) async throws -> AuthSession {
        guard email.contains("@"), email.contains(".") else {
            throw AppError.invalidEmail
        }
        try await Task.sleep(for: .milliseconds(450))
        let session = AuthSession(
            userID: seed.currentUserID,
            email: email,
            displayName: seed.currentUser.displayName,
            hasCompletedOnboarding: false
        )
        self.session = session
        return session
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
        return myStacks.filter { $0.ownerID == userID }
    }

    func fetchDiscoverStacks(query: String?) async throws -> [Stack] {
        try await Task.sleep(for: .milliseconds(250))
        let stacks = discoverStacks
        guard let query, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return stacks
        }
        return stacks.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.author.displayName.localizedCaseInsensitiveContains(query)
                || $0.author.username.localizedCaseInsensitiveContains(query)
        }
    }

    func createStack(title: String, wishlistMode: Bool, owner: UserProfile) async throws -> Stack {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else {
            throw AppError.missingRequiredField("Title")
        }
        let stack = Stack(
            id: UUID(),
            ownerID: owner.id,
            author: owner,
            title: cleanTitle,
            summary: "A new canvas for things you love.",
            visibility: .private,
            wishlistMode: wishlistMode,
            collaborators: [],
            items: [],
            createdAt: Date(),
            updatedAt: Date(),
            isBookmarked: false,
            isFollowingAuthor: false
        )
        myStacks.insert(stack, at: 0)
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
            summary: stack.summary,
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
        return discoverStacks
    }
}

actor MockProfileRepository: ProfileRepository {
    private let seed: MockSeedData

    init(seed: MockSeedData) {
        self.seed = seed
    }

    func currentProfile(for session: AuthSession) async throws -> UserProfile {
        try await Task.sleep(for: .milliseconds(150))
        return seed.currentUser
    }

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
    func affiliateURL(for url: URL) async throws -> URL {
        URL(string: "https://go.example.com?url=\(url.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") ?? url
    }
}

actor MockClaimService: ClaimService {
    func claim(item: StackItem, claimerName: String) async throws -> GiftClaim {
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
}

actor MockCollaborationService: CollaborationService {
    private let seed: MockSeedData

    init(seed: MockSeedData) {
        self.seed = seed
    }

    func invite(email: String, to stack: Stack) async throws -> Collaborator {
        guard email.contains("@") else { throw AppError.invalidEmail }
        return Collaborator(
            id: UUID(),
            user: seed.isabella,
            permission: .edit,
            invitedAt: Date()
        )
    }
}

actor MockStorageService: StorageService {
    func uploadImageData(_ data: Data, preferredName: String) async throws -> URL {
        guard !data.isEmpty else {
            throw AppError.missingRequiredField("Image")
        }

        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OriginalUploads", isDirectory: true)
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

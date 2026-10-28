import Foundation

/// Editorial Stacks are read-only content served by stacks.spot. They are not
/// Supabase users, so updating the website catalog updates the app feed without
/// creating a login or publishing a new app binary.
enum CuratedStackCatalog {
    static let profileID = UUID(uuidString: "BA3B2730-7A5B-4D1E-8602-74A926B33F20")!
    static let fallResetID = UUID(uuidString: "49949342-C9A7-400E-B43F-A992A8522951")!
    private static let knownStackIDsKey = "stacks.curatedStackIDs"

    static func isCuratedProfile(_ id: UUID) -> Bool { id == profileID }
    static func isCuratedStack(_ id: UUID) -> Bool {
        id == fallResetID || UserDefaults.standard.stringArray(forKey: knownStackIDsKey)?.contains(id.uuidString) == true
    }

    static func fetchStacks() async throws -> [Stack] {
        var request = URLRequest(url: URL(string: "https://stacks.spot/api/curated")!)
        request.timeoutInterval = 8
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            throw CuratedCatalogError.unavailable
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let catalog = try decoder.decode(Catalog.self, from: data)
        guard catalog.profile.id == profileID else { throw CuratedCatalogError.unavailable }
        UserDefaults.standard.set(catalog.stacks.map { $0.id.uuidString }, forKey: knownStackIDsKey)

        let author = UserProfile(
            id: catalog.profile.id,
            displayName: catalog.profile.displayName,
            username: catalog.profile.username,
            avatarURL: catalog.profile.avatarURL,
            bio: catalog.profile.bio,
            linkInBioURL: URL(string: "https://stacks.spot/aliva"),
            isFollowing: false,
            profileShareEnabled: true
        )

        return catalog.stacks.map { entry in
            Stack(
                id: entry.id,
                ownerID: author.id,
                author: author,
                title: entry.title,
                visibility: .publicDiscover,
                wishlistMode: false,
                collaborators: [],
                items: entry.items.enumerated().map { index, item in
                    StackItem(
                        id: item.id,
                        stackID: entry.id,
                        title: item.title,
                        brand: item.brand,
                        shortDescription: "",
                        price: 0,
                        currencyCode: "USD",
                        sourceURL: item.sourceURL,
                        buyURL: item.sourceURL,
                        affiliateURL: nil,
                        originalImageURL: item.imageURL,
                        removedBackgroundImageURL: item.imageURL,
                        removalStatus: item.imageURL == nil ? .failed : .complete,
                        placement: StickerPlacement(
                            xRatio: index.isMultiple(of: 2) ? 0.29 : 0.71,
                            yRatio: Double(index / 2 + 1) / Double((entry.items.count + 1) / 2 + 1),
                            scale: 1,
                            rotationDegrees: 0
                        ),
                        hasCustomPlacement: false,
                        addSource: .pastedLink,
                        claimStatus: nil
                    )
                },
                createdAt: entry.createdAt,
                updatedAt: entry.updatedAt,
                isBookmarked: false,
                isFollowingAuthor: false
            )
        }
    }

    private struct Catalog: Decodable {
        let profile: Curator
        let stacks: [Entry]
    }

    private struct Curator: Decodable {
        let id: UUID
        let displayName: String
        let username: String
        let bio: String
        let avatarURL: URL?
    }

    private struct Entry: Decodable {
        let id: UUID
        let title: String
        let createdAt: Date
        let updatedAt: Date
        let items: [Item]
    }

    private struct Item: Decodable {
        let id: UUID
        let title: String
        let brand: String
        let imageURL: URL?
        let sourceURL: URL
    }

    private enum CuratedCatalogError: Error {
        case unavailable
    }
}

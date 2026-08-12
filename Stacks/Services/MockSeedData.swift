import Foundation

struct MockSeedData: Sendable {
    let currentUserID = UUID(uuidString: "2DB1814B-145C-478F-A730-0D5F47EF6B93")!
    let isabellaID = UUID(uuidString: "796EF807-A099-42B0-B1BE-D5E16D0A7891")!
    let stackID = UUID(uuidString: "B19D9F63-938F-4AE2-8B7A-6569D2E5C63E")!

    var currentUser: UserProfile {
        UserProfile(
            id: currentUserID,
            displayName: "Owen Hacker",
            username: "owen",
            avatarURL: nil,
            bio: "Collecting beautiful, useful things.",
            linkInBioURL: URL(string: "https://stacks.example/owen"),
            isFollowing: false
        )
    }

    var isabella: UserProfile {
        UserProfile(
            id: isabellaID,
            displayName: "Isabella Martinez",
            username: "isabella",
            avatarURL: nil,
            bio: "Objects, jokes, and tiny visual obsessions.",
            linkInBioURL: URL(string: "https://stacks.example/isabella"),
            isFollowing: true
        )
    }

    var myStacks: [Stack] {
        [
            makeReferenceStack(owner: currentUser, title: "Summer", isMine: true),
            Stack(
                id: UUID(uuidString: "80DAB29E-6623-4D5F-82F8-3486808DE7A0")!,
                ownerID: currentUserID,
                author: currentUser,
                title: "Desk Dreams",
                summary: "Work Mode",
                visibility: .publicDiscover,
                wishlistMode: false,
                collaborators: [],
                items: deskItems(stackID: UUID(uuidString: "80DAB29E-6623-4D5F-82F8-3486808DE7A0")!),
                createdAt: Date(timeIntervalSince1970: 1_775_580_000),
                updatedAt: Date(timeIntervalSince1970: 1_775_580_000),
                isBookmarked: false,
                isFollowingAuthor: false
            )
        ]
    }

    var discoverStacks: [Stack] {
        [
            makeReferenceStack(owner: isabella, title: "Summer", isMine: false),
            Stack(
                id: UUID(uuidString: "2F51A9C0-CFF0-4AEF-AD81-8139BFA33FC1")!,
                ownerID: isabellaID,
                author: isabella,
                title: "Good Luck Charms",
                summary: "Lucky Things",
                visibility: .publicDiscover,
                wishlistMode: true,
                collaborators: [],
                items: charmItems(stackID: UUID(uuidString: "2F51A9C0-CFF0-4AEF-AD81-8139BFA33FC1")!),
                createdAt: Date(timeIntervalSince1970: 1_775_493_000),
                updatedAt: Date(timeIntervalSince1970: 1_775_493_000),
                isBookmarked: true,
                isFollowingAuthor: true
            )
        ]
    }

    func makeReferenceStack(owner: UserProfile, title: String, isMine: Bool) -> Stack {
        Stack(
            id: isMine ? stackID : UUID(uuidString: "6056C082-B3A0-4E2E-BC46-F0EE5B782735")!,
            ownerID: owner.id,
            author: owner,
            title: title,
            summary: "The Creative",
            visibility: .publicDiscover,
            wishlistMode: false,
            collaborators: [],
            items: referenceItems(stackID: isMine ? stackID : UUID(uuidString: "6056C082-B3A0-4E2E-BC46-F0EE5B782735")!),
            createdAt: Date(timeIntervalSince1970: 1_775_232_000),
            updatedAt: Date(timeIntervalSince1970: 1_775_232_000),
            isBookmarked: !isMine,
            isFollowingAuthor: !isMine
        )
    }

    private func referenceItems(stackID: UUID) -> [StackItem] {
        [
            item(stackID: stackID, title: "Graphic T-Shirt", brand: "Studio Summer", price: 68, glyph: "", x: 0.12, y: 0.12, scale: 1.05, rotation: -3, description: "A bright cotton tee for the start of the season."),
            item(stackID: stackID, title: "Gallery Tee", brand: "Studio Summer", price: 72, glyph: "", x: 0.37, y: 0.12, scale: 1.0, rotation: 1, description: "A softer white tee with a framed print."),
            item(stackID: stackID, title: "Denim Shorts", brand: "Studio Summer", price: 94, glyph: "", x: 0.62, y: 0.12, scale: 1.08, rotation: -2, description: "Easy denim with the right amount of wear."),
            item(stackID: stackID, title: "Charcoal Sweatshirt", brand: "Studio Summer", price: 128, glyph: "", x: 0.87, y: 0.12, scale: 1.06, rotation: 2, description: "A dark layer for cold evenings."),
            item(stackID: stackID, title: "Puffer Jacket", brand: "Studio Summer", price: 180, glyph: "", x: 0.12, y: 0.39, scale: 1.08, rotation: -2, description: "A graphic jacket that carries a full look."),
            item(stackID: stackID, title: "Black Trench", brand: "Studio Summer", price: 210, glyph: "", x: 0.37, y: 0.39, scale: 1.05, rotation: 1, description: "A long black layer with easy structure."),
            item(stackID: stackID, title: "Patterned Jacket", brand: "Studio Summer", price: 198, glyph: "", x: 0.62, y: 0.39, scale: 1.06, rotation: -1, description: "A bold layer with a little texture."),
            item(stackID: stackID, title: "Slip Dress", brand: "Studio Summer", price: 118, glyph: "", x: 0.87, y: 0.39, scale: 1.02, rotation: 2, description: "A simple dress for late dinners."),
            item(stackID: stackID, title: "White Robe", brand: "Studio Summer", price: 142, glyph: "", x: 0.12, y: 0.66, scale: 1.03, rotation: -1, description: "Soft cotton for slower mornings."),
            item(stackID: stackID, title: "Black Robe", brand: "Studio Summer", price: 142, glyph: "", x: 0.37, y: 0.66, scale: 1.03, rotation: 1, description: "The dark version, equally easy."),
            item(stackID: stackID, title: "Red Sneaker", brand: "Studio Summer", price: 96, glyph: "", x: 0.62, y: 0.66, scale: 1.02, rotation: -2, description: "A red sneaker to break up the neutrals."),
            item(stackID: stackID, title: "Black Tote Bag", brand: "Studio Summer", price: 154, glyph: "", x: 0.87, y: 0.66, scale: 1.06, rotation: 1, description: "A carryall that keeps the rest together.")
        ]
    }

    private func deskItems(stackID: UUID) -> [StackItem] {
        [
            item(stackID: stackID, title: "Chrome Task Lamp", brand: "Anglepoise", price: 160, glyph: "💡", x: 0.25, y: 0.22, scale: 1.1, rotation: -6, description: "A clean pool of light for late edits and early ideas."),
            item(stackID: stackID, title: "Dot Grid Notebook", brand: "Leuchtturm", price: 28, glyph: "📓", x: 0.68, y: 0.34, scale: 1.08, rotation: 7, description: "A quiet place to make messy thinking look intentional."),
            item(stackID: stackID, title: "Black Fountain Pen", brand: "Kaweco", price: 35, glyph: "🖋️", x: 0.42, y: 0.64, scale: 1.0, rotation: -12, description: "A tiny ritual for signing, sketching, and pretending emails are not real.")
        ]
    }

    private func charmItems(stackID: UUID) -> [StackItem] {
        [
            item(stackID: stackID, title: "Lucky Matchbook", brand: "Hotel Shop", price: 16, glyph: "🎫", x: 0.3, y: 0.2, scale: 0.9, rotation: -8, description: "A miniature souvenir that makes the whole table feel cinematic."),
            item(stackID: stackID, title: "Pearl Dice", brand: "Dice House", price: 44, glyph: "🎲", x: 0.7, y: 0.35, scale: 1.1, rotation: 10, description: "Glossy little odds, ready to make a shelf look luckier."),
            item(stackID: stackID, title: "Ribbon Pin", brand: "Ribbon Room", price: 22, glyph: "🎀", x: 0.45, y: 0.62, scale: 1.0, rotation: 3, description: "Sweet, graphic, and just sharp enough to keep the stack awake.")
        ]
    }

    private func item(
        stackID: UUID,
        title: String,
        brand: String,
        price: Decimal,
        glyph: String,
        x: Double,
        y: Double,
        scale: Double,
        rotation: Double,
        description: String
    ) -> StackItem {
        StackItem(
            id: UUID(),
            stackID: stackID,
            title: title,
            brand: brand,
            shortDescription: description,
            price: price,
            currencyCode: "USD",
            sourceURL: URL(string: "https://example.com/products/\(title.slugified)")!,
            buyURL: URL(string: "https://example.com/products/\(title.slugified)")!,
            affiliateURL: URL(string: "https://go.example.com/\(title.slugified)")!,
            originalImageURL: nil,
            removedBackgroundImageURL: nil,
            removalStatus: .complete,
            placement: StickerPlacement(xRatio: x, yRatio: y, scale: scale, rotationDegrees: rotation),
            addSource: .search,
            claimStatus: nil,
            demoGlyph: glyph
        )
    }
}

private extension String {
    var slugified: String {
        lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
    }
}

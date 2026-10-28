import Foundation

struct MockSeedData: Sendable {
    private typealias SeedProduct = (title: String, brand: String, price: Decimal, description: String)

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
            makeTemplateStack(
                id: "AF735F3C-90FD-4AB2-8A47-23E316B40C11",
                owner: currentUser,
                title: "Weekend Uniform",
                visibility: .publicDiscover,
                wishlistMode: false,
                ageInDays: 1,
                products: weekendUniformProducts
            ),
            makeTemplateStack(
                id: "4A62D874-45B3-47A3-94C8-E6AD42AB3741",
                owner: currentUser,
                title: "Lighting I Keep Thinking About",
                visibility: .publicLink,
                wishlistMode: true,
                ageInDays: 2,
                products: lightingProducts
            ),
            makeTemplateStack(
                id: "D0B12EE4-1248-47AC-A6D0-7B22D5D1586A",
                owner: currentUser,
                title: "A Good Weekend Indoors",
                visibility: .publicDiscover,
                wishlistMode: false,
                ageInDays: 2.5,
                products: weekendIndoorsProducts
            ),
            makeTemplateStack(
                id: "29B0C3FE-4AD8-40DF-9A3B-D8B915E0E87A",
                owner: currentUser,
                title: "Everyday Carry",
                visibility: .private,
                wishlistMode: false,
                ageInDays: 3,
                products: everydayCarryProducts
            ),
        ]
    }

    var discoverStacks: [Stack] {
        [
            makeTemplateStack(
                id: "B199C993-B912-4EDB-BD67-39621E3D42BE",
                owner: isabella,
                title: "Blue Hour",
                visibility: .publicDiscover,
                wishlistMode: false,
                ageInDays: 1,
                products: blueHourProducts,
                isBookmarked: true
            ),
            makeTemplateStack(
                id: "4F867896-FD29-448D-A0DD-89BD272BF3AE",
                owner: isabella,
                title: "Warm Little Rooms",
                visibility: .publicDiscover,
                wishlistMode: true,
                ageInDays: 2,
                products: warmRoomProducts
            ),
            makeTemplateStack(
                id: "B94D9F08-D10E-41D2-B820-E4A985E73252",
                owner: isabella,
                title: "Carry-On Only",
                visibility: .publicDiscover,
                wishlistMode: false,
                ageInDays: 3,
                products: carryOnProducts,
                isBookmarked: true
            ),
            Stack(
                id: UUID(uuidString: "2F51A9C0-CFF0-4AEF-AD81-8139BFA33FC1")!,
                ownerID: isabellaID,
                author: isabella,
                title: "Good Luck Charms",
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

    private func makeTemplateStack(
        id: String,
        owner: UserProfile,
        title: String,
        visibility: StackVisibility,
        wishlistMode: Bool,
        ageInDays: Double,
        products: [SeedProduct],
        isBookmarked: Bool = false
    ) -> Stack {
        let stackID = UUID(uuidString: id)!
        let date = Date().addingTimeInterval(-ageInDays * 86_400)
        return Stack(
            id: stackID,
            ownerID: owner.id,
            author: owner,
            title: title,
            visibility: visibility,
            wishlistMode: wishlistMode,
            collaborators: [],
            items: templateItems(stackID: stackID, products: products),
            createdAt: date.addingTimeInterval(-86_400 * 12),
            updatedAt: date,
            isBookmarked: isBookmarked,
            isFollowingAuthor: owner.id != currentUserID
        )
    }

    private func templateItems(stackID: UUID, products: [SeedProduct]) -> [StackItem] {
        let placements: [(Double, Double, Double, Double)] = [
            (0.18, 0.16, 0.92, -8), (0.49, 0.14, 1.05, 4), (0.79, 0.18, 0.88, 8),
            (0.30, 0.38, 1.08, 5), (0.65, 0.37, 0.96, -5), (0.87, 0.46, 0.78, 7),
            (0.14, 0.61, 0.82, -7), (0.46, 0.59, 1.04, 3), (0.76, 0.65, 0.94, -4),
            (0.26, 0.82, 0.90, 6), (0.57, 0.82, 1.02, -6), (0.84, 0.84, 0.82, 5)
        ]

        return products.enumerated().map { index, product in
            let placement = placements[index % placements.count]
            return item(
                stackID: stackID,
                title: product.title,
                brand: product.brand,
                price: product.price,
                glyph: "",
                x: placement.0,
                y: placement.1,
                scale: placement.2,
                rotation: placement.3,
                description: product.description
            )
        }
    }

    private var weekendUniformProducts: [SeedProduct] {
        [
            ("Ramblin Cord Cap", "Ramblin", 42, "A soft blue cord cap with the perfect faded vacation energy."),
            ("Navy Script Cap", "Passin Thru", 38, "An easy navy cap that already feels broken in."),
            ("Film Crew Cap", "Archive Supply", 34, "A low-profile canvas cap for pretending every day is a location shoot."),
            ("Boston Red Cap", "Boston Athletic", 40, "A bright red cap that does all the work in a simple outfit."),
            ("Forest Green Tee", "Field Notes", 52, "A heavyweight green tee with a relaxed vintage shape."),
            ("Memorial Graphic Tee", "Memory Motel", 68, "A graphic white tee that looks collected rather than designed."),
            ("Cobalt Windbreaker", "North Line", 148, "A crisp blue shell for windy evenings and sudden rain."),
            ("Navy Adidas Shorts", "Adidas", 64, "Short running shorts with a clean navy-and-white finish."),
            ("Gingham Boxer Shorts", "Studio Summer", 58, "Airy gingham shorts that work at home or over swimwear."),
            ("Black Samba Sneakers", "Adidas", 120, "Black leather Sambas with warm cream stripes and gum soles."),
            ("Studio Sneakers", "Maison Archive", 190, "Paint-speckled trainers that make basics feel intentional."),
            ("Canvas Weekender", "Workshop", 136, "A soft duffel with enough room for one very good weekend.")
        ]
    }

    private var lightingProducts: [SeedProduct] {
        [
            ("Orange Mushroom Lamp", "Murano Mood", 240, "A glossy orange pool of light for a side table."),
            ("Aqua Mushroom Lamp", "Murano Mood", 228, "A cool aqua mushroom lamp with a soft sculptural silhouette."),
            ("Red Mushroom Lamp", "Murano Mood", 235, "A saturated red lamp that makes a room feel instantly warmer."),
            ("Blue Orb Lamp", "Orbital", 198, "A blue globe lamp with a calm late-night glow."),
            ("Black Ribbed Lamp", "Forma", 184, "A dark ribbed base that gives a shelf a little architecture."),
            ("Burgundy Shade Lamp", "Atelier 78", 212, "A deep burgundy shade with hotel-lobby drama."),
            ("Green Dome Lamp", "Forma", 176, "A compact green dome lamp for a desk or reading corner."),
            ("Tall Green Lamp", "Forma", 260, "A tall green silhouette that can anchor an empty corner."),
            ("Navy Dome Lamp", "Night Studio", 190, "A navy dome lamp with focused, flattering light."),
            ("Pleated Blue Lamp", "Soft Focus", 168, "A pleated blue shade that feels handmade and slightly nostalgic."),
            ("Red Shade Lamp", "Atelier 78", 205, "A warm red shade for evenings when overhead lighting is forbidden."),
            ("Yellow Stem Lamp", "Sunroom", 154, "A slim yellow lamp that brings daylight energy after dark.")
        ]
    }

    private var everydayCarryProducts: [SeedProduct] {
        [
            ("Everyday Keyring", "Utility Objects", 32, "A compact key set that looks better than the keys deserve."),
            ("Illustrated Canvas Tote", "Sunday Press", 46, "A roomy cream tote with a tiny illustrated cyclist."),
            ("Leather Zip Wallet", "Field Leather", 78, "A warm brown zip wallet that improves with scratches."),
            ("Vintage Gold Watch", "West End Time", 220, "A slim gold watch with exactly the right amount of shine."),
            ("Pearl Drop Earrings", "Objet Studio", 88, "Small pearl drops that can rescue a plain T-shirt."),
            ("Weekend Red Wine", "House Bottle", 28, "The bottle to bring when you do not know what dinner is."),
            ("Essential White Tee", "Everyday Standard", 54, "A clean white tee with a close neck and easy body.")
        ]
    }

    private var weekendIndoorsProducts: [SeedProduct] {
        Array(weekendUniformProducts.prefix(6)) + Array(lightingProducts.prefix(6))
    }

    private var blueHourProducts: [SeedProduct] {
        [
            ("Cobalt Windbreaker", "North Line", 148, "A blue shell for the hour after sunset."),
            ("Navy Adidas Shorts", "Adidas", 64, "Quick shorts for city runs and coffee afterward."),
            ("Black Samba Sneakers", "Adidas", 120, "The pair that makes every travel outfit work."),
            ("Ramblin Cord Cap", "Ramblin", 42, "A faded blue cap with just enough color."),
            ("Blue Orb Lamp", "Orbital", 198, "A small blue glow for the end of the day."),
            ("Canvas Weekender", "Workshop", 136, "One bag for an unplanned overnight.")
        ]
    }

    private var warmRoomProducts: [SeedProduct] {
        [
            ("Orange Mushroom Lamp", "Murano Mood", 240, "The instant focal point."),
            ("Red Mushroom Lamp", "Murano Mood", 235, "Warm red glass for a low shelf."),
            ("Burgundy Shade Lamp", "Atelier 78", 212, "A deep shade with soft hotel light."),
            ("Yellow Stem Lamp", "Sunroom", 154, "A little artificial sunshine."),
            ("Red Shade Lamp", "Atelier 78", 205, "The no-overhead-lighting lamp."),
            ("Weekend Red Wine", "House Bottle", 28, "For admiring the new lighting after dark.")
        ]
    }

    private var carryOnProducts: [SeedProduct] {
        [
            ("Canvas Weekender", "Workshop", 136, "The entire packing strategy starts here."),
            ("Forest Green Tee", "Field Notes", 52, "One shirt, several outfits."),
            ("Memorial Graphic Tee", "Memory Motel", 68, "The fun dinner option."),
            ("Gingham Boxer Shorts", "Studio Summer", 58, "Lightweight and easy to layer."),
            ("Black Samba Sneakers", "Adidas", 120, "The only shoes coming along."),
            ("Navy Script Cap", "Passin Thru", 38, "For the travel day and every morning after."),
            ("Leather Zip Wallet", "Field Leather", 78, "Cards, coins, and one folded receipt."),
            ("Illustrated Canvas Tote", "Sunday Press", 46, "The extra bag that packs completely flat.")
        ]
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

import Foundation
import Observation

enum DiscoverSearchScope: String, CaseIterable, Identifiable {
    case usernames
    case stackTitles
    case brands
    case genres
    case products

    var id: String { rawValue }

    var title: String {
        switch self {
        case .usernames: "Usernames"
        case .stackTitles: "Stack titles"
        case .brands: "Brands"
        case .genres: "Genre"
        case .products: "Product"
        }
    }

    var prompt: String {
        switch self {
        case .usernames: "Search usernames"
        case .stackTitles: "Search Stack titles"
        case .brands: "Search brands"
        case .genres: "Choose a genre"
        case .products: "Search products or categories"
        }
    }
}

enum DiscoverGenre: String, CaseIterable, Identifiable {
    case clothing, shoes, accessories, bags, jewelry, watches, beauty, skincare
    case fragrance, furniture, homeDecor, lighting, kitchen, dining, art, books
    case music, tech, gaming, photography, fitness, outdoors, travel, kids
    case pets, foodDrink, vintage, sports, stationery, plants

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clothing: "Clothing"
        case .shoes: "Shoes"
        case .accessories: "Accessories"
        case .bags: "Bags"
        case .jewelry: "Jewelry"
        case .watches: "Watches"
        case .beauty: "Beauty"
        case .skincare: "Skincare"
        case .fragrance: "Fragrance"
        case .furniture: "Furniture"
        case .homeDecor: "Home decor"
        case .lighting: "Lighting"
        case .kitchen: "Kitchen"
        case .dining: "Dining"
        case .art: "Art"
        case .books: "Books"
        case .music: "Music"
        case .tech: "Tech"
        case .gaming: "Gaming"
        case .photography: "Photography"
        case .fitness: "Fitness"
        case .outdoors: "Outdoors"
        case .travel: "Travel"
        case .kids: "Kids"
        case .pets: "Pets"
        case .foodDrink: "Food & drink"
        case .vintage: "Vintage"
        case .sports: "Sports"
        case .stationery: "Stationery"
        case .plants: "Plants"
        }
    }

    private var keywords: [String] {
        switch self {
        case .clothing: ["clothing", "apparel", "shirt", "tee", "jacket", "hoodie", "pants", "jeans", "dress", "skirt", "shorts", "coat", "sweater", "knitwear"]
        case .shoes: ["shoe", "shoes", "sneaker", "sneakers", "boots", "heels", "sandals", "loafers", "samba"]
        case .accessories: ["accessory", "accessories", "hat", "cap", "scarf", "belt", "sunglasses", "glasses"]
        case .bags: ["bag", "bags", "tote", "backpack", "purse", "duffel", "handbag"]
        case .jewelry: ["jewelry", "jewellery", "ring", "necklace", "earrings", "bracelet"]
        case .watches: ["watch", "watches", "timepiece"]
        case .beauty: ["beauty", "makeup", "lipstick", "mascara", "cosmetics"]
        case .skincare: ["skincare", "serum", "moisturizer", "cleanser", "sunscreen"]
        case .fragrance: ["fragrance", "perfume", "cologne", "scent"]
        case .furniture: ["furniture", "chair", "sofa", "couch", "table", "desk", "shelf", "dresser"]
        case .homeDecor: ["decor", "decorative", "homeware", "vase", "mirror", "rug", "candle", "pillow"]
        case .lighting: ["lighting", "lamp", "lamps", "sconce", "pendant", "chandelier"]
        case .kitchen: ["kitchen", "cookware", "pan", "pot", "knife", "coffee", "espresso"]
        case .dining: ["dining", "plate", "glassware", "cutlery", "ceramic", "mug"]
        case .art: ["art", "print", "painting", "sculpture", "poster"]
        case .books: ["book", "books", "novel", "magazine", "reading"]
        case .music: ["music", "vinyl", "record", "album", "speaker", "headphones"]
        case .tech: ["tech", "technology", "phone", "laptop", "tablet", "computer", "keyboard", "charger"]
        case .gaming: ["gaming", "game", "console", "controller", "nintendo", "playstation"]
        case .photography: ["photography", "camera", "lens", "film", "tripod"]
        case .fitness: ["fitness", "workout", "gym", "exercise", "yoga", "weights"]
        case .outdoors: ["outdoor", "outdoors", "camping", "hiking", "trail", "tent"]
        case .travel: ["travel", "luggage", "suitcase", "passport", "weekender"]
        case .kids: ["kids", "children", "baby", "toy", "toys", "stroller"]
        case .pets: ["pet", "pets", "dog", "cat", "leash", "collar"]
        case .foodDrink: ["food", "drink", "snack", "tea", "wine", "chocolate"]
        case .vintage: ["vintage", "antique", "retro", "secondhand", "thrift"]
        case .sports: ["sport", "sports", "tennis", "basketball", "soccer", "golf", "running"]
        case .stationery: ["stationery", "notebook", "pen", "pencil", "planner", "journal"]
        case .plants: ["plant", "plants", "flower", "flowers", "garden", "botanical"]
        }
    }

    func matches(_ stack: Stack) -> Bool {
        let text = ([stack.title] + stack.items.flatMap {
            [$0.title, $0.brand, $0.shortDescription]
        }).joined(separator: " ").lowercased()
        let words = Set(text.components(separatedBy: CharacterSet.alphanumerics.inverted))
        return keywords.contains { keyword in
            keyword.contains(" ") ? text.contains(keyword) : words.contains(keyword)
        }
    }
}

@MainActor
@Observable
final class DiscoverViewModel {
    var query = ""
    var searchScope: DiscoverSearchScope = .usernames
    var selectedGenre: DiscoverGenre?
    var stacks: [Stack] = []
    var suggestedCreators: [UserProfile] = []
    var isLoading = false
    var errorMessage: String?

    var matchingCreators: [UserProfile] {
        guard searchScope == .usernames else { return [] }
        var normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedQuery.hasPrefix("@") { normalizedQuery.removeFirst() }
        guard !normalizedQuery.isEmpty else { return [] }
        var seen = Set<UUID>()
        let creators = suggestedCreators + stacks.map(\.author)
        return creators.filter {
            guard seen.insert($0.id).inserted else { return false }
            return $0.displayName.localizedCaseInsensitiveContains(normalizedQuery)
                || $0.username.localizedCaseInsensitiveContains(normalizedQuery)
        }
    }

    func load(services: AppServices) async {
        await refresh(services: services, query: query)
        let curatedAuthor = (try? await CuratedStackCatalog.fetchStacks())?.first?.author
        do {
            suggestedCreators = ([curatedAuthor].compactMap { $0 }) + (try await services.profiles.suggestedCreators())
        } catch {
            suggestedCreators = [curatedAuthor].compactMap { $0 }
            errorMessage = error.localizedDescription
        }
    }

    func refresh(services: AppServices, query: String? = nil, showsLoading: Bool = true) async {
        if showsLoading { isLoading = true }
        defer { if showsLoading { isLoading = false } }
        do {
            let allStacks = try await services.stacks.fetchDiscoverStacks(query: nil)
            guard !Task.isCancelled else { return }
            stacks = filteredStacks(allStacks, query: query)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func search(services: AppServices, query: String) async {
        self.query = query
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if searchScope == .usernames && !cleanQuery.isEmpty {
            stacks = []
        } else {
            await refresh(services: services, query: cleanQuery.isEmpty ? nil : cleanQuery)
        }
        guard searchScope == .usernames else { return }
        let curatedAuthor = (try? await CuratedStackCatalog.fetchStacks())?.first?.author
        do {
            let liveCreators = cleanQuery.isEmpty
                ? try await services.profiles.suggestedCreators()
                : try await services.profiles.searchCreators(query: cleanQuery)
            suggestedCreators = ([curatedAuthor].compactMap { $0 }) + liveCreators
        } catch is CancellationError {
            return
        } catch {
            suggestedCreators = [curatedAuthor].compactMap { $0 }
            errorMessage = error.localizedDescription
        }
    }

    func toggleBookmark(stack: Stack, services: AppServices, user: UserProfile) async {
        do {
            let updated = try await services.stacks.toggleBookmark(stackID: stack.id, userID: user.id)
            replace(updated)
            services.haptics.impact(.medium)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleFollow(authorID: UUID, services: AppServices, user: UserProfile) async {
        do {
            let wasFollowing = suggestedCreators.first { $0.id == authorID }?.isFollowing
                ?? stacks.first { $0.author.id == authorID }?.isFollowingAuthor
                ?? false
            let updatedStacks = try await services.stacks.toggleFollow(authorID: authorID, userID: user.id)
            Analytics.capture(wasFollowing ? "creator_unfollowed" : "creator_followed", ["source": "discover"])
            for index in suggestedCreators.indices where suggestedCreators[index].id == authorID {
                suggestedCreators[index].isFollowing.toggle()
            }
            stacks = filteredStacks(updatedStacks, query: query)
            services.haptics.impact(.medium)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func replace(_ stack: Stack) {
        guard let index = stacks.firstIndex(where: { $0.id == stack.id }) else { return }
        stacks[index] = stack
    }

    private func filteredStacks(_ allStacks: [Stack], query: String?) -> [Stack] {
        if searchScope == .genres {
            guard let selectedGenre else { return [] }
            return allStacks.filter { selectedGenre.matches($0) }
        }
        guard let query, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return allStacks
        }
        if searchScope == .usernames { return [] }
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return allStacks.filter { stack in
            switch searchScope {
            case .usernames:
                return false
            case .stackTitles:
                return stack.title.localizedCaseInsensitiveContains(needle)
            case .brands:
                return stack.items.contains { $0.brand.localizedCaseInsensitiveContains(needle) }
            case .genres:
                return false
            case .products:
                return stack.items.contains {
                    $0.title.localizedCaseInsensitiveContains(needle)
                        || $0.shortDescription.localizedCaseInsensitiveContains(needle)
                }
            }
        }
    }
}

import Foundation

struct SharedPagePreview: Codable, Equatable, Sendable {
    var pageURL: URL?
    var title: String?
    var brand: String?
    var imageURL: URL?
    var price: Decimal?
    var currencyCode: String?

    init?(dictionary: [String: Any]) {
        if let raw = dictionary["url"] as? String,
           let url = URL(string: raw), ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            pageURL = url
        } else {
            pageURL = nil
        }
        let title = (dictionary["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.title = title?.isEmpty == false ? title : nil
        let brand = (dictionary["brand"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.brand = brand?.isEmpty == false ? brand : nil
        if let raw = dictionary["imageURL"] as? String,
           let url = URL(string: raw), ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            imageURL = url
        } else {
            imageURL = nil
        }
        price = (dictionary["price"] as? String).flatMap { Decimal(string: $0) }
        let currency = (dictionary["currencyCode"] as? String)?.uppercased() ?? ""
        currencyCode = currency.range(of: "^[A-Z]{3}$", options: .regularExpression) == nil ? nil : currency
        guard pageURL != nil || self.title != nil || imageURL != nil else { return nil }
    }
}

struct PendingSharedLink: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var url: URL
    var title: String?
    var pagePreview: SharedPagePreview?
    /// Chosen directly in the share extension. A missing destination keeps the
    /// older “ask in Stacks” behavior as a safe fallback.
    var destinationStackID: UUID?
    var destinationStackTitle: String?
    /// When set by the share extension, the containing app creates this Stack
    /// before importing the shared product.
    var newStackTitle: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        url: URL,
        title: String? = nil,
        pagePreview: SharedPagePreview? = nil,
        destinationStackID: UUID? = nil,
        destinationStackTitle: String? = nil,
        newStackTitle: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.pagePreview = pagePreview
        self.destinationStackID = destinationStackID
        self.destinationStackTitle = destinationStackTitle
        self.newStackTitle = newStackTitle
        self.createdAt = createdAt
    }
}

struct SharedStackDestination: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let title: String
    let ownerName: String
    let avatarURL: URL?
    let avatarData: Data?
    let updatedAt: Date?

    init(
        id: UUID,
        title: String,
        ownerName: String = "You",
        avatarURL: URL? = nil,
        avatarData: Data? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.ownerName = ownerName
        self.avatarURL = avatarURL
        self.avatarData = avatarData
        self.updatedAt = updatedAt
    }
}

enum SharedImportConfiguration {
    static let appGroupID = "group.spot.stacks.app"
    static let pendingLinkKey = "stacks.pendingSharedLink"
    static let destinationsKey = "stacks.shareDestinations"
    static let callbackURL = URL(string: "stacks://shared-link")!
    static let maximumPendingLinks = 20
}

enum SharedImportError: LocalizedError {
    case appGroupUnavailable

    var errorDescription: String? {
        "Stacks cannot save this link right now. Open Stacks once, then try sharing again."
    }
}

/// The app refreshes this tiny snapshot whenever it becomes active. The
/// extension can then offer destinations without signing in or making a slow
/// network request inside the system share sheet.
enum SharedStackDestinationStore {
    private struct Snapshot: Codable {
        let ownerID: UUID
        let destinations: [SharedStackDestination]
    }

    static var isAvailable: Bool {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: SharedImportConfiguration.appGroupID
        ) != nil
    }

    static var ownerID: UUID? {
        snapshot?.ownerID
    }

    static func save(_ destinations: [SharedStackDestination], for ownerID: UUID) {
        var seen = Set<UUID>()
        let unique = destinations.filter { seen.insert($0.id).inserted }
        guard let defaults,
              let encoded = try? JSONEncoder().encode(Snapshot(ownerID: ownerID, destinations: unique)) else { return }
        defaults.set(encoded, forKey: SharedImportConfiguration.destinationsKey)
    }

    static func upsert(_ destination: SharedStackDestination, for ownerID: UUID) {
        let existing = snapshot?.ownerID == ownerID ? load() : []
        save([destination] + existing.filter { $0.id != destination.id }, for: ownerID)
    }

    static func load() -> [SharedStackDestination] {
        snapshot?.destinations ?? []
    }

    static func clear() {
        defaults?.removeObject(forKey: SharedImportConfiguration.destinationsKey)
    }

    private static var snapshot: Snapshot? {
        guard let data = defaults?.data(forKey: SharedImportConfiguration.destinationsKey) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    private static var defaults: UserDefaults? {
        guard isAvailable else { return nil }
        return UserDefaults(suiteName: SharedImportConfiguration.appGroupID)
    }
}

enum PendingSharedLinkStore {
    static func save(_ link: PendingSharedLink) throws {
        var links = all()
        // A host app may invoke the share extension twice while its sheet is
        // animating. Keep one pending import per URL/destination pair, while
        // allowing the same product to be saved to different Stacks.
        links.removeAll { existing in
            existing.url.absoluteString == link.url.absoluteString
                && existing.destinationStackID == link.destinationStackID
                && existing.destinationStackTitle == link.destinationStackTitle
                && existing.newStackTitle == link.newStackTitle
        }
        links.append(link)
        links = Array(links.suffix(SharedImportConfiguration.maximumPendingLinks))
        try persist(links)
    }

    static func load() -> PendingSharedLink? {
        all().first
    }

    static func clear() {
        var links = all()
        guard !links.isEmpty else { return }
        links.removeFirst()
        try? persist(links)
    }

    static func remove(_ link: PendingSharedLink) {
        var links = all()
        links.removeAll { $0.id == link.id }
        try? persist(links)
    }

    static func clearDestination(for link: PendingSharedLink) {
        var links = all()
        guard let index = links.firstIndex(where: { $0.id == link.id }) else { return }
        links[index].destinationStackID = nil
        links[index].destinationStackTitle = nil
        links[index].newStackTitle = nil
        try? persist(links)
    }

    static func setDestination(id: UUID, title: String, for link: PendingSharedLink) {
        var links = all()
        guard let index = links.firstIndex(where: { $0.id == link.id }) else { return }
        links[index].destinationStackID = id
        links[index].destinationStackTitle = title
        links[index].newStackTitle = nil
        try? persist(links)
    }

    static func clearAll() {
        defaults?.removeObject(forKey: SharedImportConfiguration.pendingLinkKey)
    }

    private static var defaults: UserDefaults? {
        guard SharedStackDestinationStore.isAvailable else { return nil }
        return UserDefaults(suiteName: SharedImportConfiguration.appGroupID)
    }

    private static func all() -> [PendingSharedLink] {
        guard let data = defaults?.data(forKey: SharedImportConfiguration.pendingLinkKey) else {
            return []
        }

        if let links = try? JSONDecoder().decode([PendingSharedLink].self, from: data) {
            return links
        }

        if let legacyLink = try? JSONDecoder().decode(PendingSharedLink.self, from: data) {
            return [legacyLink]
        }

        return []
    }

    private static func persist(_ links: [PendingSharedLink]) throws {
        guard let defaults else { throw SharedImportError.appGroupUnavailable }
        if links.isEmpty {
            defaults.removeObject(forKey: SharedImportConfiguration.pendingLinkKey)
        } else {
            defaults.set(try JSONEncoder().encode(links), forKey: SharedImportConfiguration.pendingLinkKey)
        }
    }
}

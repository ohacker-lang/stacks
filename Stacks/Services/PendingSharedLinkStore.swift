import Foundation

struct PendingSharedLink: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var url: URL
    var title: String?
    var createdAt: Date

    init(id: UUID = UUID(), url: URL, title: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.url = url
        self.title = title
        self.createdAt = createdAt
    }
}

enum SharedImportConfiguration {
    static let appGroupID = "group.com.example.stacks"
    static let pendingLinkKey = "stacks.pendingSharedLink"
    static let callbackURL = URL(string: "stacks://shared-link")!
    static let maximumPendingLinks = 20
}

enum PendingSharedLinkStore {
    static func save(_ link: PendingSharedLink) throws {
        var links = all()
        links.removeAll { $0.url == link.url }
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

    static func clearAll() {
        defaults.removeObject(forKey: SharedImportConfiguration.pendingLinkKey)
    }

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: SharedImportConfiguration.appGroupID) ?? .standard
    }

    private static func all() -> [PendingSharedLink] {
        guard let data = defaults.data(forKey: SharedImportConfiguration.pendingLinkKey) else {
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
        if links.isEmpty {
            defaults.removeObject(forKey: SharedImportConfiguration.pendingLinkKey)
        } else {
            defaults.set(try JSONEncoder().encode(links), forKey: SharedImportConfiguration.pendingLinkKey)
        }
    }
}

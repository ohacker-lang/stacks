import Foundation

struct Stack: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var ownerID: UUID
    var author: UserProfile
    var title: String
    var visibility: StackVisibility
    var wishlistMode: Bool
    var collaborationEnabled: Bool = false
    var collaborators: [Collaborator]
    var items: [StackItem]
    /// Opaque capability used only for link-only Stacks. It is never shown in
    /// Discover and possession of it is required to open the Stack.
    var publicLinkToken: UUID? = nil
    var createdAt: Date
    var updatedAt: Date
    var isBookmarked: Bool
    var isFollowingAuthor: Bool

    var displayTitle: String {
        title
    }

    var shareURL: URL? {
        guard visibility == .publicLink || visibility == .publicDiscover,
              let siteURL = URL(string: "https://stacks.spot") else { return nil }
        var components = URLComponents(url: siteURL.appending(path: "s/\(id.uuidString)"), resolvingAgainstBaseURL: false)
        if visibility == .publicLink {
            guard let publicLinkToken else { return nil }
            components?.queryItems = [URLQueryItem(name: "token", value: publicLinkToken.uuidString)]
        }
        return components?.url
    }

    func canEdit(userID: UUID?) -> Bool {
        guard let userID else { return false }
        if ownerID == userID { return true }
        return collaborationEnabled && collaborators.contains {
            $0.user.id == userID && $0.permission == .edit
        }
    }
}

enum StackVisibility: String, Codable, CaseIterable, Hashable, Sendable {
    case `private`
    case inviteOnly
    case publicLink
    case publicDiscover

    var title: String {
        switch self {
        case .private: "Private"
        case .inviteOnly: "Invite Only"
        case .publicLink: "Public Link"
        case .publicDiscover: "Discover"
        }
    }
}

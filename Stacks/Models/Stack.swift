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

    /// Mirrors `stackSlug` in web/src/index.js and the web-preview function,
    /// which resolve stacks.spot/username/slug back to this Stack.
    var webSlug: String {
        let folded = title.folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX")).lowercased()
        var slug = ""
        var needsDash = false
        for scalar in folded.unicodeScalars {
            if ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar) {
                if needsDash && !slug.isEmpty { slug.append("-") }
                slug.unicodeScalars.append(scalar)
                needsDash = false
            } else {
                needsDash = true
            }
        }
        return slug.isEmpty ? "stack" : slug
    }

    var shareURL: URL? {
        guard visibility == .publicLink || visibility == .publicDiscover,
              let siteURL = URL(string: "https://stacks.spot") else { return nil }
        if visibility == .publicDiscover, !author.username.isEmpty {
            return siteURL.appending(path: "\(author.username.lowercased())/\(webSlug)")
        }
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

    /// Like Pinterest boards, new Stacks appear on the owner's public profile
    /// at stacks.spot/username unless they choose Private.
    static let defaultForNewStacks: StackVisibility = .publicDiscover

    var title: String {
        switch self {
        case .private: "Private"
        case .inviteOnly: "Invite Only"
        case .publicLink: "Public Link"
        case .publicDiscover: "Public"
        }
    }
}

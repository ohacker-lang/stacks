import Foundation

extension Notification.Name {
    static let stacksCollaborationDidChange = Notification.Name("stacks.collaboration.didChange")
    static let stacksShareDestinationsDidChange = Notification.Name("stacks.shareDestinations.didChange")
}

struct StackBookmark: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var stackID: UUID
    var userID: UUID
    var createdAt: Date
}

struct FollowRelationship: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var followerID: UUID
    var followedUserID: UUID
    var createdAt: Date
}

struct CollectionFolder: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var ownerID: UUID
    var title: String
    var stackIDs: [UUID]
    var createdAt: Date
}

struct GiftClaim: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var itemID: UUID
    var stackID: UUID
    var claimerName: String
    var privateMessage: String?
    var status: GiftClaimStatus
    var createdAt: Date
}

enum GiftClaimStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case available
    case claimed
    case purchased
}

struct Collaborator: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var user: UserProfile
    var permission: CollaboratorPermission
    var invitedAt: Date
}

enum CollaboratorPermission: String, Codable, CaseIterable, Hashable, Sendable {
    case view
    case edit
    case owner
}

struct CollaborationInvite: Identifiable, Hashable, Sendable {
    let id: UUID
    let stackID: UUID
    let token: UUID
    let permission: CollaboratorPermission
    let expiresAt: Date

    var deepLink: URL? {
        URL(string: "https://stacks.spot/invite/\(token.uuidString)")
    }
}

struct CollaborationInvitePreview: Identifiable, Hashable, Sendable {
    let token: UUID
    let stackID: UUID
    let stackTitle: String
    let owner: UserProfile
    let permission: CollaboratorPermission
    let expiresAt: Date

    var id: UUID { token }
}

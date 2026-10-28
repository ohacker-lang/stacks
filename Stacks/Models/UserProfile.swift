import Foundation

struct UserProfile: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var displayName: String
    var username: String
    var avatarURL: URL?
    var bio: String
    var linkInBioURL: URL?
    var isFollowing: Bool
    var profileShareEnabled: Bool? = nil

    var initials: String {
        displayName
            .split(separator: " ")
            .compactMap(\.first)
            .prefix(2)
            .map(String.init)
            .joined()
    }
}

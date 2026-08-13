import Foundation

enum EmailAuthenticationResult: Sendable, Equatable {
    case authenticated(AuthSession)
    case linkSent
}

struct AuthSession: Codable, Hashable, Sendable {
    let userID: UUID
    var email: String?
    var displayName: String
    var hasCompletedOnboarding: Bool
}

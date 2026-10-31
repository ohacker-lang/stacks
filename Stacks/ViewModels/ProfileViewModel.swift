import Foundation
import Observation

@MainActor
@Observable
final class ProfileViewModel {
    var stacks: [Stack] = []
    var bookmarkedStacks: [Stack] = []
    var followerCount = 0
    var followingCount = 0
    var isLoading = false
    var errorMessage: String?

    var stackCount: Int { stacks.count }
    var bookmarkCount: Int { bookmarkedStacks.count }
    var productCount: Int { stacks.reduce(0) { $0 + $1.items.count } }

    func load(services: AppServices, profile: UserProfile, currentUser: UserProfile?) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let discoverStacks = try await services.stacks.fetchDiscoverStacks(query: nil)
            if profile.id == currentUser?.id {
                stacks = try await services.stacks.fetchMyStacks(for: profile.id)
            } else if let currentUser {
                // Matches what visitors see at stacks.spot/username.
                stacks = try await services.stacks.fetchPublicStacks(ownerID: profile.id, for: currentUser.id)
            } else {
                stacks = discoverStacks.filter { $0.ownerID == profile.id }
            }
            bookmarkedStacks = discoverStacks.filter(\.isBookmarked)
            if currentUser != nil {
                await loadFollowCounts(services: services, profileID: profile.id)
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadFollowCounts(services: AppServices, profileID: UUID) async {
        guard let counts = try? await services.profiles.followCounts(profileID: profileID) else { return }
        followerCount = counts.followers
        followingCount = counts.following
    }
}

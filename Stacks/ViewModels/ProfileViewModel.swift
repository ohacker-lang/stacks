import Foundation
import Observation

@MainActor
@Observable
final class ProfileViewModel {
    var stacks: [Stack] = []
    var bookmarkedStacks: [Stack] = []
    var followerCount = 1
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
                followerCount = max(1, discoverStacks.filter { $0.author.id == profile.id && $0.isFollowingAuthor }.count)
            } else if let currentUser {
                // Matches what visitors see at stacks.spot/username.
                stacks = try await services.stacks.fetchPublicStacks(ownerID: profile.id, for: currentUser.id)
                followerCount = profile.isFollowing ? 1 : 0
            } else {
                stacks = discoverStacks.filter { $0.ownerID == profile.id }
                followerCount = profile.isFollowing ? 1 : 0
            }
            bookmarkedStacks = discoverStacks.filter(\.isBookmarked)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

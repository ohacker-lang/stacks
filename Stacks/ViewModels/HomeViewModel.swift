import Foundation
import Observation

@MainActor
@Observable
final class HomeViewModel {
    var myStacks: [Stack] = []
    var discoverStacks: [Stack] = []
    var isLoading = false
    var errorMessage: String?
    var createTitle = ""
    var createWishlistMode = false

    func load(services: AppServices, user: UserProfile) async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let fetchedStacks = services.stacks.fetchMyStacks(for: user.id)
            async let discoveredStacks = services.stacks.fetchDiscoverStacks(query: nil)

            let (myStacks, discoverStacks) = try await (fetchedStacks, discoveredStacks)
            self.myStacks = myStacks.sorted { $0.updatedAt > $1.updatedAt }
            self.discoverStacks = discoverStacks.sorted { $0.updatedAt > $1.updatedAt }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createStack(services: AppServices, user: UserProfile) async -> Stack? {
        do {
            let stack = try await services.stacks.createStack(
                title: createTitle.isEmpty ? "Untitled Stack" : createTitle,
                wishlistMode: createWishlistMode,
                owner: user
            )
            myStacks.insert(stack, at: 0)
            createTitle = ""
            createWishlistMode = false
            services.haptics.notification(.success)
            return stack
        } catch {
            errorMessage = error.localizedDescription
            services.haptics.notification(.error)
            return nil
        }
    }
}

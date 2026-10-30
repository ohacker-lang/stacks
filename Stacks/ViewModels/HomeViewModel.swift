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
    var createWishlistMode = true
    var createVisibility: StackVisibility = .defaultForNewStacks

    func load(services: AppServices, user: UserProfile) async {
        isLoading = true
        defer { isLoading = false }
        async let fetchedStacks = services.stacks.fetchMyStacks(for: user.id)
        async let discoveredStacks = services.stacks.fetchDiscoverStacks(query: nil)
        do {
            let owned = try await fetchedStacks
            myStacks = owned.sorted { $0.updatedAt > $1.updatedAt }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        do {
            let discovered = try await discoveredStacks
            discoverStacks = discovered.sorted { $0.updatedAt > $1.updatedAt }
        } catch {
            if errorMessage == nil { errorMessage = error.localizedDescription }
        }
    }

    func createStack(services: AppServices, user: UserProfile) async -> Stack? {
        do {
            let stack = try await services.stacks.createStack(
                title: createTitle.isEmpty ? "Untitled Stack" : createTitle,
                wishlistMode: createWishlistMode,
                visibility: createVisibility,
                owner: user
            )
            myStacks.insert(stack, at: 0)
            SharedStackDestinationStore.upsert(
                SharedStackDestination(
                    id: stack.id,
                    title: stack.displayTitle,
                    ownerName: user.displayName,
                    avatarURL: user.avatarURL,
                    updatedAt: stack.updatedAt
                ),
                for: user.id
            )
            NotificationCenter.default.post(name: .stacksShareDestinationsDidChange, object: nil)
            createTitle = ""
            createWishlistMode = true
            createVisibility = .defaultForNewStacks
            services.haptics.notification(.success)
            return stack
        } catch {
            errorMessage = error.localizedDescription
            services.haptics.notification(.error)
            return nil
        }
    }

}

import Foundation
import PostHog

/// Product analytics, sent to PostHog. Event names and properties are
/// documented in docs/ANALYTICS.md; add new events there first.
///
/// Analytics is off unless the build sets STACKS_POSTHOG_API_KEY, so previews,
/// demo builds and Debug builds without a key never send anything. People can
/// also turn it off in Privacy choices.
enum Analytics {
    private static let optOutDefaultsKey = "stacks.analytics.optedOut"
    nonisolated(unsafe) private static var isConfigured = false

    static func configure() {
        guard !isConfigured,
              let key = (Bundle.main.object(forInfoDictionaryKey: "STACKS_POSTHOG_API_KEY") as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              key.hasPrefix("phc_") else { return }
        let host = (Bundle.main.object(forInfoDictionaryKey: "STACKS_POSTHOG_HOST") as? String)?.nonEmptyTrimmed
            ?? "https://us.i.posthog.com"
        let config = PostHogConfig(projectToken: key, host: host)
        config.captureApplicationLifecycleEvents = true
        // SwiftUI screens are recorded explicitly with `screen(_:)`.
        config.captureScreenViews = false
        config.personProfiles = .identifiedOnly
        config.sessionReplay = false
        PostHogSDK.shared.setup(config)
        isConfigured = true
        if UserDefaults.standard.bool(forKey: optOutDefaultsKey) {
            PostHogSDK.shared.optOut()
        }
    }

    /// Whether this device shares usage analytics. Defaults to on.
    static var isSharingEnabled: Bool {
        get { !UserDefaults.standard.bool(forKey: optOutDefaultsKey) }
        set {
            UserDefaults.standard.set(!newValue, forKey: optOutDefaultsKey)
            guard isConfigured else { return }
            if newValue { PostHogSDK.shared.optIn() } else { PostHogSDK.shared.optOut() }
        }
    }

    /// Links events to the Stacks account UUID only (never email or name).
    static func identify(_ userID: UUID) {
        guard isConfigured else { return }
        PostHogSDK.shared.identify(userID.uuidString.lowercased())
    }

    static func reset() {
        guard isConfigured else { return }
        PostHogSDK.shared.reset()
    }

    static func capture(_ event: String, _ properties: [String: Any] = [:]) {
        guard isConfigured else { return }
        PostHogSDK.shared.capture(event, properties: properties.isEmpty ? nil : properties)
    }

    static func screen(_ name: String) {
        guard isConfigured else { return }
        PostHogSDK.shared.screen(name)
    }

    static func host(of url: URL?) -> String {
        url?.host()?.lowercased().replacingOccurrences(of: "www.", with: "") ?? ""
    }

    static func milliseconds(since start: ContinuousClock.Instant) -> Int {
        let elapsed = ContinuousClock.now - start
        return Int(elapsed.components.seconds * 1_000 + elapsed.components.attoseconds / 1_000_000_000_000_000)
    }
}

private extension String {
    var nonEmptyTrimmed: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension StackVisibility {
    var analyticsValue: String {
        switch self {
        case .private, .inviteOnly: "private"
        case .publicLink: "link_only"
        case .publicDiscover: "public"
        }
    }
}

// MARK: - Service wrappers
//
// Record data-level events once, where the work happens, instead of at every
// screen that can create a Stack or save an item.

struct AnalyticsStackRepository: StackRepository {
    let base: any StackRepository

    func fetchMyStacks(for userID: UUID) async throws -> [Stack] { try await base.fetchMyStacks(for: userID) }
    func fetchOwnedStackDestinations(for user: UserProfile) async throws -> [SharedStackDestination] { try await base.fetchOwnedStackDestinations(for: user) }
    func fetchStack(id: UUID, for userID: UUID) async throws -> Stack { try await base.fetchStack(id: id, for: userID) }
    func fetchPublicStacks(ownerID: UUID, for viewerID: UUID) async throws -> [Stack] { try await base.fetchPublicStacks(ownerID: ownerID, for: viewerID) }
    func fetchDiscoverStacks(query: String?) async throws -> [Stack] { try await base.fetchDiscoverStacks(query: query) }
    func fetchSharedStack(token: UUID) async throws -> Stack { try await base.fetchSharedStack(token: token) }
    func rotateWishlistLink(stackID: UUID, revoke: Bool) async throws -> Stack { try await base.rotateWishlistLink(stackID: stackID, revoke: revoke) }

    func createStack(title: String, wishlistMode: Bool, visibility: StackVisibility, owner: UserProfile) async throws -> Stack {
        let stack = try await base.createStack(title: title, wishlistMode: wishlistMode, visibility: visibility, owner: owner)
        Analytics.capture("stack_created", ["visibility": visibility.analyticsValue, "wishlist": wishlistMode])
        return stack
    }

    func copyStack(_ stack: Stack, to owner: UserProfile) async throws -> Stack {
        let copy = try await base.copyStack(stack, to: owner)
        Analytics.capture("stack_copied")
        return copy
    }

    func updateStack(_ stack: Stack) async throws -> Stack {
        let updated = try await base.updateStack(stack)
        Analytics.capture("stack_updated", ["visibility": updated.visibility.analyticsValue, "wishlist": updated.wishlistMode])
        return updated
    }

    func deleteStack(id: UUID) async throws {
        try await base.deleteStack(id: id)
        Analytics.capture("stack_deleted")
    }

    func addItem(_ item: StackItem, to stackID: UUID) async throws -> Stack {
        let stack = try await base.addItem(item, to: stackID)
        Analytics.capture("item_saved", [
            "source": item.addSource.rawValue,
            "has_link": item.sourceURL.scheme?.hasPrefix("http") == true,
            "has_price": item.price > 0,
            "has_cutout": item.removedBackgroundImageURL != nil,
            "stack_visibility": stack.visibility.analyticsValue,
        ])
        return stack
    }

    func updateItem(_ item: StackItem, in stackID: UUID) async throws -> Stack { try await base.updateItem(item, in: stackID) }

    func removeItem(id: UUID, from stackID: UUID) async throws -> Stack {
        let stack = try await base.removeItem(id: id, from: stackID)
        Analytics.capture("item_removed")
        return stack
    }

    func toggleBookmark(stackID: UUID, userID: UUID) async throws -> Stack {
        let stack = try await base.toggleBookmark(stackID: stackID, userID: userID)
        Analytics.capture(stack.isBookmarked ? "stack_pinned" : "stack_unpinned")
        return stack
    }

    func toggleFollow(authorID: UUID, userID: UUID) async throws -> [Stack] {
        let stacks = try await base.toggleFollow(authorID: authorID, userID: userID)
        let following = stacks.first { $0.ownerID == authorID }?.isFollowingAuthor
        if let following { Analytics.capture(following ? "creator_followed" : "creator_unfollowed") }
        return stacks
    }
}

struct AnalyticsProductSearchService: ProductSearchService {
    let base: any ProductSearchService

    func searchProducts(query: String) async throws -> [ProductSearchResult] { try await base.searchProducts(query: query) }

    func previewProductLink(_ url: URL) async throws -> ProductLinkPreview {
        let start = ContinuousClock.now
        Analytics.capture("item_import_started", ["source": "link"])
        do {
            let preview = try await base.previewProductLink(url)
            Analytics.capture("item_import_finished", [
                "source": "link",
                "outcome": preview.imageURL == nil ? "no_image" : "ok",
                "has_price": preview.price != nil,
                "retailer_host": Analytics.host(of: url),
                "duration_ms": Analytics.milliseconds(since: start),
            ])
            return preview
        } catch {
            Analytics.capture("item_import_finished", [
                "source": "link",
                "outcome": "failed",
                "retailer_host": Analytics.host(of: url),
                "duration_ms": Analytics.milliseconds(since: start),
            ])
            throw error
        }
    }

    func productFromPastedLink(_ url: URL, stackID: UUID, placement: StickerPlacement) async throws -> StackItem {
        try await base.productFromPastedLink(url, stackID: stackID, placement: placement)
    }
}

struct AnalyticsBackgroundRemovalService: BackgroundRemovalService {
    let base: any BackgroundRemovalService

    func removeBackground(for item: StackItem) async throws -> URL? {
        let start = ContinuousClock.now
        do {
            let url = try await base.removeBackground(for: item)
            Analytics.capture("background_removal_finished", [
                "result": url == nil ? "failed" : "ok",
                "source": item.addSource.rawValue,
                "duration_ms": Analytics.milliseconds(since: start),
            ])
            return url
        } catch {
            Analytics.capture("background_removal_finished", [
                "result": "failed",
                "source": item.addSource.rawValue,
                "duration_ms": Analytics.milliseconds(since: start),
            ])
            throw error
        }
    }
}

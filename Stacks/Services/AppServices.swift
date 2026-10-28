import SwiftUI
import UIKit

struct AppServices: @unchecked Sendable {
    let auth: any AuthService
    let stacks: any StackRepository
    let profiles: any ProfileRepository
    let productSearch: any ProductSearchService
    let backgroundRemoval: any BackgroundRemovalService
    let affiliate: any AffiliateService
    let claims: any ClaimService
    let collaboration: any CollaborationService
    let storage: any StorageService
    let realtime: any RealtimeService
    let safety: any SafetyService
    let haptics: HapticsService

    static func mock() -> AppServices {
        let seed = MockSeedData()
        let stackRepository = MockStackRepository(seed: seed)
        return AppServices(
            auth: MockAuthService(seed: seed),
            stacks: stackRepository,
            profiles: MockProfileRepository(seed: seed),
            productSearch: EdgeFunctionProductSearchService(),
            backgroundRemoval: AppleVisionBackgroundRemovalService(),
            affiliate: MockAffiliateService(),
            claims: MockClaimService(),
            collaboration: MockCollaborationService(seed: seed),
            storage: MockStorageService(),
            realtime: MockRealtimeService(),
            safety: MockSafetyService(),
            haptics: HapticsService()
        )
    }

    static func supabaseBackedPlaceholder() -> AppServices {
        guard let configuration = SupabaseConfiguration.fromAppBundle() else {
            return mock()
        }
        return AppServices(
            auth: SupabaseAuthService(configuration: configuration),
            stacks: SupabaseStackRepository(configuration: configuration),
            profiles: SupabaseProfileRepository(configuration: configuration),
            productSearch: EdgeFunctionProductSearchService(),
            backgroundRemoval: AppleVisionBackgroundRemovalService(),
            affiliate: EdgeFunctionAffiliateService(configuration: configuration),
            claims: EdgeFunctionClaimService(configuration: configuration),
            collaboration: SupabaseCollaborationService(configuration: configuration),
            storage: SupabaseStorageService(),
            realtime: SupabaseRealtimeService(),
            safety: SupabaseSafetyService(configuration: configuration),
            haptics: HapticsService()
        )
    }

    /// Uses the live backend only after an Xcode configuration provides both
    /// the Supabase URL and anon key. This keeps local previews usable before
    /// production credentials are installed.
    static func configured() -> AppServices {
        Analytics.configure()
        return unmeasured().withAnalytics()
    }

    /// Wraps the services that create Stacks, save items and import products
    /// so their events are recorded once (see docs/ANALYTICS.md).
    func withAnalytics() -> AppServices {
        AppServices(
            auth: auth,
            stacks: AnalyticsStackRepository(base: stacks),
            profiles: profiles,
            productSearch: AnalyticsProductSearchService(base: productSearch),
            backgroundRemoval: AnalyticsBackgroundRemovalService(base: backgroundRemoval),
            affiliate: affiliate,
            claims: claims,
            collaboration: collaboration,
            storage: storage,
            realtime: realtime,
            safety: safety,
            haptics: haptics
        )
    }

    private static func unmeasured() -> AppServices {
        #if STACKS_PERSONAL_TEAM_DEMO
        // Free Personal Teams cannot provision Sign in with Apple or App
        // Groups. The Debug configuration therefore runs a self-contained
        // local account while Release remains fully production-backed.
        return mock()
        #else
        #if DEBUG
        if ProcessInfo.processInfo.environment["STACKS_PRO_LOCAL_STOREKIT"] == "1" { return mock() }
        #endif
        return SupabaseConfiguration.fromAppBundle() == nil ? mock() : supabaseBackedPlaceholder()
        #endif
    }
}

private final class AppServicesBox: @unchecked Sendable {
    let services: AppServices

    init(_ services: AppServices) {
        self.services = services
    }
}

private struct AppServicesKey: EnvironmentKey {
    static let defaultValue = AppServicesBox(.mock())
}

extension EnvironmentValues {
    var appServices: AppServices {
        get { self[AppServicesKey.self].services }
        set { self[AppServicesKey.self] = AppServicesBox(newValue) }
    }
}

struct HapticsService: Sendable {
    @MainActor
    func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }

    @MainActor
    func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type)
    }
}

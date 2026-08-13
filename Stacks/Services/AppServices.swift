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
            affiliate: EdgeFunctionAffiliateService(),
            claims: EdgeFunctionClaimService(),
            collaboration: SupabaseCollaborationService(),
            storage: SupabaseStorageService(),
            realtime: SupabaseRealtimeService(),
            haptics: HapticsService()
        )
    }

    /// Uses the live backend only after an Xcode configuration provides both
    /// the Supabase URL and anon key. This keeps local previews usable before
    /// production credentials are installed.
    static func configured() -> AppServices {
        SupabaseConfiguration.fromAppBundle() == nil ? mock() : supabaseBackedPlaceholder()
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

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
        AppServices(
            auth: SupabaseAuthService(),
            stacks: SupabaseStackRepository(),
            profiles: SupabaseProfileRepository(),
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

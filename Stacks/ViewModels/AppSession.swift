import Foundation
import Observation

@MainActor
@Observable
final class AppSession {
    enum State: Equatable {
        case launching
        case signedOut
        case onboarding(AuthSession)
        case signedIn(UserProfile)
    }

    let services: AppServices
    var state: State = .launching
    var lastError: String?

    init(services: AppServices) {
        self.services = services
    }

    var currentUser: UserProfile? {
        if case .signedIn(let profile) = state {
            return profile
        }
        return nil
    }

    func restore() async {
        do {
            if let session = try await services.auth.restoreSession() {
                if session.hasCompletedOnboarding {
                    let profile = try await services.profiles.currentProfile(for: session)
                    state = .signedIn(profile)
                } else {
                    state = .onboarding(session)
                }
            } else {
                state = .signedOut
            }
        } catch {
            lastError = error.localizedDescription
            state = .signedOut
        }
    }

    func signInWithApple() async {
        do {
            let session = try await services.auth.signInWithApple()
            state = .onboarding(session)
            lastError = nil
            services.haptics.notification(.success)
        } catch {
            lastError = error.localizedDescription
            services.haptics.notification(.error)
        }
    }

    func signInWithEmail(_ email: String) async {
        do {
            let session = try await services.auth.signInWithEmail(email)
            state = .onboarding(session)
            lastError = nil
            services.haptics.notification(.success)
        } catch {
            lastError = error.localizedDescription
            services.haptics.notification(.error)
        }
    }

    func completeOnboarding() async {
        guard case .onboarding(let session) = state else { return }
        do {
            var completed = session
            completed.hasCompletedOnboarding = true
            let profile = try await services.profiles.currentProfile(for: completed)
            state = .signedIn(profile)
            lastError = nil
            services.haptics.notification(.success)
        } catch {
            lastError = error.localizedDescription
            services.haptics.notification(.error)
        }
    }

    func signOut() async {
        do {
            try await services.auth.signOut()
            state = .signedOut
        } catch {
            lastError = error.localizedDescription
        }
    }

    func updateCurrentProfile(displayName: String, username: String) {
        guard case .signedIn(var profile) = state else { return }
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let handle = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !handle.isEmpty else { return }
        profile.displayName = name
        profile.username = handle
        state = .signedIn(profile)
    }

    func requestAccountDeletion() async {
        do {
            try await services.auth.requestAccountDeletion()
            state = .signedOut
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}

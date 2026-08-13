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
    var pendingEmailSignIn = false

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

    @discardableResult
    func signInWithApple() async -> Bool {
        do {
            let session = try await services.auth.signInWithApple()
            state = .onboarding(session)
            lastError = nil
            services.haptics.notification(.success)
            return true
        } catch {
            lastError = error.localizedDescription
            services.haptics.notification(.error)
            return false
        }
    }

    @discardableResult
    func signInWithEmail(_ email: String) async -> Bool {
        do {
            let result = try await services.auth.signInWithEmail(email)
            switch result {
            case .authenticated(let session):
                state = .onboarding(session)
                pendingEmailSignIn = false
            case .linkSent:
                pendingEmailSignIn = true
            }
            lastError = nil
            services.haptics.notification(.success)
            return true
        } catch {
            lastError = error.localizedDescription
            services.haptics.notification(.error)
            return false
        }
    }

    func handleIncomingURL(_ url: URL) async {
        do {
            guard let authSession = try await services.auth.handleAuthCallback(url) else { return }
            pendingEmailSignIn = false
            lastError = nil
            if authSession.hasCompletedOnboarding {
                state = .signedIn(try await services.profiles.currentProfile(for: authSession))
            } else {
                state = .onboarding(authSession)
            }
            services.haptics.notification(.success)
        } catch {
            lastError = error.localizedDescription
            services.haptics.notification(.error)
        }
    }

    @discardableResult
    func completeOnboarding() async -> Bool {
        guard case .onboarding(let session) = state else { return false }
        do {
            var completed = session
            completed.hasCompletedOnboarding = true
            try await services.auth.completeOnboarding(for: completed.userID)
            let profile = try await services.profiles.currentProfile(for: completed)
            state = .signedIn(profile)
            pendingEmailSignIn = false
            lastError = nil
            services.haptics.notification(.success)
            return true
        } catch {
            lastError = error.localizedDescription
            services.haptics.notification(.error)
            return false
        }
    }

    func signOut() async {
        do {
            try await services.auth.signOut()
            state = .signedOut
            pendingEmailSignIn = false
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

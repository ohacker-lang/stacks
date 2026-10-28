import Foundation
import Observation

private enum SessionRestoreError: Error {
    case timedOut
}

private enum SessionRestoreOutcome: Sendable {
    case signedOut
    case onboarding(AuthSession)
    case signedIn(UserProfile)
}

struct SharedStackUniversalLink: Equatable, Sendable {
    let stackID: UUID
    let token: UUID?

    init?(url: URL) {
        guard url.scheme?.lowercased() == "https",
              url.host?.lowercased() == "stacks.spot",
              url.pathComponents.count == 3,
              url.pathComponents[1] == "s",
              let stackID = UUID(uuidString: url.pathComponents[2]) else { return nil }
        let suppliedToken = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "token" })?.value
        if let suppliedToken {
            guard let token = UUID(uuidString: suppliedToken) else { return nil }
            self.token = token
        } else {
            token = nil
        }
        self.stackID = stackID
    }
}

private func withSessionRestoreTimeout<T: Sendable>(
    _ duration: Duration,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: duration)
            throw SessionRestoreError.timedOut
        }
        guard let result = try await group.next() else { throw CancellationError() }
        group.cancelAll()
        return result
    }
}

@MainActor
@Observable
final class AppSession {
    private static let pendingInviteDefaultsKey = "stacks.pendingCollaborationInviteToken"
    private static let cachedProfileDefaultsKey = "stacks.cachedCurrentProfile"
    private static let pendingLegalAcceptanceDefaultsKey = "stacks.pendingLegalAcceptanceVersion"
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
    var pendingCollaborationInvite: CollaborationInvitePreview?
    var isAcceptingCollaborationInvite = false
    var pendingSharedStackLink: SharedStackUniversalLink?

    init(services: AppServices) {
        self.services = services
    }

    var currentUser: UserProfile? {
        if case .signedIn(let profile) = state {
            return profile
        }
        return nil
    }

    var currentAccountID: UUID? {
        switch state {
        case .onboarding(let session): session.userID
        case .signedIn(let profile): profile.id
        case .launching, .signedOut: nil
        }
    }

    func restore() async {
        let cachedProfile = Self.cachedProfile()
        if let cachedProfile {
            // A returning member should see their library immediately. The
            // backend refresh below updates or invalidates this snapshot.
            if SharedStackDestinationStore.ownerID != cachedProfile.id {
                SharedStackDestinationStore.clear()
            }
            state = .signedIn(cachedProfile)
        }

        let auth = services.auth
        let profiles = services.profiles
        do {
            let outcome = try await withSessionRestoreTimeout(.seconds(4)) {
                guard let session = try await auth.restoreSession() else {
                    return SessionRestoreOutcome.signedOut
                }
                if session.hasCompletedOnboarding {
                    return .signedIn(try await profiles.currentProfile(for: session))
                }
                return .onboarding(session)
            }

            switch outcome {
            case .signedOut:
                state = .signedOut
                Self.cache(profile: nil)
                SharedStackDestinationStore.clear()
            case .onboarding(let session):
                state = .onboarding(session)
                Self.cache(profile: nil)
                SharedStackDestinationStore.clear()
            case .signedIn(let profile):
                if SharedStackDestinationStore.ownerID != profile.id {
                    SharedStackDestinationStore.clear()
                }
                state = .signedIn(profile)
                Self.cache(profile: profile)
                await preparePendingCollaborationInviteIfPossible()
            }
        } catch is CancellationError {
            return
        } catch SessionRestoreError.timedOut {
            // Keep a cached signed-in experience usable offline. On a first
            // launch, stop waiting and present sign-in instead of a blank app.
            if cachedProfile == nil { state = .signedOut }
            lastError = cachedProfile == nil ? "The connection is taking too long. Please try again." : nil
        } catch {
            if cachedProfile == nil {
                lastError = error.localizedDescription
                state = .signedOut
                SharedStackDestinationStore.clear()
            }
        }
    }

    @discardableResult
    func signInWithApple(acceptingLegalTerms: Bool = false) async -> Bool {
        guard acceptingLegalTerms else {
            lastError = "Agree to the Terms and Privacy Policy to continue."
            return false
        }
        do {
            let session = try await services.auth.signInWithApple()
            try await services.auth.recordLegalAcceptance(for: session.userID, version: StacksLegalAgreement.version)
            state = .onboarding(session)
            SharedStackDestinationStore.clear()
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
    func signInWithGoogle(acceptingLegalTerms: Bool = false) async -> Bool {
        guard acceptingLegalTerms else {
            lastError = "Agree to the Terms and Privacy Policy to continue."
            return false
        }
        do {
            let session = try await services.auth.signInWithGoogle()
            try await services.auth.recordLegalAcceptance(for: session.userID, version: StacksLegalAgreement.version)
            state = .onboarding(session)
            SharedStackDestinationStore.clear()
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
    func signInWithEmail(_ email: String, acceptingLegalTerms: Bool = false) async -> Bool {
        guard acceptingLegalTerms else {
            lastError = "Agree to the Terms and Privacy Policy to continue."
            return false
        }
        do {
            let result = try await services.auth.signInWithEmail(email)
            switch result {
            case .authenticated(let session):
                try await services.auth.recordLegalAcceptance(for: session.userID, version: StacksLegalAgreement.version)
                state = .onboarding(session)
                SharedStackDestinationStore.clear()
                pendingEmailSignIn = false
            case .linkSent:
                pendingEmailSignIn = true
                UserDefaults.standard.set(
                    StacksLegalAgreement.version,
                    forKey: Self.pendingLegalAcceptanceDefaultsKey
                )
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
        if let token = collaborationInviteToken(from: url) {
            UserDefaults.standard.set(token.uuidString, forKey: Self.pendingInviteDefaultsKey)
            await preparePendingCollaborationInviteIfPossible()
            return
        }
        if let stackLink = SharedStackUniversalLink(url: url) {
            pendingSharedStackLink = stackLink
            return
        }
        // The signed-in shell opens private wishlist links. They are not auth callbacks.
        if url.scheme?.lowercased() == "stacks", url.host?.lowercased() == "wishlist" {
            return
        }
        do {
            guard let authSession = try await services.auth.handleAuthCallback(url) else { return }
            if let version = UserDefaults.standard.string(forKey: Self.pendingLegalAcceptanceDefaultsKey) {
                try await services.auth.recordLegalAcceptance(for: authSession.userID, version: version)
                UserDefaults.standard.removeObject(forKey: Self.pendingLegalAcceptanceDefaultsKey)
            }
            pendingEmailSignIn = false
            lastError = nil
            if authSession.hasCompletedOnboarding {
                let profile = try await services.profiles.currentProfile(for: authSession)
                if SharedStackDestinationStore.ownerID != profile.id {
                    SharedStackDestinationStore.clear()
                }
                state = .signedIn(profile)
                Self.cache(profile: profile)
                await preparePendingCollaborationInviteIfPossible()
            } else {
                state = .onboarding(authSession)
                SharedStackDestinationStore.clear()
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
            SharedStackDestinationStore.clear()
            state = .signedIn(profile)
            Self.cache(profile: profile)
            await preparePendingCollaborationInviteIfPossible()
            pendingEmailSignIn = false
            UserDefaults.standard.removeObject(forKey: Self.pendingLegalAcceptanceDefaultsKey)
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
            Self.cache(profile: nil)
            SharedStackDestinationStore.clear()
            pendingEmailSignIn = false
        } catch {
            lastError = error.localizedDescription
        }
    }

    func updateCurrentProfile(displayName: String, username: String, bio: String? = nil) -> UserProfile? {
        guard case .signedIn(var profile) = state else { return nil }
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let handle = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !handle.isEmpty else { return nil }
        profile.displayName = name
        profile.username = handle
        if let bio {
            profile.bio = bio.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        state = .signedIn(profile)
        Self.cache(profile: profile)
        return profile
    }

    func replaceCurrentProfile(with profile: UserProfile) {
        guard currentUser?.id == profile.id else { return }
        state = .signedIn(profile)
        Self.cache(profile: profile)
    }

    func acceptPendingCollaborationInvite() async -> UUID? {
        guard let invite = pendingCollaborationInvite else { return nil }
        isAcceptingCollaborationInvite = true
        defer { isAcceptingCollaborationInvite = false }
        do {
            let stackID = try await services.collaboration.acceptInvite(token: invite.token)
            pendingCollaborationInvite = nil
            UserDefaults.standard.removeObject(forKey: Self.pendingInviteDefaultsKey)
            lastError = nil
            NotificationCenter.default.post(name: .stacksCollaborationDidChange, object: stackID)
            services.haptics.notification(.success)
            return stackID
        } catch {
            lastError = error.localizedDescription
            services.haptics.notification(.error)
            return nil
        }
    }

    func dismissPendingCollaborationInvite() {
        pendingCollaborationInvite = nil
        UserDefaults.standard.removeObject(forKey: Self.pendingInviteDefaultsKey)
    }

    func clearPendingSharedStackLink() {
        pendingSharedStackLink = nil
    }

    private func collaborationInviteToken(from url: URL) -> UUID? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        if url.scheme?.lowercased() == "stacks", url.host?.lowercased() == "invite",
           let value = components.queryItems?.first(where: { $0.name == "token" })?.value {
            return UUID(uuidString: value)
        }
        if url.scheme?.lowercased() == "https",
           url.host?.lowercased() == "stacks.spot",
           let inviteIndex = url.pathComponents.firstIndex(of: "invite"),
           url.pathComponents.indices.contains(inviteIndex + 1) {
            return UUID(uuidString: url.pathComponents[inviteIndex + 1])
        }
        return nil
    }

    private func preparePendingCollaborationInviteIfPossible() async {
        guard currentUser != nil,
              let rawToken = UserDefaults.standard.string(forKey: Self.pendingInviteDefaultsKey),
              let token = UUID(uuidString: rawToken) else { return }
        do {
            pendingCollaborationInvite = try await services.collaboration.previewInvite(token: token)
            lastError = nil
        } catch {
            UserDefaults.standard.removeObject(forKey: Self.pendingInviteDefaultsKey)
            lastError = error.localizedDescription
            services.haptics.notification(.error)
        }
    }

    @discardableResult
    func requestAccountDeletion() async -> Bool {
        do {
            try await services.auth.requestAccountDeletion()
            state = .signedOut
            Self.cache(profile: nil)
            SharedStackDestinationStore.clear()
            lastError = nil
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    private static func cachedProfile() -> UserProfile? {
        guard let data = UserDefaults.standard.data(forKey: cachedProfileDefaultsKey) else { return nil }
        return try? JSONDecoder().decode(UserProfile.self, from: data)
    }

    private static func cache(profile: UserProfile?) {
        guard let profile,
              let data = try? JSONEncoder().encode(profile) else {
            UserDefaults.standard.removeObject(forKey: cachedProfileDefaultsKey)
            return
        }
        UserDefaults.standard.set(data, forKey: cachedProfileDefaultsKey)
    }
}

import AuthenticationServices
import CryptoKit
import Foundation
import Security
import UIKit

/// Runtime configuration loaded from Xcode's generated Info.plist. The anon
/// key is intentionally not committed; it belongs in the developer's local
/// `.xcconfig` or build settings.
struct SupabaseConfiguration: Sendable {
    let projectURL: URL
    let anonKey: String
    let redirectURL: URL

    static func fromAppBundle() -> Self? {
        let redirectURLString = configuredString(for: "STACKS_AUTH_REDIRECT_URL") ?? "stacks://auth/callback"
        guard let projectURLString = configuredString(for: "STACKS_SUPABASE_URL"),
              let projectURL = URL(string: projectURLString),
              projectURL.scheme == "https",
              let anonKey = configuredString(for: "STACKS_SUPABASE_ANON_KEY"),
              let redirectURL = URL(string: redirectURLString) else {
            return nil
        }
        return Self(projectURL: projectURL, anonKey: anonKey, redirectURL: redirectURL)
    }
}

private func configuredString(for key: String) -> String? {
    guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty || trimmed.hasPrefix("$(") ? nil : trimmed
}

private struct StoredSupabaseSession: Codable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date?
}

/// Tokens live in the Keychain, never in app preferences, files, or the
/// database. The actor serializes refresh and clear operations across services.
private actor SupabaseSessionStore {
    static let shared = SupabaseSessionStore()
    private let service = "spot.stacks.app.supabase"
    private let account = "current-session"
    private var refreshTask: Task<StoredSupabaseSession, Error>?

    /// Requests that find the token expiring all wait on one refresh. Six
    /// parallel refreshes each rotated the refresh token, which risks Supabase
    /// treating a stale one as reuse and signing the person out.
    func sharedRefresh(
        of session: StoredSupabaseSession,
        perform: @escaping @Sendable (StoredSupabaseSession) async throws -> StoredSupabaseSession
    ) async throws -> StoredSupabaseSession {
        if let refreshTask {
            return try await refreshTask.value
        }
        // Another caller already refreshed after this one read the old session.
        if let stored = load(), stored.refreshToken != session.refreshToken {
            return stored
        }
        let task = Task { try await perform(session) }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    func load() -> StoredSupabaseSession? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(StoredSupabaseSession.self, from: data)
    }

    func save(_ session: StoredSupabaseSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        let attributes: [CFString: Any] = [
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var insert = query
            attributes.forEach { insert[$0.key] = $0.value }
            _ = SecItemAdd(insert as CFDictionary, nil)
        }
    }

    func clear() {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    func savePendingPKCEVerifier(_ verifier: String) {
        saveData(Data(verifier.utf8), account: "pending-pkce-verifier")
    }

    func takePendingPKCEVerifier() -> String? {
        defer { deleteData(account: "pending-pkce-verifier") }
        guard let data = loadData(account: "pending-pkce-verifier") else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func loadData(account: String) -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    private func saveData(_ data: Data, account: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        let attributes: [CFString: Any] = [
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        if SecItemUpdate(query as CFDictionary, attributes as CFDictionary) == errSecItemNotFound {
            var insert = query
            attributes.forEach { insert[$0.key] = $0.value }
            _ = SecItemAdd(insert as CFDictionary, nil)
        }
    }

    private func deleteData(account: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

private struct SupabaseClient: Sendable {
    let configuration: SupabaseConfiguration
    private let sessionStore = SupabaseSessionStore.shared

    func currentAccessToken() async throws -> String {
        guard let session = await sessionStore.load() else {
            throw AppError.unavailable("Your session expired. Please sign in again.")
        }

        if let expiresAt = session.expiresAt, expiresAt.timeIntervalSinceNow < 90 {
            return try await sessionStore.sharedRefresh(of: session) { stale in
                try await refresh(session: stale)
            }.accessToken
        }
        return session.accessToken
    }

    func restoredSession() async throws -> AuthSession? {
        guard await sessionStore.load() != nil else { return nil }
        let token = try await currentAccessToken()
        let user = try await authUser(accessToken: token)
        let profile = try await profileRow(id: user.id)
        return AuthSession(
            userID: user.id,
            email: user.email,
            displayName: profile?.displayName ?? user.displayName,
            hasCompletedOnboarding: profile?.onboardingCompletedAt != nil
        )
    }

    func saveAuthResponse(_ response: SupabaseAuthResponse) async throws -> AuthSession {
        guard let accessToken = response.accessToken,
              let refreshToken = response.refreshToken else {
            throw AppError.unavailable("Supabase did not return a sign-in session.")
        }
        let expiresAt = response.expiresIn.map { Date().addingTimeInterval(TimeInterval($0)) }
        await sessionStore.save(StoredSupabaseSession(accessToken: accessToken, refreshToken: refreshToken, expiresAt: expiresAt))
        let user: SupabaseAuthUser
        if let responseUser = response.user {
            user = responseUser
        } else {
            user = try await authUser(accessToken: accessToken)
        }
        let profile = try await profileRow(id: user.id)
        return AuthSession(
            userID: user.id,
            email: user.email,
            displayName: profile?.displayName ?? user.displayName,
            hasCompletedOnboarding: profile?.onboardingCompletedAt != nil
        )
    }

    func authUser(accessToken: String? = nil) async throws -> SupabaseAuthUser {
        let token: String
        if let accessToken {
            token = accessToken
        } else {
            token = try await currentAccessToken()
        }
        let data = try await request(
            url: configuration.projectURL.appending(path: "auth/v1/user"),
            method: "GET",
            accessToken: token
        )
        return try decoder.decode(SupabaseAuthUser.self, from: data)
    }

    func profileRow(id: UUID) async throws -> ProfileRow? {
        let rows: [ProfileRow] = try await rest(
            "profiles",
            query: [
                URLQueryItem(name: "id", value: "eq.\(id.uuidString)"),
                URLQueryItem(name: "select", value: "*")
            ]
        )
        return rows.first
    }

    func rest<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        let data = try await restData(path, query: query, method: "GET")
        return try decoder.decode(T.self, from: data)
    }

    func restData(
        _ path: String,
        query: [URLQueryItem] = [],
        method: String,
        body: Data? = nil,
        preferRepresentation: Bool = false
    ) async throws -> Data {
        var components = URLComponents(url: configuration.projectURL.appending(path: "rest/v1/\(path)"), resolvingAgainstBaseURL: false)
        components?.queryItems = query
        guard let url = components?.url else { throw AppError.invalidURL }
        return try await request(url: url, method: method, body: body, preferRepresentation: preferRepresentation)
    }

    func function<T: Decodable, Body: Encodable>(_ name: String, body: Body) async throws -> T {
        let data = try encoder.encode(AnyEncodable(body))
        let response = try await request(
            url: configuration.projectURL.appending(path: "functions/v1/\(name)"),
            method: "POST",
            body: data
        )
        return try decoder.decode(T.self, from: response)
    }

    func updateProfileOnboarding(id: UUID) async throws {
        let body = try encoder.encode(["onboarding_completed_at": iso8601.string(from: Date())])
        _ = try await restData(
            "profiles",
            query: [URLQueryItem(name: "id", value: "eq.\(id.uuidString)")],
            method: "PATCH",
            body: body
        )
    }

    func recordLegalAcceptance(id: UUID, version: String) async throws {
        struct AcceptancePayload: Encodable {
            let userID: UUID
            let legalTermsVersion: String
            let privacyPolicyVersion: String
            let acceptanceSource: String
            let appVersion: String?
            let appBuild: String?

            enum CodingKeys: String, CodingKey {
                case userID = "user_id"
                case legalTermsVersion = "legal_terms_version"
                case privacyPolicyVersion = "privacy_policy_version"
                case acceptanceSource = "acceptance_source"
                case appVersion = "app_version"
                case appBuild = "app_build"
            }
        }

        let acceptance = AcceptancePayload(
            userID: id,
            legalTermsVersion: version,
            privacyPolicyVersion: version,
            acceptanceSource: "ios_clickwrap",
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            appBuild: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        )
        _ = try await restData(
            "legal_acceptances",
            method: "POST",
            body: try encoder.encode(acceptance)
        )

        let acceptedAt = iso8601.string(from: Date())
        let body = try encoder.encode([
            "legal_terms_version": version,
            "legal_terms_accepted_at": acceptedAt,
            "privacy_policy_version": version,
            "privacy_policy_accepted_at": acceptedAt
        ])
        _ = try await restData(
            "profiles",
            query: [URLQueryItem(name: "id", value: "eq.\(id.uuidString)")],
            method: "PATCH",
            body: body
        )
    }

    func sendMagicLink(email: String) async throws {
        let verifier = PKCE.verifier()
        let challenge = PKCE.challenge(for: verifier)
        await sessionStore.savePendingPKCEVerifier(verifier)
        let body = try encoder.encode(SupabaseOTPRequest(
            email: email,
            createUser: true,
            codeChallenge: challenge,
            codeChallengeMethod: "s256"
        ))
        // GoTrue reads the email link's redirect from the query string, not the body.
        _ = try await request(
            url: configuration.projectURL.appending(path: "auth/v1/otp")
                .appending(queryItems: [URLQueryItem(name: "redirect_to", value: configuration.redirectURL.absoluteString)]),
            method: "POST",
            body: body,
            authenticated: false
        )
    }

    func exchangeAuthorizationCode(_ code: String) async throws -> AuthSession {
        guard let verifier = await sessionStore.takePendingPKCEVerifier() else {
            throw AppError.unavailable("That sign-in link has expired. Request a new one and open it on this device.")
        }
        let body = try encoder.encode(["auth_code": code, "code_verifier": verifier])
        let data = try await request(
            url: tokenURL(grantType: "pkce"),
            method: "POST",
            body: body,
            authenticated: false
        )
        return try await saveAuthResponse(decoder.decode(SupabaseAuthResponse.self, from: data))
    }

    func exchangeAppleIdentityToken(_ identityToken: String) async throws -> AuthSession {
        let body = try encoder.encode(["provider": "apple", "id_token": identityToken])
        let data = try await request(
            url: tokenURL(grantType: "id_token"),
            method: "POST",
            body: body,
            authenticated: false
        )
        return try await saveAuthResponse(decoder.decode(SupabaseAuthResponse.self, from: data))
    }

    func verifyEmailOTP(email: String, token: String) async throws -> AuthSession {
        let body = try encoder.encode(["type": "email", "email": email, "token": token])
        let data = try await request(
            url: configuration.projectURL.appending(path: "auth/v1/verify"),
            method: "POST",
            body: body,
            authenticated: false
        )
        return try await saveAuthResponse(decoder.decode(SupabaseAuthResponse.self, from: data))
    }

    /// The App Review account signs in with a fixed code checked by the
    /// review-sign-in function, since reviewers can't read its email.
    func verifyReviewCode(email: String, code: String) async throws -> AuthSession {
        let body = try encoder.encode(["email": email, "code": code])
        let data = try await request(
            url: configuration.projectURL.appending(path: "functions/v1/review-sign-in"),
            method: "POST",
            body: body,
            authenticated: false
        )
        return try await saveAuthResponse(decoder.decode(SupabaseAuthResponse.self, from: data))
    }

    func exchangeGoogleIdentityToken(_ identityToken: String, nonce: String) async throws -> AuthSession {
        let body = try encoder.encode(["provider": "google", "id_token": identityToken, "nonce": nonce])
        let data = try await request(
            url: tokenURL(grantType: "id_token"),
            method: "POST",
            body: body,
            authenticated: false
        )
        return try await saveAuthResponse(decoder.decode(SupabaseAuthResponse.self, from: data))
    }

    /// `appending(path:)` would percent-encode a `?` into the path, so the
    /// grant type goes in as a real query item.
    private func tokenURL(grantType: String) -> URL {
        configuration.projectURL.appending(path: "auth/v1/token")
            .appending(queryItems: [URLQueryItem(name: "grant_type", value: grantType)])
    }

    func googleOAuthAuthorizationURL() async throws -> (url: URL, callbackScheme: String) {
        let verifier = PKCE.verifier()
        let challenge = PKCE.challenge(for: verifier)
        await sessionStore.savePendingPKCEVerifier(verifier)

        var components = URLComponents(
            url: configuration.projectURL.appending(path: "auth/v1/authorize"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "provider", value: "google"),
            URLQueryItem(name: "redirect_to", value: configuration.redirectURL.absoluteString),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "s256")
        ]
        guard let url = components?.url,
              let callbackScheme = configuration.redirectURL.scheme else {
            throw AppError.invalidURL
        }
        return (url, callbackScheme)
    }

    func signOut() async throws {
        guard let session = await sessionStore.load() else { return }
        _ = try? await request(
            url: configuration.projectURL.appending(path: "auth/v1/logout"),
            method: "POST",
            accessToken: session.accessToken
        )
        await sessionStore.clear()
    }

    func uploadMedia(_ data: Data, path: String, contentType: String) async throws {
        try await uploadData(data, bucket: "stack-media", path: path, contentType: contentType)
    }

    func uploadProfileAvatar(_ data: Data, ownerID: UUID) async throws -> String {
        guard let image = UIImage(data: data),
              let jpegData = image.jpegData(compressionQuality: 0.86) else {
            throw AppError.unavailable("We couldn't prepare that profile photo. Try another image.")
        }
        // Storage policies compare the folder with auth.uid(), which is lowercase.
        let path = "\(ownerID.uuidString.lowercased())/avatar.jpg"
        try await uploadData(jpegData, bucket: "profile-media", path: path, contentType: "image/jpeg")
        return path
    }

    private func uploadData(_ data: Data, bucket: String, path: String, contentType: String) async throws {
        guard !data.isEmpty else { throw AppError.missingRequiredField("Image") }
        let encodedPath = path.split(separator: "/").map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }.joined(separator: "/")
        var request = URLRequest(url: configuration.projectURL.appending(path: "storage/v1/object/\(bucket)/\(encodedPath)"))
        request.httpMethod = "POST"
        request.httpBody = data
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("true", forHTTPHeaderField: "x-upsert")
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(try await currentAccessToken())", forHTTPHeaderField: "Authorization")
        _ = try await perform(request, authenticated: false)
    }

    func signedMediaURL(path: String, stackID: UUID, linkToken: UUID? = nil) async -> URL? {
        struct MediaRequest: Encodable { let stackID: UUID; let path: String; let linkToken: UUID? }
        struct MediaResponse: Decodable { let signedURL: URL }
        guard let response: MediaResponse = try? await function(
            "media-url",
            body: MediaRequest(stackID: stackID, path: path, linkToken: linkToken)
        ) else {
            return nil
        }
        return response.signedURL
    }

    func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try decoder.decode(type, from: data)
    }

    private func refresh(session: StoredSupabaseSession) async throws -> StoredSupabaseSession {
        var components = URLComponents(url: configuration.projectURL.appending(path: "auth/v1/token"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "grant_type", value: "refresh_token")]
        guard let url = components?.url else { throw AppError.invalidURL }
        let body = try encoder.encode(["refresh_token": session.refreshToken])
        let data = try await request(url: url, method: "POST", body: body, authenticated: false)
        let response = try decoder.decode(SupabaseAuthResponse.self, from: data)
        guard let accessToken = response.accessToken,
              let refreshToken = response.refreshToken else {
            await sessionStore.clear()
            throw AppError.unavailable("Your session expired. Please sign in again.")
        }
        let refreshed = StoredSupabaseSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: response.expiresIn.map { Date().addingTimeInterval(TimeInterval($0)) }
        )
        await sessionStore.save(refreshed)
        return refreshed
    }

    private func request(
        url: URL,
        method: String,
        body: Data? = nil,
        preferRepresentation: Bool = false,
        accessToken: String? = nil,
        authenticated: Bool = true
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.httpBody = body
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if preferRepresentation { request.setValue("return=representation", forHTTPHeaderField: "Prefer") }
        if authenticated {
            let token: String
            if let accessToken {
                token = accessToken
            } else {
                token = try await currentAccessToken()
            }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return try await perform(request, authenticated: false)
    }

    private func perform(_ request: URLRequest, authenticated: Bool) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.unavailable("Supabase did not return a valid response.")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let response = try? decoder.decode(SupabaseErrorResponse.self, from: data)
            throw AppError.unavailable(SupabaseErrorResponse.userFacingMessage(
                response,
                statusCode: httpResponse.statusCode
            ))
        }
        return data
    }

    private var encoder: JSONEncoder {
        JSONEncoder()
    }

    var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = ISO8601DateFormatter.stacks.date(from: value) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO-8601 date.")
        }
        return decoder
    }

    private var iso8601: ISO8601DateFormatter { .stacks }
}

struct SupabaseProEntitlementService: Sendable {
    private struct Request: Encodable { let transactionID: String? }
    struct Status: Decodable { let isPro: Bool; let expiresAt: Date? }

    func sync(transactionID: String? = nil) async throws -> Status {
        guard let configuration = SupabaseConfiguration.fromAppBundle() else {
            throw AppError.unavailable("Supabase is not configured.")
        }
        let response: Status = try await SupabaseClient(configuration: configuration)
            .function("sync-pro-entitlement", body: Request(transactionID: transactionID))
        return response
    }
}

struct SupabasePushTokenService: Sendable {
    private struct Request: Encodable {
        let deviceToken: String
        let platform = "ios"
        let environment: String
    }

    func register(deviceToken: String) async throws {
        guard let configuration = SupabaseConfiguration.fromAppBundle() else { return }
        #if DEBUG
        let environment = "sandbox"
        #else
        let environment = "production"
        #endif
        let _: EmptyFunctionResponse = try await SupabaseClient(configuration: configuration)
            .function("register-push-token", body: Request(deviceToken: deviceToken, environment: environment))
    }
}

struct SupabasePriceAlertService: Sendable {
    struct Listing: Decodable, Sendable {
        let alerts: [PriceAlert]
        let events: [PriceAlertEvent]
        let notificationsEnabled: Bool
    }

    private struct Request: Encodable {
        let action: String
        var itemID: UUID?
        var alertID: UUID?
        var eventID: UUID?
        var mode: String?
        var targetPrice: Decimal?
        var paused: Bool?
        var enabled: Bool?
        var linkToken: UUID?
    }
    private struct Response: Decodable { let enabled: Bool? }

    private func client() throws -> SupabaseClient {
        guard let configuration = SupabaseConfiguration.fromAppBundle() else {
            throw AppError.unavailable("Price alerts are not configured for this build.")
        }
        return SupabaseClient(configuration: configuration)
    }

    func list() async throws -> Listing {
        try await client().function("price-alerts", body: Request(action: "list"))
    }

    func save(itemID: UUID, mode: PriceAlertMode, targetPrice: Decimal?, linkToken: UUID?) async throws {
        let _: Response = try await client().function(
            "price-alerts",
            body: Request(action: "upsert", itemID: itemID, mode: mode.rawValue, targetPrice: targetPrice, linkToken: linkToken)
        )
    }

    func delete(alertID: UUID) async throws {
        let _: Response = try await client().function("price-alerts", body: Request(action: "delete", alertID: alertID))
    }

    func setPaused(_ paused: Bool, alertID: UUID) async throws {
        let _: Response = try await client().function(
            "price-alerts", body: Request(action: "set_status", alertID: alertID, paused: paused)
        )
    }

    func setNotificationsEnabled(_ enabled: Bool) async throws {
        let _: Response = try await client().function(
            "price-alerts", body: Request(action: "set_notifications", enabled: enabled)
        )
    }

    func markRead(eventID: UUID) async throws {
        let _: Response = try await client().function("price-alerts", body: Request(action: "mark_read", eventID: eventID))
    }
}

private struct EmptyFunctionResponse: Decodable {}

struct SupabaseAuthService: AuthService {
    private let client: SupabaseClient

    init(configuration: SupabaseConfiguration) {
        client = SupabaseClient(configuration: configuration)
    }

    func restoreSession() async throws -> AuthSession? {
        try await client.restoredSession()
    }

    func signInWithApple() async throws -> AuthSession {
        let authorization = try await AppleSignInAuthorizer.authorize()
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let identityTokenData = credential.identityToken,
              let identityToken = String(data: identityTokenData, encoding: .utf8) else {
            throw AppError.unavailable("Apple did not return a sign-in token. Please try again.")
        }
        return try await client.exchangeAppleIdentityToken(identityToken)
    }

    func signInWithGoogle() async throws -> AuthSession {
        // With an iOS client ID, Google's own sheet names the app "Stacks".
        // Without one, fall back to Supabase's web flow, where Google shows
        // the Supabase project domain instead.
        if let clientID = configuredString(for: "STACKS_GOOGLE_IOS_CLIENT_ID") {
            let credential = try await GoogleNativeSignIn.authorize(clientID: clientID)
            return try await client.exchangeGoogleIdentityToken(credential.idToken, nonce: credential.rawNonce)
        }
        let authorization = try await client.googleOAuthAuthorizationURL()
        let callbackURL = try await OAuthSignInAuthorizer.authorize(
            url: authorization.url,
            callbackScheme: authorization.callbackScheme
        )
        guard let session = try await handleAuthCallback(callbackURL) else {
            throw AppError.unavailable("Google did not return a sign-in callback. Please try again.")
        }
        return session
    }

    func signInWithEmail(_ email: String) async throws -> EmailAuthenticationResult {
        guard email.contains("@"), email.contains(".") else { throw AppError.invalidEmail }
        try await client.sendMagicLink(email: email)
        return .linkSent
    }

    func handleAuthCallback(_ url: URL) async throws -> AuthSession? {
        guard url.scheme?.lowercased() == "stacks", url.host?.lowercased() == "auth" else { return nil }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let query = Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        let fragment = Dictionary(uniqueKeysWithValues: (components?.fragment ?? "")
            .split(separator: "&")
            .map { part -> (String, String) in
                let pieces = part.split(separator: "=", maxSplits: 1).map(String.init)
                return (pieces.first ?? "", pieces.count > 1 ? pieces[1].removingPercentEncoding ?? pieces[1] : "")
            }
        )
        if let code = query["code"], !code.isEmpty {
            return try await client.exchangeAuthorizationCode(code)
        }
        let accessToken = fragment["access_token"] ?? query["access_token"]
        let refreshToken = fragment["refresh_token"] ?? query["refresh_token"]
        guard let accessToken, let refreshToken else {
            throw AppError.unavailable("The sign-in link was incomplete. Request another one and open it on this device.")
        }
        let expiresIn = Int(fragment["expires_in"] ?? query["expires_in"] ?? "")
        return try await client.saveAuthResponse(SupabaseAuthResponse(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresIn: expiresIn,
            user: nil
        ))
    }

    func verifyEmailCode(_ code: String, email: String) async throws -> AuthSession {
        let digits = code.filter(\.isNumber)
        guard !digits.isEmpty else { throw AppError.missingRequiredField("Code") }
        do {
            return try await client.verifyEmailOTP(email: email, token: digits)
        } catch let emailError {
            // Only the review account has a fixed code; for everyone else
            // the function says no and the email code's error stands.
            do {
                return try await client.verifyReviewCode(email: email, code: digits)
            } catch {
                throw emailError
            }
        }
    }

    func recordLegalAcceptance(for userID: UUID, version: String) async throws {
        try await client.recordLegalAcceptance(id: userID, version: version)
    }

    func completeOnboarding(for userID: UUID) async throws {
        try await client.updateProfileOnboarding(id: userID)
    }

    func signOut() async throws {
        try await client.signOut()
    }

    func requestAccountDeletion() async throws {
        struct EmptyRequest: Encodable {}
        struct DeleteResponse: Decodable { let deleted: Bool? }
        _ = try await client.function("delete-account", body: EmptyRequest()) as DeleteResponse
        try await client.signOut()
    }
}

/// Google sign-in with the iOS OAuth client: PKCE in an
/// ASWebAuthenticationSession, then the ID token goes to Supabase. Google's
/// consent screen shows the app's name rather than the Supabase domain.
private enum GoogleNativeSignIn {
    struct Credential {
        let idToken: String
        let rawNonce: String
    }

    private struct TokenResponse: Decodable {
        let idToken: String?

        enum CodingKeys: String, CodingKey {
            case idToken = "id_token"
        }
    }

    static func authorize(clientID: String) async throws -> Credential {
        // Google's iOS redirect scheme is the client ID reversed.
        let scheme = clientID.split(separator: ".").reversed().joined(separator: ".")
        let redirectURI = "\(scheme):/oauth2redirect"
        let verifier = PKCE.verifier()
        let state = PKCE.verifier()
        let rawNonce = PKCE.verifier()
        let hashedNonce = CryptoKit.SHA256.hash(data: Data(rawNonce.utf8))
            .map { String(format: "%02x", $0) }
            .joined()

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email profile"),
            URLQueryItem(name: "code_challenge", value: PKCE.challenge(for: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "nonce", value: hashedNonce),
            URLQueryItem(name: "prompt", value: "select_account")
        ]
        guard let url = components?.url else { throw AppError.invalidURL }

        let callbackURL = try await OAuthSignInAuthorizer.authorize(url: url, callbackScheme: scheme)
        let query = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if query.first(where: { $0.name == "error" })?.value == "access_denied" {
            throw CancellationError()
        }
        guard query.first(where: { $0.name == "state" })?.value == state,
              let code = query.first(where: { $0.name == "code" })?.value else {
            throw AppError.unavailable("Google sign-in didn't finish. Please try again.")
        }

        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = [
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "code_verifier", value: verifier),
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI)
        ]
        request.httpBody = form.percentEncodedQuery?.data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let idToken = try JSONDecoder().decode(TokenResponse.self, from: data).idToken else {
            throw AppError.unavailable("Google sign-in didn't finish. Please try again.")
        }
        return Credential(idToken: idToken, rawNonce: rawNonce)
    }
}

@MainActor
fileprivate final class AppleSignInAuthorizer: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<ASAuthorization, Error>?

    static func authorize() async throws -> ASAuthorization {
        let authorizer = AppleSignInAuthorizer()
        return try await withCheckedThrowingContinuation { continuation in
            authorizer.continuation = continuation
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = authorizer
            controller.presentationContextProvider = authorizer
            controller.performRequests()
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        continuation?.resume(returning: authorization)
        continuation = nil
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: { $0.isKeyWindow }) ?? ASPresentationAnchor()
    }
}

@MainActor
fileprivate final class OAuthSignInAuthorizer: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var continuation: CheckedContinuation<URL, Error>?
    private var session: ASWebAuthenticationSession?

    static func authorize(url: URL, callbackScheme: String) async throws -> URL {
        let authorizer = OAuthSignInAuthorizer()
        return try await authorizer.start(url: url, callbackScheme: callbackScheme)
    }

    private func start(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme
            ) { [weak self] callbackURL, error in
                guard let self else { return }
                if let callbackURL {
                    self.continuation?.resume(returning: callbackURL)
                } else {
                    self.continuation?.resume(throwing: error ?? ASWebAuthenticationSessionError(.canceledLogin))
                }
                self.continuation = nil
                self.session = nil
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            guard session.start() else {
                self.continuation?.resume(throwing: AppError.unavailable("Could not open Google sign-in. Please try again."))
                self.continuation = nil
                self.session = nil
                return
            }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: { $0.isKeyWindow }) ?? ASPresentationAnchor()
    }
}

struct SupabaseStackRepository: StackRepository {
    private let client: SupabaseClient

    init(configuration: SupabaseConfiguration) {
        client = SupabaseClient(configuration: configuration)
    }

    func fetchMyStacks(for userID: UUID) async throws -> [Stack] {
        let collaboratorRows: [StackCollaboratorAccessRow] = try await client.rest(
            "stack_collaborators",
            query: [
                URLQueryItem(name: "user_id", value: "eq.\(userID.uuidString)"),
                URLQueryItem(name: "accepted_at", value: "not.is.null"),
                URLQueryItem(name: "select", value: "stack_id")
            ]
        )
        let collaboratorIDs = collaboratorRows.map(\.stackID)
        let accessFilter: URLQueryItem
        if collaboratorIDs.isEmpty {
            accessFilter = URLQueryItem(name: "owner_id", value: "eq.\(userID.uuidString)")
        } else {
            let ids = collaboratorIDs.map(\.uuidString).joined(separator: ",")
            accessFilter = URLQueryItem(
                name: "or",
                value: "(owner_id.eq.\(userID.uuidString),id.in.(\(ids)))"
            )
        }
        let rows: [StackRow] = try await client.rest(
            "stacks",
            query: [
                accessFilter,
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "order", value: "updated_at.desc")
            ]
        )
        return try await compose(rows: rows, viewerID: userID)
    }

    func fetchOwnedStackDestinations(for user: UserProfile) async throws -> [SharedStackDestination] {
        // The Share Sheet only needs owned Stack names. Fetching full Stacks
        // also fetches items and collaborators, so an unrelated failure there
        // must not make an owner's destinations disappear.
        let rows: [OwnedStackDestinationRow] = try await client.rest(
            "stacks",
            query: [
                URLQueryItem(name: "owner_id", value: "eq.\(user.id.uuidString)"),
                URLQueryItem(name: "select", value: "id,title,updated_at"),
                URLQueryItem(name: "order", value: "updated_at.desc")
            ]
        )
        return rows.map {
            SharedStackDestination(
                id: $0.id,
                title: $0.title,
                ownerName: user.displayName,
                avatarURL: user.avatarURL,
                updatedAt: $0.updatedAt
            )
        }
    }

    func fetchStack(id: UUID, for userID: UUID) async throws -> Stack {
        try await fetchStack(id: id, viewerID: userID)
    }

    func fetchPublicStacks(ownerID: UUID, for viewerID: UUID) async throws -> [Stack] {
        let rows: [StackRow] = try await client.rest(
            "stacks",
            query: [
                URLQueryItem(name: "owner_id", value: "eq.\(ownerID.uuidString)"),
                URLQueryItem(name: "visibility", value: "eq.public"),
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "order", value: "updated_at.desc")
            ]
        )
        return try await compose(rows: rows, viewerID: viewerID)
    }

    func fetchDiscoverStacks(query: String?) async throws -> [Stack] {
        let curated = (try? await CuratedStackCatalog.fetchStacks()) ?? []
        let viewer = try await client.authUser()
        let liveStacks: [Stack]
        do {
            let rows: [StackRow] = try await client.rest(
                "stacks",
                query: [
                    URLQueryItem(name: "visibility", value: "eq.public"),
                    URLQueryItem(name: "select", value: "*"),
                    URLQueryItem(name: "order", value: "updated_at.desc")
                ]
            )
            // Empty Stacks (a just-made "test") aren't worth showing anyone.
            liveStacks = try await compose(rows: rows, viewerID: viewer.id).filter { !$0.items.isEmpty }
        } catch {
            guard !curated.isEmpty else { throw error }
            liveStacks = []
        }
        // Real members' Stacks replace the editorial ones; the curated
        // catalog only fills Discover until someone has a public Stack.
        let stacks = (liveStacks.isEmpty ? curated : liveStacks).sorted(by: discoverSort)
        guard let query, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return stacks }
        return stacks.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.author.displayName.localizedCaseInsensitiveContains(query)
                || $0.author.username.localizedCaseInsensitiveContains(query)
        }
    }

    /// The founders' Stacks lead Discover while the community is small.
    private static let featuredUsernames: [String] = ["neeha", "owen"]

    private func discoverSort(_ lhs: Stack, _ rhs: Stack) -> Bool {
        let featured = Self.featuredUsernames
        let lhsRank = featured.firstIndex(of: lhs.author.username.lowercased()) ?? featured.count
        let rhsRank = featured.firstIndex(of: rhs.author.username.lowercased()) ?? featured.count
        if lhsRank != rhsRank {
            return lhsRank < rhsRank
        }
        if lhs.isFollowingAuthor != rhs.isFollowingAuthor {
            return lhs.isFollowingAuthor
        }
        return lhs.updatedAt > rhs.updatedAt
    }

    func createStack(title: String, wishlistMode: Bool, visibility: StackVisibility, owner: UserProfile) async throws -> Stack {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { throw AppError.missingRequiredField("Title") }
        let body = try JSONEncoder().encode(StackWrite(
            ownerID: owner.id,
            title: cleanTitle,
            visibility: visibility.databaseValue,
            wishlistMode: wishlistMode,
            collaborationEnabled: false
        ))
        let rows: [StackRow] = try await decodeRest(
            "stacks",
            method: "POST",
            body: body,
            preferRepresentation: true
        )
        guard let row = rows.first,
              let stack = try await compose(rows: [row], viewerID: owner.id).first else {
            throw AppError.notFound
        }
        return stack
    }

    func fetchSharedStack(token: UUID) async throws -> Stack {
        struct SharedPayload: Decodable {
            let stack: StackRow
            let items: [ItemRow]
        }

        let body = try JSONEncoder().encode(["link_token": token.uuidString])
        let data = try await client.restData("rpc/get_link_only_stack", method: "POST", body: body)
        let payload = try client.decode(SharedPayload.self, from: data)
        let author = (try? await client.profileRow(id: payload.stack.ownerID))?.profile(using: client.configuration)
            ?? UserProfile(
                id: payload.stack.ownerID,
                displayName: "Stacks member",
                username: "stacker",
                avatarURL: nil,
                bio: "",
                linkInBioURL: nil,
                isFollowing: false
            )
        let mappedItems = await mapItems(payload.items, stackID: payload.stack.id, linkToken: token)
        return Stack(
            id: payload.stack.id,
            ownerID: payload.stack.ownerID,
            author: author,
            title: payload.stack.title,
            visibility: .publicLink,
            wishlistMode: payload.stack.wishlistMode,
            collaborationEnabled: payload.stack.collaborationEnabled,
            collaborators: [],
            items: mappedItems,
            publicLinkToken: token,
            createdAt: payload.stack.createdAt,
            updatedAt: payload.stack.updatedAt,
            isBookmarked: false,
            isFollowingAuthor: false
        )
    }

    func copyStack(_ stack: Stack, to owner: UserProfile) async throws -> Stack {
        struct CopyRequest: Encodable { let stackID: UUID; let title: String }
        struct CopyResponse: Decodable { let stackID: UUID }
        let response: CopyResponse = try await client.function("copy-public-stack", body: CopyRequest(stackID: stack.id, title: "\(stack.title) copy"))
        return try await fetchStack(id: response.stackID, viewerID: owner.id)
    }

    func updateStack(_ stack: Stack) async throws -> Stack {
        let body = try JSONEncoder().encode(StackWrite(
            ownerID: stack.ownerID,
            title: stack.title,
            visibility: stack.visibility.databaseValue,
            wishlistMode: stack.wishlistMode,
            collaborationEnabled: stack.collaborationEnabled
        ))
        _ = try await client.restData(
            "stacks",
            query: [URLQueryItem(name: "id", value: "eq.\(stack.id.uuidString)")],
            method: "PATCH",
            body: body
        )
        let viewer = try await client.authUser()
        return try await fetchStack(id: stack.id, viewerID: viewer.id)
    }

    func rotateWishlistLink(stackID: UUID, revoke: Bool) async throws -> Stack {
        struct Request: Encodable {
            let targetStackID: UUID
            let revokeLink: Bool
            enum CodingKeys: String, CodingKey { case targetStackID = "target_stack_id", revokeLink = "revoke_link" }
        }
        let body = try JSONEncoder().encode(Request(targetStackID: stackID, revokeLink: revoke))
        _ = try await client.restData("rpc/rotate_wishlist_link", method: "POST", body: body)
        let viewer = try await client.authUser()
        return try await fetchStack(id: stackID, viewerID: viewer.id)
    }

    func deleteStack(id: UUID) async throws {
        _ = try await client.restData(
            "stacks",
            query: [URLQueryItem(name: "id", value: "eq.\(id.uuidString)")],
            method: "DELETE"
        )
    }

    func addItem(_ item: StackItem, to stackID: UUID) async throws -> Stack {
        let prepared = try await preparedItem(item, stackID: stackID, uploadsOriginal: true, uploadsRemoved: true)
        let body = try JSONEncoder().encode(prepared)
        let _: [ItemRow] = try await decodeRest(
            "stack_items",
            method: "POST",
            body: body,
            preferRepresentation: true
        )
        let viewer = try await client.authUser()
        return try await fetchStack(id: stackID, viewerID: viewer.id)
    }

    func updateItem(_ item: StackItem, in stackID: UUID) async throws -> Stack {
        let prepared = try await preparedItem(
            item,
            stackID: stackID,
            uploadsOriginal: item.originalImageURL?.isFileURL == true,
            uploadsRemoved: item.removedBackgroundImageURL?.isFileURL == true
        )
        let body = try JSONEncoder().encode(prepared)
        _ = try await client.restData(
            "stack_items",
            query: [URLQueryItem(name: "id", value: "eq.\(item.id.uuidString)")],
            method: "PATCH",
            body: body
        )
        let viewer = try await client.authUser()
        return try await fetchStack(id: stackID, viewerID: viewer.id)
    }

    func removeItem(id: UUID, from stackID: UUID) async throws -> Stack {
        _ = try await client.restData(
            "stack_items",
            query: [URLQueryItem(name: "id", value: "eq.\(id.uuidString)")],
            method: "DELETE"
        )
        let viewer = try await client.authUser()
        return try await fetchStack(id: stackID, viewerID: viewer.id)
    }

    func toggleBookmark(stackID: UUID, userID: UUID) async throws -> Stack {
        let existing: [PinRow] = try await client.rest(
            "stack_pins",
            query: [
                URLQueryItem(name: "stack_id", value: "eq.\(stackID.uuidString)"),
                URLQueryItem(name: "user_id", value: "eq.\(userID.uuidString)"),
                URLQueryItem(name: "select", value: "stack_id")
            ]
        )
        if existing.isEmpty {
            let body = try JSONEncoder().encode(PinWrite(stackID: stackID, userID: userID))
            _ = try await client.restData("stack_pins", method: "POST", body: body)
        } else {
            _ = try await client.restData(
                "stack_pins",
                query: [
                    URLQueryItem(name: "stack_id", value: "eq.\(stackID.uuidString)"),
                    URLQueryItem(name: "user_id", value: "eq.\(userID.uuidString)")
                ],
                method: "DELETE"
            )
        }
        return try await fetchStack(id: stackID, viewerID: userID)
    }

    func toggleFollow(authorID: UUID, userID: UUID) async throws -> [Stack] {
        let existing: [FollowRow] = try await client.rest(
            "follows",
            query: [
                URLQueryItem(name: "follower_id", value: "eq.\(userID.uuidString)"),
                URLQueryItem(name: "followed_user_id", value: "eq.\(authorID.uuidString)"),
                URLQueryItem(name: "select", value: "follower_id")
            ]
        )
        if existing.isEmpty {
            let body = try JSONEncoder().encode(FollowWrite(followerID: userID, followedUserID: authorID))
            _ = try await client.restData("follows", method: "POST", body: body)
        } else {
            _ = try await client.restData(
                "follows",
                query: [
                    URLQueryItem(name: "follower_id", value: "eq.\(userID.uuidString)"),
                    URLQueryItem(name: "followed_user_id", value: "eq.\(authorID.uuidString)")
                ],
                method: "DELETE"
            )
        }
        return try await fetchDiscoverStacks(query: nil)
    }

    private func fetchStack(id: UUID, viewerID: UUID) async throws -> Stack {
        if CuratedStackCatalog.isCuratedStack(id) {
            let curated = try await CuratedStackCatalog.fetchStacks()
            guard let stack = curated.first(where: { $0.id == id }) else {
                throw AppError.notFound
            }
            return stack
        }
        let rows: [StackRow] = try await client.rest(
            "stacks",
            query: [
                URLQueryItem(name: "id", value: "eq.\(id.uuidString)"),
                URLQueryItem(name: "select", value: "*")
            ]
        )
        guard let stack = try await compose(rows: rows, viewerID: viewerID).first else {
            if let curated = (try? await CuratedStackCatalog.fetchStacks())?.first(where: { $0.id == id }) {
                return curated
            }
            throw AppError.notFound
        }
        return stack
    }

    private func compose(rows: [StackRow], viewerID: UUID) async throws -> [Stack] {
        guard !rows.isEmpty else { return [] }
        let stackIDs = rows.map(\.id)
        let ownerIDs = Array(Set(rows.map(\.ownerID)))
        let stackList = stackIDs.map(\.uuidString).joined(separator: ",")

        let collaboratorRows: [StackCollaboratorRow] = try await client.rest(
            "stack_collaborators",
            query: [
                URLQueryItem(name: "stack_id", value: "in.(\(stackList))"),
                URLQueryItem(name: "accepted_at", value: "not.is.null"),
                URLQueryItem(name: "select", value: "stack_id,user_id,permission,accepted_at,created_at")
            ]
        )
        let profileIDs = Array(Set(ownerIDs + collaboratorRows.map(\.userID)))
        let profileList = profileIDs.map(\.uuidString).joined(separator: ",")
        var profiles: [ProfileRow] = try await client.rest(
            "profiles",
            query: [
                URLQueryItem(name: "id", value: "in.(\(profileList))"),
                URLQueryItem(name: "select", value: "*")
            ]
        )
        // Row security only exposes Discover and Collab profiles directly.
        // Every profile is public at stacks.spot/username, so fetch the
        // remaining authors' public fields instead of showing a placeholder.
        let missingProfileIDs = Set(profileIDs).subtracting(profiles.map(\.id))
        if !missingProfileIDs.isEmpty {
            let body = try JSONEncoder().encode(["target_ids": missingProfileIDs.map(\.uuidString)])
            let data = try await client.restData("rpc/public_profiles", method: "POST", body: body)
            profiles += (try? client.decoder.decode([ProfileRow].self, from: data)) ?? []
        }
        let items: [ItemRow] = try await client.rest(
            "stack_items",
            query: [
                URLQueryItem(name: "stack_id", value: "in.(\(stackList))"),
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "order", value: "created_at.asc")
            ]
        )
        let pins: [PinRow] = try await client.rest(
            "stack_pins",
            query: [
                URLQueryItem(name: "user_id", value: "eq.\(viewerID.uuidString)"),
                URLQueryItem(name: "stack_id", value: "in.(\(stackList))"),
                URLQueryItem(name: "select", value: "stack_id")
            ]
        )
        let follows: [FollowRow] = try await client.rest(
            "follows",
            query: [
                URLQueryItem(name: "follower_id", value: "eq.\(viewerID.uuidString)"),
                URLQueryItem(name: "select", value: "followed_user_id")
            ]
        )

        let profileByID = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0.profile(using: client.configuration)) })
        let itemsByStack = Dictionary(grouping: items, by: \.stackID)
        let collaboratorsByStack = Dictionary(grouping: collaboratorRows, by: \.stackID)
        let pinnedStackIDs = Set(pins.map(\.stackID))
        let followedIDs = Set(follows.compactMap(\.followedUserID))

        var output: [Stack] = []
        for row in rows {
            let author = profileByID[row.ownerID] ?? UserProfile(
                id: row.ownerID,
                displayName: "Stacks member",
                username: "stacker",
                avatarURL: nil,
                bio: "",
                linkInBioURL: nil,
                isFollowing: followedIDs.contains(row.ownerID)
            )
            var mappedItems = await mapItems(itemsByStack[row.id] ?? [], stackID: row.id)
            if row.wishlistMode && row.ownerID != viewerID {
                struct ClaimState: Decodable {
                    let itemID: UUID
                    let status: GiftClaimStatus?
                    enum CodingKeys: String, CodingKey { case itemID = "item_id", status }
                }
                struct Request: Encodable {
                    let targetStackID: UUID
                    let linkToken: UUID?
                    enum CodingKeys: String, CodingKey { case targetStackID = "target_stack_id", linkToken = "link_token" }
                }
                if let request = try? JSONEncoder().encode(Request(targetStackID: row.id, linkToken: nil)),
                   let data = try? await client.restData("rpc/get_wishlist_claim_states", method: "POST", body: request),
                   let states = try? JSONDecoder().decode([ClaimState].self, from: data) {
                    let byItem = Dictionary(uniqueKeysWithValues: states.map { ($0.itemID, $0.status) })
                    for index in mappedItems.indices { mappedItems[index].claimStatus = byItem[mappedItems[index].id] ?? nil }
                }
            }
            let collaborators = (collaboratorsByStack[row.id] ?? []).compactMap { collaborator -> Collaborator? in
                guard let profile = profileByID[collaborator.userID] else { return nil }
                return Collaborator(
                    id: collaborator.userID,
                    user: profile,
                    permission: collaborator.permission == "viewer" ? .view : .edit,
                    invitedAt: collaborator.acceptedAt ?? collaborator.createdAt
                )
            }
            output.append(Stack(
                id: row.id,
                ownerID: row.ownerID,
                author: author,
                title: row.title,
                visibility: StackVisibility(databaseValue: row.visibility),
                wishlistMode: row.wishlistMode,
                collaborationEnabled: row.collaborationEnabled,
                collaborators: collaborators,
                items: mappedItems,
                publicLinkToken: row.publicLinkToken,
                createdAt: row.createdAt,
                updatedAt: row.updatedAt,
                isBookmarked: pinnedStackIDs.contains(row.id),
                isFollowingAuthor: followedIDs.contains(row.ownerID)
            ))
        }
        return output
    }

    private func mapItems(_ rows: [ItemRow], stackID: UUID, linkToken: UUID? = nil) async -> [StackItem] {
        await withTaskGroup(of: (Int, StackItem).self) { group in
            for (index, row) in rows.enumerated() {
                group.addTask {
                    let originalURL: URL?
                    if let path = row.originalImagePath {
                        originalURL = await self.client.signedMediaURL(path: path, stackID: stackID, linkToken: linkToken)
                    } else {
                        originalURL = nil
                    }
                    let removedURL: URL?
                    if let path = row.removedBackgroundImagePath {
                        removedURL = await self.client.signedMediaURL(path: path, stackID: stackID, linkToken: linkToken)
                    } else {
                        removedURL = nil
                    }
                    return (index, row.stackItem(originalImageURL: originalURL, removedBackgroundImageURL: removedURL))
                }
            }
            var indexedItems: [(Int, StackItem)] = []
            for await result in group { indexedItems.append(result) }
            return indexedItems.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    private func preparedItem(
        _ item: StackItem,
        stackID: UUID,
        uploadsOriginal: Bool,
        uploadsRemoved: Bool
    ) async throws -> ItemWrite {
        let user = try await client.authUser()
        // Storage policies compare the first folder with auth.uid(), which is lowercase.
        let prefix = "\(user.id.uuidString.lowercased())/\(stackID.uuidString)/\(item.id.uuidString)"
        var originalPath: String?
        var removedPath: String?

        if uploadsOriginal, let imageURL = item.originalImageURL {
            let data = try await mediaData(from: imageURL)
            originalPath = "\(prefix)/original.jpg"
            try await client.uploadMedia(data, path: originalPath!, contentType: "image/jpeg")
        }
        if uploadsRemoved, let imageURL = item.removedBackgroundImageURL {
            let data = try await mediaData(from: imageURL)
            removedPath = "\(prefix)/removed.png"
            try await client.uploadMedia(data, path: removedPath!, contentType: "image/png")
        }

        return ItemWrite(
            id: item.id,
            stackID: stackID,
            title: item.title.trimmingCharacters(in: .whitespacesAndNewlines),
            brand: item.brand.trimmingCharacters(in: .whitespacesAndNewlines),
            description: item.shortDescription.trimmingCharacters(in: .whitespacesAndNewlines),
            price: item.price,
            currencyCode: item.currencyCode.uppercased(),
            sourceURL: item.sourceURL.absoluteString,
            buyURL: item.buyURL.absoluteString,
            affiliateURL: item.affiliateURL?.absoluteString,
            originalImagePath: originalPath,
            removedBackgroundImagePath: removedPath,
            removalStatus: item.removalStatus.rawValue,
            placementX: item.placement.xRatio,
            placementY: item.placement.yRatio,
            placementScale: item.placement.scale,
            rotationDegrees: item.placement.rotationDegrees,
            hasCustomPlacement: item.hasCustomPlacement ?? false,
            sourceType: item.addSource.databaseValue
        )
    }

    private func mediaData(from url: URL) async throws -> Data {
        if url.isFileURL { return try Data(contentsOf: url) }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw AppError.unavailable("The product image is no longer available.")
        }
        return data
    }

    private func decodeRest<T: Decodable>(
        _ path: String,
        method: String,
        body: Data,
        preferRepresentation: Bool
    ) async throws -> T {
        let data = try await client.restData(path, method: method, body: body, preferRepresentation: preferRepresentation)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            guard let date = ISO8601DateFormatter.stacks.date(from: value) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date")
            }
            return date
        }
        return try decoder.decode(T.self, from: data)
    }
}

struct SupabaseProfileRepository: ProfileRepository {
    private let client: SupabaseClient

    init(configuration: SupabaseConfiguration) {
        client = SupabaseClient(configuration: configuration)
    }

    func currentProfile(for session: AuthSession) async throws -> UserProfile {
        guard let profile = try await client.profileRow(id: session.userID) else { throw AppError.notFound }
        return profile.profile(using: client.configuration)
    }

    func enableProfileSharing() async throws {
        _ = try await client.restData("rpc/enable_profile_sharing", method: "POST", body: Data("{}".utf8))
    }

    func publicProfile(username: String) async throws -> UserProfile? {
        let body = try JSONEncoder().encode(["target_username": username])
        let data = try await client.restData("rpc/public_profile_by_username", method: "POST", body: body)
        return try client.decoder.decode([ProfileRow].self, from: data).first?.profile(using: client.configuration)
    }

    func disableProfileSharing() async throws {
        let user = try await client.authUser()
        _ = try await client.restData(
            "profiles",
            query: [URLQueryItem(name: "id", value: "eq.\(user.id.uuidString)")],
            method: "PATCH",
            body: Data("{\"profile_share_enabled\":false}".utf8)
        )
    }

    func updateProfile(_ profile: UserProfile, avatarData: Data?) async throws -> UserProfile {
        let avatarPath: String?
        if let avatarData {
            avatarPath = try await client.uploadProfileAvatar(avatarData, ownerID: profile.id)
        } else {
            avatarPath = nil
        }
        let body = try JSONEncoder().encode(ProfileUpdatePayload(
            displayName: profile.displayName,
            username: profile.username,
            bio: profile.bio,
            avatarPath: avatarPath
        ))
        let data = try await client.restData(
            "profiles",
            query: [URLQueryItem(name: "id", value: "eq.\(profile.id.uuidString)")],
            method: "PATCH",
            body: body,
            preferRepresentation: true
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            guard let date = ISO8601DateFormatter.stacks.date(from: value) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date")
            }
            return date
        }
        let rows = try decoder.decode([ProfileRow].self, from: data)
        guard let updated = rows.first else { throw AppError.notFound }
        return updated.profile(using: client.configuration)
    }

    func suggestedCreators() async throws -> [UserProfile] {
        let user = try await client.authUser()
        let profiles: [ProfileRow] = try await client.rest(
            "profiles",
            query: [
                URLQueryItem(name: "discovery_enabled", value: "eq.true"),
                URLQueryItem(name: "id", value: "neq.\(user.id.uuidString)"),
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "limit", value: "12")
            ]
        )
        let follows: [FollowRow] = try await client.rest(
            "follows",
            query: [
                URLQueryItem(name: "follower_id", value: "eq.\(user.id.uuidString)"),
                URLQueryItem(name: "select", value: "followed_user_id")
            ]
        )
        let followed = Set(follows.map(\.followedUserID))
        return profiles.map { row in
            var profile = row.profile(using: client.configuration)
            profile.isFollowing = followed.contains(row.id)
            return profile
        }
    }

    func searchCreators(query: String) async throws -> [UserProfile] {
        let user = try await client.authUser()
        let cleanQuery = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .filter { $0.isLetter || $0.isNumber || $0 == " " || $0 == "_" || $0 == "-" }
        guard !cleanQuery.isEmpty else { return try await suggestedCreators() }

        let profiles: [ProfileRow] = try await client.rest(
            "profiles",
            query: [
                URLQueryItem(name: "discovery_enabled", value: "eq.true"),
                URLQueryItem(name: "id", value: "neq.\(user.id.uuidString)"),
                URLQueryItem(name: "or", value: "(display_name.ilike.*\(cleanQuery)*,username.ilike.*\(cleanQuery)*)"),
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "limit", value: "20")
            ]
        )
        let follows: [FollowRow] = try await client.rest(
            "follows",
            query: [
                URLQueryItem(name: "follower_id", value: "eq.\(user.id.uuidString)"),
                URLQueryItem(name: "select", value: "followed_user_id")
            ]
        )
        let followed = Set(follows.compactMap(\.followedUserID))
        return profiles.map { row in
            var profile = row.profile(using: client.configuration)
            profile.isFollowing = followed.contains(row.id)
            return profile
        }
    }
}

struct EdgeFunctionProductSearchService: ProductSearchService {
    private let configuration: ProductSearchEdgeFunctionConfiguration?
    private let fallback = MockProductSearchService()

    init(configuration: ProductSearchEdgeFunctionConfiguration? = .fromAppBundle()) {
        self.configuration = configuration
    }

    func searchProducts(query: String) async throws -> [ProductSearchResult] {
        guard let configuration else {
            return try await fallback.searchProducts(query: query)
        }

        var request = URLRequest(url: configuration.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let accessToken = await SupabaseSessionStore.shared.load()?.accessToken ?? configuration.anonKey
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONEncoder().encode(ProductSearchRequest(query: query))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.unavailable("Product search did not return a valid response.")
        }

        let decoded = try JSONDecoder().decode(ProductSearchEdgeFunctionResponse.self, from: data)
        guard (200...299).contains(httpResponse.statusCode) else {
            throw AppError.unavailable(decoded.error ?? "Product search is temporarily unavailable.")
        }

        return decoded.results.map { result in
            ProductSearchResult(
                id: UUID(),
                title: result.title,
                brand: result.brand,
                price: result.price,
                currencyCode: result.currencyCode,
                sourceURL: result.sourceURL,
                imageURL: result.imageURL,
                shortDescription: result.shortDescription,
                demoGlyph: nil
            )
        }
    }

    func previewProductLink(_ url: URL) async throws -> ProductLinkPreview {
        guard url.scheme?.hasPrefix("http") == true else { throw AppError.invalidURL }

        if let configuration = ProductLinkParserConfiguration.fromAppBundle() {
            do {
                return try await configuration.previewProductLink(for: url)
            } catch {
                // Merchant pages sometimes reject server requests. The on-device
                // extractor is deliberately retained as a best-effort fallback,
                // not as the primary production scraper.
                let fallback = await ProductPageImageExtractor.previewProductLink(for: url)
                if fallback.imageURL != nil || fallback.title != "Linked Find" {
                    return fallback
                }
                throw error
            }
        }

        return await ProductPageImageExtractor.previewProductLink(for: url)
    }

    func productFromPastedLink(_ url: URL, stackID: UUID, placement: StickerPlacement) async throws -> StackItem {
        guard url.scheme?.hasPrefix("http") == true else {
            throw AppError.invalidURL
        }

        let preview = try await previewProductLink(url)

        return StackItem(
            id: UUID(),
            stackID: stackID,
            title: preview.title,
            brand: preview.brand,
            shortDescription: preview.shortDescription,
            price: preview.price ?? 0,
            currencyCode: preview.currencyCode,
            sourceURL: url,
            buyURL: url,
            affiliateURL: nil,
            originalImageURL: preview.imageURL,
            removedBackgroundImageURL: nil,
            removalStatus: .processing,
            placement: placement,
            addSource: .pastedLink,
            claimStatus: nil,
            demoGlyph: nil
        )
    }
}

private struct SupabaseAuthResponse: Decodable {
    let accessToken: String?
    let refreshToken: String?
    let expiresIn: Int?
    let user: SupabaseAuthUser?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case user
    }
}

private struct SupabaseAuthUser: Decodable {
    let id: UUID
    let email: String?
    let userMetadata: UserMetadata?

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case userMetadata = "user_metadata"
    }

    var displayName: String {
        userMetadata?.fullName ?? userMetadata?.name ?? email?.split(separator: "@").first.map(String.init) ?? "Stacks member"
    }
}

private struct UserMetadata: Decodable {
    let fullName: String?
    let name: String?

    enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
        case name
    }
}

private struct SupabaseOTPRequest: Encodable {
    let email: String
    let createUser: Bool
    let codeChallenge: String
    let codeChallengeMethod: String

    enum CodingKeys: String, CodingKey {
        case email
        case createUser = "create_user"
        case codeChallenge = "code_challenge"
        case codeChallengeMethod = "code_challenge_method"
    }
}

private enum PKCE {
    static func verifier() -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return String((0..<64).compactMap { _ in alphabet.randomElement() })
    }

    static func challenge(for verifier: String) -> String {
        let digest = CryptoKit.SHA256.hash(data: Data(verifier.utf8))
        return Data(digest)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private struct SupabaseErrorResponse: Decodable {
    let message: String?
    let error: String?
    let errorDescription: String?
    /// PostgREST's Postgres error code, such as 42501 for a policy failure.
    /// GoTrue sends a numeric HTTP code here instead, which is ignored.
    let code: String?

    enum CodingKeys: String, CodingKey {
        case message
        case msg
        case error
        case errorDescription = "error_description"
        case code
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        message = try container.decodeIfPresent(String.self, forKey: .message)
            ?? container.decodeIfPresent(String.self, forKey: .msg)
        error = try? container.decodeIfPresent(String.self, forKey: .error)
        errorDescription = try container.decodeIfPresent(String.self, forKey: .errorDescription)
        code = try? container.decodeIfPresent(String.self, forKey: .code)
    }

    var bestMessage: String? { message ?? errorDescription ?? error }

    /// Database and gateway errors ("new row violates row-level security
    /// policy…") were shown to people word for word. Keep messages that are
    /// already meant for people, such as sign-in errors, and translate the rest.
    static func userFacingMessage(_ response: Self?, statusCode: Int) -> String {
        let raw = response?.bestMessage ?? ""
        let lowered = raw.lowercased()
        if lowered.contains("username") && (lowered.contains("duplicate") || lowered.contains("reserved")) {
            return "That @handle is taken. Try another."
        }
        if statusCode == 401 || lowered.contains("jwt expired") {
            return "Your session expired. Please sign in again."
        }
        if statusCode >= 500 {
            return "Stacks is having trouble right now. Please try again in a moment."
        }
        if response?.code == "42501" || lowered.contains("row-level security") || lowered.contains("permission denied") {
            return "You don't have access to do that. If it keeps happening, sign out and back in."
        }
        if response?.code?.count == 5 || lowered.contains("violates") || lowered.contains("constraint") || raw.isEmpty {
            return "Something didn't save. Please try again."
        }
        return raw
    }
}

private struct ProfileRow: Decodable {
    let id: UUID
    let displayName: String
    let username: String
    let avatarPath: String?
    let bio: String
    let linkInBioURL: String?
    let onboardingCompletedAt: Date?
    let profileShareEnabled: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case username
        case avatarPath = "avatar_path"
        case bio
        case linkInBioURL = "link_in_bio_url"
        case onboardingCompletedAt = "onboarding_completed_at"
        case profileShareEnabled = "profile_share_enabled"
    }

    func profile(using configuration: SupabaseConfiguration) -> UserProfile {
        UserProfile(
            id: id,
            displayName: displayName,
            username: username,
            avatarURL: avatarPath.flatMap { Self.publicAvatarURL(path: $0, configuration: configuration) },
            bio: bio,
            linkInBioURL: linkInBioURL.flatMap(URL.init(string:)),
            isFollowing: false,
            profileShareEnabled: profileShareEnabled
        )
    }

    private static func publicAvatarURL(path: String, configuration: SupabaseConfiguration) -> URL? {
        let encodedPath = path.split(separator: "/").map {
            String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0)
        }.joined(separator: "/")
        return configuration.projectURL.appending(path: "storage/v1/object/public/profile-media/\(encodedPath)")
    }
}

private struct ProfileUpdatePayload: Encodable {
    let displayName: String
    let username: String
    let bio: String
    let avatarPath: String?

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case username
        case bio
        case avatarPath = "avatar_path"
    }
}

private struct OwnedStackDestinationRow: Decodable {
    let id: UUID
    let title: String
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, title
        case updatedAt = "updated_at"
    }
}

private struct StackRow: Decodable {
    let id: UUID
    let ownerID: UUID
    let title: String
    let visibility: String
    let wishlistMode: Bool
    let collaborationEnabled: Bool
    let publicLinkToken: UUID?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case ownerID = "owner_id"
        case title
        case visibility
        case wishlistMode = "wishlist_mode"
        case collaborationEnabled = "collaboration_enabled"
        case publicLinkToken = "public_link_token"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

private struct StackCollaboratorAccessRow: Decodable {
    let stackID: UUID

    enum CodingKeys: String, CodingKey {
        case stackID = "stack_id"
    }
}

private struct StackCollaboratorRow: Decodable {
    let stackID: UUID
    let userID: UUID
    let permission: String
    let acceptedAt: Date?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case stackID = "stack_id"
        case userID = "user_id"
        case permission
        case acceptedAt = "accepted_at"
        case createdAt = "created_at"
    }
}

private struct ItemRow: Decodable {
    let id: UUID
    let stackID: UUID
    let title: String
    let brand: String
    let description: String
    let price: Decimal?
    let currencyCode: String?
    let sourceURL: String?
    let buyURL: String?
    let affiliateURL: String?
    let originalImagePath: String?
    let removedBackgroundImagePath: String?
    let removalStatus: String
    let placementX: Double
    let placementY: Double
    let placementScale: Double
    let rotationDegrees: Double
    let hasCustomPlacement: Bool
    let sourceType: String
    let claimStatus: String?

    enum CodingKeys: String, CodingKey {
        case id
        case stackID = "stack_id"
        case title
        case brand
        case description
        case price
        case currencyCode = "currency_code"
        case sourceURL = "source_url"
        case buyURL = "buy_url"
        case affiliateURL = "affiliate_url"
        case originalImagePath = "original_image_path"
        case removedBackgroundImagePath = "removed_background_image_path"
        case removalStatus = "removal_status"
        case placementX = "placement_x"
        case placementY = "placement_y"
        case placementScale = "placement_scale"
        case rotationDegrees = "rotation_degrees"
        case hasCustomPlacement = "has_custom_placement"
        case sourceType = "source_type"
        case claimStatus = "claim_status"
    }

    func stackItem(originalImageURL: URL?, removedBackgroundImageURL: URL?) -> StackItem {
        StackItem(
            id: id,
            stackID: stackID,
            title: title,
            brand: brand,
            shortDescription: description,
            price: price ?? 0,
            currencyCode: currencyCode ?? "USD",
            sourceURL: sourceURL.flatMap(URL.init(string:)) ?? Self.unidentifiedURL(id: id),
            buyURL: buyURL.flatMap(URL.init(string:)) ?? Self.unidentifiedURL(id: id),
            affiliateURL: affiliateURL.flatMap(URL.init(string:)),
            originalImageURL: originalImageURL,
            removedBackgroundImageURL: removedBackgroundImageURL,
            removalStatus: BackgroundRemovalStatus(rawValue: removalStatus) ?? .failed,
            placement: StickerPlacement(
                xRatio: placementX,
                yRatio: placementY,
                scale: placementScale,
                rotationDegrees: rotationDegrees
            ),
            hasCustomPlacement: hasCustomPlacement,
            addSource: AddItemSource(databaseValue: sourceType),
            claimStatus: claimStatus.flatMap(GiftClaimStatus.init(rawValue:)),
            demoGlyph: nil
        )
    }

    private static func unidentifiedURL(id: UUID) -> URL {
        URL(string: "https://stacks.app/find/\(id.uuidString)")!
    }
}

private struct PinRow: Decodable {
    let stackID: UUID

    enum CodingKeys: String, CodingKey {
        case stackID = "stack_id"
    }
}

private struct FollowRow: Decodable {
    let followedUserID: UUID?
    let followerID: UUID?

    enum CodingKeys: String, CodingKey {
        case followedUserID = "followed_user_id"
        case followerID = "follower_id"
    }
}

private struct StackWrite: Encodable {
    let ownerID: UUID
    let title: String
    let visibility: String
    let wishlistMode: Bool
    let collaborationEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case ownerID = "owner_id"
        case title
        case visibility
        case wishlistMode = "wishlist_mode"
        case collaborationEnabled = "collaboration_enabled"
    }
}

private struct ItemWrite: Encodable {
    let id: UUID
    let stackID: UUID
    let title: String
    let brand: String
    let description: String
    let price: Decimal
    let currencyCode: String
    let sourceURL: String
    let buyURL: String
    let affiliateURL: String?
    let originalImagePath: String?
    let removedBackgroundImagePath: String?
    let removalStatus: String
    let placementX: Double
    let placementY: Double
    let placementScale: Double
    let rotationDegrees: Double
    let hasCustomPlacement: Bool
    let sourceType: String

    enum CodingKeys: String, CodingKey {
        case id
        case stackID = "stack_id"
        case title
        case brand
        case description
        case price
        case currencyCode = "currency_code"
        case sourceURL = "source_url"
        case buyURL = "buy_url"
        case affiliateURL = "affiliate_url"
        case originalImagePath = "original_image_path"
        case removedBackgroundImagePath = "removed_background_image_path"
        case removalStatus = "removal_status"
        case placementX = "placement_x"
        case placementY = "placement_y"
        case placementScale = "placement_scale"
        case rotationDegrees = "rotation_degrees"
        case hasCustomPlacement = "has_custom_placement"
        case sourceType = "source_type"
    }
}

private struct PinWrite: Encodable {
    let stackID: UUID
    let userID: UUID

    enum CodingKeys: String, CodingKey {
        case stackID = "stack_id"
        case userID = "user_id"
    }
}

private struct FollowWrite: Encodable {
    let followerID: UUID
    let followedUserID: UUID

    enum CodingKeys: String, CodingKey {
        case followerID = "follower_id"
        case followedUserID = "followed_user_id"
    }
}

private struct AnyEncodable: Encodable {
    private let encodeValue: (Encoder) throws -> Void

    init(_ value: some Encodable) {
        encodeValue = value.encode
    }

    func encode(to encoder: Encoder) throws {
        try encodeValue(encoder)
    }
}

private extension StackVisibility {
    init(databaseValue: String) {
        switch databaseValue {
        case "private": self = .private
        case "link_only": self = .publicLink
        case "public": self = .publicDiscover
        default: self = .private
        }
    }

    var databaseValue: String {
        switch self {
        case .private, .inviteOnly: "private"
        case .publicLink: "link_only"
        case .publicDiscover: "public"
        }
    }
}

private extension AddItemSource {
    var databaseValue: String {
        switch self {
        case .search: "search"
        case .pastedLink: "pasted_link"
        case .camera: "camera"
        case .photoLibrary: "photo_library"
        case .manualPhoto: "manual_photo"
        }
    }

    init(databaseValue: String) {
        switch databaseValue {
        case "search": self = .search
        case "pasted_link", "share_extension": self = .pastedLink
        case "camera": self = .camera
        case "photo_library": self = .photoLibrary
        default: self = .manualPhoto
        }
    }
}

private extension ISO8601DateFormatter {
    nonisolated(unsafe) static let stacks: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

/// Public product metadata is fetched by the Supabase Edge Function so the app
/// does not need to scrape arbitrary merchant HTML itself. The endpoint is
/// intentionally configurable so development previews keep working offline.
struct ProductLinkParserConfiguration: Sendable {
    let endpoint: URL
    let anonKey: String

    static func fromAppBundle() -> Self? {
        guard let anonKey = configuredString(for: "STACKS_SUPABASE_ANON_KEY") else {
            return nil
        }

        if let explicitEndpoint = configuredString(for: "STACKS_PRODUCT_LINK_PARSER_URL"),
           let endpoint = URL(string: explicitEndpoint), endpoint.scheme == "https" {
            return Self(endpoint: endpoint, anonKey: anonKey)
        }

        guard let projectURLString = configuredString(for: "STACKS_SUPABASE_URL"),
              let projectURL = URL(string: projectURLString), projectURL.scheme == "https" else {
            return nil
        }
        return Self(
            endpoint: projectURL.appending(path: "functions/v1/link-parser"),
            anonKey: anonKey
        )
    }

    func previewProductLink(for url: URL) async throws -> ProductLinkPreview {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 18
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let accessToken = await SupabaseSessionStore.shared.load()?.accessToken ?? anonKey
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONEncoder().encode(ProductLinkParserRequest(url: url.absoluteString))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.unavailable("Product import did not return a valid response.")
        }

        let decoded = try JSONDecoder().decode(ProductLinkParserResponse.self, from: data)
        guard (200...299).contains(httpResponse.statusCode) else {
            throw AppError.unavailable(decoded.error ?? "We couldn't read that product link.")
        }
        var preview = decoded.item.productLinkPreview
        preview.importWarning = decoded.warning
        preview.importWarningCode = decoded.warningCode
        let shouldRepairTitle = ProductImportedCopy.isGenericTitle(
            preview.title,
            brand: preview.brand,
            sourceURL: url
        )
        if decoded.warning != nil || preview.imageURL == nil || shouldRepairTitle {
            // Etsy, Depop, and other marketplaces commonly reject datacenter
            // requests while still providing rich metadata through Apple's
            // on-device link service. A backend fallback is not a completed
            // import; merge in the device result before returning it.
            let devicePreview = await ProductPageImageExtractor.previewProductLink(for: url)
            if let deviceImage = devicePreview.imageURL {
                preview.imageURL = deviceImage
            }
            if shouldRepairTitle
                || preview.title == ProductPageImageExtractor.fallbackTitle(for: url)
                || preview.title.count > 80 {
                preview.title = devicePreview.title
            }
            if preview.brand.isEmpty { preview.brand = devicePreview.brand }
            if preview.shortDescription.isEmpty { preview.shortDescription = devicePreview.shortDescription }
            if preview.price == nil { preview.price = devicePreview.price }
        }
        preview.title = ProductImportedCopy.conciseTitle(preview.title, brand: preview.brand)
        return preview
    }

    private static func configuredString(for key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.hasPrefix("$(") ? nil : trimmed
    }
}

private struct ProductLinkParserRequest: Encodable {
    let url: String
}

private struct ProductLinkParserResponse: Decodable {
    let item: ProductLinkParserItem
    let warning: String?
    let warningCode: String?
    let error: String?
}

private struct ProductLinkParserItem: Decodable {
    let title: String
    let brand: String
    let description: String
    let price: Decimal?
    let currencyCode: String
    let sourceURL: URL
    let buyURL: URL
    let imageURL: URL?

    var productLinkPreview: ProductLinkPreview {
        ProductLinkPreview(
            sourceURL: sourceURL,
            title: title,
            brand: brand,
            shortDescription: description,
            price: price,
            currencyCode: currencyCode,
            imageURL: imageURL
        )
    }
}

struct ProductSearchEdgeFunctionConfiguration: Sendable {
    let endpoint: URL
    let anonKey: String

    static func fromAppBundle() -> Self? {
        guard let endpointString = configuredString(for: "STACKS_PRODUCT_SEARCH_URL"),
              let endpoint = URL(string: endpointString),
              endpoint.scheme == "https",
              let anonKey = configuredString(for: "STACKS_SUPABASE_ANON_KEY") else {
            return nil
        }
        return Self(endpoint: endpoint, anonKey: anonKey)
    }

    private static func configuredString(for key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("$(") else { return nil }
        return trimmed
    }
}

private struct ProductSearchRequest: Encodable {
    let query: String
    let country = "us"
    let language = "en"
    let limit = 12
}

private struct ProductSearchEdgeFunctionResponse: Decodable {
    let results: [ProductSearchEdgeFunctionResult]
    let error: String?

    private enum CodingKeys: String, CodingKey {
        case results
        case error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        results = try container.decodeIfPresent([ProductSearchEdgeFunctionResult].self, forKey: .results) ?? []
        error = try container.decodeIfPresent(String.self, forKey: .error)
    }
}

private struct ProductSearchEdgeFunctionResult: Decodable {
    let title: String
    let brand: String
    let price: Decimal
    let currencyCode: String
    let sourceURL: URL
    let imageURL: URL?
    let shortDescription: String
}

struct EdgeFunctionBackgroundRemovalService: BackgroundRemovalService {
    func removeBackground(for item: StackItem) async throws -> URL? {
        throw AppError.configurationRequired("Replicate rembg edge function")
    }
}

struct EdgeFunctionAffiliateService: AffiliateService {
    private let client: SupabaseClient

    init(configuration: SupabaseConfiguration) {
        client = SupabaseClient(configuration: configuration)
    }

    func resolveLink(for url: URL, countryCode: String?) async throws -> AffiliateLinkResolution {
        struct Request: Encodable {
            let url: URL
            let countryCode: String?
        }
        struct Response: Decodable {
            let affiliateURL: URL
            let isCommissionable: Bool
        }
        let response: Response = try await client.function(
            "affiliate-link",
            body: Request(url: url, countryCode: countryCode)
        )
        return AffiliateLinkResolution(url: response.affiliateURL, isCommissionable: response.isCommissionable)
    }
}

struct EdgeFunctionClaimService: ClaimService {
    private let client: SupabaseClient

    init(configuration: SupabaseConfiguration) {
        client = SupabaseClient(configuration: configuration)
    }

    func myClaimStatus(for item: StackItem) async throws -> GiftClaimStatus? {
        struct OwnClaim: Decodable { let status: GiftClaimStatus }
        let user = try await client.authUser()
        let claims: [OwnClaim] = try await client.rest("gift_claims", query: [
            URLQueryItem(name: "item_id", value: "eq.\(item.id.uuidString)"),
            URLQueryItem(name: "claimer_id", value: "eq.\(user.id.uuidString)"),
            URLQueryItem(name: "status", value: "in.(claimed,purchased)"),
            URLQueryItem(name: "select", value: "status"),
            URLQueryItem(name: "limit", value: "1")
        ])
        return claims.first?.status
    }

    func claim(item: StackItem, in stack: Stack, claimerName: String) async throws -> GiftClaim {
        struct ClaimRequest: Encodable {
            let stackID: UUID
            let itemID: UUID
            let claimerName: String
            let linkToken: UUID?
        }
        struct ClaimResponse: Decodable {
            let claim: ClaimRow
        }
        struct ClaimRow: Decodable {
            let id: UUID
            let stackID: UUID
            let itemID: UUID
            let claimerName: String
            let privateMessage: String?
            let status: GiftClaimStatus
            let createdAt: Date

            enum CodingKeys: String, CodingKey {
                case id
                case stackID
                case itemID
                case claimerName
                case privateMessage
                case status
                case createdAt
            }
        }

        let response: ClaimResponse = try await client.function(
            "claim-gift",
            body: ClaimRequest(
                stackID: item.stackID,
                itemID: item.id,
                claimerName: claimerName,
                linkToken: stack.visibility == .publicLink ? stack.publicLinkToken : nil
            )
        )
        return GiftClaim(
            id: response.claim.id,
            itemID: response.claim.itemID,
            stackID: response.claim.stackID,
            claimerName: response.claim.claimerName,
            privateMessage: response.claim.privateMessage,
            status: response.claim.status,
            createdAt: response.claim.createdAt
        )
    }

    func updateStatus(
        for item: StackItem,
        in stack: Stack,
        status: GiftClaimStatus?
    ) async throws -> GiftClaimStatus? {
        struct StatusRequest: Encodable {
            let stackID: UUID
            let itemID: UUID
            let status: String?
        }
        struct StatusResponse: Decodable {
            let status: GiftClaimStatus?
        }
        let response: StatusResponse = try await client.function(
            "update-gift-claim",
            body: StatusRequest(stackID: stack.id, itemID: item.id, status: status?.rawValue)
        )
        return response.status
    }
}

struct SupabaseCollaborationService: CollaborationService {
    private let client: SupabaseClient

    init(configuration: SupabaseConfiguration) {
        client = SupabaseClient(configuration: configuration)
    }

    func createInvite(to stack: Stack, permission: CollaboratorPermission) async throws -> CollaborationInvite {
        struct InviteRequest: Encodable { let stackID: UUID; let permission: String }
        struct InviteResponse: Decodable {
            let invite: Invite
            struct Invite: Decodable {
                let id: UUID
                let stackID: UUID
                let token: UUID
                let permission: String
                let expiresAt: Date

                enum CodingKeys: String, CodingKey {
                    case id, token, permission
                    case stackID = "stackId"
                    case expiresAt = "expiresAt"
                }
            }
        }
        let databasePermission = permission == .view ? "viewer" : "editor"
        let response: InviteResponse = try await client.function(
            "create-collaboration-invite",
            body: InviteRequest(stackID: stack.id, permission: databasePermission)
        )
        return CollaborationInvite(
            id: response.invite.id,
            stackID: response.invite.stackID,
            token: response.invite.token,
            permission: response.invite.permission == "viewer" ? .view : .edit,
            expiresAt: response.invite.expiresAt
        )
    }

    func previewInvite(token: UUID) async throws -> CollaborationInvitePreview {
        struct PreviewRequest: Encodable { let token: UUID }
        struct PreviewResponse: Decodable {
            let stackID: UUID
            let stackTitle: String
            let permission: String
            let expiresAt: Date
            let ownerID: UUID
            let ownerName: String
            let ownerUsername: String
            let ownerAvatarPath: String?
        }
        let response: PreviewResponse = try await client.function(
            "preview-collaboration-invite",
            body: PreviewRequest(token: token)
        )
        let avatarURL = response.ownerAvatarPath.map { path in
            let encodedPath = path.split(separator: "/").map {
                String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0)
            }.joined(separator: "/")
            return client.configuration.projectURL.appending(path: "storage/v1/object/public/profile-media/\(encodedPath)")
        }
        return CollaborationInvitePreview(
            token: token,
            stackID: response.stackID,
            stackTitle: response.stackTitle,
            owner: UserProfile(
                id: response.ownerID,
                displayName: response.ownerName,
                username: response.ownerUsername,
                avatarURL: avatarURL,
                bio: "",
                linkInBioURL: nil,
                isFollowing: false
            ),
            permission: response.permission == "viewer" ? .view : .edit,
            expiresAt: response.expiresAt
        )
    }

    func acceptInvite(token: UUID) async throws -> UUID {
        struct AcceptRequest: Encodable { let token: UUID }
        struct AcceptResponse: Decodable { let accepted: Bool; let stackID: UUID }
        let response: AcceptResponse = try await client.function(
            "accept-collaboration-invite",
            body: AcceptRequest(token: token)
        )
        return response.stackID
    }

    func setCollaborationEnabled(stackID: UUID, enabled: Bool) async throws {
        struct CollaborationUpdate: Encodable {
            let collaborationEnabled: Bool
            enum CodingKeys: String, CodingKey { case collaborationEnabled = "collaboration_enabled" }
        }
        _ = try await client.restData(
            "stacks",
            query: [URLQueryItem(name: "id", value: "eq.\(stackID.uuidString)")],
            method: "PATCH",
            body: JSONEncoder().encode(CollaborationUpdate(collaborationEnabled: enabled))
        )
    }

    func removeCollaborator(stackID: UUID, userID: UUID) async throws {
        _ = try await client.restData(
            "stack_collaborators",
            query: [
                URLQueryItem(name: "stack_id", value: "eq.\(stackID.uuidString)"),
                URLQueryItem(name: "user_id", value: "eq.\(userID.uuidString)")
            ],
            method: "DELETE"
        )
    }

    func leaveStack(stackID: UUID) async throws {
        let user = try await client.authUser()
        try await removeCollaborator(stackID: stackID, userID: user.id)
    }
}

struct SupabaseStorageService: StorageService {
    func uploadImageData(_ data: Data, preferredName: String) async throws -> URL {
        guard !data.isEmpty else {
            throw AppError.missingRequiredField("Image")
        }

        // The product flow needs a file immediately so Vision can create the
        // cutout before the user chooses a destination Stack. The repository
        // uploads both the original and cutout to private Supabase Storage when
        // the item is saved, using the final owner/Stack/item path.
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("Stacks/ImportStaging", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let fileName = "\(preferredName.stacksStorageSlug)-\(UUID().uuidString).jpg"
        let url = directory.appendingPathComponent(fileName)
        try data.write(to: url, options: [.atomic])
        return url
    }
}

struct SupabaseRealtimeService: RealtimeService {
    func watchStack(id: UUID) async {}
    func stopWatchingStack(id: UUID) async {}
}

struct SupabaseSafetyService: SafetyService {
    private let client: SupabaseClient

    init(configuration: SupabaseConfiguration) {
        client = SupabaseClient(configuration: configuration)
    }

    func reportStack(id: UUID, reason: String) async throws {
        struct Report: Encodable {
            let reporterID: UUID
            let reportedStackID: UUID
            let reason: String
            enum CodingKeys: String, CodingKey {
                case reporterID = "reporter_id"
                case reportedStackID = "reported_stack_id"
                case reason
            }
        }
        let user = try await client.authUser()
        let data = try JSONEncoder().encode(Report(reporterID: user.id, reportedStackID: id, reason: reason))
        _ = try await client.restData("content_reports", method: "POST", body: data)
    }

    func reportProfile(id: UUID, reason: String) async throws {
        struct Report: Encodable {
            let reporterID: UUID
            let reportedProfileID: UUID
            let reason: String
            enum CodingKeys: String, CodingKey {
                case reporterID = "reporter_id"
                case reportedProfileID = "reported_profile_id"
                case reason
            }
        }
        let user = try await client.authUser()
        let data = try JSONEncoder().encode(Report(reporterID: user.id, reportedProfileID: id, reason: reason))
        _ = try await client.restData("content_reports", method: "POST", body: data)
    }

    func blockUser(id: UUID) async throws {
        struct Block: Encodable {
            let blockerID: UUID
            let blockedUserID: UUID
            enum CodingKeys: String, CodingKey {
                case blockerID = "blocker_id"
                case blockedUserID = "blocked_user_id"
            }
        }
        let user = try await client.authUser()
        guard user.id != id else { throw AppError.unavailable("You can't block your own account.") }
        let data = try JSONEncoder().encode(Block(blockerID: user.id, blockedUserID: id))
        _ = try await client.restData("user_blocks", method: "POST", body: data)
    }
}

private extension String {
    var stacksStorageSlug: String {
        let slug = lowercased()
            .unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? String($0) : "-" }
            .joined()
            .replacingOccurrences(of: "--", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return slug.isEmpty ? "product" : String(slug.prefix(48))
    }
}

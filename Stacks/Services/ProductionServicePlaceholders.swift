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
    private let service = "com.example.stacks.supabase"
    private let account = "current-session"

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
            return try await refresh(session: session).accessToken
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

    func sendMagicLink(email: String) async throws {
        let verifier = PKCE.verifier()
        let challenge = PKCE.challenge(for: verifier)
        await sessionStore.savePendingPKCEVerifier(verifier)
        let body = try encoder.encode(SupabaseOTPRequest(
            email: email,
            createUser: true,
            options: SupabaseOTPOptions(
                emailRedirectTo: configuration.redirectURL.absoluteString,
                codeChallenge: challenge,
                codeChallengeMethod: "s256"
            )
        ))
        _ = try await request(
            url: configuration.projectURL.appending(path: "auth/v1/otp"),
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
            url: configuration.projectURL.appending(path: "auth/v1/token?grant_type=pkce"),
            method: "POST",
            body: body,
            authenticated: false
        )
        return try await saveAuthResponse(decoder.decode(SupabaseAuthResponse.self, from: data))
    }

    func exchangeAppleIdentityToken(_ identityToken: String) async throws -> AuthSession {
        let body = try encoder.encode(["provider": "apple", "id_token": identityToken])
        let data = try await request(
            url: configuration.projectURL.appending(path: "auth/v1/token?grant_type=id_token"),
            method: "POST",
            body: body,
            authenticated: false
        )
        return try await saveAuthResponse(decoder.decode(SupabaseAuthResponse.self, from: data))
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
        guard !data.isEmpty else { throw AppError.missingRequiredField("Image") }
        let encodedPath = path.split(separator: "/").map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }.joined(separator: "/")
        var request = URLRequest(url: configuration.projectURL.appending(path: "storage/v1/object/stack-media/\(encodedPath)"))
        request.httpMethod = "POST"
        request.httpBody = data
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("true", forHTTPHeaderField: "x-upsert")
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(try await currentAccessToken())", forHTTPHeaderField: "Authorization")
        _ = try await perform(request, authenticated: false)
    }

    func signedMediaURL(path: String, stackID: UUID) async -> URL? {
        struct MediaRequest: Encodable { let stackID: UUID; let path: String }
        struct MediaResponse: Decodable { let signedURL: URL }
        guard let response: MediaResponse = try? await function(
            "media-url",
            body: MediaRequest(stackID: stackID, path: path)
        ) else {
            return nil
        }
        return response.signedURL
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
            let message = (try? decoder.decode(SupabaseErrorResponse.self, from: data))?.bestMessage
            throw AppError.unavailable(message ?? "Supabase request failed (\(httpResponse.statusCode)).")
        }
        return data
    }

    private var encoder: JSONEncoder {
        JSONEncoder()
    }

    private var decoder: JSONDecoder {
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

    func signInWithEmail(_ email: String) async throws -> EmailAuthenticationResult {
        guard email.contains("@"), email.contains(".") else { throw AppError.invalidEmail }
        try await client.sendMagicLink(email: email)
        return .linkSent
    }

    func handleAuthCallback(_ url: URL) async throws -> AuthSession? {
        guard url.scheme?.lowercased() == "stacks" else { return nil }
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

struct SupabaseStackRepository: StackRepository {
    private let client: SupabaseClient

    init(configuration: SupabaseConfiguration) {
        client = SupabaseClient(configuration: configuration)
    }

    func fetchMyStacks(for userID: UUID) async throws -> [Stack] {
        let rows: [StackRow] = try await client.rest(
            "stacks",
            query: [
                URLQueryItem(name: "owner_id", value: "eq.\(userID.uuidString)"),
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "order", value: "updated_at.desc")
            ]
        )
        return try await compose(rows: rows, viewerID: userID)
    }

    func fetchDiscoverStacks(query: String?) async throws -> [Stack] {
        let viewer = try await client.authUser()
        let rows: [StackRow] = try await client.rest(
            "stacks",
            query: [
                URLQueryItem(name: "visibility", value: "eq.public"),
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "order", value: "updated_at.desc")
            ]
        )
        let stacks = try await compose(rows: rows, viewerID: viewer.id)
        guard let query, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return stacks }
        return stacks.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.author.displayName.localizedCaseInsensitiveContains(query)
                || $0.author.username.localizedCaseInsensitiveContains(query)
        }
    }

    func createStack(title: String, wishlistMode: Bool, owner: UserProfile) async throws -> Stack {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { throw AppError.missingRequiredField("Title") }
        let body = try JSONEncoder().encode(StackWrite(
            ownerID: owner.id,
            title: cleanTitle,
            summary: "",
            visibility: "private",
            wishlistMode: wishlistMode
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

    func copyStack(_ stack: Stack, to owner: UserProfile) async throws -> Stack {
        struct CopyRequest: Encodable { let stackID: UUID; let title: String }
        struct CopyResponse: Decodable { let stackID: UUID }
        let response: CopyResponse = try await client.function("copy-public-stack", body: CopyRequest(stackID: stack.id, title: "\(stack.title) copy"))
        return try await fetchStack(id: response.stackID, viewerID: owner.id)
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
        let rows: [StackRow] = try await client.rest(
            "stacks",
            query: [
                URLQueryItem(name: "id", value: "eq.\(id.uuidString)"),
                URLQueryItem(name: "select", value: "*")
            ]
        )
        guard let stack = try await compose(rows: rows, viewerID: viewerID).first else { throw AppError.notFound }
        return stack
    }

    private func compose(rows: [StackRow], viewerID: UUID) async throws -> [Stack] {
        guard !rows.isEmpty else { return [] }
        let stackIDs = rows.map(\.id)
        let ownerIDs = Array(Set(rows.map(\.ownerID)))
        let ownerList = ownerIDs.map(\.uuidString).joined(separator: ",")
        let stackList = stackIDs.map(\.uuidString).joined(separator: ",")

        let profiles: [ProfileRow] = try await client.rest(
            "profiles",
            query: [
                URLQueryItem(name: "id", value: "in.(\(ownerList))"),
                URLQueryItem(name: "select", value: "*")
            ]
        )
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

        let profileByID = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0.profile) })
        let itemsByStack = Dictionary(grouping: items, by: \.stackID)
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
            let mappedItems = await mapItems(itemsByStack[row.id] ?? [], stackID: row.id)
            output.append(Stack(
                id: row.id,
                ownerID: row.ownerID,
                author: author,
                title: row.title,
                summary: row.summary,
                visibility: StackVisibility(databaseValue: row.visibility),
                wishlistMode: row.wishlistMode,
                collaborators: [],
                items: mappedItems,
                createdAt: row.createdAt,
                updatedAt: row.updatedAt,
                isBookmarked: pinnedStackIDs.contains(row.id),
                isFollowingAuthor: followedIDs.contains(row.ownerID)
            ))
        }
        return output
    }

    private func mapItems(_ rows: [ItemRow], stackID: UUID) async -> [StackItem] {
        await withTaskGroup(of: StackItem.self) { group in
            for row in rows {
                group.addTask {
                    let originalURL: URL?
                    if let path = row.originalImagePath {
                        originalURL = await self.client.signedMediaURL(path: path, stackID: stackID)
                    } else {
                        originalURL = nil
                    }
                    let removedURL: URL?
                    if let path = row.removedBackgroundImagePath {
                        removedURL = await self.client.signedMediaURL(path: path, stackID: stackID)
                    } else {
                        removedURL = nil
                    }
                    return row.stackItem(originalImageURL: originalURL, removedBackgroundImageURL: removedURL)
                }
            }
            var items: [StackItem] = []
            for await item in group { items.append(item) }
            return items
        }
    }

    private func preparedItem(
        _ item: StackItem,
        stackID: UUID,
        uploadsOriginal: Bool,
        uploadsRemoved: Bool
    ) async throws -> ItemWrite {
        let user = try await client.authUser()
        let prefix = "\(user.id.uuidString)/\(stackID.uuidString)/\(item.id.uuidString)"
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
        return profile.profile
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
            var profile = row.profile
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
    let options: SupabaseOTPOptions

    enum CodingKeys: String, CodingKey {
        case email
        case createUser = "create_user"
        case options
    }
}

private struct SupabaseOTPOptions: Encodable {
    let emailRedirectTo: String
    let codeChallenge: String
    let codeChallengeMethod: String

    enum CodingKeys: String, CodingKey {
        case emailRedirectTo = "email_redirect_to"
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

    enum CodingKeys: String, CodingKey {
        case message
        case error
        case errorDescription = "error_description"
    }

    var bestMessage: String? { message ?? errorDescription ?? error }
}

private struct ProfileRow: Decodable {
    let id: UUID
    let displayName: String
    let username: String
    let avatarPath: String?
    let bio: String
    let linkInBioURL: String?
    let onboardingCompletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case username
        case avatarPath = "avatar_path"
        case bio
        case linkInBioURL = "link_in_bio_url"
        case onboardingCompletedAt = "onboarding_completed_at"
    }

    var profile: UserProfile {
        UserProfile(
            id: id,
            displayName: displayName,
            username: username,
            avatarURL: nil,
            bio: bio,
            linkInBioURL: linkInBioURL.flatMap(URL.init(string:)),
            isFollowing: false
        )
    }
}

private struct StackRow: Decodable {
    let id: UUID
    let ownerID: UUID
    let title: String
    let summary: String
    let visibility: String
    let wishlistMode: Bool
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case ownerID = "owner_id"
        case title
        case summary
        case visibility
        case wishlistMode = "wishlist_mode"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
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
            claimStatus: nil,
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
    let summary: String
    let visibility: String
    let wishlistMode: Bool

    enum CodingKeys: String, CodingKey {
        case ownerID = "owner_id"
        case title
        case summary
        case visibility
        case wishlistMode = "wishlist_mode"
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
        return decoded.item.productLinkPreview
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
    func affiliateURL(for url: URL) async throws -> URL {
        throw AppError.configurationRequired("Sovrn affiliate edge function")
    }
}

struct EdgeFunctionClaimService: ClaimService {
    func claim(item: StackItem, claimerName: String) async throws -> GiftClaim {
        throw AppError.configurationRequired("gift-claim edge function")
    }
}

struct SupabaseCollaborationService: CollaborationService {
    func invite(email: String, to stack: Stack) async throws -> Collaborator {
        throw AppError.configurationRequired("Supabase collaborators table")
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

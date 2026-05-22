import Foundation

protocol SessionTokenStore {
    func save(_ value: String, for key: String) throws
    func read(_ key: String) -> String?
    func delete(_ key: String)
}

extension KeychainStore: SessionTokenStore {}

final class SessionStore {
    private enum Keys {
        static let accessToken = "accessToken"
        static let refreshToken = "refreshToken"
    }

    private let api: APIClient
    private let tokenStore: SessionTokenStore

    init(api: APIClient, tokenStore: SessionTokenStore = KeychainStore.shared) {
        self.api = api
        self.tokenStore = tokenStore
    }

    var hasAccessToken: Bool {
        api.accessToken != nil
    }

    var refreshToken: String? {
        tokenStore.read(Keys.refreshToken)
    }

    @discardableResult
    func restoreAccessToken() -> String? {
        guard let accessToken = tokenStore.read(Keys.accessToken) else { return nil }
        api.accessToken = accessToken
        return accessToken
    }

    @discardableResult
    func persist(session: AuthSession) throws -> Account {
        api.accessToken = session.accessToken
        try tokenStore.save(session.accessToken, for: Keys.accessToken)
        try tokenStore.save(session.refreshToken, for: Keys.refreshToken)
        return session.account
    }

    @discardableResult
    func refreshSession(refreshToken: String) async throws -> AuthSession {
        let response: AuthSession = try await api.post("/v1/auth/refresh", body: TokenRefreshRequest(refreshToken: refreshToken))
        try persist(session: response)
        return response
    }

    func sendLogout(refreshToken: String?) async {
        guard api.accessToken != nil else { return }
        let _: EmptyResponse? = try? await api.post("/v1/auth/logout", body: LogoutRequest(refreshToken: refreshToken))
    }

    func clearSession() {
        tokenStore.delete(Keys.accessToken)
        tokenStore.delete(Keys.refreshToken)
        api.accessToken = nil
    }
}

import Foundation
import Security

public struct APITokens: Codable, Sendable {
    public var jira: String
    public var emux: String
    public init(jira: String = "", emux: String = "") { self.jira = jira; self.emux = emux }
    public var configured: Bool { !jira.isEmpty && !emux.isEmpty }
}

// Company adapters receive this provider and load credentials for each operation,
// so replacing a PAT in Settings takes effect on the next request/retry.
public protocol TokenVault: Sendable {
    func load() throws -> APITokens
    func save(_ tokens: APITokens) throws
}
public extension TokenVault {
    func update(jira: String, emux: String) throws {
        var tokens = try load()
        let jira = jira.trimmingCharacters(in: .whitespacesAndNewlines)
        let emux = emux.trimmingCharacters(in: .whitespacesAndNewlines)
        if !jira.isEmpty { tokens.jira = jira }
        if !emux.isEmpty { tokens.emux = emux }
        guard tokens.configured else { throw InputError("Jira PAT와 emux PAT를 모두 입력하세요.") }
        try save(tokens)
    }
}

public struct KeychainTokenVault: TokenVault {
    private let service: String
    public init(service: String = "local.questlet.api-tokens") { self.service = service }
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: "api-pats",
         kSecAttrSynchronizable as String: false]
    }
    public func load() throws -> APITokens {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return APITokens() }
        guard status == errSecSuccess, let data = result as? Data else { throw failure(status) }
        do { return try JSONDecoder().decode(APITokens.self, from: data) }
        catch { throw InputError("키체인에 저장된 토큰 정보를 읽을 수 없습니다.") }
    }
    public func save(_ tokens: APITokens) throws {
        guard tokens.configured else { throw InputError("두 PAT를 모두 설정해야 합니다.") }
        let data = try JSONEncoder().encode(tokens)
        // One Keychain item makes Jira + emux replacement atomic. No SQLite/UserDefaults copy.
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw failure(status) }
    }
    private func failure(_ status: OSStatus) -> InputError {
        InputError("macOS 키체인에 접근할 수 없습니다 (\(status)). 키체인 잠금 또는 접근 권한을 확인하고 다시 시도하세요.")
    }
}

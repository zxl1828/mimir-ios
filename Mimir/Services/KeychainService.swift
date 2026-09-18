import Foundation
import Security

/// Keychain 读写。API Key 只存放在这里，绝不写入 UserDefaults 或源码。
struct KeychainService: Sendable {

    static let shared = KeychainService()

    enum KeychainError: LocalizedError {
        case unexpectedStatus(OSStatus)
        case invalidData

        var errorDescription: String? {
            switch self {
            case .unexpectedStatus(let status):
                return "钥匙串操作失败（代码 \(status)）。"
            case .invalidData:
                return "钥匙串中的数据无法读取。"
            }
        }
    }

    private let service: String

    init(service: String = "com.zxl.mimir") {
        self.service = service
    }

    // MARK: - 公开接口

    @discardableResult
    func setString(_ value: String, for account: String) throws -> Bool {
        guard let data = value.data(using: .utf8) else { throw KeychainError.invalidData }

        if string(for: account) != nil {
            let query = baseQuery(account: account)
            let attributes: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            ]
            let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
            return true
        }

        var query = baseQuery(account: account)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
        return true
    }

    func string(for account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    @discardableResult
    func remove(account: String) throws -> Bool {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
        return true
    }

    // MARK: - 私有

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

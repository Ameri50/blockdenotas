import Foundation
import Security

enum KeychainError: LocalizedError {
    case itemNotFound
    case unexpectedStatus(OSStatus)
    case invalidInput

    var errorDescription: String? {
        switch self {
        case .itemNotFound:
            return "No se encontró la clave guardada."
        case .unexpectedStatus(let status):
            return "Error de almacenamiento seguro: \(status)"
        case .invalidInput:
            return "La entrada no es válida."
        }
    }
}

struct KeychainManager {
    private static let service = "NotasAI.GeminiKey"

    static func save(_ value: String, forKey key: String = "gemini_api_key") throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]

        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    static func load(forKey key: String = "gemini_api_key") throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status != errSecItemNotFound else {
            throw KeychainError.itemNotFound
        }
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }

        guard let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty else {
            throw KeychainError.invalidInput
        }

        return value
    }

    static func delete(forKey key: String = "gemini_api_key") throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}

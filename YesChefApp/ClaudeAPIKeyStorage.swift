import Foundation
import Security

enum ClaudeAPIKeyStorage {
  private static let service = "com.jon.yeschef.ai.anthropic"
  private static let account = "claude-api-key"

  static func apiKey() throws -> String? {
    var query = matchingQuery
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne

    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    switch status {
    case errSecSuccess:
      guard let data = result as? Data,
        let apiKey = String(data: data, encoding: .utf8)
      else {
        throw ClaudeAPIKeyStorageError.invalidData
      }
      return apiKey
    case errSecItemNotFound:
      return nil
    default:
      throw ClaudeAPIKeyStorageError.unhandledStatus(status)
    }
  }

  static func saveAPIKey(_ apiKey: String) throws {
    let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedAPIKey.isEmpty else {
      try deleteAPIKey()
      return
    }

    let data = Data(trimmedAPIKey.utf8)
    let status = SecItemUpdate(
      matchingQuery as CFDictionary,
      [kSecValueData as String: data] as CFDictionary
    )
    switch status {
    case errSecSuccess:
      return
    case errSecItemNotFound:
      var item = syncedItemQuery
      item[kSecValueData as String] = data
      item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
      let addStatus = SecItemAdd(item as CFDictionary, nil)
      guard addStatus == errSecSuccess else {
        throw ClaudeAPIKeyStorageError.unhandledStatus(addStatus)
      }
    default:
      throw ClaudeAPIKeyStorageError.unhandledStatus(status)
    }
  }

  static func deleteAPIKey() throws {
    let status = SecItemDelete(matchingQuery as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw ClaudeAPIKeyStorageError.unhandledStatus(status)
    }
  }

  private static var baseQuery: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
  }

  private static var matchingQuery: [String: Any] {
    var query = baseQuery
    query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
    return query
  }

  private static var syncedItemQuery: [String: Any] {
    var query = baseQuery
    query[kSecAttrSynchronizable as String] = true
    return query
  }
}

enum ClaudeAPIKeyStorageError: Error, LocalizedError {
  case invalidData
  case unhandledStatus(OSStatus)

  var errorDescription: String? {
    switch self {
    case .invalidData:
      "The stored Claude API key could not be read."
    case let .unhandledStatus(status):
      "Keychain could not update the Claude API key (status \(status))."
    }
  }
}

import CryptoKit
import Foundation

public enum DeterministicID {
  /// Uses UUIDv5's RFC-defined OID namespace and a stable recipe-category key.
  public static func recipeCategory(recipeID: Recipe.ID, categoryID: Category.ID) -> UUID {
    uuidV5(
      namespace: oidNamespace,
      name: "recipeCategory:\(recipeID.uuidString):\(categoryID.uuidString)"
    )
  }

  private static let oidNamespace = UUID(uuidString: "6ba7b812-9dad-11d1-80b4-00c04fd430c8")!

  private static func uuidV5(namespace: UUID, name: String) -> UUID {
    var data = withUnsafeBytes(of: namespace.uuid) { Data($0) }
    data.append(contentsOf: name.utf8)
    var bytes = Array(Insecure.SHA1.hash(data: data))
    bytes[6] = (bytes[6] & 0x0F) | 0x50
    bytes[8] = (bytes[8] & 0x3F) | 0x80
    return UUID(uuid: (
      bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
      bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
    ))
  }
}

import Dependencies
import Foundation
import LLMClientKit

public struct GroceryCategorizationClient: Sendable {
  public var classify: @Sendable (_ names: [String], _ tier: ModelTier) async throws -> [String: GroceryStoreArea]

  public init(
    classify: @escaping @Sendable (_ names: [String], _ tier: ModelTier) async throws -> [String: GroceryStoreArea]
  ) {
    self.classify = classify
  }

  public func callAsFunction(
    names: [String],
    tier: ModelTier
  ) async throws -> [String: GroceryStoreArea] {
    try await classify(names, tier)
  }
}

extension GroceryCategorizationClient: DependencyKey {
  public static let liveValue = GroceryCategorizationClient { names, tier in
    @Dependency(\.modelClient) var modelClient
    var classified: [String: GroceryStoreArea] = [:]

    for chunk in names.chunked(into: 40) {
      try Task.checkCancellation()
      let response = try await modelClient.complete(
        ModelRequest(
          tier: tier,
          system: instructions,
          prompt: prompt(names: chunk),
          maxTokens: 1_024,
          reasoningEffort: .low
        )
      )
      classified.merge(parse(response.text), uniquingKeysWith: { _, latest in latest })
    }

    return classified
  }

  public static let testValue = GroceryCategorizationClient { _, _ in [:] }

  static let instructions = """
    You categorize grocery ingredient names by the store area where a shopper would buy them.
    Return ONLY a strict JSON object mapping every supplied name to one concise store-area string.
    Use a practical grocery-store department such as Produce, Bakery, Deli, Canned & Dry,
    Condiments & Oils, Spices, Baking, Beverages, Meat & Seafood, Household, Dairy, Frozen, or
    a more specific real department when appropriate. Do not omit names, add names, quantities, or
    explanations.
    """

  static func prompt(names: [String]) -> String {
    "Classify these exact canonical ingredient names:\n\n" + names.joined(separator: "\n")
  }

  public static func parse(_ text: String) -> [String: GroceryStoreArea] {
    guard
      let json = jsonObjectSlice(text),
      let data = json.data(using: .utf8),
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return [:] }

    return object.reduce(into: [:]) { result, entry in
      guard
        let name = CanonicalIngredient.canonicalName(entry.key),
        let area = GroceryStoreArea.normalized(entry.value as? String)
      else { return }
      result[name] = area
    }
  }

  private static func jsonObjectSlice(_ text: String) -> String? {
    guard let open = text.firstIndex(of: "{"), let close = text.lastIndex(of: "}"), open < close
    else { return nil }
    return String(text[open...close])
  }
}

extension DependencyValues {
  public var groceryCategorizationClient: GroceryCategorizationClient {
    get { self[GroceryCategorizationClient.self] }
    set { self[GroceryCategorizationClient.self] = newValue }
  }
}

private extension Array {
  func chunked(into size: Int) -> [Array] {
    stride(from: 0, to: count, by: size).map { start in
      Array(self[start..<Swift.min(start + size, count)])
    }
  }
}

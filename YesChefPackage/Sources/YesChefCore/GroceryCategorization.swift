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

    for chunk in names.chunked(into: maximumNamesPerRequest) {
      try Task.checkCancellation()
      let firstResponse = try await call(names: chunk, tier: tier).complete(using: modelClient)
      let firstPass = parse(firstResponse.text)
      classified.merge(firstPass, uniquingKeysWith: { _, latest in latest })

      let omittedNames = chunk.filter { firstPass[$0] == nil }
      guard !omittedNames.isEmpty else { continue }

      try Task.checkCancellation()
      let retryResponse = try await call(names: omittedNames, tier: tier).complete(using: modelClient)
      classified.merge(parse(retryResponse.text), uniquingKeysWith: { _, latest in latest })
    }

    return classified
  }

  public static let testValue = GroceryCategorizationClient { _, _ in [:] }

  /// Eight entries leave ample room for the complete name-to-area JSON map within the 1,024-token
  /// response budget on constrained on-device models, including one retry for omitted names.
  static let maximumNamesPerRequest = 8
  static let maximumResponseTokens = 1_024

  static let instructions = """
    You categorize grocery ingredient names by the store area where a shopper would buy them.
    Return ONLY a strict JSON object mapping every supplied name to one concise store-area string.
    Choose exactly one of these store areas for each name: Produce, Bakery, Deli, Canned & Dry,
    Condiments & Oils, Spices, Baking, Beverages, Meat & Seafood, Household, Dairy, Frozen, or Other.
    Do not omit names, add names, quantities, or explanations.
    """

  static func prompt(names: [String]) -> String {
    "Classify these exact canonical ingredient names:\n\n" + names.joined(separator: "\n")
  }

  static func call(names: [String], tier: ModelTier) -> ModelCall {
    ModelCall(
      surface: .grocery,
      task: .categorization,
      tierResolution: .callerProvided,
      contextLayers: [.ingredientNames],
      tier: tier,
      system: instructions,
      prompt: prompt(names: names),
      maxTokens: maximumResponseTokens,
      reasoningEffort: .low
    )
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

public struct GroceryCategorizationAttemptCache: Sendable {
  private var attemptedNames: Set<String> = []

  public init() {}

  public mutating func namesToClassify(from uncategorizedNames: [String]) -> [String] {
    uncategorizedNames.filter { attemptedNames.insert($0).inserted }
  }
}

private extension Array {
  func chunked(into size: Int) -> [Array] {
    stride(from: 0, to: count, by: size).map { start in
      Array(self[start..<Swift.min(start + size, count)])
    }
  }
}

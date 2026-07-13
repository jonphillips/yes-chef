import Foundation
import SQLiteData

public enum GroceryStoreArea: Hashable, Sendable {
  case produce
  case bakery
  case deli
  case cannedAndDry
  case condimentsAndOils
  case spices
  case baking
  case beverages
  case meatAndSeafood
  case household
  case dairy
  case frozen
  case other
  case custom(String)

  public struct Section: Identifiable, Equatable, Sendable {
    public let area: GroceryStoreArea
    public let rows: [GroceryItemRowData]

    public init(area: GroceryStoreArea, rows: [GroceryItemRowData]) {
      self.area = area
      self.rows = rows
    }

    public var id: String { area.id }
    public var title: String { area.title }
  }

  /// ADR-0035's fixed store walk keeps refrigerated departments at the end of a trip.
  public static let canonicalAreas: [Self] = [
    .produce,
    .bakery,
    .deli,
    .cannedAndDry,
    .condimentsAndOils,
    .spices,
    .baking,
    .beverages,
    .meatAndSeafood,
    .household,
    .dairy,
    .frozen,
    .other,
  ]

  public var title: String {
    switch self {
    case .produce: "Produce"
    case .bakery: "Bakery"
    case .deli: "Deli"
    case .cannedAndDry: "Canned & Dry"
    case .condimentsAndOils: "Condiments & Oils"
    case .spices: "Spices"
    case .baking: "Baking"
    case .beverages: "Beverages"
    case .meatAndSeafood: "Meat & Seafood"
    case .household: "Household"
    case .dairy: "Dairy"
    case .frozen: "Frozen"
    case .other: "Other"
    case let .custom(title): title
    }
  }

  public static func normalized(_ value: String?) -> Self? {
    guard let normalizedValue = normalizedText(value) else { return nil }
    if let area = canonicalAreas.first(where: { normalizedText($0.title) == normalizedValue }) {
      return area
    }
    if let area = synonyms[normalizedValue] {
      return area
    }
    return .custom(titleCased(normalizedValue))
  }

  public static func seed(for canonicalName: String?) -> Self? {
    guard let canonicalName = CanonicalIngredient.canonicalName(canonicalName) else { return nil }
    return seedAreas[canonicalName]
  }

  public static func sections(for rows: [GroceryItemRowData]) -> [Section] {
    Dictionary(grouping: rows) { normalized($0.item.aisle) ?? .other }
      .map { Section(area: $0.key, rows: $0.value) }
      .sorted { lhs, rhs in
        if lhs.area.sortOrder != rhs.area.sortOrder {
          return lhs.area.sortOrder < rhs.area.sortOrder
        }
        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
      }
  }

  private var id: String {
    switch self {
    case .produce: "produce"
    case .bakery: "bakery"
    case .deli: "deli"
    case .cannedAndDry: "canned-and-dry"
    case .condimentsAndOils: "condiments-and-oils"
    case .spices: "spices"
    case .baking: "baking"
    case .beverages: "beverages"
    case .meatAndSeafood: "meat-and-seafood"
    case .household: "household"
    case .dairy: "dairy"
    case .frozen: "frozen"
    case .other: "other"
    case let .custom(title): "custom-\(title.lowercased())"
    }
  }

  private var sortOrder: Int {
    switch self {
    case .produce: 0
    case .bakery: 1
    case .deli: 2
    case .cannedAndDry: 3
    case .condimentsAndOils: 4
    case .spices: 5
    case .baking: 6
    case .beverages: 7
    case .meatAndSeafood: 8
    case .household: 9
    case .dairy: 10
    case .frozen: 11
    case .custom: 12
    case .other: 13
    }
  }

  private static let synonyms: [String: Self] = [
    "produce": .produce,
    "vegetable": .produce,
    "vegetables": .produce,
    "veg": .produce,
    "fruit": .produce,
    "fruits": .produce,
    "bakery": .bakery,
    "bread": .bakery,
    "baked goods": .bakery,
    "deli": .deli,
    "charcuterie": .deli,
    "canned and dry": .cannedAndDry,
    "canned dry": .cannedAndDry,
    "dry goods": .cannedAndDry,
    "pantry": .cannedAndDry,
    "tinned": .cannedAndDry,
    "condiment": .condimentsAndOils,
    "condiments": .condimentsAndOils,
    "oil": .condimentsAndOils,
    "oils": .condimentsAndOils,
    "vinegar": .condimentsAndOils,
    "spice": .spices,
    "spices": .spices,
    "seasoning": .spices,
    "seasonings": .spices,
    "baking": .baking,
    "baking supplies": .baking,
    "beverage": .beverages,
    "beverages": .beverages,
    "drink": .beverages,
    "drinks": .beverages,
    "meat": .meatAndSeafood,
    "butcher": .meatAndSeafood,
    "seafood": .meatAndSeafood,
    "fish": .meatAndSeafood,
    "poultry": .meatAndSeafood,
    "household": .household,
    "cleaning": .household,
    "paper goods": .household,
    "dairy": .dairy,
    "refrigerated": .dairy,
    "frozen": .frozen,
    "freezer": .frozen,
    "other": .other,
    "miscellaneous": .other,
  ]

  /// A small, editable quality floor before S2 classifies the long tail on-device.
  private static let seedAreas: [String: Self] = [
    "apple": .produce,
    "avocado": .produce,
    "banana": .produce,
    "basil": .produce,
    "bell pepper": .produce,
    "broccoli": .produce,
    "carrot": .produce,
    "cauliflower": .produce,
    "celery": .produce,
    "cilantro": .produce,
    "cucumber": .produce,
    "garlic": .produce,
    "ginger": .produce,
    "green onions": .produce,
    "kale": .produce,
    "lemon": .produce,
    "lettuce": .produce,
    "lime": .produce,
    "mushroom": .produce,
    "onion": .produce,
    "parsley": .produce,
    "potato": .produce,
    "spinach": .produce,
    "sweet potato": .produce,
    "tomatoes": .produce,
    "zucchini": .produce,
    "bagel": .bakery,
    "bread": .bakery,
    "tortilla": .bakery,
    "ham": .deli,
    "prosciutto": .deli,
    "salami": .deli,
    "black bean": .cannedAndDry,
    "chickpea": .cannedAndDry,
    "coconut milk": .cannedAndDry,
    "lentil": .cannedAndDry,
    "pasta": .cannedAndDry,
    "rice": .cannedAndDry,
    "tomato paste": .cannedAndDry,
    "tomato sauce": .cannedAndDry,
    "broth": .cannedAndDry,
    "stock": .cannedAndDry,
    "ketchup": .condimentsAndOils,
    "mayonnaise": .condimentsAndOils,
    "mustard": .condimentsAndOils,
    "olive oil": .condimentsAndOils,
    "soy sauce": .condimentsAndOils,
    "vinegar": .condimentsAndOils,
    "black pepper": .spices,
    "cinnamon": .spices,
    "cumin": .spices,
    "paprika": .spices,
    "salt": .spices,
    "all purpose flour": .baking,
    "baking powder": .baking,
    "baking soda": .baking,
    "brown sugar": .baking,
    "sugar": .baking,
    "vanilla extract": .baking,
    "coffee": .beverages,
    "sparkling water": .beverages,
    "tea": .beverages,
    "chicken breast": .meatAndSeafood,
    "chicken thigh": .meatAndSeafood,
    "ground beef": .meatAndSeafood,
    "salmon": .meatAndSeafood,
    "shrimp": .meatAndSeafood,
    "toilet paper": .household,
    "butter": .dairy,
    "cheddar cheese": .dairy,
    "cream": .dairy,
    "egg": .dairy,
    "milk": .dairy,
    "parmesan cheese": .dairy,
    "sour cream": .dairy,
    "yogurt": .dairy,
    "frozen pea": .frozen,
    "frozen spinach": .frozen,
  ]

  private static func normalizedText(_ value: String?) -> String? {
    guard let value else { return nil }
    let normalized = value
      .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
      .replacingOccurrences(of: "&", with: " and ")
      .replacingOccurrences(of: "-", with: " ")
      .split(whereSeparator: \.isWhitespace)
      .joined(separator: " ")
    return normalized.isEmpty ? nil : normalized
  }

  private static func titleCased(_ value: String) -> String {
    value.capitalized(with: Locale(identifier: "en_US_POSIX"))
  }
}

public enum GroceryStoreAreaCache {
  public static func backfill(in db: Database) throws {
    for var item in try GroceryItem.fetchAll(db) where item.aisle == nil {
      guard let area = GroceryStoreArea.seed(for: item.canonicalIngredientName) else { continue }
      item.aisle = area.title
      try GroceryItem.upsert { item }.execute(db)
    }
  }
}

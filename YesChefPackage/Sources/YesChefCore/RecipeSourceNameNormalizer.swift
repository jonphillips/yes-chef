import Foundation

/// Maps an imported source label / URL to a clean publication name using a deterministic,
/// real-observed domain map (the M1/M2 constants register: extend only with real domains,
/// never guess). Shared by Paprika import and web recipe capture so both paths produce the
/// same provenance — a bare domain like `cooksillustrated.com` becomes `Cook's Illustrated`,
/// a non-domain label is kept as-is, and an unknown domain yields `nil` rather than a fake
/// publication name (the URL still carries provenance).
enum RecipeSourceNameNormalizer {
  static func name(importedName: String?, url: String?) -> String? {
    let importedName = importedName?.nonEmpty
    if let importedName, !isDomainLike(importedName) {
      return importedName
    }

    guard let host = host(from: url) ?? importedName.flatMap(host(from:)) else {
      return importedName
    }
    let normalizedHost = normalizedHost(host)
    return knownPublicationNames[normalizedHost] ?? importedName
  }

  private static let knownPublicationNames = [
    "177milkstreet.com": "Milk Street",
    "allrecipes.com": "Allrecipes",
    "americastestkitchen.com": "America's Test Kitchen",
    "bonappetit.com": "Bon Appetit",
    "cooking.nytimes.com": "NYT Cooking",
    "cooksillustrated.com": "Cook's Illustrated",
    "davidlebovitz.com": "David Lebovitz",
    "eatingwell.com": "EatingWell",
    "epicurious.com": "Epicurious",
    "foodandwine.com": "Food & Wine",
    "foodnetwork.com": "Food Network",
    "kingarthurbaking.com": "King Arthur Baking",
    "latimes.com": "Los Angeles Times",
    "marthastewart.com": "Martha Stewart",
    "milkstreetkitchen.com": "Milk Street",
    "nytimes.com": "The New York Times",
    "saveur.com": "Saveur",
    "seriouseats.com": "Serious Eats",
    "smittenkitchen.com": "Smitten Kitchen",
    "thekitchn.com": "The Kitchn",
    "washingtonpost.com": "The Washington Post",
    "wsj.com": "The Wall Street Journal",
  ]

  private static func isDomainLike(_ value: String) -> Bool {
    host(from: value) != nil
  }

  private static func host(from value: String?) -> String? {
    guard let value = value?.nonEmpty else { return nil }
    if let url = URL(string: value), let host = url.host() {
      return host
    }
    if let url = URL(string: "https://\(value)"), let host = url.host(), host.contains(".") {
      return host
    }
    return nil
  }

  private static func normalizedHost(_ host: String) -> String {
    var labels = host.lowercased().split(separator: ".").map(String.init)
    while labels.first == "www" || labels.first == "m" {
      labels.removeFirst()
    }
    return labels.joined(separator: ".")
  }
}

private extension String {
  var nonEmpty: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}

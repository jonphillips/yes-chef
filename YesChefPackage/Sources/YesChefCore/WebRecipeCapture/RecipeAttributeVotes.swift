import Foundation

enum RecipePageAttribute: Hashable {
  case title
  case summary
  case author
  case publisherName
  case sourceURL
  case servingsText
  case prepTime
  case cookTime
  case totalTime
  case rating
}

/// Harvested from GalavantCapture's `AttributeVotes`: scalar page facts vote by
/// source priority first, then corroboration count, then first-seen order.
struct RecipeAttributeVotes {
  static let chromePriority = 0
  static let microdataPriority = 1
  static let jsonLDPriority = 2

  private var tallies: [RecipePageAttribute: [(value: String, count: Int, priority: Int)]] = [:]

  mutating func add(
    _ attribute: RecipePageAttribute,
    _ rawValue: String?,
    priority: Int = chromePriority
  ) {
    guard let value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty
    else { return }
    var candidates = tallies[attribute] ?? []
    if let index = candidates.firstIndex(where: { $0.value == value }) {
      candidates[index].count += 1
      candidates[index].priority = max(candidates[index].priority, priority)
    } else {
      candidates.append((value, 1, priority))
    }
    tallies[attribute] = candidates
  }

  func winner(_ attribute: RecipePageAttribute) -> String? {
    best(of: attribute)?.value
  }

  func winnerPriority(_ attribute: RecipePageAttribute) -> Int? {
    best(of: attribute)?.priority
  }

  private func best(of attribute: RecipePageAttribute) -> (value: String, count: Int, priority: Int)? {
    guard let candidates = tallies[attribute], !candidates.isEmpty else { return nil }
    var best = candidates[0]
    for candidate in candidates.dropFirst()
    where (candidate.priority, candidate.count) > (best.priority, best.count) {
      best = candidate
    }
    return best
  }
}

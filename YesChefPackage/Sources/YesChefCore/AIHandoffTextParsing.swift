import Foundation

extension String {
  func labeledHandoffBlocks(startingWith label: String) -> [String] {
    var blocks: [String] = []
    var current: [String] = []

    for line in components(separatedBy: .newlines) {
      if line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix(label), !current.isEmpty {
        let block = current.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if !block.isEmpty { blocks.append(block) }
        current = []
      }
      current.append(line)
    }

    let block = current.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    if !block.isEmpty { blocks.append(block) }
    return blocks
  }
}

extension MealPlanItemSlot {
  init?(handoffPlacementLine line: String) {
    guard let slotText = line.components(separatedBy: " - ").last?
      .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    else { return nil }
    guard let slot = Self.allCases.first(where: {
      $0.rawValue == slotText || $0.title.lowercased() == slotText
    }) else { return nil }
    self = slot
  }
}

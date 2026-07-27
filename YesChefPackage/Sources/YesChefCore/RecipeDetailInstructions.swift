import Foundation

/// A run of instruction steps under the section that owns them, for all recipe-reading surfaces.
public struct InstructionStepGroup: Identifiable, Equatable, Sendable {
  public let id: InstructionSection.ID
  public let name: String?
  public let steps: [InstructionStep]

  public init(id: InstructionSection.ID, name: String?, steps: [InstructionStep]) {
    self.id = id
    self.name = name
    self.steps = steps
  }
}

public extension RecipeDetailData {
  /// Presents instructions in their persisted section order rather than relying on globally unique step orders.
  var instructionGroups: [InstructionStepGroup] {
    let stepsBySection = Dictionary(grouping: instructionSteps) { $0.sectionID }

    return instructionSections
      .sorted { lhs, rhs in
        if lhs.sortOrder != rhs.sortOrder {
          return lhs.sortOrder < rhs.sortOrder
        }
        return lhs.id.uuidString < rhs.id.uuidString
      }
      .compactMap { section in
        let steps = (stepsBySection[section.id] ?? []).sorted { lhs, rhs in
          if lhs.sortOrder != rhs.sortOrder {
            return lhs.sortOrder < rhs.sortOrder
          }
          return lhs.id.uuidString < rhs.id.uuidString
        }
        guard !steps.isEmpty else { return nil }
        return InstructionStepGroup(id: section.id, name: section.name, steps: steps)
      }
  }
}

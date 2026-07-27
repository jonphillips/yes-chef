import Foundation

/// A run of instruction steps under the section that owns them, for all recipe-reading surfaces.
public struct InstructionStepGroup: Identifiable, Equatable, Sendable {
  public let id: InstructionSection.ID
  public let name: String?
  public let steps: [InstructionStep]

  public init(id: InstructionSection.ID, name: String?, steps: [InstructionStep]) {
    self.id = id
    if let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
      self.name = name
    } else {
      self.name = nil
    }
    self.steps = steps
  }
}

public extension InstructionStepGroup {
  static func groups(
    sections: [InstructionSection],
    steps: [InstructionStep]
  ) -> [InstructionStepGroup] {
    let stepsBySection = Dictionary(grouping: steps) { $0.sectionID }
    let knownSectionIDs = Set(sections.map(\.id))
    let knownGroups: [InstructionStepGroup] = sections
      .sorted { lhs, rhs in
        if lhs.sortOrder != rhs.sortOrder {
          return lhs.sortOrder < rhs.sortOrder
        }
        return lhs.id.uuidString < rhs.id.uuidString
      }
      .compactMap { section -> InstructionStepGroup? in
        let steps = sortedInstructionSteps(stepsBySection[section.id] ?? [])
        guard !steps.isEmpty else { return nil }
        return InstructionStepGroup(id: section.id, name: section.name, steps: steps)
      }
    let orphanGroups = stepsBySection.compactMap { sectionID, steps -> (firstSortOrder: Int, group: InstructionStepGroup)? in
      guard !knownSectionIDs.contains(sectionID), let firstSortOrder = steps.map(\.sortOrder).min() else {
        return nil
      }
      return (
        firstSortOrder,
        InstructionStepGroup(id: sectionID, name: nil, steps: sortedInstructionSteps(steps))
      )
    }
    .sorted { lhs, rhs in
      if lhs.firstSortOrder != rhs.firstSortOrder {
        return lhs.firstSortOrder < rhs.firstSortOrder
      }
      return lhs.group.id.uuidString < rhs.group.id.uuidString
    }

    return knownGroups + orphanGroups.map(\.group)
  }
}

public extension RecipeDetailData {
  /// Presents instructions in their persisted section order rather than relying on globally unique step orders.
  /// This projection is total over `instructionSteps`, making `isEmpty` call-site gates safe.
  var instructionGroups: [InstructionStepGroup] {
    InstructionStepGroup.groups(sections: instructionSections, steps: instructionSteps)
  }
}

private func sortedInstructionSteps(_ steps: [InstructionStep]) -> [InstructionStep] {
  steps.sorted { lhs, rhs in
    if lhs.sortOrder != rhs.sortOrder {
      return lhs.sortOrder < rhs.sortOrder
    }
    return lhs.id.uuidString < rhs.id.uuidString
  }
}

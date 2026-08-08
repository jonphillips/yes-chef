import Dependencies
import Foundation
import LLMClientKit
import SQLiteData

// The variation resolver and its inverse deliberately share this file so their
// stable-ID semantics remain reviewable as one pair.
// swiftlint:disable file_length

public enum RecipeAdjustmentError: Error, Equatable, LocalizedError {
  case responseTruncated
  case responseUnreadable
  case emptyProposal
  case missingRecipe(Recipe.ID)
  case missingVariation(RecipeVariation.ID)
  case variationPayloadUnreadable(RecipeVariation.ID)
  case variationNeedsReview(String, String)
  case unresolvedIngredient(String)
  case unresolvedInstructionStep(String)
  case invalidVariationAnchorRepair
  case invalidVariationAnchorTarget

  public var errorDescription: String? {
    switch self {
    case .responseTruncated:
      "The model ran out of room before it finished the adjustment. Try again."
    case .responseUnreadable:
      "The model's response couldn't be read as a recipe adjustment. Try again."
    case .emptyProposal:
      "The assistant did not find a concrete recipe adjustment to review."
    case .missingRecipe:
      "The recipe could not be found."
    case .missingVariation:
      "The variation could not be found."
    case .variationPayloadUnreadable:
      "The variation could not be read."
    case let .variationNeedsReview(name, reason):
      "\"\(name)\" needs review before this recipe can be overwritten: \(reason)"
    case let .unresolvedIngredient(text):
      "The adjustment references an ingredient that could not be matched: \(text)"
    case let .unresolvedInstructionStep(text):
      "The adjustment references an instruction step that could not be matched: \(text)"
    case .invalidVariationAnchorRepair:
      "This variation anchor is no longer available to repair."
    case .invalidVariationAnchorTarget:
      "The selected recipe row is no longer available."
    }
  }
}

public struct RecipeAdjustmentProposal: Codable, Equatable, Sendable {
  public var summary: String
  public var ingredientOps: [RecipeIngredientDelta]
  public var methodNote: String?
  public var methodStepReplacements: [RecipeMethodStepReplacement]

  public init(
    summary: String = "",
    ingredientOps: [RecipeIngredientDelta] = [],
    methodNote: String? = nil,
    methodStepReplacements: [RecipeMethodStepReplacement] = []
  ) {
    self.summary = summary
    self.ingredientOps = ingredientOps
    self.methodNote = methodNote
    self.methodStepReplacements = methodStepReplacements
  }

  public var isEmpty: Bool {
    ingredientOps.isEmpty
      && methodStepReplacements.isEmpty
      && (methodNote?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
  }

  public func reviewSummary() -> String {
    var lines: [String] = []
    let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmedSummary.isEmpty {
      lines.append(trimmedSummary)
    }
    if !ingredientOps.isEmpty {
      lines.append("\(ingredientOps.count) ingredient \(ingredientOps.count == 1 ? "change" : "changes").")
    }
    if !methodStepReplacements.isEmpty {
      lines.append("\(methodStepReplacements.count) instruction \(methodStepReplacements.count == 1 ? "change" : "changes").")
    }
    if let methodNote = methodNote?.trimmingCharacters(in: .whitespacesAndNewlines), !methodNote.isEmpty {
      lines.append("Method note: \(methodNote)")
    }
    return lines.joined(separator: "\n")
  }

  public func proposedDetail(
    applyingTo detail: RecipeDetailData,
    now: Date,
    uuid: () -> UUID
  ) throws -> RecipeDetailData {
    let resolution = try applyingResolvedOperations(to: detail, now: now, uuid: uuid)
    guard let unresolvedAnchor = resolution.unresolvedAnchors.first else {
      return resolution.detail
    }
    throw unresolvedAnchor.adjustmentError
  }

  fileprivate func applyingResolvedOperations(
    to detail: RecipeDetailData,
    now: Date,
    uuid: () -> UUID,
    methodStepStructuralOps: [RecipeMethodStepStructuralOp] = []
  ) throws -> RecipeVariationResolution {
    var ingredientSections = detail.ingredientSections
    var ingredientLines = sortedIngredientLines(detail.ingredientLines, sections: ingredientSections)
    var unresolvedAnchors: [RecipeVariationUnresolvedAnchor] = []
    for op in ingredientOps {
      switch op {
      case let .add(line, sectionName):
        guard let section = targetIngredientSection(
          named: sectionName,
          sections: &ingredientSections,
          recipeID: detail.recipe.id,
          uuid: uuid
        ) else { continue }
        if let line = newIngredientLine(
          line,
          recipeID: detail.recipe.id,
          sectionID: section.id,
          sortOrder: nextIngredientSortOrder(in: section.id, lines: ingredientLines),
          uuid: uuid
        ) {
          ingredientLines.append(line)
        }

      case let .remove(reference):
        guard let index = reference.index(in: ingredientLines) else {
          unresolvedAnchors.append(.ingredient(reference.displayText))
          continue
        }
        ingredientLines.remove(at: index)

      case let .substitute(reference, line), let .scale(reference, line):
        guard let index = reference.index(in: ingredientLines) else {
          unresolvedAnchors.append(.ingredient(reference.displayText))
          continue
        }
        ingredientLines[index] = ingredientLines[index].replacingOriginalText(with: line)
      }
      ingredientLines = sortedIngredientLines(ingredientLines, sections: ingredientSections)
    }

    var instructionSteps = detail.instructionGroups.flatMap(\.steps)
    for replacement in methodStepReplacements {
      guard let index = replacement.index(in: instructionSteps) else {
        unresolvedAnchors.append(.instructionStep(replacement.displayText))
        continue
      }
      instructionSteps[index].text = replacement.replacementText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    instructionSteps = applyingStepStructuralOps(
      methodStepStructuralOps,
      to: instructionSteps,
      sections: detail.instructionSections,
      recipeID: detail.recipe.id,
      unresolvedAnchors: &unresolvedAnchors,
      uuid: uuid
    )

    let notes = notesWithMethodNote(
      existing: detail.notes,
      methodNote: methodNote,
      recipeID: detail.recipe.id,
      now: now,
      uuid: uuid
    )
    var recipe = detail.recipe
    recipe.dateModified = now
    let resolvedDetail = RecipeDetailData(
      recipe: recipe,
      source: detail.source,
      ingredientSections: ingredientSections.sorted { $0.sortOrder < $1.sortOrder },
      ingredientLines: ingredientLines,
      instructionSections: detail.instructionSections.sorted { $0.sortOrder < $1.sortOrder },
      instructionSteps: instructionSteps,
      notes: notes,
      photos: detail.photos,
      categories: detail.categories,
      categoryDisplayNames: detail.categoryDisplayNames,
      equipment: detail.equipment,
      recipeEquipment: detail.recipeEquipment,
      serveWith: detail.serveWith
    )
    return RecipeVariationResolution(detail: resolvedDetail, unresolvedAnchors: unresolvedAnchors)
  }
}

public struct RecipeVariationPayload: Codable, Equatable, Sendable {
  public var ingredientOps: [RecipeIngredientDelta]
  public var methodStepReplacements: [RecipeMethodStepReplacement]
  public var methodStepStructuralOps: [RecipeMethodStepStructuralOp]

  public init(
    ingredientOps: [RecipeIngredientDelta],
    methodStepReplacements: [RecipeMethodStepReplacement],
    methodStepStructuralOps: [RecipeMethodStepStructuralOp] = []
  ) {
    self.ingredientOps = ingredientOps
    self.methodStepReplacements = methodStepReplacements
    self.methodStepStructuralOps = methodStepStructuralOps
  }

  public init(proposal: RecipeAdjustmentProposal) {
    self.init(
      ingredientOps: proposal.ingredientOps,
      methodStepReplacements: proposal.methodStepReplacements
    )
  }

  // Decodes tolerantly: variations stored before Amd4-D4 carry no `methodStepStructuralOps` key,
  // so its absence must read as an empty op list rather than fail the whole payload.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.ingredientOps = try container.decode([RecipeIngredientDelta].self, forKey: .ingredientOps)
    self.methodStepReplacements = try container.decode([RecipeMethodStepReplacement].self, forKey: .methodStepReplacements)
    self.methodStepStructuralOps = try container.decodeIfPresent(
      [RecipeMethodStepStructuralOp].self,
      forKey: .methodStepStructuralOps
    ) ?? []
  }

  public func encodedData() throws -> Data {
    try JSONEncoder().encode(self)
  }

  public static func decode(_ data: Data?, variationID: RecipeVariation.ID) throws -> Self {
    guard let data else { return Self(ingredientOps: [], methodStepReplacements: []) }
    do {
      return try JSONDecoder().decode(Self.self, from: data)
    } catch {
      throw RecipeAdjustmentError.variationPayloadUnreadable(variationID)
    }
  }

  fileprivate func normalizingAnchors(in detail: RecipeDetailData) throws -> Self {
    var payload = self
    let steps = detail.instructionGroups.flatMap(\.steps)
    payload.ingredientOps = try ingredientOps.map { operation in
      switch operation {
      case .add:
        return operation
      case let .remove(reference):
        return .remove(try normalizedIngredientReference(reference, in: detail.ingredientLines))
      case let .substitute(reference, line):
        return .substitute(try normalizedIngredientReference(reference, in: detail.ingredientLines), line: line)
      case let .scale(reference, line):
        return .scale(try normalizedIngredientReference(reference, in: detail.ingredientLines), line: line)
      }
    }
    payload.methodStepReplacements = try methodStepReplacements.map { replacement in
      var replacement = replacement
      guard let index = replacement.index(in: steps) else {
        throw RecipeAdjustmentError.unresolvedInstructionStep(replacement.displayText)
      }
      replacement.id = steps[index].id
      return replacement
    }
    payload.methodStepStructuralOps = try methodStepStructuralOps.map { op in
      switch op {
      case let .insert(after, sectionID, text):
        guard let after else { return .insert(after: nil, sectionID: sectionID, text: text) }
        guard let normalized = after.normalizedIfPossible(in: steps) else {
          throw RecipeAdjustmentError.unresolvedInstructionStep(after.displayText)
        }
        return .insert(after: normalized, sectionID: sectionID, text: text)
      case let .remove(reference):
        guard let normalized = reference.normalizedIfPossible(in: steps) else {
          throw RecipeAdjustmentError.unresolvedInstructionStep(reference.displayText)
        }
        return .remove(normalized)
      }
    }
    return payload
  }

  fileprivate func backfillingAnchors(
    in detail: RecipeDetailData,
    variation: RecipeVariation
  ) -> (payload: Self, unresolvedAnchors: [RecipeVariationAnchorBackfillReport.UnresolvedAnchor]) {
    var payload = self
    var unresolvedAnchors: [RecipeVariationAnchorBackfillReport.UnresolvedAnchor] = []

    payload.ingredientOps = ingredientOps.map { operation in
      switch operation {
      case .add:
        return operation
      case let .remove(reference):
        guard let reference = normalizedIngredientReferenceIfPossible(reference, in: detail.ingredientLines) else {
          unresolvedAnchors.append(
            .ingredient(variationID: variation.id, variationName: variation.name, text: reference.displayText)
          )
          return operation
        }
        return .remove(reference)
      case let .substitute(reference, line):
        guard let reference = normalizedIngredientReferenceIfPossible(reference, in: detail.ingredientLines) else {
          unresolvedAnchors.append(
            .ingredient(variationID: variation.id, variationName: variation.name, text: reference.displayText)
          )
          return operation
        }
        return .substitute(reference, line: line)
      case let .scale(reference, line):
        guard let reference = normalizedIngredientReferenceIfPossible(reference, in: detail.ingredientLines) else {
          unresolvedAnchors.append(
            .ingredient(variationID: variation.id, variationName: variation.name, text: reference.displayText)
          )
          return operation
        }
        return .scale(reference, line: line)
      }
    }

    let steps = detail.instructionGroups.flatMap(\.steps)
    payload.methodStepReplacements = methodStepReplacements.map { replacement in
      var replacement = replacement
      guard let index = replacement.index(in: steps) else {
        unresolvedAnchors.append(
          .instructionStep(
            variationID: variation.id,
            variationName: variation.name,
            text: replacement.displayText
          )
        )
        return replacement
      }
      replacement.id = steps[index].id
      return replacement
    }
    payload.methodStepStructuralOps = methodStepStructuralOps.map { op in
      switch op {
      case let .insert(after, sectionID, text):
        guard let after else { return .insert(after: nil, sectionID: sectionID, text: text) }
        guard let normalized = after.normalizedIfPossible(in: steps) else {
          unresolvedAnchors.append(
            .instructionStep(variationID: variation.id, variationName: variation.name, text: after.displayText)
          )
          return op
        }
        return .insert(after: normalized, sectionID: sectionID, text: text)
      case let .remove(reference):
        guard let normalized = reference.normalizedIfPossible(in: steps) else {
          unresolvedAnchors.append(
            .instructionStep(variationID: variation.id, variationName: variation.name, text: reference.displayText)
          )
          return op
        }
        return .remove(normalized)
      }
    }
    return (payload, unresolvedAnchors)
  }

  fileprivate func repairItems(
    in detail: RecipeDetailData,
    variationID: RecipeVariation.ID
  ) -> [RecipeVariationAnchorRepairItem] {
    var items: [RecipeVariationAnchorRepairItem] = []
    var ingredientSections = detail.ingredientSections
    var ingredientLines = sortedIngredientLines(detail.ingredientLines, sections: ingredientSections)
    var uuids = VariationUUIDSequence(variationID: variationID)
    for (index, operation) in ingredientOps.enumerated() {
      switch operation {
      case let .add(line, sectionName):
        guard let section = targetIngredientSection(
          named: sectionName,
          sections: &ingredientSections,
          recipeID: detail.recipe.id,
          uuid: { uuids.next() }
        ) else { continue }
        if let line = newIngredientLine(
          line,
          recipeID: detail.recipe.id,
          sectionID: section.id,
          sortOrder: nextIngredientSortOrder(in: section.id, lines: ingredientLines),
          uuid: { uuids.next() }
        ) {
          ingredientLines.append(line)
        }

      case let .remove(reference):
        guard let lineIndex = reference.index(in: ingredientLines) else {
          items.append(
            RecipeVariationAnchorRepairItem(
              address: .ingredientOperation(index),
              kind: .ingredient,
              originalText: reference.displayText
            )
          )
          continue
        }
        ingredientLines.remove(at: lineIndex)

      case let .substitute(reference, line), let .scale(reference, line):
        guard let lineIndex = reference.index(in: ingredientLines) else {
          items.append(
            RecipeVariationAnchorRepairItem(
              address: .ingredientOperation(index),
              kind: .ingredient,
              originalText: reference.displayText
            )
          )
          continue
        }
        ingredientLines[lineIndex] = ingredientLines[lineIndex].replacingOriginalText(with: line)
      }
      ingredientLines = sortedIngredientLines(ingredientLines, sections: ingredientSections)
    }

    var instructionSteps = detail.instructionGroups.flatMap(\.steps)
    for (index, replacement) in methodStepReplacements.enumerated() {
      guard let stepIndex = replacement.index(in: instructionSteps) else {
        items.append(
          RecipeVariationAnchorRepairItem(
            address: .methodStepReplacement(index),
            kind: .instructionStep,
            originalText: replacement.displayText
          )
        )
        continue
      }
      instructionSteps[stepIndex].text = replacement.replacementText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    let orderedSteps = InstructionStepGroup.groups(
      sections: detail.instructionSections,
      steps: instructionSteps
    )
    .flatMap(\.steps)
    for (index, operation) in methodStepStructuralOps.enumerated() {
      let reference: RecipeStepReference?
      switch operation {
      case let .insert(after, _, _):
        reference = after
      case let .remove(candidate):
        reference = candidate
      }
      guard let reference, reference.index(in: orderedSteps) == nil else { continue }
      items.append(
        RecipeVariationAnchorRepairItem(
          address: .methodStepStructuralOperation(index),
          kind: .instructionStep,
          originalText: reference.displayText
        )
      )
    }
    return items
  }
}

public struct RecipeVariationAnchorBackfillReport: Equatable, Sendable {
  public enum UnresolvedAnchor: Equatable, Sendable {
    case ingredient(variationID: RecipeVariation.ID, variationName: String, text: String)
    case instructionStep(variationID: RecipeVariation.ID, variationName: String, text: String)
    case unreadablePayload(variationID: RecipeVariation.ID, variationName: String)
  }

  public var updatedVariationIDs: [RecipeVariation.ID]
  public var unresolvedAnchors: [UnresolvedAnchor]

  public init(
    updatedVariationIDs: [RecipeVariation.ID] = [],
    unresolvedAnchors: [UnresolvedAnchor] = []
  ) {
    self.updatedVariationIDs = updatedVariationIDs
    self.unresolvedAnchors = unresolvedAnchors
  }

  public var requiresReview: Bool { !unresolvedAnchors.isEmpty }
  public var hasFindings: Bool { !updatedVariationIDs.isEmpty || requiresReview }

  public var logSummary: String {
    let unresolved = unresolvedAnchors.map { anchor in
      switch anchor {
      case let .ingredient(variationID, variationName, text):
        "ingredient(variation=\(variationName),id=\(variationID.uuidString),text=\(text))"
      case let .instructionStep(variationID, variationName, text):
        "instructionStep(variation=\(variationName),id=\(variationID.uuidString),text=\(text))"
      case let .unreadablePayload(variationID, variationName):
        "unreadablePayload(variation=\(variationName),id=\(variationID.uuidString))"
      }
    }
    return [
      "variation-anchor-backfill",
      "updatedVariationIDs=[\(updatedVariationIDs.map(\.uuidString).joined(separator: ","))]",
      "unresolved=[\(unresolved.joined(separator: ","))]",
    ]
    .joined(separator: " ")
  }
}

/// A lossless description of an edit the current variation vocabulary cannot carry.
/// The editor may still let a cook make these edits; saving then offers split-off rather
/// than persisting a partial overlay.
public enum RecipeVariationUnrepresentableEdit: Equatable, Sendable {
  case ingredientSectionAdded(String)
  case ingredientSectionRemoved(String)
  case ingredientSectionChanged(String)
  case ingredientLineMoved(String)
  case ingredientLineAnchorUnavailable(String)
  case instructionSectionAdded(String)
  case instructionSectionRemoved(String)
  case instructionSectionChanged(String)
  case instructionStepMoved(String)

  public var description: String {
    switch self {
    case let .ingredientSectionAdded(name): "a new ingredient section (\(name))"
    case let .ingredientSectionRemoved(name): "the ingredient section (\(name))"
    case let .ingredientSectionChanged(name): "the ingredient section (\(name))"
    case let .ingredientLineMoved(text): "the ingredient order for \(text)"
    case let .ingredientLineAnchorUnavailable(text): "the original ingredient (\(text)), which no longer exists in the new base"
    case let .instructionSectionAdded(name): "a new instruction section (\(name))"
    case let .instructionSectionRemoved(name): "the instruction section (\(name))"
    case let .instructionSectionChanged(name): "the instruction section (\(name))"
    case let .instructionStepMoved(text): "the instruction order for \(text)"
    }
  }
}

public struct RecipeVariationDerivation: Equatable, Sendable {
  public var payload: RecipeVariationPayload
  public var unrepresentableEdits: [RecipeVariationUnrepresentableEdit]

  public init(
    payload: RecipeVariationPayload,
    unrepresentableEdits: [RecipeVariationUnrepresentableEdit]
  ) {
    self.payload = payload
    self.unrepresentableEdits = unrepresentableEdits
  }

  public var isRepresentable: Bool { unrepresentableEdits.isEmpty }
}

/// A stored variation can outlive one of its base anchors. Reading it still applies every
/// operation that remains exact and carries the repair queue to the UI; writing remains strict.
public struct RecipeVariationResolution: Equatable, Sendable {
  public var detail: RecipeDetailData
  public var unresolvedAnchors: [RecipeVariationUnresolvedAnchor]

  public init(
    detail: RecipeDetailData,
    unresolvedAnchors: [RecipeVariationUnresolvedAnchor] = []
  ) {
    self.detail = detail
    self.unresolvedAnchors = unresolvedAnchors
  }

  public var requiresRepair: Bool { !unresolvedAnchors.isEmpty }

  public func requiringAllAnchorsResolved() throws -> RecipeDetailData {
    guard let unresolvedAnchor = unresolvedAnchors.first else { return detail }
    throw unresolvedAnchor.adjustmentError
  }
}

public enum RecipeVariationUnresolvedAnchor: Equatable, Sendable {
  case ingredient(String)
  case instructionStep(String)

  public var displayText: String {
    switch self {
    case let .ingredient(text), let .instructionStep(text): text
    }
  }

  fileprivate var adjustmentError: RecipeAdjustmentError {
    switch self {
    case let .ingredient(text): .unresolvedIngredient(text)
    case let .instructionStep(text): .unresolvedInstructionStep(text)
    }
  }
}

/// The precise stored operation that needs a new base-row ID or an explicit discard.
/// The position is intentionally payload-local: variation operations have no independent
/// persisted identity and no other consumer anchors to them.
public enum RecipeVariationAnchorRepairAddress: Hashable, Sendable {
  case ingredientOperation(Int)
  case methodStepReplacement(Int)
  case methodStepStructuralOperation(Int)
}

public enum RecipeVariationAnchorRepairKind: Equatable, Sendable {
  case ingredient
  case instructionStep
}

public struct RecipeVariationAnchorRepairItem: Identifiable, Equatable, Sendable {
  public let address: RecipeVariationAnchorRepairAddress
  public let kind: RecipeVariationAnchorRepairKind
  public let originalText: String

  public var id: RecipeVariationAnchorRepairAddress { address }

  public init(
    address: RecipeVariationAnchorRepairAddress,
    kind: RecipeVariationAnchorRepairKind,
    originalText: String
  ) {
    self.address = address
    self.kind = kind
    self.originalText = originalText
  }
}

public enum RecipeVariationPromotionResult: Equatable, Sendable {
  case promoted
  case needsConfirmation(removingVariations: [String])
}

public enum RecipeVariationIngredientHighlight: Equatable, Sendable {
  case added
  case removed
  case changed
}

public enum RecipeIngredientDelta: Codable, Equatable, Sendable {
  case add(line: String, sectionName: String?)
  case remove(RecipeIngredientReference)
  case substitute(RecipeIngredientReference, line: String)
  case scale(RecipeIngredientReference, line: String)
}

public struct RecipeIngredientReference: Codable, Equatable, Sendable {
  public var id: IngredientLine.ID?
  public var originalText: String?

  public init(id: IngredientLine.ID? = nil, originalText: String? = nil) {
    self.id = id
    self.originalText = originalText
  }

  public var displayText: String {
    originalText?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyAdjustmentText
      ?? id?.uuidString
      ?? "unknown ingredient"
  }

  fileprivate func index(in lines: [IngredientLine]) -> Int? {
    if let id, let existingIndex = lines.firstIndex(where: { $0.id == id }) {
      return existingIndex
    }
    guard let originalText = originalText?.trimmingCharacters(in: .whitespacesAndNewlines), !originalText.isEmpty else {
      return nil
    }
    return lines.firstIndex { $0.originalText.trimmingCharacters(in: .whitespacesAndNewlines) == originalText }
  }
}

public struct RecipeMethodStepReplacement: Codable, Equatable, Sendable {
  public var id: InstructionStep.ID?
  public var stepNumber: Int?
  public var originalText: String?
  public var replacementText: String

  public init(
    id: InstructionStep.ID? = nil,
    stepNumber: Int? = nil,
    originalText: String? = nil,
    replacementText: String
  ) {
    self.id = id
    self.stepNumber = stepNumber
    self.originalText = originalText
    self.replacementText = replacementText
  }

  public var displayText: String {
    originalText?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyAdjustmentText
      ?? stepNumber.map { "step \($0)" }
      ?? id?.uuidString
      ?? "unknown step"
  }

  fileprivate func index(in steps: [InstructionStep]) -> Int? {
    if let id, let existingIndex = steps.firstIndex(where: { $0.id == id }) {
      return existingIndex
    }
    guard let originalText = originalText?.trimmingCharacters(in: .whitespacesAndNewlines), !originalText.isEmpty else {
      return nil
    }
    return steps.firstIndex { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) == originalText }
  }
}

/// A base-step anchor. Reuses `RecipeMethodStepReplacement`'s id → stepNumber → originalText
/// resolution so the anchor-repair machinery (normalize/backfill) treats the structural step
/// ops and text substitutions identically.
public struct RecipeStepReference: Codable, Equatable, Sendable {
  public var id: InstructionStep.ID?
  public var stepNumber: Int?
  public var originalText: String?

  public init(
    id: InstructionStep.ID? = nil,
    stepNumber: Int? = nil,
    originalText: String? = nil
  ) {
    self.id = id
    self.stepNumber = stepNumber
    self.originalText = originalText
  }

  public var displayText: String {
    originalText?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyAdjustmentText
      ?? stepNumber.map { "step \($0)" }
      ?? id?.uuidString
      ?? "unknown step"
  }

  fileprivate func index(in steps: [InstructionStep]) -> Int? {
    if let id, let existingIndex = steps.firstIndex(where: { $0.id == id }) {
      return existingIndex
    }
    guard let originalText = originalText?.trimmingCharacters(in: .whitespacesAndNewlines), !originalText.isEmpty else {
      return nil
    }
    return steps.firstIndex { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) == originalText }
  }

  /// Returns a copy whose `id` is pinned to the resolved base step, or `nil` when the anchor no
  /// longer resolves against `steps`.
  fileprivate func normalizedIfPossible(in steps: [InstructionStep]) -> RecipeStepReference? {
    guard let index = index(in: steps) else { return nil }
    var reference = self
    reference.id = steps[index].id
    return reference
  }
}

/// The two structural instruction-step ops a variation may carry (Amd4-D4), and deliberately only
/// these two: any edit that requires placing something relative to steps it was not anchored to (a
/// move, an instruction-section op) stays unrepresentable and routes to split-off.
public enum RecipeMethodStepStructuralOp: Codable, Equatable, Sendable {
  /// Insert a new step immediately after `after` (a base step); a nil anchor means "before everything".
  ///
  /// `sectionID` is the base instruction section the new step belongs to, carried explicitly
  /// because the anchor's section is *not* always the right home: a step added at the head of a
  /// section anchors to the last step of the *previous* section, and inheriting that anchor's
  /// section would silently move it. This mirrors the ingredient `add` op, which carries its
  /// section too. It falls back to the anchor's section when it no longer resolves — the section
  /// is a placement hint, not a second anchor, so it never reports an unresolved anchor of its own.
  case insert(after: RecipeStepReference?, sectionID: InstructionSection.ID?, text: String)
  /// Remove an anchored base step.
  case remove(RecipeStepReference)
}

private func normalizedIngredientReference(
  _ reference: RecipeIngredientReference,
  in lines: [IngredientLine]
) throws -> RecipeIngredientReference {
  guard let reference = normalizedIngredientReferenceIfPossible(reference, in: lines) else {
    throw RecipeAdjustmentError.unresolvedIngredient(reference.displayText)
  }
  return reference
}

private func normalizedIngredientReferenceIfPossible(
  _ reference: RecipeIngredientReference,
  in lines: [IngredientLine]
) -> RecipeIngredientReference? {
  guard let index = reference.index(in: lines) else { return nil }
  var reference = reference
  reference.id = lines[index].id
  return reference
}

private func reanchoring(
  _ reference: RecipeIngredientReference,
  to line: IngredientLine
) -> RecipeIngredientReference {
  var reference = reference
  reference.id = line.id
  reference.originalText = line.originalText
  return reference
}

private func reanchoring(
  _ reference: RecipeStepReference,
  to step: InstructionStep
) -> RecipeStepReference {
  var reference = reference
  reference.id = step.id
  reference.stepNumber = nil
  reference.originalText = step.text
  return reference
}

/// Applies the variation's structural step ops (Amd4-D4) to the resolved step list: an insert
/// mints a new step in *its own* section immediately after its anchor (or at the head of the first
/// section for a nil anchor), a remove drops an anchored base step. Unresolved anchors are
/// reported (read-lenient) rather than thrown. `sortOrder` is re-sequenced to the rebuilt display
/// order — downstream readers regroup by section identity, so global ordering is sufficient.
private func applyingStepStructuralOps(
  _ ops: [RecipeMethodStepStructuralOp],
  to steps: [InstructionStep],
  sections: [InstructionSection],
  recipeID: Recipe.ID,
  unresolvedAnchors: inout [RecipeVariationUnresolvedAnchor],
  uuid: () -> UUID
) -> [InstructionStep] {
  guard !ops.isEmpty else { return steps }
  // Resolve anchors against the reader's display order so they match what the derivation saw.
  let ordered = InstructionStepGroup.groups(sections: sections, steps: steps).flatMap(\.steps)
  let knownSectionIDs = Set(sections.map(\.id))
  var removedIDs: Set<InstructionStep.ID> = []
  var headInserts: [(text: String, sectionID: InstructionSection.ID?)] = []
  var insertsAfter: [InstructionStep.ID: [(text: String, sectionID: InstructionSection.ID?)]] = [:]
  for op in ops {
    switch op {
    case let .remove(reference):
      guard let index = reference.index(in: ordered) else {
        unresolvedAnchors.append(.instructionStep(reference.displayText))
        continue
      }
      removedIDs.insert(ordered[index].id)
    case let .insert(after, sectionID, text):
      // A section that no longer exists degrades to the anchor's section rather than reporting an
      // anchor failure: placement is a hint, the step anchor is the thing that has to resolve.
      let section = sectionID.flatMap { knownSectionIDs.contains($0) ? $0 : nil }
      guard let after else {
        headInserts.append((text, section))
        continue
      }
      guard let index = after.index(in: ordered) else {
        unresolvedAnchors.append(.instructionStep(after.displayText))
        continue
      }
      insertsAfter[ordered[index].id, default: []].append((text, section))
    }
  }

  let firstSectionID = sections
    .sorted { $0.sortOrder != $1.sortOrder ? $0.sortOrder < $1.sortOrder : $0.id.uuidString < $1.id.uuidString }
    .first?.id ?? ordered.first?.sectionID
  var rebuilt: [InstructionStep] = []
  for insert in headInserts {
    guard let sectionID = insert.sectionID ?? firstSectionID else { continue }
    rebuilt.append(newVariationStep(insert.text, recipeID: recipeID, sectionID: sectionID, uuid: uuid))
  }
  for step in ordered where !removedIDs.contains(step.id) {
    rebuilt.append(step)
    for insert in insertsAfter[step.id] ?? [] {
      rebuilt.append(
        newVariationStep(insert.text, recipeID: recipeID, sectionID: insert.sectionID ?? step.sectionID, uuid: uuid)
      )
    }
  }
  return rebuilt.enumerated().map { offset, step in
    var step = step
    step.sortOrder = offset
    return step
  }
}

private func newVariationStep(
  _ text: String,
  recipeID: Recipe.ID,
  sectionID: InstructionSection.ID,
  uuid: () -> UUID
) -> InstructionStep {
  InstructionStep(
    id: uuid(),
    recipeID: recipeID,
    sectionID: sectionID,
    text: text.trimmingCharacters(in: .whitespacesAndNewlines),
    sortOrder: 0
  )
}

public struct RecipeAdjustmentClient: Sendable {
  public var extract: @Sendable (
    _ selection: String,
    _ messages: [RecipeChatMessage],
    _ detail: RecipeDetailData,
    _ tier: ModelTier,
    _ tierResolution: ModelCallTierResolution
  ) async throws -> RecipeAdjustmentProposal

  public init(
    extract: @escaping @Sendable (
      _ selection: String,
      _ messages: [RecipeChatMessage],
      _ detail: RecipeDetailData,
      _ tier: ModelTier,
      _ tierResolution: ModelCallTierResolution
    ) async throws -> RecipeAdjustmentProposal
  ) {
    self.extract = extract
  }

  public func callAsFunction(
    selection: String,
    messages: [RecipeChatMessage],
    detail: RecipeDetailData,
    tier: ModelTier,
    tierResolution: ModelCallTierResolution
  ) async throws -> RecipeAdjustmentProposal {
    try await extract(selection, messages, detail, tier, tierResolution)
  }
}

extension RecipeAdjustmentClient: DependencyKey {
  public static let liveValue = RecipeAdjustmentClient { selection, messages, detail, tier, tierResolution in
    @Dependency(\.modelClient) var modelClient
    let call = ModelCall(
      surface: .recipe,
      task: .recipeAdjustment,
      tierResolution: tierResolution,
      contextLayers: [.recipe, .selection, .conversation],
      tier: tier,
      system: instructions,
      prompt: prompt(selection: selection, messages: messages, detail: detail),
      // Same ceiling as WorkbenchDraftRecipe: reasoning models share this budget between thinking and
      // output, and the extractor must have enough room to emit complete strict JSON instead of a
      // partial delta. Billing is for tokens used, so the high ceiling avoids truncation without
      // forcing high spend on small adjustments.
      maxTokens: 16_384,
      reasoningEffort: .high
    )
    let response = try await call.complete(using: modelClient)
    let trimmed = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
    if response.wasTruncated || trimmed.isEmpty {
      throw RecipeAdjustmentError.responseTruncated
    }
    guard jsonObject(in: response.text) != nil else {
      throw RecipeAdjustmentError.responseUnreadable
    }
    let proposal = parse(response.text)
    guard !proposal.isEmpty else {
      throw RecipeAdjustmentError.emptyProposal
    }
    return proposal
  }

  public static let testValue = RecipeAdjustmentClient { _, _, _, _, _ in RecipeAdjustmentProposal() }

  static let instructions = """
    You extract a proposed edit to one existing recipe from a cooking conversation.

    Return ONLY strict JSON:
    {"summary":"brief rationale","ingredientOps":[{"op":"add","line":"new ingredient line","sectionName":"optional existing section name or null"},{"op":"remove","baseIngredientID":"uuid-or-null","originalText":"exact current line"},{"op":"substitute","baseIngredientID":"uuid-or-null","originalText":"exact current line","line":"replacement ingredient line"},{"op":"scale","baseIngredientID":"uuid-or-null","originalText":"exact current line","line":"full replacement ingredient line"}],"methodNote":"optional prose note","methodStepReplacements":[{"baseStepID":"uuid-or-null","stepNumber":1,"originalText":"exact current step","replacementText":"full replacement step text"}]}.

    Emit a structured delta only. Do not return a rewritten recipe. For ingredient edits use only add,
    remove, substitute, and scale. For method edits either write a concise methodNote or replace whole
    step text; do not merge, reorder, or rewrite the whole procedure. Ingredient edits may target any
    section; when adding to a specific section, set sectionName to the exact existing section name. Use
    exact IDs or exact current text from the recipe context when changing existing rows. Return empty
    arrays and null methodNote when there is no concrete edit to review.
    """

  static func prompt(selection: String, messages: [RecipeChatMessage], detail: RecipeDetailData) -> String {
    let conversation = messages.isEmpty
      ? "(No conversation yet.)"
      : messages.map { "\($0.role.adjustmentPromptLabel): \($0.text)" }.joined(separator: "\n")
    return """
      Current recipe:
      \(adjustmentContext(detail))

      User-selected subject:
      \(selection.isEmpty ? "(No selected subject.)" : selection)

      Conversation so far:
      \(conversation)

      Extract only the concrete recipe edit the user is asking to review.
      """
  }

  public static func parse(_ text: String) -> RecipeAdjustmentProposal {
    guard let object = jsonObject(in: text) else { return RecipeAdjustmentProposal() }
    return RecipeAdjustmentProposal(
      summary: string("summary", in: object) ?? "",
      ingredientOps: ingredientOps(in: object),
      methodNote: string("methodNote", in: object),
      methodStepReplacements: methodStepReplacements(in: object)
    )
  }

  private static func ingredientOps(in object: [String: Any]) -> [RecipeIngredientDelta] {
    let elements = object["ingredientOps"] as? [[String: Any]] ?? []
    return elements.compactMap { element in
      guard let op = string("op", in: element) else { return nil }
      let reference = RecipeIngredientReference(
        id: uuid("baseIngredientID", in: element),
        originalText: string("originalText", in: element)
      )
      switch op {
      case "add":
        return string("line", in: element).map { .add(line: $0, sectionName: string("sectionName", in: element)) }
      case "remove":
        return .remove(reference)
      case "substitute":
        return string("line", in: element).map { .substitute(reference, line: $0) }
      case "scale":
        return string("line", in: element).map { .scale(reference, line: $0) }
      default:
        return nil
      }
    }
  }

  private static func methodStepReplacements(in object: [String: Any]) -> [RecipeMethodStepReplacement] {
    let elements = object["methodStepReplacements"] as? [[String: Any]] ?? []
    return elements.compactMap { element in
      guard let replacementText = string("replacementText", in: element) else { return nil }
      return RecipeMethodStepReplacement(
        id: uuid("baseStepID", in: element),
        stepNumber: integer("stepNumber", in: element),
        originalText: string("originalText", in: element),
        replacementText: replacementText
      )
    }
  }

  private static func jsonObject(in text: String) -> [String: Any]? {
    guard
      let open = text.firstIndex(of: "{"),
      let close = text.lastIndex(of: "}"),
      open < close,
      let data = String(text[open...close]).data(using: .utf8)
    else { return nil }
    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
  }

  private static func string(_ key: String, in object: [String: Any]) -> String? {
    if object[key] is NSNull { return nil }
    return (object[key] as? String)?.nonEmptyAdjustmentText
  }

  private static func uuid(_ key: String, in object: [String: Any]) -> UUID? {
    string(key, in: object).flatMap(UUID.init(uuidString:))
  }

  private static func integer(_ key: String, in object: [String: Any]) -> Int? {
    if let int = object[key] as? Int { return int }
    if let double = object[key] as? Double { return Int(double) }
    return string(key, in: object).flatMap(Int.init)
  }
}

extension DependencyValues {
  public var recipeAdjustmentClient: RecipeAdjustmentClient {
    get { self[RecipeAdjustmentClient.self] }
    set { self[RecipeAdjustmentClient.self] = newValue }
  }
}

extension RecipeRepository {
  public static func variationAnchorRepairItems(
    for variation: RecipeVariation,
    in detail: RecipeDetailData
  ) throws -> [RecipeVariationAnchorRepairItem] {
    try RecipeVariationPayload
      .decode(variation.deltas, variationID: variation.id)
      .repairItems(in: detail, variationID: variation.id)
  }

  /// Replaces one unresolved anchor's base-row ID, or discards its whole operation when no target
  /// is supplied. The repair queue is recomputed in the same transaction so a stale sheet cannot
  /// rewrite an anchor that has already been fixed by another device.
  @discardableResult
  public static func repairVariationAnchor(
    _ address: RecipeVariationAnchorRepairAddress,
    in variationID: RecipeVariation.ID,
    reanchoringTo targetID: UUID?,
    in db: Database,
    now: Date
  ) throws -> RecipeVariation {
    guard var variation = try RecipeVariation.find(variationID).fetchOne(db) else {
      throw RecipeAdjustmentError.missingVariation(variationID)
    }
    guard let detail = try fetchDetail(recipeID: variation.recipeID, in: db) else {
      throw RecipeAdjustmentError.missingRecipe(variation.recipeID)
    }
    var payload = try RecipeVariationPayload.decode(variation.deltas, variationID: variationID)
    guard payload.repairItems(in: detail, variationID: variationID).contains(where: { $0.address == address }) else {
      throw RecipeAdjustmentError.invalidVariationAnchorRepair
    }

    switch address {
    case let .ingredientOperation(index):
      guard payload.ingredientOps.indices.contains(index) else {
        throw RecipeAdjustmentError.invalidVariationAnchorRepair
      }
      guard let targetID else {
        payload.ingredientOps.remove(at: index)
        break
      }
      guard let target = detail.ingredientLines.first(where: { $0.id == targetID }) else {
        throw RecipeAdjustmentError.invalidVariationAnchorTarget
      }
      switch payload.ingredientOps[index] {
      case .add:
        throw RecipeAdjustmentError.invalidVariationAnchorRepair
      case let .remove(reference):
        payload.ingredientOps[index] = .remove(reanchoring(reference, to: target))
      case let .substitute(reference, line):
        payload.ingredientOps[index] = .substitute(reanchoring(reference, to: target), line: line)
      case let .scale(reference, line):
        payload.ingredientOps[index] = .scale(reanchoring(reference, to: target), line: line)
      }

    case let .methodStepReplacement(index):
      guard payload.methodStepReplacements.indices.contains(index) else {
        throw RecipeAdjustmentError.invalidVariationAnchorRepair
      }
      guard let targetID else {
        payload.methodStepReplacements.remove(at: index)
        break
      }
      guard let target = detail.instructionSteps.first(where: { $0.id == targetID }) else {
        throw RecipeAdjustmentError.invalidVariationAnchorTarget
      }
      payload.methodStepReplacements[index].id = target.id
      payload.methodStepReplacements[index].stepNumber = nil
      payload.methodStepReplacements[index].originalText = target.text

    case let .methodStepStructuralOperation(index):
      guard payload.methodStepStructuralOps.indices.contains(index) else {
        throw RecipeAdjustmentError.invalidVariationAnchorRepair
      }
      guard let targetID else {
        payload.methodStepStructuralOps.remove(at: index)
        break
      }
      guard let target = detail.instructionSteps.first(where: { $0.id == targetID }) else {
        throw RecipeAdjustmentError.invalidVariationAnchorTarget
      }
      switch payload.methodStepStructuralOps[index] {
      case let .insert(after, sectionID, text):
        guard let after else { throw RecipeAdjustmentError.invalidVariationAnchorRepair }
        payload.methodStepStructuralOps[index] = .insert(
          after: reanchoring(after, to: target),
          sectionID: sectionID,
          text: text
        )
      case let .remove(reference):
        payload.methodStepStructuralOps[index] = .remove(reanchoring(reference, to: target))
      }
    }

    variation.deltas = try payload.encodedData()
    variation.dateModified = now
    try RecipeVariation.upsert { variation }.execute(db)
    return variation
  }

  /// Repairs legacy model-authored anchors after the sync engine is installed, so updates to the
  /// existing `recipeVariations` table are observed and uploaded. It deliberately preserves an
  /// anchor when the current base cannot match it exactly; the report is the repair queue.
  public static func backfillVariationAnchors(in db: Database) throws -> RecipeVariationAnchorBackfillReport {
    var report = RecipeVariationAnchorBackfillReport()
    let variations = try RecipeVariation.fetchAll(db).sorted { $0.id.uuidString < $1.id.uuidString }

    for var variation in variations {
      guard let detail = try fetchDetail(recipeID: variation.recipeID, in: db) else { continue }
      let payload: RecipeVariationPayload
      do {
        payload = try RecipeVariationPayload.decode(variation.deltas, variationID: variation.id)
      } catch {
        report.unresolvedAnchors.append(
          .unreadablePayload(variationID: variation.id, variationName: variation.name)
        )
        continue
      }

      let repaired = payload.backfillingAnchors(in: detail, variation: variation)
      report.unresolvedAnchors.append(contentsOf: repaired.unresolvedAnchors)
      guard repaired.payload != payload else { continue }

      variation.deltas = try repaired.payload.encodedData()
      try RecipeVariation.upsert { variation }.execute(db)
      report.updatedVariationIDs.append(variation.id)
    }
    return report
  }

  public static func overwriteRecipeWithAdjustmentProposal(
    _ proposal: RecipeAdjustmentProposal,
    recipeID: Recipe.ID,
    deliberationBody: String?,
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws -> Data {
    guard let detail = try fetchDetail(recipeID: recipeID, in: db) else {
      throw RecipeAdjustmentError.missingRecipe(recipeID)
    }
    let restorePoint = try adjustmentRestorePoint(for: detail)
    let proposedDetail = try proposal.proposedDetail(applyingTo: detail, now: now, uuid: uuid)
    try validateVariationsCanRebase(detail.variations, onto: proposedDetail)
    try Recipe.upsert { proposedDetail.recipe }.execute(db)
    try replaceEditableChildren(
      recipeID: recipeID,
      ingredientSections: proposedDetail.ingredientSections,
      ingredientLines: proposedDetail.ingredientLines,
      instructionSections: proposedDetail.instructionSections,
      instructionSteps: proposedDetail.instructionSteps,
      generalNotes: proposedDetail.notes.filter { $0.noteType == .general },
      in: db
    )
    try addDeliberationLogEntry(
      body: deliberationBody,
      recipeID: recipeID,
      in: db,
      now: now,
      uuid: uuid
    )
    return restorePoint
  }

  public static func keepAdjustmentProposalAsVariation(
    _ proposal: RecipeAdjustmentProposal,
    recipeID: Recipe.ID,
    name: String,
    deliberationBody: String?,
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws -> RecipeVariation {
    guard let detail = try fetchDetail(recipeID: recipeID, in: db) else {
      throw RecipeAdjustmentError.missingRecipe(recipeID)
    }
    let payload = try RecipeVariationPayload(proposal: proposal).normalizingAnchors(in: detail)
    let variationID = uuid()
    let variation = RecipeVariation(
      id: variationID,
      recipeID: recipeID,
      name: variationName(name, fallback: proposal.summary),
      note: proposal.methodNote?.nonEmptyAdjustmentText,
      sortIndex: try nextVariationSortIndex(recipeID: recipeID, in: db),
      deltas: try payload.encodedData(),
      origin: .chat,
      dateCreated: now,
      dateModified: now
    )
    _ = try detail.resolved(applying: variation).requiringAllAnchorsResolved()
    try RecipeVariation.insert { variation }.execute(db)
    try addDeliberationLogEntry(
      body: deliberationBody,
      recipeID: recipeID,
      variationID: variation.id,
      in: db,
      now: now,
      uuid: uuid
    )
    try setActiveVariation(variation.id, recipeID: recipeID, in: db, now: now, uuid: uuid)
    return variation
  }

  public static func setActiveVariation(
    _ variationID: RecipeVariation.ID?,
    recipeID: Recipe.ID,
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws {
    if let variationID {
      guard let variation = try RecipeVariation.find(variationID).fetchOne(db),
            variation.recipeID == recipeID
      else {
        throw RecipeAdjustmentError.missingVariation(variationID)
      }
    }

    try #sql("DELETE FROM \"recipeActiveVariations\" WHERE \"recipeID\" = \(bind: recipeID)")
      .execute(db)

    if let variationID {
      try RecipeActiveVariation.insert {
        RecipeActiveVariation(
          id: uuid(),
          recipeID: recipeID,
          variationID: variationID,
          dateModified: now
        )
      }
      .execute(db)
    }
  }

  public static func renameVariation(
    _ variationID: RecipeVariation.ID,
    to name: String,
    in db: Database,
    now: Date
  ) throws {
    guard let variation = try RecipeVariation.find(variationID).fetchOne(db) else {
      throw RecipeAdjustmentError.missingVariation(variationID)
    }
    try RecipeVariation.find(variationID).update {
      $0.name = variationName(name, fallback: variation.name)
      $0.dateModified = now
    }
    .execute(db)
  }

  /// Deletes a variation overlay (Amd2-D4). Clears the recipe's active selection
  /// *only* when the deleted variation was the active one — a different active
  /// variation must survive, so this must not blindly `setActiveVariation(nil,…)`.
  public static func deleteVariation(
    _ variationID: RecipeVariation.ID,
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws {
    guard let variation = try RecipeVariation.find(variationID).fetchOne(db) else {
      throw RecipeAdjustmentError.missingVariation(variationID)
    }
    // Resolve the active selection against the pre-deletion variation set so we
    // know whether the row we are about to remove was the active one.
    let variations = try RecipeVariation
      .where { $0.recipeID.eq(variation.recipeID) }
      .fetchAll(db)
    let currentActiveID = try activeVariationID(
      recipeID: variation.recipeID,
      variations: variations,
      in: db
    )
    try RecipeVariation.find(variationID).delete().execute(db)
    if currentActiveID == variationID {
      try setActiveVariation(nil, recipeID: variation.recipeID, in: db, now: now, uuid: uuid)
    }
  }

  /// Re-derives a variation from its edited resolved detail. A caller must inspect
  /// `unrepresentableEdits` before writing so no part of a richer edit is lost.
  @discardableResult
  public static func saveEditedVariation(
    _ variationID: RecipeVariation.ID,
    resolvedDetail: RecipeDetailData,
    name: String,
    note: String?,
    in db: Database,
    now: Date
  ) throws -> RecipeVariationDerivation {
    guard let variation = try RecipeVariation.find(variationID).fetchOne(db) else {
      throw RecipeAdjustmentError.missingVariation(variationID)
    }
    guard let baseDetail = try fetchDetail(recipeID: variation.recipeID, in: db) else {
      throw RecipeAdjustmentError.missingRecipe(variation.recipeID)
    }

    let derivation = baseDetail.derivingVariation(from: resolvedDetail)
    guard derivation.isRepresentable else { return derivation }
    let deltas = try derivation.payload.encodedData()

    try RecipeVariation.find(variationID).update {
      $0.name = #bind(variationName(name, fallback: variation.name))
      $0.note = #bind(note?.nonEmptyAdjustmentText)
      $0.deltas = #bind(deltas)
      $0.dateModified = #bind(now)
    }
    .execute(db)
    return derivation
  }

  /// Materializes the resolved variation into a separate recipe and removes the
  /// overlay. `resolvedDetail` may contain an edit the overlay vocabulary could
  /// not express, which is precisely why this path accepts it intact.
  @discardableResult
  public static func splitVariationOff(
    _ variationID: RecipeVariation.ID,
    resolvedDetail: RecipeDetailData,
    name: String,
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws -> Recipe.ID {
    guard let variation = try RecipeVariation.find(variationID).fetchOne(db) else {
      throw RecipeAdjustmentError.missingVariation(variationID)
    }
    let recipeID = try createStandaloneRecipe(
      from: resolvedDetail,
      title: variationName(name, fallback: variation.name),
      in: db,
      now: now,
      uuid: uuid
    )
    let deliberationLogEntries = try RecipeDeliberationLogEntry
      .where { $0.recipeID.eq(variation.recipeID) }
      .fetchAll(db)
    for entry in deliberationLogEntries {
      try RecipeDeliberationLogEntry.insert {
        RecipeDeliberationLogEntry(
          id: uuid(),
          recipeID: recipeID,
          body: entry.body,
          dateCreated: entry.dateCreated
        )
      }
      .execute(db)
    }
    try linkRelatedRecipes(variation.recipeID, recipeID, in: db, now: now, uuid: uuid)
    try RecipeVariation.find(variationID).delete().execute(db)
    try setActiveVariation(nil, recipeID: variation.recipeID, in: db, now: now, uuid: uuid)
    return recipeID
  }

  /// Replaces the base with one variation and re-derives every surviving overlay.
  /// If an overlay cannot be represented against the new base, the caller must
  /// explicitly confirm its removal; nothing is discarded implicitly.
  public static func promoteVariationToBase(
    _ variationID: RecipeVariation.ID,
    confirmingRemovalOfUnrepresentableVariations: Bool = false,
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws -> RecipeVariationPromotionResult {
    guard let variation = try RecipeVariation.find(variationID).fetchOne(db) else {
      throw RecipeAdjustmentError.missingVariation(variationID)
    }
    guard let oldBase = try fetchDetail(recipeID: variation.recipeID, in: db) else {
      throw RecipeAdjustmentError.missingRecipe(variation.recipeID)
    }
    let newBase = try oldBase.resolved(applying: variation).requiringAllAnchorsResolved()
    var rederived: [(RecipeVariation, RecipeVariationDerivation)] = []
    for sibling in oldBase.variations where sibling.id != variationID {
      let siblingResolved = try oldBase.resolved(applying: sibling).requiringAllAnchorsResolved()
      var derivation = newBase.derivingVariation(from: siblingResolved)
      derivation.unrepresentableEdits.append(
        contentsOf: try unavailableIngredientAnchors(in: sibling, against: newBase)
      )
      rederived.append((sibling, derivation))
    }
    let invalidNames = rederived
      .filter { !$0.1.isRepresentable }
      .map { $0.0.name }
    guard invalidNames.isEmpty || confirmingRemovalOfUnrepresentableVariations else {
      return .needsConfirmation(removingVariations: invalidNames)
    }

    var promotedRecipe = newBase.recipe
    promotedRecipe.dateModified = now
    try Recipe.upsert { promotedRecipe }.execute(db)
    try replaceEditableChildren(
      recipeID: variation.recipeID,
      ingredientSections: newBase.ingredientSections,
      ingredientLines: newBase.ingredientLines,
      instructionSections: newBase.instructionSections,
      instructionSteps: newBase.instructionSteps,
      generalNotes: newBase.notes.filter { $0.noteType == .general },
      in: db
    )

    try RecipeVariation.find(variationID).delete().execute(db)
    for (sibling, derivation) in rederived {
      guard derivation.isRepresentable else {
        try RecipeVariation.find(sibling.id).delete().execute(db)
        continue
      }
      let deltas = try derivation.payload.encodedData()
      try RecipeVariation.find(sibling.id).update {
        $0.deltas = #bind(deltas)
        $0.dateModified = #bind(now)
      }
      .execute(db)
    }

    let previousBase = newBase.derivingVariation(from: oldBase)
    precondition(previousBase.isRepresentable, "A resolved variation must be representable against its base")
    let restoredBase = RecipeVariation(
      id: uuid(),
      recipeID: variation.recipeID,
      name: variationName(oldBase.recipe.title, fallback: "Base Recipe"),
      sortIndex: try nextVariationSortIndex(recipeID: variation.recipeID, in: db),
      deltas: try previousBase.payload.encodedData(),
      origin: .hand,
      dateCreated: now,
      dateModified: now
    )
    try RecipeVariation.insert { restoredBase }.execute(db)
    try setActiveVariation(nil, recipeID: variation.recipeID, in: db, now: now, uuid: uuid)
    return .promoted
  }

  public static func restoreRecipeAdjustment(
    _ restorePoint: Data,
    recipeID: Recipe.ID,
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws {
    let snapshot = try RecipeBundleCoding.decodeSnapshot(restorePoint)
    var recipe = snapshot.recipe
    recipe.dateModified = now
    try Recipe.upsert { recipe }.execute(db)
    try replaceEditableChildren(
      recipeID: recipeID,
      ingredientSections: snapshot.ingredientSections,
      ingredientLines: snapshot.ingredientLines,
      instructionSections: snapshot.instructionSections,
      instructionSteps: snapshot.instructionSteps,
      generalNotes: snapshot.recipeNotes.filter { $0.noteType == .general },
      in: db
    )
    _ = uuid
  }

  public static func adjustmentRestorePoint(for detail: RecipeDetailData) throws -> Data {
    try RecipeBundleCoding.snapshotData(
      recipe: detail.recipe,
      source: detail.source,
      ingredientSections: detail.ingredientSections,
      ingredientLines: detail.ingredientLines,
      instructionSections: detail.instructionSections,
      instructionSteps: detail.instructionSteps,
      notes: detail.notes,
      tagNames: [],
      categoryNames: detail.categoryDisplayNames,
      // Snapshots strip image bytes anyway (leanSnapshotPhotos); the restore path
      // never re-writes photo rows, so a metadata-only conversion is faithful.
      photos: detail.photos.map(\.leanRecipePhoto),
      equipment: detail.equipment,
      recipeEquipment: detail.recipeEquipment
    )
  }

  static func activeVariationID(
    recipeID: Recipe.ID,
    variations: [RecipeVariation],
    in db: Database
  ) throws -> RecipeVariation.ID? {
    let validVariationIDs = Set(variations.map(\.id))
    return try RecipeActiveVariation
      .where { $0.recipeID.eq(recipeID) }
      .fetchAll(db)
      .filter { validVariationIDs.contains($0.variationID) }
      .sorted(by: areActiveVariationsInDecreasingOrder)
      .first?
      .variationID
  }

  private static func validateVariationsCanRebase(
    _ variations: [RecipeVariation],
    onto proposedDetail: RecipeDetailData
  ) throws {
    for variation in variations {
      do {
        _ = try proposedDetail.resolved(applying: variation).requiringAllAnchorsResolved()
      } catch {
        throw RecipeAdjustmentError.variationNeedsReview(
          variation.name,
          (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        )
      }
    }
  }

  private static func createStandaloneRecipe(
    from detail: RecipeDetailData,
    title: String,
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws -> Recipe.ID {
    let recipeID = uuid()
    let ingredientSectionIDs = Dictionary(
      uniqueKeysWithValues: detail.ingredientSections.map { ($0.id, uuid()) }
    )
    let instructionSectionIDs = Dictionary(
      uniqueKeysWithValues: detail.instructionSections.map { ($0.id, uuid()) }
    )
    let fullPhotos = try RecipePhoto.where { $0.recipeID.eq(detail.recipe.id) }.fetchAll(db)
    let photoIDs = Dictionary(uniqueKeysWithValues: fullPhotos.map { ($0.id, uuid()) })

    let recipe = Recipe(
      id: recipeID,
      title: title,
      subtitle: detail.recipe.subtitle,
      summary: detail.recipe.summary,
      servings: detail.recipe.servings,
      servingsText: detail.recipe.servingsText,
      yieldText: detail.recipe.yieldText,
      prepTimeMinutes: detail.recipe.prepTimeMinutes,
      cookTimeMinutes: detail.recipe.cookTimeMinutes,
      totalTimeMinutes: detail.recipe.totalTimeMinutes,
      activeTimeMinutes: detail.recipe.activeTimeMinutes,
      restTimeMinutes: detail.recipe.restTimeMinutes,
      cuisine: detail.recipe.cuisine,
      course: detail.recipe.course,
      difficulty: detail.recipe.difficulty,
      rating: detail.recipe.rating,
      favorite: detail.recipe.favorite,
      libraryPlacement: detail.recipe.libraryPlacement,
      dateCreated: now,
      dateModified: now,
      originalImportText: detail.recipe.originalImportText,
      makeAhead: detail.recipe.makeAhead,
      chefItUp: detail.recipe.chefItUp,
      serveWith: nil,
      viewScale: detail.recipe.viewScale,
      coverPhotoID: detail.recipe.coverPhotoID.flatMap { photoIDs[$0] }
    )
    try Recipe.insert { recipe }.execute(db)

    try cloneServeWith(detail.serveWith, to: recipeID, in: db, now: now, uuid: uuid)

    if let source = detail.source {
      try RecipeSource.insert {
        RecipeSource(
          id: uuid(), recipeID: recipeID, name: source.name, url: source.url,
          author: source.author, publicationName: source.publicationName, bookTitle: source.bookTitle,
          pageNumber: source.pageNumber, importedFrom: source.importedFrom, dateImported: source.dateImported,
          sourceNotes: source.sourceNotes
        )
      }
      .execute(db)
    }

    for section in detail.ingredientSections {
      try IngredientSection.insert {
        IngredientSection(
          id: ingredientSectionIDs[section.id]!, recipeID: recipeID,
          name: section.name, sortOrder: section.sortOrder
        )
      }
      .execute(db)
    }
    for line in detail.ingredientLines {
      try IngredientLine.insert {
        IngredientLine(
          id: uuid(), recipeID: recipeID, sectionID: ingredientSectionIDs[line.sectionID]!,
          originalText: line.originalText, quantity: line.quantity, quantityText: line.quantityText,
          unit: line.unit, item: line.item, canonicalName: line.canonicalName, preparation: line.preparation,
          comment: line.comment, isOptional: line.isOptional, shoppingCategory: line.shoppingCategory,
          doNotShop: line.doNotShop, isHeader: line.isHeader, sortOrder: line.sortOrder,
          confidence: line.confidence
        )
      }
      .execute(db)
    }
    for section in detail.instructionSections {
      try InstructionSection.insert {
        InstructionSection(
          id: instructionSectionIDs[section.id]!, recipeID: recipeID,
          name: section.name, sortOrder: section.sortOrder
        )
      }
      .execute(db)
    }
    for step in detail.instructionSteps {
      try InstructionStep.insert {
        InstructionStep(
          id: uuid(), recipeID: recipeID, sectionID: instructionSectionIDs[step.sectionID]!,
          text: step.text, sortOrder: step.sortOrder, isOptional: step.isOptional
        )
      }
      .execute(db)
    }
    for note in detail.notes {
      try RecipeNote.insert {
        RecipeNote(
          id: uuid(), recipeID: recipeID, text: note.text, noteType: note.noteType,
          dateCreated: now, dateModified: now, cookingSessionID: nil, pinned: note.pinned
        )
      }
      .execute(db)
    }
    for photo in fullPhotos {
      let id = photoIDs[photo.id]!
      try RecipePhoto.insert {
        RecipePhoto(
          id: id, recipeID: recipeID, imageDataReference: "recipePhotos/\(id.uuidString)",
          displayData: photo.displayData, thumbnailData: photo.thumbnailData, mediaType: photo.mediaType,
          pixelWidth: photo.pixelWidth, pixelHeight: photo.pixelHeight,
          originalSourcePath: photo.originalSourcePath, sourceURL: photo.sourceURL, checksum: photo.checksum,
          kind: photo.kind, caption: photo.caption, source: photo.source, sortOrder: photo.sortOrder,
          dateCreated: photo.dateCreated
        )
      }
      .execute(db)
    }
    for category in detail.categories {
      try RecipeCategory.insert {
        RecipeCategory(id: uuid(), recipeID: recipeID, categoryID: category.id)
      }
      .execute(db)
    }
    for join in detail.recipeEquipment {
      try RecipeEquipment.insert {
        RecipeEquipment(id: uuid(), recipeID: recipeID, equipmentID: join.equipmentID, notes: join.notes)
      }
      .execute(db)
    }

    guard let savedDetail = try fetchDetail(recipeID: recipeID, in: db) else {
      throw RecipeAdjustmentError.missingRecipe(recipeID)
    }
    let snapshot = try RecipeBundleCoding.snapshotData(
      recipe: recipe,
      source: savedDetail.source,
      ingredientSections: savedDetail.ingredientSections,
      ingredientLines: savedDetail.ingredientLines,
      instructionSections: savedDetail.instructionSections,
      instructionSteps: savedDetail.instructionSteps,
      notes: savedDetail.notes,
      tagNames: [],
      categoryNames: savedDetail.categoryDisplayNames,
      photos: fullPhotos.map { photo in
        let id = photoIDs[photo.id]!
        return RecipePhoto(
          id: id, recipeID: recipeID, imageDataReference: "recipePhotos/\(id.uuidString)",
          displayData: photo.displayData, thumbnailData: photo.thumbnailData, mediaType: photo.mediaType,
          pixelWidth: photo.pixelWidth, pixelHeight: photo.pixelHeight,
          originalSourcePath: photo.originalSourcePath, sourceURL: photo.sourceURL, checksum: photo.checksum,
          kind: photo.kind, caption: photo.caption, source: photo.source, sortOrder: photo.sortOrder,
          dateCreated: photo.dateCreated
        )
      },
      equipment: savedDetail.equipment,
      recipeEquipment: savedDetail.recipeEquipment
    )
    try Recipe.find(recipeID).update { $0.originalSnapshot = #bind(snapshot) }.execute(db)
    return recipeID
  }

  private static func cloneServeWith(
    _ rows: [RecipeServeWith],
    to recipeID: Recipe.ID,
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws {
    for row in rows {
      try RecipeServeWith.insert {
        RecipeServeWith(
          id: uuid(), recipeID: recipeID, title: row.title, note: row.note,
          sortOrder: row.sortOrder, provenance: row.provenance, dateCreated: now, dateModified: now
        )
      }
      .execute(db)
    }
  }

  private static func nextVariationSortIndex(recipeID: Recipe.ID, in db: Database) throws -> Int {
    try RecipeVariation
      .where { $0.recipeID.eq(recipeID) }
      .fetchAll(db)
      .map(\.sortIndex)
      .max()
      .map { $0 + 1 }
      ?? 0
  }

  private static func replaceEditableChildren(
    recipeID: Recipe.ID,
    ingredientSections: [IngredientSection],
    ingredientLines: [IngredientLine],
    instructionSections: [InstructionSection],
    instructionSteps: [InstructionStep],
    generalNotes: [RecipeNote],
    in db: Database
  ) throws {
    try #sql("DELETE FROM \"ingredientLines\" WHERE \"recipeID\" = \(bind: recipeID)").execute(db)
    try #sql("DELETE FROM \"ingredientSections\" WHERE \"recipeID\" = \(bind: recipeID)").execute(db)
    try #sql("DELETE FROM \"instructionSteps\" WHERE \"recipeID\" = \(bind: recipeID)").execute(db)
    try #sql("DELETE FROM \"instructionSections\" WHERE \"recipeID\" = \(bind: recipeID)").execute(db)
    try #sql("""
      DELETE FROM "recipeNotes"
      WHERE "recipeID" = \(bind: recipeID)
        AND "noteType" = 'general'
      """)
      .execute(db)

    for section in ingredientSections {
      try IngredientSection.insert { section }.execute(db)
    }
    for line in ingredientLines {
      try IngredientLine.insert { line }.execute(db)
    }
    for section in instructionSections {
      try InstructionSection.insert { section }.execute(db)
    }
    for step in instructionSteps {
      try InstructionStep.insert { step }.execute(db)
    }
    for note in generalNotes {
      try RecipeNote.insert { note }.execute(db)
    }
  }
}

public extension RecipeDetailData {
  var activeVariation: RecipeVariation? {
    guard let activeVariationID else { return nil }
    return variations.first { $0.id == activeVariationID }
  }

  /// Mirrors `resolved(applying:)`: turns a resolved, ID-preserving edit back into
  /// the minimal overlay against this base detail. It deliberately reports edits
  /// outside the finite delta vocabulary instead of dropping them.
  func derivingVariation(from edited: RecipeDetailData) -> RecipeVariationDerivation {
    var ingredientOps: [RecipeIngredientDelta] = []
    var stepReplacements: [RecipeMethodStepReplacement] = []
    var stepStructuralOps: [RecipeMethodStepStructuralOp] = []
    var unrepresentable: [RecipeVariationUnrepresentableEdit] = []

    let baseIngredientSections = Dictionary(uniqueKeysWithValues: ingredientSections.map { ($0.id, $0) })
    let editedIngredientSections = Dictionary(uniqueKeysWithValues: edited.ingredientSections.map { ($0.id, $0) })
    for section in edited.ingredientSections where baseIngredientSections[section.id] == nil {
      unrepresentable.append(.ingredientSectionAdded(section.name ?? "unnamed"))
    }
    for section in ingredientSections where editedIngredientSections[section.id] == nil {
      unrepresentable.append(.ingredientSectionRemoved(section.name ?? "unnamed"))
    }
    for base in ingredientSections {
      guard let current = editedIngredientSections[base.id] else { continue }
      if base.name != current.name || base.sortOrder != current.sortOrder {
        unrepresentable.append(.ingredientSectionChanged(current.name ?? base.name ?? "unnamed"))
      }
    }

    let baseLines = Dictionary(uniqueKeysWithValues: ingredientLines.map { ($0.id, $0) })
    let editedLines = Dictionary(uniqueKeysWithValues: edited.ingredientLines.map { ($0.id, $0) })
    for base in sortedIngredientLines(ingredientLines, sections: ingredientSections) {
      guard let current = editedLines[base.id] else {
        ingredientOps.append(.remove(RecipeIngredientReference(id: base.id, originalText: base.originalText)))
        continue
      }
      if current.sectionID != base.sectionID || current.sortOrder != base.sortOrder {
        unrepresentable.append(.ingredientLineMoved(current.originalText))
      }
      if current.originalText != base.originalText {
        ingredientOps.append(
          .substitute(
            RecipeIngredientReference(id: base.id, originalText: base.originalText),
            line: current.originalText
          )
        )
      }
    }
    for line in sortedIngredientLines(edited.ingredientLines, sections: edited.ingredientSections)
    where baseLines[line.id] == nil {
      guard let section = editedIngredientSections[line.sectionID], baseIngredientSections[section.id] != nil else {
        continue
      }
      ingredientOps.append(.add(line: line.originalText, sectionName: section.name))
    }

    let baseInstructionSections = Dictionary(uniqueKeysWithValues: instructionSections.map { ($0.id, $0) })
    let editedInstructionSections = Dictionary(uniqueKeysWithValues: edited.instructionSections.map { ($0.id, $0) })
    for section in edited.instructionSections where baseInstructionSections[section.id] == nil {
      unrepresentable.append(.instructionSectionAdded(section.name ?? "unnamed"))
    }
    for section in instructionSections where editedInstructionSections[section.id] == nil {
      unrepresentable.append(.instructionSectionRemoved(section.name ?? "unnamed"))
    }
    for base in instructionSections {
      guard let current = editedInstructionSections[base.id] else { continue }
      if base.name != current.name || base.sortOrder != current.sortOrder {
        unrepresentable.append(.instructionSectionChanged(current.name ?? base.name ?? "unnamed"))
      }
    }

    let baseSteps = Dictionary(uniqueKeysWithValues: instructionSteps.map { ($0.id, $0) })
    let editedSteps = Dictionary(uniqueKeysWithValues: edited.instructionSteps.map { ($0.id, $0) })
    // A within-section move is detected from the *relative* order of the base steps that survive
    // into the edit, not their absolute `sortOrder`: resolving a variation that carries structural
    // ops re-sequences sortOrder, so an absolute comparison would false-positive on a re-edit
    // (Amd4-D4). Inserts and removes leave the surviving base steps' relative order intact.
    let survivingBaseOrderInBase = instructionGroups.flatMap(\.steps).map(\.id)
      .filter { editedSteps[$0] != nil }
    let survivingBaseOrderInEdited = edited.instructionGroups.flatMap(\.steps).map(\.id)
      .filter { baseSteps[$0] != nil }
    let basePositions = Dictionary(
      uniqueKeysWithValues: survivingBaseOrderInBase.enumerated().map { ($1, $0) }
    )
    let editedPositions = Dictionary(
      uniqueKeysWithValues: survivingBaseOrderInEdited.enumerated().map { ($1, $0) }
    )
    for base in instructionGroups.flatMap(\.steps) {
      guard let current = editedSteps[base.id] else {
        stepStructuralOps.append(.remove(RecipeStepReference(id: base.id, originalText: base.text)))
        continue
      }
      if current.sectionID != base.sectionID || basePositions[base.id] != editedPositions[base.id] {
        unrepresentable.append(.instructionStepMoved(current.text))
      }
      if current.text != base.text {
        stepReplacements.append(
          RecipeMethodStepReplacement(id: base.id, originalText: base.text, replacementText: current.text)
        )
      }
    }
    // A newly added step becomes an insert anchored to the nearest preceding *base* step in the
    // edited order (nil = head), carrying its own section: a step added at the head of a section
    // anchors to the last step of the *previous* section, so inheriting the anchor's section on
    // resolve would silently move it. A step added into a brand-new section is left to the
    // `instructionSectionAdded` report above, which keeps the whole edit unrepresentable.
    var lastBaseStepID: InstructionStep.ID?
    for step in edited.instructionGroups.flatMap(\.steps) {
      if baseSteps[step.id] != nil {
        lastBaseStepID = step.id
        continue
      }
      guard baseInstructionSections[step.sectionID] != nil else { continue }
      let anchor = lastBaseStepID.map { id in
        RecipeStepReference(id: id, originalText: baseSteps[id]?.text)
      }
      stepStructuralOps.append(.insert(after: anchor, sectionID: step.sectionID, text: step.text))
    }

    return RecipeVariationDerivation(
      payload: RecipeVariationPayload(
        ingredientOps: ingredientOps,
        methodStepReplacements: stepReplacements,
        methodStepStructuralOps: stepStructuralOps
      ),
      unrepresentableEdits: unrepresentable
    )
  }

  func resolved(applying variation: RecipeVariation) throws -> RecipeVariationResolution {
    #if DEBUG
      let clock = ContinuousClock()
      let start = clock.now
      defer {
        let duration = String(describing: start.duration(to: clock.now))
        AppLog.performance.log(
          "recipe-variation-resolve duration=\(duration, privacy: .public)"
        )
      }
    #endif
    let payload = try RecipeVariationPayload.decode(variation.deltas, variationID: variation.id)
    var uuids = VariationUUIDSequence(variationID: variation.id)
    var resolution = try RecipeAdjustmentProposal(
      summary: variation.name,
      ingredientOps: payload.ingredientOps,
      methodStepReplacements: payload.methodStepReplacements
    )
    .applyingResolvedOperations(
      to: self,
      now: recipe.dateModified,
      uuid: { uuids.next() },
      methodStepStructuralOps: payload.methodStepStructuralOps
    )
    resolution.detail.variations = variations
    resolution.detail.activeVariationID = variation.id
    return resolution
  }

  func variationIngredientHighlights(
    for variation: RecipeVariation
  ) throws -> RecipeVariationIngredientHighlightResolution {
    #if DEBUG
      let clock = ContinuousClock()
      let start = clock.now
      defer {
        let duration = String(describing: start.duration(to: clock.now))
        AppLog.performance.log(
          "recipe-variation-highlights duration=\(duration, privacy: .public)"
        )
      }
    #endif
    let payload = try RecipeVariationPayload.decode(variation.deltas, variationID: variation.id)
    let resolution = try resolved(applying: variation)
    let baseLineIDs = Set(ingredientLines.map(\.id))
    var highlights = Dictionary(
      uniqueKeysWithValues: resolution.detail.ingredientLines
        .filter { !baseLineIDs.contains($0.id) }
        .map { ($0.id, RecipeVariationIngredientHighlight.added) }
    )

    for op in payload.ingredientOps {
      switch op {
      case .add:
        break
      case let .remove(reference):
        if let index = reference.index(in: ingredientLines) {
          highlights[ingredientLines[index].id] = .removed
        }
      case let .substitute(reference, _), let .scale(reference, _):
        if let index = reference.index(in: ingredientLines) {
          highlights[ingredientLines[index].id] = .changed
        }
      }
    }
    return RecipeVariationIngredientHighlightResolution(
      highlights: highlights,
      unresolvedAnchors: resolution.unresolvedAnchors
    )
  }
}

public struct RecipeVariationIngredientHighlightResolution: Equatable, Sendable {
  public var highlights: [IngredientLine.ID: RecipeVariationIngredientHighlight]
  public var unresolvedAnchors: [RecipeVariationUnresolvedAnchor]

  public init(
    highlights: [IngredientLine.ID: RecipeVariationIngredientHighlight],
    unresolvedAnchors: [RecipeVariationUnresolvedAnchor]
  ) {
    self.highlights = highlights
    self.unresolvedAnchors = unresolvedAnchors
  }
}

private func adjustmentContext(_ detail: RecipeDetailData) -> String {
  let ingredientLinesBySection = Dictionary(grouping: detail.ingredientLines) { $0.sectionID }
  var stepNumber = 1
  var lines: [String] = []
  lines.append("- Title: \(detail.recipe.title)")
  if let summary = detail.recipe.summary { lines.append("- Summary: \(summary)") }
  if let servings = detail.recipe.servingsText { lines.append("- Servings: \(servings)") }
  if let yield = detail.recipe.yieldText { lines.append("- Yield: \(yield)") }
  lines.append("Ingredients:")
  for section in detail.ingredientSections.sorted(by: { $0.sortOrder < $1.sortOrder }) {
    if let name = section.name { lines.append("- Section: \(name)") }
    for line in (ingredientLinesBySection[section.id] ?? []).sorted(by: { $0.sortOrder < $1.sortOrder }) {
      lines.append("  - id=\(line.id.uuidString) text=\(line.originalText)")
    }
  }
  lines.append("Instructions:")
  for group in detail.instructionGroups {
    if let name = group.name { lines.append("- Section: \(name)") }
    for step in group.steps {
      lines.append("  - id=\(step.id.uuidString) step=\(stepNumber) text=\(step.text)")
      stepNumber += 1
    }
  }
  return lines.joined(separator: "\n")
}

private func targetIngredientSection(
  named sectionName: String?,
  sections: inout [IngredientSection],
  recipeID: Recipe.ID,
  uuid: () -> UUID
) -> IngredientSection? {
  let sortedSections = sections.sorted { $0.sortOrder < $1.sortOrder }
  if let sectionName,
    let section = sortedSections.first(where: { $0.name?.caseInsensitiveCompare(sectionName) == .orderedSame })
  {
    return section
  }
  if let firstSection = sortedSections.first {
    return firstSection
  }
  let section = IngredientSection(id: uuid(), recipeID: recipeID, sortOrder: 0)
  sections.append(section)
  return section
}

private func newIngredientLine(
  _ text: String,
  recipeID: Recipe.ID,
  sectionID: IngredientSection.ID,
  sortOrder: Int,
  uuid: () -> UUID
) -> IngredientLine? {
  let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
  guard !trimmed.isEmpty else { return nil }
  var line = IngredientParser.lines(
    from: trimmed,
    recipeID: recipeID,
    sectionID: sectionID,
    uuid: uuid
  ).first ?? IngredientLine(
    id: uuid(),
    recipeID: recipeID,
    sectionID: sectionID,
    originalText: trimmed,
    sortOrder: sortOrder
  )
  line.sortOrder = sortOrder
  return line
}

private func nextIngredientSortOrder(in sectionID: IngredientSection.ID, lines: [IngredientLine]) -> Int {
  lines
    .filter { $0.sectionID == sectionID }
    .map(\.sortOrder)
    .max()
    .map { $0 + 1 }
    ?? 0
}

private func sortedIngredientLines(
  _ lines: [IngredientLine],
  sections: [IngredientSection]
) -> [IngredientLine] {
  let sectionSortOrders = Dictionary(uniqueKeysWithValues: sections.map { ($0.id, $0.sortOrder) })
  return lines.sorted { lhs, rhs in
    let lhsSectionSortOrder = sectionSortOrders[lhs.sectionID] ?? Int.max
    let rhsSectionSortOrder = sectionSortOrders[rhs.sectionID] ?? Int.max
    if lhsSectionSortOrder != rhsSectionSortOrder {
      return lhsSectionSortOrder < rhsSectionSortOrder
    }
    if lhs.sortOrder != rhs.sortOrder {
      return lhs.sortOrder < rhs.sortOrder
    }
    return lhs.id.uuidString < rhs.id.uuidString
  }
}

private func notesWithMethodNote(
  existing: [RecipeNote],
  methodNote: String?,
  recipeID: Recipe.ID,
  now: Date,
  uuid: () -> UUID
) -> [RecipeNote] {
  guard let methodNote = methodNote?.trimmingCharacters(in: .whitespacesAndNewlines), !methodNote.isEmpty else {
    return existing
  }
  return existing + [
    RecipeNote(id: uuid(), recipeID: recipeID, text: methodNote, noteType: .general, dateCreated: now, dateModified: now)
  ]
}

private struct VariationUUIDSequence {
  private let variationID: RecipeVariation.ID
  private var offset = 0

  init(variationID: RecipeVariation.ID) {
    self.variationID = variationID
  }

  mutating func next() -> UUID {
    defer { offset += 1 }
    return deterministicVariationUUID(variationID: variationID, offset: offset)
  }
}

private func deterministicVariationUUID(variationID: RecipeVariation.ID, offset: Int) -> UUID {
  let uuid = variationID.uuid
  var bytes = [
    uuid.0, uuid.1, uuid.2, uuid.3,
    uuid.4, uuid.5, uuid.6, uuid.7,
    uuid.8, uuid.9, uuid.10, uuid.11,
    uuid.12, uuid.13, uuid.14, uuid.15,
  ]
  var value = UInt64(offset)
  for index in stride(from: bytes.indices.upperBound - 1, through: bytes.indices.upperBound - 8, by: -1) {
    bytes[index] ^= UInt8(value & 0xff)
    value >>= 8
  }
  bytes[6] = (bytes[6] & 0x0f) | 0x50
  bytes[8] = (bytes[8] & 0x3f) | 0x80
  return UUID(uuid: (
    bytes[0], bytes[1], bytes[2], bytes[3],
    bytes[4], bytes[5], bytes[6], bytes[7],
    bytes[8], bytes[9], bytes[10], bytes[11],
    bytes[12], bytes[13], bytes[14], bytes[15]
  ))
}

private func variationName(_ name: String, fallback: String) -> String {
  name.nonEmptyAdjustmentText
    ?? fallback.nonEmptyAdjustmentText
    ?? "Variation"
}

/// A sibling can only be re-derived when each of its changed ingredient anchors
/// still exists in the promoted base. Recasting a lost substitution as an add
/// would preserve text while silently losing the stable-ID relationship.
private func unavailableIngredientAnchors(
  in variation: RecipeVariation,
  against newBase: RecipeDetailData
) throws -> [RecipeVariationUnrepresentableEdit] {
  let payload = try RecipeVariationPayload.decode(variation.deltas, variationID: variation.id)
  return payload.ingredientOps.compactMap { operation in
    let reference: RecipeIngredientReference?
    switch operation {
    case let .substitute(candidate, _), let .scale(candidate, _):
      reference = candidate
    case .add, .remove:
      reference = nil
    }
    guard let reference else { return nil }
    let anchorIsAvailable: Bool
    if let id = reference.id {
      anchorIsAvailable = newBase.ingredientLines.contains { $0.id == id }
    } else {
      anchorIsAvailable = reference.index(in: newBase.ingredientLines) != nil
    }
    return anchorIsAvailable ? nil : .ingredientLineAnchorUnavailable(reference.displayText)
  }
}

private func areActiveVariationsInDecreasingOrder(
  _ lhs: RecipeActiveVariation,
  _ rhs: RecipeActiveVariation
) -> Bool {
  if lhs.dateModified != rhs.dateModified {
    return lhs.dateModified > rhs.dateModified
  }
  return lhs.id.uuidString < rhs.id.uuidString
}

private extension IngredientLine {
  func replacingOriginalText(with text: String) -> IngredientLine {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    var replacement = IngredientParser.lines(
      from: trimmed,
      recipeID: recipeID,
      sectionID: sectionID,
      uuid: { id }
    ).first ?? IngredientLine(
      id: id,
      recipeID: recipeID,
      sectionID: sectionID,
      originalText: trimmed,
      sortOrder: sortOrder
    )
    replacement.sortOrder = sortOrder
    replacement.comment = comment
    replacement.shoppingCategory = shoppingCategory
    return replacement
  }
}

private extension RecipeChatMessage.Role {
  var adjustmentPromptLabel: String {
    switch self {
    case .user: "User"
    case .assistant: "Assistant"
    }
  }
}

private extension String {
  var nonEmptyAdjustmentText: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}

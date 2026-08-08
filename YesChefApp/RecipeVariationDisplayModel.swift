import Foundation
import SwiftUI
import YesChefCore

/// A run of ingredient lines under an optional section heading, for grouped detail display.
struct IngredientLineGroup: Identifiable {
  let id: IngredientSection.ID
  var name: String?
  var lines: [IngredientLineDisplay]
}

struct IngredientLineDisplay: Identifiable {
  var line: IngredientLine
  var highlight: RecipeVariationIngredientHighlight?

  var id: IngredientLine.ID { line.id }
}

/// How the active variation changed an instruction step, for the reader's overlay grammar
/// (ADR-0021 D3 — the base stays legible underneath, same as ingredient adds/removes).
enum InstructionStepHighlight {
  case inserted
  case removed
}

/// An instruction step as the reader shows it. A removed step is not in the resolved detail at all
/// — it is re-injected at its base position so the cook can see *what the variation drops*, which
/// is the ingredient list's grammar applied to the procedure (D3).
struct InstructionStepDisplay: Identifiable {
  var step: InstructionStep
  var highlight: InstructionStepHighlight?
  /// The cooking number. Nil for a removed step: it is shown for reference, not to be performed,
  /// so it must not consume a position in the sequence the cook follows.
  var number: Int?

  var id: InstructionStep.ID { step.id }
}

struct InstructionStepDisplayGroup: Identifiable {
  let id: InstructionSection.ID
  var name: String?
  var steps: [InstructionStepDisplay]
}

/// The one place the variation overlay's chip treatment is defined, so ingredient rows and
/// instruction rows cannot drift apart (they were hand-rolling the same literals).
enum VariationHighlightChip {
  static let added = Color.green.opacity(0.14)
  static let changed = Color.accentColor.opacity(0.12)
  static let removed = Color.secondary.opacity(0.10)
}

extension View {
  /// Wraps a row in the variation-overlay chip, or leaves it untouched when `color` is nil.
  func variationHighlightChip(_ color: Color?) -> some View {
    padding(.horizontal, color == nil ? 0 : 8)
      .padding(.vertical, color == nil ? 0 : 4)
      .background(color ?? .clear, in: RoundedRectangle(cornerRadius: 6))
  }
}

extension RecipeDetailModel {
  var recipe: Recipe? {
    detail?.recipe
  }

  var displayDetail: RecipeDetailData? {
    guard let detail else { return nil }
    guard let variation = detail.activeVariation else { return detail }
    return (try? detail.resolved(applying: variation).detail) ?? detail
  }

  var activeVariationUnresolvedAnchors: [RecipeVariationUnresolvedAnchor] {
    guard let detail, let variation = detail.activeVariation else { return [] }
    return (try? detail.resolved(applying: variation).unresolvedAnchors) ?? []
  }

  var activeVariation: RecipeVariation? {
    detail?.activeVariation
  }

  var relatedRecipes: [Recipe] {
    detail?.relatedRecipes ?? []
  }

  var activeVariationNote: String? {
    guard let note = activeVariation?.note?.trimmingCharacters(in: .whitespacesAndNewlines),
          !note.isEmpty
    else { return nil }
    return note
  }

  var ingredientLines: [IngredientLine] {
    displayDetail?.ingredientLines.sorted { $0.sortOrder < $1.sortOrder } ?? []
  }

  var ingredientLineDisplays: [IngredientLineDisplay] {
    displayIngredientLines(for: nil)
  }

  var ingredientGroups: [IngredientLineGroup] {
    guard let detail = displayDetail else { return [] }
    let linesBySection = Dictionary(grouping: detail.ingredientLines) { $0.sectionID }
    return detail.ingredientSections
      .sorted { $0.sortOrder < $1.sortOrder }
      .compactMap { section in
        let lines = displayIngredientLines(
          for: section.id,
          foldedLines: (linesBySection[section.id] ?? []).sorted { $0.sortOrder < $1.sortOrder }
        )
        guard !lines.isEmpty else { return nil }
        return IngredientLineGroup(id: section.id, name: section.name, lines: lines)
      }
  }

  var instructionGroups: [InstructionStepGroup] {
    displayDetail?.instructionGroups ?? []
  }

  /// The reader's instruction list under the active variation (Amd4-D4). Resolution already folded
  /// the inserted steps in and dropped the removed ones, so the two structural ops are read back off
  /// the difference between the base and resolved step sets — an insert is a resolved step the base
  /// never had, a remove is a base step resolution dropped. Removed steps are then spliced back in
  /// at their base position so the base procedure stays legible underneath the overlay (D3).
  var instructionStepDisplayGroups: [InstructionStepDisplayGroup] {
    guard let baseDetail = detail, baseDetail.activeVariation != nil, let displayDetail else {
      return instructionGroups.map { group in
        InstructionStepDisplayGroup(id: group.id, name: group.name, steps: numbered(group.steps.map {
          InstructionStepDisplay(step: $0, highlight: nil)
        }))
      }
    }

    let resolvedStepIDs = Set(displayDetail.instructionSteps.map(\.id))
    let baseStepIDs = Set(baseDetail.instructionSteps.map(\.id))
    let removedStepIDs = baseStepIDs.subtracting(resolvedStepIDs)
    let resolvedGroups = Dictionary(uniqueKeysWithValues: instructionGroups.map { ($0.id, $0) })
    let baseGroups = baseDetail.instructionGroups

    var groups: [InstructionStepDisplayGroup] = []
    var placedSectionIDs: Set<InstructionSection.ID> = []
    for baseGroup in baseGroups {
      placedSectionIDs.insert(baseGroup.id)
      let resolvedGroup = resolvedGroups[baseGroup.id]
      var displays = (resolvedGroup?.steps ?? []).map { step in
        InstructionStepDisplay(
          step: step,
          highlight: baseStepIDs.contains(step.id) ? nil : .inserted
        )
      }
      // Walk the base order and drop each removed step back in behind the last step still standing
      // ahead of it — a removed step then becomes the anchor for the next one, so a run of removals
      // keeps its original order.
      var anchorID: InstructionStep.ID?
      for step in baseGroup.steps {
        guard removedStepIDs.contains(step.id) else {
          anchorID = step.id
          continue
        }
        let index = anchorID
          .flatMap { id in displays.firstIndex { $0.id == id } }
          .map { $0 + 1 } ?? 0
        displays.insert(InstructionStepDisplay(step: step, highlight: .removed), at: index)
        anchorID = step.id
      }
      guard !displays.isEmpty else { continue }
      groups.append(
        InstructionStepDisplayGroup(
          id: baseGroup.id,
          name: resolvedGroup?.name ?? baseGroup.name,
          steps: numbered(displays)
        )
      )
    }
    // A section the base had no steps in can still receive an insert; it has no base group to merge.
    for group in instructionGroups where !placedSectionIDs.contains(group.id) {
      groups.append(
        InstructionStepDisplayGroup(id: group.id, name: group.name, steps: numbered(group.steps.map { step in
          InstructionStepDisplay(step: step, highlight: baseStepIDs.contains(step.id) ? nil : .inserted)
        }))
      )
    }
    return groups
  }

  /// Numbers the steps a cook actually performs; a removed step is skipped, not renumbered around.
  private func numbered(_ displays: [InstructionStepDisplay]) -> [InstructionStepDisplay] {
    var number = 0
    return displays.map { display in
      guard display.highlight != .removed else { return display }
      number += 1
      var display = display
      display.number = number
      return display
    }
  }

  var visibleNotes: [RecipeNote] {
    displayDetail?.notes.filter { $0.noteType != .retrospective } ?? []
  }

  private func displayIngredientLines(
    for sectionID: IngredientSection.ID?,
    foldedLines: [IngredientLine]? = nil
  ) -> [IngredientLineDisplay] {
    let foldedLines = foldedLines ?? ingredientLines
    guard
      let baseDetail = detail,
      let variation = baseDetail.activeVariation,
      let highlights = try? baseDetail.variationIngredientHighlights(for: variation).highlights
    else {
      return foldedLines.map { IngredientLineDisplay(line: $0, highlight: nil) }
    }

    var displays = foldedLines.map { line in
      IngredientLineDisplay(line: line, highlight: highlights[line.id])
    }
    let foldedLineIDs = Set(foldedLines.map(\.id))
    let removedLines = baseDetail.ingredientLines
      .filter { line in
        highlights[line.id] == .removed
          && !foldedLineIDs.contains(line.id)
          && (sectionID == nil || line.sectionID == sectionID)
      }
      .map { IngredientLineDisplay(line: $0, highlight: .removed) }
    displays.append(contentsOf: removedLines)
    return displays.sorted { lhs, rhs in
      if lhs.line.sortOrder != rhs.line.sortOrder {
        return lhs.line.sortOrder < rhs.line.sortOrder
      }
      return lhs.id.uuidString < rhs.id.uuidString
    }
  }
}

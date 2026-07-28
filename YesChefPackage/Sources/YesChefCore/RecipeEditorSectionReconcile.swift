import Foundation

/// Reconciles a `RecipeEditorDraft`'s per-section drafts against a recipe's persisted sections.
///
/// The editor now carries every ingredient and instruction section (ADR-0048's grain rule: the
/// affordance is a readout of storage, and storage here is rows). This turns each draft section into
/// the rows to upsert plus the identifiers to delete. Ingredient line identity is global to the recipe,
/// so a line may move between cards without being deleted and recreated. Orphan lines/steps whose section
/// row no longer exists are carried through untouched. An empty named ingredient section is kept; an empty
/// unnamed section is dropped.
enum RecipeEditorSectionReconcile {
  struct IngredientPlan: Equatable {
    /// Sections to upsert, in draft order with `sortOrder` assigned by position. Empty named sections kept.
    var sections: [IngredientSection]
    /// Reconciled lines to upsert, keyed by section id (kept sections only).
    var linesBySectionID: [IngredientSection.ID: [IngredientLine]]
    /// Existing sections the save must delete — removed from the draft, or now empty and unnamed.
    var removedSectionIDs: [IngredientSection.ID]
    /// Sections as they will exist after the save (for the original-snapshot capture).
    var snapshotSections: [IngredientSection]
    /// Lines as they will exist after the save: every kept line plus carried-through orphan lines.
    var snapshotLines: [IngredientLine]
  }

  struct InstructionPlan: Equatable {
    var sections: [InstructionSection]
    var stepsBySectionID: [InstructionSection.ID: [InstructionStep]]
    var removedSectionIDs: [InstructionSection.ID]
    var snapshotSections: [InstructionSection]
    var snapshotSteps: [InstructionStep]
  }

  static func ingredients(
    draftSections: [RecipeEditorIngredientSectionDraft],
    existingSections: [IngredientSection],
    existingLines: [IngredientLine],
    recipeID: Recipe.ID,
    uuid: () -> UUID
  ) -> IngredientPlan {
    var sections: [IngredientSection] = []
    var linesBySectionID: [IngredientSection.ID: [IngredientLine]] = [:]
    let existingLinesByID = Dictionary(uniqueKeysWithValues: existingLines.map { ($0.id, $0) })

    for (index, draftSection) in draftSections.enumerated() {
      let parsedLines = IngredientParser.lines(
        from: draftSection.text,
        recipeID: recipeID,
        sectionID: draftSection.id,
        uuid: uuid
      )
      let reconciled = reconcileIngredientLines(
        parsedLines,
        drafts: draftSection.lineDrafts,
        existingByID: existingLinesByID
      )
      guard !reconciled.isEmpty || draftSection.name.nonEmptySectionName != nil else { continue }
      sections.append(
        IngredientSection(
          id: draftSection.id,
          recipeID: recipeID,
          name: draftSection.name.nonEmptySectionName,
          sortOrder: index
        )
      )
      linesBySectionID[draftSection.id] = reconciled
    }

    let keptSectionIDs = Set(sections.map(\.id))
    let existingSectionIDs = Set(existingSections.map(\.id))
    let removedSectionIDs = existingSections.map(\.id).filter { !keptSectionIDs.contains($0) }
    let orphanLines = existingLines.filter {
      !existingSectionIDs.contains($0.sectionID) && !keptSectionIDs.contains($0.sectionID)
    }
    let snapshotLines = sections.flatMap { linesBySectionID[$0.id] ?? [] } + orphanLines

    return IngredientPlan(
      sections: sections,
      linesBySectionID: linesBySectionID,
      removedSectionIDs: removedSectionIDs,
      snapshotSections: sections,
      snapshotLines: snapshotLines
    )
  }

  static func instructions(
    draftSections: [RecipeEditorInstructionSectionDraft],
    existingSections: [InstructionSection],
    existingSteps: [InstructionStep],
    recipeID: Recipe.ID,
    uuid: () -> UUID
  ) -> InstructionPlan {
    var sections: [InstructionSection] = []
    var stepsBySectionID: [InstructionSection.ID: [InstructionStep]] = [:]
    let existingStepsBySection = Dictionary(grouping: existingSteps, by: \.sectionID)

    for (index, draftSection) in draftSections.enumerated() {
      let parsedSteps = InstructionParser.steps(
        from: draftSection.text,
        recipeID: recipeID,
        sectionID: draftSection.id,
        uuid: uuid
      )
      let reconciled = RecipeRepository.reconcileInstructionSteps(
        parsedSteps,
        existing: existingStepsBySection[draftSection.id] ?? []
      )
      guard !reconciled.isEmpty else { continue }
      sections.append(
        InstructionSection(
          id: draftSection.id,
          recipeID: recipeID,
          name: draftSection.name.nonEmptySectionName,
          sortOrder: index
        )
      )
      stepsBySectionID[draftSection.id] = reconciled
    }

    let keptSectionIDs = Set(sections.map(\.id))
    let existingSectionIDs = Set(existingSections.map(\.id))
    let removedSectionIDs = existingSections.map(\.id).filter { !keptSectionIDs.contains($0) }
    let orphanSteps = existingSteps.filter {
      !existingSectionIDs.contains($0.sectionID) && !keptSectionIDs.contains($0.sectionID)
    }
    let snapshotSteps = sections.flatMap { stepsBySectionID[$0.id] ?? [] } + orphanSteps

    return InstructionPlan(
      sections: sections,
      stepsBySectionID: stepsBySectionID,
      removedSectionIDs: removedSectionIDs,
      snapshotSections: sections,
      snapshotSteps: snapshotSteps
    )
  }
}

private extension String {
  /// A section name trimmed of surrounding whitespace, or `nil` when nothing remains — the persisted
  /// `name` column is nullable, and a blank field reads as "no name" (matching `save`'s prior behaviour).
  var nonEmptySectionName: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}

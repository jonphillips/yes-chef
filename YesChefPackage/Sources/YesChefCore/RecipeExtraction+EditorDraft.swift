import Foundation

extension RecipeExtraction {
  /// Builds the extraction core from a deterministically parsed page (ADR-0053's JSON-LD branch).
  /// The page already parsed durations to whole minutes, so they ride back as bare-number strings
  /// that `editorDraft`'s duration reader restores losslessly.
  init(page: ParsedRecipePage) {
    self.init(
      title: page.title,
      summary: page.summary,
      author: page.author,
      publisherName: page.publisherName,
      servingsText: page.servingsText,
      prepTime: page.prepTimeMinutes.map(String.init),
      cookTime: page.cookTimeMinutes.map(String.init),
      totalTime: page.totalTimeMinutes.map(String.init),
      cuisine: page.categoryNames
        .first { $0.hasPrefix("Cuisine > ") }
        .map { String($0.dropFirst("Cuisine > ".count)) },
      course: page.categoryNames.first { !$0.hasPrefix("Cuisine > ") },
      ingredientSections: page.ingredientSections.map { .init(name: $0.name, lines: $0.lines) },
      instructionSections: page.instructionSections.map { .init(name: $0.name, steps: $0.steps) },
      warnings: page.warnings
    )
  }

  /// Maps a faithful extraction onto the editor sink — the single terminal draft type every
  /// text→recipe path shares (ADR-0051 D1). Every named ingredient and instruction section is
  /// preserved, and colon-terminated heading syntax inside a section is promoted before save, exactly
  /// as the workbench-draft path does (`WorkbenchDraftRecipe.editorDraft`), so the repository receives
  /// stable per-line identity. Fidelity only: no field is invented here — a missing value stays empty
  /// (ADR-0053 D7).
  public func editorDraft(uuid: () -> UUID) -> RecipeEditorDraft {
    var draft = RecipeEditorDraft(
      title: title ?? "",
      summary: summary ?? "",
      sourceAuthor: author ?? "",
      sourcePublicationName: publisherName ?? "",
      servingsText: servingsText ?? "",
      prepTimeMinutes: prepTime.flatMap(RecipeDurationParser.minutes) ?? 0,
      cookTimeMinutes: cookTime.flatMap(RecipeDurationParser.minutes) ?? 0,
      cuisine: cuisine ?? "",
      course: course ?? ""
    )

    // The model already segmented ingredients and instructions; the sink's save path re-derives steps
    // and lines by splitting the flat text on *every* newline (`InstructionParser`, `ingredientTextChanged`).
    // So each item is flattened to a single line first — otherwise an internal line break inside one
    // model step or line would explode into several, inflating the numbered steps. One model item stays
    // one saved item.
    let ingredientDrafts = ingredientSections.map { section in
      RecipeEditorIngredientSectionDraft(
        id: uuid(),
        name: section.name ?? "",
        text: section.lines.map(Self.singleLine).joined(separator: "\n")
      )
    }
    draft.ingredientSections = ingredientDrafts.isEmpty
      ? [RecipeEditorIngredientSectionDraft(id: uuid())]
      : ingredientDrafts

    let instructionDrafts = instructionSections.map { section in
      RecipeEditorInstructionSectionDraft(
        id: uuid(),
        name: section.name ?? "",
        text: section.steps.map(Self.singleLine).joined(separator: "\n\n")
      )
    }
    draft.instructionSections = instructionDrafts.isEmpty
      ? [RecipeEditorInstructionSectionDraft(id: uuid())]
      : instructionDrafts

    for sectionID in draft.ingredientSections.map(\.id) {
      _ = draft.ingredientTextChanged(sectionID: sectionID, uuid: uuid)
    }
    return draft
  }

  /// Collapses any internal line breaks in a single extracted step or ingredient line to spaces, so the
  /// sink's newline-splitting save path preserves the model's segmentation (one item = one saved item)
  /// rather than re-splitting a paragraph-shaped step into several numbered ones.
  static func singleLine(_ text: String) -> String {
    text
      .split(whereSeparator: \.isNewline)
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
      .joined(separator: " ")
  }

}

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
      ingredientSections: page.ingredientSections.map { .init(name: $0.name, lines: $0.lines) },
      instructionSections: page.instructionSections.map { .init(name: $0.name, steps: $0.steps) }
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
      prepTimeMinutes: Self.minutes(from: prepTime) ?? 0,
      cookTimeMinutes: Self.minutes(from: cookTime) ?? 0
    )

    let ingredientDrafts = ingredientSections.map { section in
      RecipeEditorIngredientSectionDraft(
        id: uuid(),
        name: section.name ?? "",
        text: section.lines.joined(separator: "\n")
      )
    }
    draft.ingredientSections = ingredientDrafts.isEmpty
      ? [RecipeEditorIngredientSectionDraft(id: uuid())]
      : ingredientDrafts

    let instructionDrafts = instructionSections.map { section in
      RecipeEditorInstructionSectionDraft(
        id: uuid(),
        name: section.name ?? "",
        text: section.steps.joined(separator: "\n\n")
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

  /// Reads whole minutes from the varied duration shapes the two front-ends emit: an ISO-8601 duration
  /// (`PT1H30M`, common in schema.org JSON-LD), a spelled-out span (`1 hr 30 min`), or a bare number of
  /// minutes (how the JSON-LD branch re-encodes an already-parsed page time). Returns nil when nothing
  /// numeric is present, leaving the draft's time at zero rather than guessing.
  static func minutes(from text: String?) -> Int? {
    guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
      return nil
    }
    if let iso = iso8601Minutes(text) { return iso }

    let lowercased = text.lowercased()
    let hours = firstNumber(#"(\d+(?:\.\d+)?)\s*(?:hours?|hrs?|hr|h)\b"#, in: lowercased) ?? 0
    let minutes = firstNumber(#"(\d+(?:\.\d+)?)\s*(?:minutes?|mins?|min|m)\b"#, in: lowercased) ?? 0
    let total = hours * 60 + minutes
    if total > 0 { return Int(total.rounded()) }

    return firstNumber(#"^\s*(\d+(?:\.\d+)?)\s*$"#, in: lowercased).map { Int($0.rounded()) }
  }

  private static func iso8601Minutes(_ text: String) -> Int? {
    let upper = text.uppercased()
    guard upper.hasPrefix("PT") else { return nil }
    let hours = firstNumber(#"(\d+(?:\.\d+)?)\s*H"#, in: upper) ?? 0
    let minutes = firstNumber(#"(\d+(?:\.\d+)?)\s*M"#, in: upper) ?? 0
    let total = hours * 60 + minutes
    return total > 0 ? Int(total.rounded()) : nil
  }

  private static func firstNumber(_ pattern: String, in text: String) -> Double? {
    guard
      let range = text.range(of: pattern, options: .regularExpression)
    else { return nil }
    // Pull the leading numeric run out of the matched slice.
    let matched = String(text[range])
    guard let numberRange = matched.range(of: #"\d+(?:\.\d+)?"#, options: .regularExpression) else {
      return nil
    }
    return Double(matched[numberRange])
  }
}

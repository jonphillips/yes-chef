import Foundation

/// The staged review for an outboarded workbench **draft** return (ADR-0042 Amendment 2, S3b).
///
/// The return is *extraction, not synthesis*: the editorial choice already happened in the external
/// thread, and what comes back is text that already **is** a recipe — a schema.org `Recipe` JSON-LD
/// block (parsed for free by the deterministic `RecipeJSONLDExtractor`) plus a separate prose
/// rationale block. This carries the parsed draft into the *existing* workbench draft review + promote
/// path; nothing here re-runs synthesis, and no new parser is introduced.
public struct AIHandoffWorkbenchDraftReview: Equatable, Sendable {
  public let handoffID: AIHandoff.ID
  public let workbenchID: Workbench.ID
  public let draftRecipe: WorkbenchDraftRecipe
  /// Argument residue — candidates considered and rejected, or constraints on the dish (Amd2-D6).
  /// Combines bulleted and naked-sentence learning lines so nothing is silently dropped.
  public let learnings: [String]

  public init(
    handoffID: AIHandoff.ID,
    workbenchID: Workbench.ID,
    draftRecipe: WorkbenchDraftRecipe,
    learnings: [String]
  ) {
    self.handoffID = handoffID
    self.workbenchID = workbenchID
    self.draftRecipe = draftRecipe
    self.learnings = learnings
  }
}

extension AIHandoffReturn {
  public struct WorkbenchDraftReturn: Equatable, Sendable {
    /// `nil` when the outboard declined to draft (empty JSON-LD, or a block with no title and no
    /// ingredients or instructions) — the import route degrades that to a loud "no draft returned"
    /// rather than promoting an empty recipe into review (ADR-0042 Amd 2, the declined-draft contract).
    public var draftRecipe: WorkbenchDraftRecipe?
    public var learnings: [String]

    public init(draftRecipe: WorkbenchDraftRecipe?, learnings: [String]) {
      self.draftRecipe = draftRecipe
      self.learnings = learnings
    }
  }

  public static func workbenchDraft(from text: String, capturedAt: Date) -> WorkbenchDraftReturn {
    let split = plainText(from: text)
    let parts = splittingJSONLDAndRationale(split.deliverable)
    let draftRecipe = WorkbenchDraftRecipe.fromJSONLD(
      parts.jsonLD,
      rationale: parts.rationale,
      capturedAt: capturedAt
    )
    // The learnings section may arrive bulleted or as naked sentences; keep both so argument
    // residue is deposited losslessly rather than dropped to `unparsedLines`. NOTE: this is a
    // verb-local patch of the known `learningBullets` floor bug (it drops naked-sentence learnings
    // to `unparsedLines`). It diverges from every other verb and reorders (bullets first, naked
    // lines appended). When the global floor fix lands in `learningBullets`/`plainText`, fold this
    // back and drop the local combine.
    let learnings = split.learnings + split.unparsedLines
    return WorkbenchDraftReturn(draftRecipe: draftRecipe, learnings: learnings)
  }

  /// Split the deliverable into the JSON-LD object and the rationale prose. The JSON block is found
  /// by brace-depth from the first `{` (robust to the curly-quote mangling the paste path introduces,
  /// since it does not depend on string delimiters). The rationale is whichever of the text *after*
  /// or *before* the block is non-empty (models sometimes write the rationale first), so neither is
  /// silently dropped; a leading Markdown code fence and a `Rationale:` label are stripped.
  static func splittingJSONLDAndRationale(_ deliverable: String) -> (jsonLD: String, rationale: String) {
    guard let start = deliverable.firstIndex(of: "{") else {
      return ("", rationale(from: deliverable))
    }
    var depth = 0
    var close: String.Index?
    var index = start
    while index < deliverable.endIndex {
      switch deliverable[index] {
      case "{": depth += 1
      case "}":
        depth -= 1
        if depth == 0 { close = index }
      default: break
      }
      if close != nil { break }
      index = deliverable.index(after: index)
    }
    guard let close else {
      return (String(deliverable[start...]), rationale(from: String(deliverable[..<start])))
    }
    let jsonLD = String(deliverable[start...close])
    let after = rationale(from: String(deliverable[deliverable.index(after: close)...]))
    let before = rationale(from: String(deliverable[..<start]))
    return (jsonLD, after.isEmpty ? before : after)
  }

  /// Normalize a rationale candidate: drop Markdown code-fence lines (models fence JSON reflexively,
  /// leaving a stray ``` outside the block), then strip a leading `Rationale:` label.
  private static func rationale(from text: String) -> String {
    let defenced = text
      .components(separatedBy: .newlines)
      .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("```") }
      .joined(separator: "\n")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard let labelRange = defenced.range(of: "Rationale:", options: [.caseInsensitive, .anchored]) else {
      return defenced
    }
    return String(defenced[labelRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

extension WorkbenchDraftRecipe {
  /// Map a schema.org `Recipe` JSON-LD block to the pre-canonical draft, reusing the capture
  /// pipeline's deterministic extractor (ADR-0042 Amd2-D2/D3). Returns `nil` only when the block
  /// yields **no ingredients and no instructions** — the ADR's declined-draft test, which the caller
  /// makes loud. A missing rationale is *not* a decline; it stages as an empty field.
  ///
  /// Ingredient group headings are preserved: when the extractor sections the ingredients under
  /// names, those names are re-inlined as colon-terminated heading lines (the form the editor reads
  /// back via `IngredientSectionHeading`), so nothing is silently dropped (ADR-0040 lossless). Named
  /// `HowToSection` instruction groups carry as typed draft sections into the editor. `capturedAt` is
  /// provenance only.
  static func fromJSONLD(_ jsonLD: String, rationale: String, capturedAt: Date) -> WorkbenchDraftRecipe? {
    let trimmed = jsonLD.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    var builder = RecipeParseBuilder(sourceURL: nil, originalHTML: "")
    RecipeJSONLDExtractor.extract(fromJSONLD: trimmed, into: &builder)
    let page = builder.build(capturedAt: capturedAt)

    let title = page.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let instructionSections = page.instructionSections.map {
      WorkbenchDraftInstructionSection(name: $0.name, steps: $0.steps)
    }
    let (ingredientLines, ingredientSectionName) = flattenedIngredients(page.ingredientSections)
    guard !ingredientLines.isEmpty || !instructionSections.flatMap(\.steps).isEmpty else { return nil }

    let cuisinePrefix = "Cuisine > "
    let cuisine = page.categoryNames
      .first { $0.hasPrefix(cuisinePrefix) }
      .map { String($0.dropFirst(cuisinePrefix.count)) }
    let course = page.categoryNames.first { !$0.hasPrefix(cuisinePrefix) }

    return WorkbenchDraftRecipe(
      title: title,
      summary: page.summary,
      servingsText: page.servingsText,
      prepTimeMinutes: page.prepTimeMinutes,
      cookTimeMinutes: page.cookTimeMinutes,
      cuisine: cuisine,
      course: course,
      ingredientSectionName: ingredientSectionName,
      ingredientLines: ingredientLines,
      instructionSections: instructionSections,
      notes: [],
      rationale: rationale
    )
  }

  /// A single named section keeps its name in `ingredientSectionName`. Multiple sections re-inline
  /// each name as a `Name:` heading line so the editor reconstructs the groups on promote, rather
  /// than the cook silently losing them.
  private static func flattenedIngredients(
    _ sections: [ParsedRecipeIngredientSection]
  ) -> (lines: [String], sectionName: String?) {
    let named = sections.filter { !($0.name ?? "").isEmpty }
    guard named.count > 1 || (named.count == 1 && sections.count > 1) else {
      return (sections.flatMap(\.lines), sections.count == 1 ? sections.first?.name : nil)
    }
    let lines = sections.flatMap { section -> [String] in
      guard let name = section.name, !name.isEmpty else { return section.lines }
      return ["\(name):"] + section.lines
    }
    return (lines, nil)
  }
}

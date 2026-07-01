import Foundation

public struct ParsedRecipeIngredientSection: Equatable, Sendable {
  public var name: String?
  public var lines: [String]

  public init(name: String? = nil, lines: [String]) {
    self.name = name
    self.lines = lines
  }
}

public struct ParsedRecipeInstructionSection: Equatable, Sendable {
  public var name: String?
  public var steps: [String]

  public init(name: String? = nil, steps: [String]) {
    self.name = name
    self.steps = steps
  }
}

public struct ParsedRecipeEditorialBlock: Equatable, Sendable {
  public var label: String
  public var text: String

  public init(label: String, text: String) {
    self.label = label.trimmingCharacters(in: .whitespacesAndNewlines)
    self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  public var noteText: String {
    "\(label)\n\n\(text)"
  }
}

public enum WebRecipeCaptureWarning: String, Equatable, Sendable {
  case noStructuredRecipeData
  case truncatedStructuredData
  case untitledRecipe
  case noIngredients
  case noInstructions
}

public struct ParsedRecipePage: Equatable, Sendable {
  public var sourceURL: URL?
  public var title: String?
  public var titleIsStructured: Bool
  public var summary: String?
  public var author: String?
  public var publisherName: String?
  public var servingsText: String?
  public var prepTimeMinutes: Int?
  public var cookTimeMinutes: Int?
  public var totalTimeMinutes: Int?
  public var rating: Int?
  public var categoryNames: [String]
  public var ingredientSections: [ParsedRecipeIngredientSection]
  public var instructionSections: [ParsedRecipeInstructionSection]
  public var editorialBlocks: [ParsedRecipeEditorialBlock]
  public var imageURLs: [URL]
  public var processedImages: [URL: ProcessedRecipePhoto]
  public var schemaTypes: [String]
  public var capturedAt: Date
  public var textExcerpt: String?
  public var bodyText: String?
  public var originalHTML: String
  public var warnings: [WebRecipeCaptureWarning]

  public init(
    sourceURL: URL? = nil,
    title: String? = nil,
    titleIsStructured: Bool = false,
    summary: String? = nil,
    author: String? = nil,
    publisherName: String? = nil,
    servingsText: String? = nil,
    prepTimeMinutes: Int? = nil,
    cookTimeMinutes: Int? = nil,
    totalTimeMinutes: Int? = nil,
    rating: Int? = nil,
    categoryNames: [String] = [],
    ingredientSections: [ParsedRecipeIngredientSection] = [],
    instructionSections: [ParsedRecipeInstructionSection] = [],
    editorialBlocks: [ParsedRecipeEditorialBlock] = [],
    imageURLs: [URL] = [],
    processedImages: [URL: ProcessedRecipePhoto] = [:],
    schemaTypes: [String] = [],
    capturedAt: Date = Date(),
    textExcerpt: String? = nil,
    bodyText: String? = nil,
    originalHTML: String = "",
    warnings: [WebRecipeCaptureWarning] = []
  ) {
    self.sourceURL = sourceURL
    self.title = title
    self.titleIsStructured = titleIsStructured
    self.summary = summary
    self.author = author
    self.publisherName = publisherName
    self.servingsText = servingsText
    self.prepTimeMinutes = prepTimeMinutes
    self.cookTimeMinutes = cookTimeMinutes
    self.totalTimeMinutes = totalTimeMinutes
    self.rating = rating
    self.categoryNames = categoryNames
    self.ingredientSections = ingredientSections
    self.instructionSections = instructionSections
    self.editorialBlocks = editorialBlocks
    self.imageURLs = imageURLs
    self.processedImages = processedImages
    self.schemaTypes = schemaTypes
    self.capturedAt = capturedAt
    self.textExcerpt = textExcerpt
    self.bodyText = bodyText
    self.originalHTML = originalHTML
    self.warnings = warnings
  }

  public var isEmpty: Bool {
    title == nil
      && summary == nil
      && author == nil
      && publisherName == nil
      && servingsText == nil
      && prepTimeMinutes == nil
      && cookTimeMinutes == nil
      && totalTimeMinutes == nil
      && rating == nil
      && categoryNames.isEmpty
      && ingredientSections.allSatisfy(\.lines.isEmpty)
      && instructionSections.allSatisfy(\.steps.isEmpty)
      && imageURLs.isEmpty
      && schemaTypes.isEmpty
  }

  public func makeRecipeBundle(
    now: Date,
    uuid: () -> UUID,
    preserveRawImportHTML: Bool = false
  ) throws -> RecipeBundleCoding.RecipeBundle {
    let recipeID = uuid()
    let ingredientSections = makeIngredientSections(recipeID: recipeID, uuid: uuid)
    let ingredientLines = makeIngredientLines(recipeID: recipeID, sections: ingredientSections, uuid: uuid)
    let instructionSections = makeInstructionSections(recipeID: recipeID, uuid: uuid)
    let instructionSteps = makeInstructionSteps(recipeID: recipeID, sections: instructionSections, uuid: uuid)
    let recipeNotes = makeRecipeNotes(recipeID: recipeID, now: now, uuid: uuid)
    let photos = imageURLs.enumerated().map { index, url in
      let photoID = uuid()
      let processedImage = processedImages[url]
      return RecipePhoto(
        id: photoID,
        recipeID: recipeID,
        imageDataReference: "recipePhotos/\(photoID.uuidString)",
        displayData: processedImage?.displayData,
        thumbnailData: processedImage?.thumbnailData,
        mediaType: processedImage?.mediaType,
        pixelWidth: processedImage?.pixelWidth,
        pixelHeight: processedImage?.pixelHeight,
        sourceURL: url.absoluteString,
        checksum: processedImage?.checksum,
        kind: index == 0 ? .hero : .gallery,
        source: .extracted,
        sortOrder: index,
        dateCreated: now
      )
    }
    let source = makeSource(recipeID: recipeID, now: now, uuid: uuid)
    var recipe = Recipe(
      id: recipeID,
      title: title?.nonEmpty ?? "Untitled Recipe",
      summary: summary?.nonEmpty,
      servings: servingsText.flatMap(ServingParser.servings),
      servingsText: servingsText?.nonEmpty,
      prepTimeMinutes: prepTimeMinutes,
      cookTimeMinutes: cookTimeMinutes,
      totalTimeMinutes: totalTimeMinutes ?? Self.totalTime(prep: prepTimeMinutes, cook: cookTimeMinutes),
      rating: rating,
      dateCreated: now,
      dateModified: now,
      originalImportText: preserveRawImportHTML ? originalHTML : nil
    )
    recipe.originalSnapshot = try RecipeBundleCoding.snapshotData(
      recipe: recipe,
      source: source,
      ingredientSections: ingredientSections,
      ingredientLines: ingredientLines,
      instructionSections: instructionSections,
      instructionSteps: instructionSteps,
      notes: recipeNotes,
      tagNames: [],
      categoryNames: categoryNames,
      photos: photos
    )

    return RecipeBundleCoding.RecipeBundle(
      recipe: recipe,
      source: source,
      ingredientSections: ingredientSections,
      ingredientLines: ingredientLines,
      instructionSections: instructionSections,
      instructionSteps: instructionSteps,
      recipeNotes: recipeNotes,
      photos: photos,
      tagNames: [],
      categoryNames: categoryNames
    )
  }

  private func makeIngredientSections(
    recipeID: Recipe.ID,
    uuid: () -> UUID
  ) -> [IngredientSection] {
    ingredientSections
      .filter { !$0.lines.isEmpty }
      .enumerated()
      .map { index, section in
        IngredientSection(id: uuid(), recipeID: recipeID, name: section.name?.nonEmpty, sortOrder: index)
      }
  }

  private func makeIngredientLines(
    recipeID: Recipe.ID,
    sections: [IngredientSection],
    uuid: () -> UUID
  ) -> [IngredientLine] {
    var lines: [IngredientLine] = []
    var globalOrder = 0
    for (index, parsedSection) in ingredientSections.filter({ !$0.lines.isEmpty }).enumerated() {
      guard sections.indices.contains(index) else { continue }
      let sectionID = sections[index].id
      for text in parsedSection.lines {
        let parsed = IngredientParser.parse(text)
        lines.append(
          IngredientLine(
            id: uuid(),
            recipeID: recipeID,
            sectionID: sectionID,
            originalText: text,
            quantity: parsed.quantity,
            quantityText: parsed.quantityText,
            unit: parsed.unit,
            item: parsed.item,
            preparation: parsed.preparation,
            isOptional: text.localizedCaseInsensitiveContains("optional"),
            doNotShop: false,
            isHeader: false,
            sortOrder: globalOrder,
            confidence: parsed.quantity == nil ? .low : .medium
          )
        )
        globalOrder += 1
      }
    }
    return lines
  }

  private func makeInstructionSections(
    recipeID: Recipe.ID,
    uuid: () -> UUID
  ) -> [InstructionSection] {
    instructionSections
      .filter { !$0.steps.isEmpty }
      .enumerated()
      .map { index, section in
        InstructionSection(id: uuid(), recipeID: recipeID, name: section.name?.nonEmpty, sortOrder: index)
      }
  }

  private func makeInstructionSteps(
    recipeID: Recipe.ID,
    sections: [InstructionSection],
    uuid: () -> UUID
  ) -> [InstructionStep] {
    var steps: [InstructionStep] = []
    var globalOrder = 0
    for (index, parsedSection) in instructionSections.filter({ !$0.steps.isEmpty }).enumerated() {
      guard sections.indices.contains(index) else { continue }
      let sectionID = sections[index].id
      for text in parsedSection.steps {
        steps.append(
          InstructionStep(id: uuid(), recipeID: recipeID, sectionID: sectionID, text: text, sortOrder: globalOrder)
        )
        globalOrder += 1
      }
    }
    return steps
  }

  private func makeRecipeNotes(
    recipeID: Recipe.ID,
    now: Date,
    uuid: () -> UUID
  ) -> [RecipeNote] {
    editorialBlocks
      .map { ParsedRecipeEditorialBlock(label: $0.label, text: $0.text) }
      .filter { !$0.text.isEmpty }
      .enumerated()
      .map { index, block in
        let createdAt = now.addingTimeInterval(TimeInterval(index))
        return RecipeNote(
          id: uuid(),
          recipeID: recipeID,
          text: block.noteText,
          dateCreated: createdAt,
          dateModified: createdAt
        )
      }
  }

  private func makeSource(
    recipeID: Recipe.ID,
    now: Date,
    uuid: () -> UUID
  ) -> RecipeSource? {
    let sourceURL = sourceURL?.absoluteString.nonEmpty
    let name = RecipeSourceNameNormalizer.name(importedName: publisherName, url: sourceURL)
    guard name != nil || sourceURL != nil || author?.nonEmpty != nil else { return nil }
    return RecipeSource(
      id: uuid(),
      recipeID: recipeID,
      name: name,
      url: sourceURL,
      author: author?.nonEmpty,
      importedFrom: "Web Recipe Capture",
      dateImported: now
    )
  }

  private static func totalTime(prep: Int?, cook: Int?) -> Int? {
    switch (prep, cook) {
    case let (prep?, cook?): prep + cook
    case let (prep?, nil): prep
    case let (nil, cook?): cook
    case (nil, nil): nil
    }
  }
}

private extension String {
  var nonEmpty: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}

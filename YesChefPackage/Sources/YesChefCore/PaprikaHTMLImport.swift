import Foundation

public enum PaprikaHTMLImportError: Error, Equatable, Sendable {
  case missingRecipesDirectory(String)
}

public struct PaprikaHTMLImportResult: Equatable, Sendable {
  public var recipes: [PaprikaHTMLRecipe]
  public var warnings: [PaprikaHTMLImportWarning]

  public init(
    recipes: [PaprikaHTMLRecipe],
    warnings: [PaprikaHTMLImportWarning] = []
  ) {
    self.recipes = recipes
    self.warnings = warnings
  }
}

public struct PaprikaHTMLImportWarning: Equatable, Sendable {
  public enum Kind: String, Equatable, Sendable {
    case missingRecipePages
    case missingPhoto
    case unreadableRecipe
  }

  public var kind: Kind
  public var path: String?
  public var message: String
  public var affectedCount: Int?
  public var examples: [String]

  public init(
    kind: Kind,
    path: String? = nil,
    message: String,
    affectedCount: Int? = nil,
    examples: [String] = []
  ) {
    self.kind = kind
    self.path = path
    self.message = message
    self.affectedCount = affectedCount
    self.examples = examples
  }
}

public struct PaprikaHTMLRecipe: Equatable, Sendable {
  public var title: String
  public var summary: String?
  public var servingsText: String?
  public var prepTimeMinutes: Int?
  public var cookTimeMinutes: Int?
  public var totalTimeMinutes: Int?
  public var rating: Int?
  public var difficulty: RecipeDifficulty?
  public var sourceName: String?
  public var sourceURL: String?
  public var categoryNames: [String]
  public var ingredients: [String]
  public var instructions: [String]
  public var notes: [String]
  public var photos: [PaprikaHTMLPhotoReference]
  public var originalHTML: String

  public init(
    title: String,
    summary: String? = nil,
    servingsText: String? = nil,
    prepTimeMinutes: Int? = nil,
    cookTimeMinutes: Int? = nil,
    totalTimeMinutes: Int? = nil,
    rating: Int? = nil,
    difficulty: RecipeDifficulty? = nil,
    sourceName: String? = nil,
    sourceURL: String? = nil,
    categoryNames: [String] = [],
    ingredients: [String] = [],
    instructions: [String] = [],
    notes: [String] = [],
    photos: [PaprikaHTMLPhotoReference] = [],
    originalHTML: String
  ) {
    self.title = title
    self.summary = summary
    self.servingsText = servingsText
    self.prepTimeMinutes = prepTimeMinutes
    self.cookTimeMinutes = cookTimeMinutes
    self.totalTimeMinutes = totalTimeMinutes
    self.rating = rating
    self.difficulty = difficulty
    self.sourceName = sourceName
    self.sourceURL = sourceURL
    self.categoryNames = categoryNames
    self.ingredients = ingredients
    self.instructions = instructions
    self.notes = notes
    self.photos = photos
    self.originalHTML = originalHTML
  }

  public func makeRecipeBundle(
    now: Date,
    uuid: () -> UUID
  ) throws -> RecipeBundleCoding.RecipeBundle {
    let recipeID = uuid()

    var ingredientSections: [IngredientSection] = []
    var ingredientLines: [IngredientLine] = []
    for (index, group) in IngredientSectionHeading.sections(in: ingredients).enumerated() {
      let sectionID = uuid()
      ingredientSections.append(
        IngredientSection(id: sectionID, recipeID: recipeID, name: group.name?.nonEmpty, sortOrder: index)
      )
      let sortOffset = ingredientLines.count
      ingredientLines.append(
        contentsOf: IngredientParser.lines(
          from: group.lines.joined(separator: "\n"),
          recipeID: recipeID,
          sectionID: sectionID,
          uuid: uuid
        )
        .map { line in
          var line = line
          line.sortOrder += sortOffset
          return line
        }
      )
    }

    let instructionSectionID = uuid()
    let instructionSections = instructions.isEmpty
      ? []
      : [InstructionSection(id: instructionSectionID, recipeID: recipeID, sortOrder: 0)]
    let instructionSteps = instructions.enumerated().map { index, text in
      InstructionStep(
        id: uuid(),
        recipeID: recipeID,
        sectionID: instructionSectionID,
        text: text,
        sortOrder: index
      )
    }
    let recipeNotes = notes.enumerated().map { index, text in
      RecipeNote(
        id: uuid(),
        recipeID: recipeID,
        text: text,
        dateCreated: now.addingTimeInterval(TimeInterval(index)),
        dateModified: now.addingTimeInterval(TimeInterval(index))
      )
    }
    let recipePhotos = photos
      .filter(\.isAvailable)
      .enumerated()
      .map { index, photo in
        let photoID = uuid()
        return RecipePhoto(
          id: photoID,
          recipeID: recipeID,
          imageDataReference: "recipePhotos/\(photoID.uuidString)",
          displayData: photo.displayData,
          thumbnailData: photo.thumbnailData,
          mediaType: photo.mediaType,
          pixelWidth: photo.pixelWidth,
          pixelHeight: photo.pixelHeight,
          originalSourcePath: photo.path,
          checksum: photo.checksum,
          kind: photo.kind,
          caption: photo.caption,
          source: .imported,
          sortOrder: index,
          dateCreated: now
        )
      }
    let normalizedSourceName = RecipeSourceNameNormalizer.name(
      importedName: sourceName,
      url: sourceURL
    )
    let source = normalizedSourceName != nil || sourceURL?.nonEmpty != nil
      ? RecipeSource(
        id: uuid(),
        recipeID: recipeID,
        name: normalizedSourceName,
        url: sourceURL?.nonEmpty,
        importedFrom: "Paprika HTML",
        dateImported: now
      )
      : nil
    var recipe = Recipe(
      id: recipeID,
      title: title.nonEmpty ?? "Untitled Recipe",
      summary: summary?.nonEmpty,
      servings: servingsText.flatMap(ServingParser.servings),
      servingsText: servingsText?.nonEmpty,
      prepTimeMinutes: prepTimeMinutes,
      cookTimeMinutes: cookTimeMinutes,
      totalTimeMinutes: totalTimeMinutes ?? Self.totalTime(prep: prepTimeMinutes, cook: cookTimeMinutes),
      difficulty: difficulty,
      rating: rating,
      dateCreated: now,
      dateModified: now,
      originalImportText: originalHTML
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
      photos: recipePhotos
    )

    return RecipeBundleCoding.RecipeBundle(
      recipe: recipe,
      source: source,
      ingredientSections: ingredientSections,
      ingredientLines: ingredientLines,
      instructionSections: instructionSections,
      instructionSteps: instructionSteps,
      recipeNotes: recipeNotes,
      photos: recipePhotos,
      tagNames: [],
      categoryNames: categoryNames
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

public struct PaprikaHTMLPhotoReference: Equatable, Sendable {
  public var path: String
  public var caption: String?
  public var isAvailable: Bool
  public var displayData: Data?
  public var thumbnailData: Data?
  public var mediaType: String?
  public var pixelWidth: Int?
  public var pixelHeight: Int?
  public var checksum: String?
  public var kind: RecipePhotoKind

  public init(
    path: String,
    caption: String? = nil,
    isAvailable: Bool,
    displayData: Data? = nil,
    thumbnailData: Data? = nil,
    mediaType: String? = nil,
    pixelWidth: Int? = nil,
    pixelHeight: Int? = nil,
    checksum: String? = nil,
    kind: RecipePhotoKind = .gallery
  ) {
    self.path = path
    self.caption = caption
    self.isAvailable = isAvailable
    self.displayData = displayData
    self.thumbnailData = thumbnailData
    self.mediaType = mediaType
    self.pixelWidth = pixelWidth
    self.pixelHeight = pixelHeight
    self.checksum = checksum
    self.kind = kind
  }
}

public enum PaprikaHTMLImporter {
  public static func parseExport(
    at exportURL: URL,
    fileManager: FileManager = .default
  ) throws -> PaprikaHTMLImportResult {
    let recipesDirectory = exportURL.appendingPathComponent("Recipes", isDirectory: true)
    guard fileManager.fileExists(atPath: recipesDirectory.path) else {
      throw PaprikaHTMLImportError.missingRecipesDirectory(recipesDirectory.path)
    }

    var warnings: [PaprikaHTMLImportWarning] = []
    let recipeURLs = try fileManager
      .contentsOfDirectory(
        at: recipesDirectory,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
      )
      .filter { url in
        (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
          && url.pathExtension.localizedCaseInsensitiveCompare("html") == .orderedSame
      }
      .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

    let indexURL = exportURL.appendingPathComponent("index.html")
    if
      fileManager.fileExists(atPath: indexURL.path),
      let indexHTML = try? String(contentsOf: indexURL, encoding: .utf8)
    {
      let availableFiles = Set(recipeURLs.map(\.lastPathComponent))
      let missingLinks = Self.indexRecipeLinks(from: indexHTML)
        .filter { !availableFiles.contains($0.fileName) }
      if !missingLinks.isEmpty {
        warnings.append(
          PaprikaHTMLImportWarning(
            kind: .missingRecipePages,
            path: indexURL.path,
            message: "The Paprika index references recipe pages that are not present in this export folder.",
            affectedCount: missingLinks.count,
            examples: missingLinks.prefix(5).map(\.href)
          )
        )
      }
    }

    var recipes: [PaprikaHTMLRecipe] = []
    for recipeURL in recipeURLs {
      do {
        let html = try String(contentsOf: recipeURL, encoding: .utf8)
        let recipe = parseRecipePage(
          html,
          recipeFileURL: recipeURL,
          fileManager: fileManager
        )
        warnings.append(
          contentsOf: recipe.photos
            .filter { !$0.isAvailable }
            .map { photo in
              PaprikaHTMLImportWarning(
                kind: .missingPhoto,
                path: recipeURL.path,
                message: "A Paprika recipe references an image file that is not present in this export folder.",
                examples: [photo.path]
              )
            }
        )
        recipes.append(recipe)
      } catch {
        warnings.append(
          PaprikaHTMLImportWarning(
            kind: .unreadableRecipe,
            path: recipeURL.path,
            message: "The Paprika recipe page could not be read.",
            examples: [String(describing: error)]
          )
        )
      }
    }

    return PaprikaHTMLImportResult(recipes: recipes, warnings: warnings)
  }

  public static func parseRecipePage(
    _ html: String,
    recipeFileURL: URL? = nil,
    fileManager: FileManager = .default
  ) -> PaprikaHTMLRecipe {
    let title = firstItemText(in: html, itemprop: "name")
      ?? recipeFileURL?.deletingPathExtension().lastPathComponent
      ?? "Untitled Recipe"
    let categoryNames = firstItemText(in: html, itemprop: "recipeCategory")
      .map(Self.listNames)
      ?? []
    let sourceURL = firstItemAttribute(in: html, itemprop: "url", attribute: "href")
    let sourceName = firstItemText(in: html, itemprop: "author")
    let description = firstItemBlockText(in: html, itemprop: "description")
    let notes = firstItemBlockText(in: html, itemprop: "comment").map { [$0] } ?? []
    let recipeDirectoryURL = recipeFileURL?.deletingLastPathComponent()

    return PaprikaHTMLRecipe(
      title: title,
      summary: description,
      servingsText: firstItemText(in: html, itemprop: "recipeYield"),
      prepTimeMinutes: firstItemText(in: html, itemprop: "prepTime").flatMap(parseDurationMinutes),
      cookTimeMinutes: firstItemText(in: html, itemprop: "cookTime").flatMap(parseDurationMinutes),
      totalTimeMinutes: firstItemText(in: html, itemprop: "totalTime").flatMap(parseDurationMinutes),
      rating: rating(in: html),
      difficulty: difficulty(in: html),
      sourceName: sourceName,
      sourceURL: sourceURL,
      categoryNames: categoryNames,
      ingredients: lineTexts(in: html, itemprop: "recipeIngredient"),
      instructions: firstItemHTML(in: html, itemprop: "recipeInstructions").map { lineTexts(in: $0) } ?? [],
      notes: notes,
      photos: photoReferences(
        in: html,
        recipeDirectoryURL: recipeDirectoryURL,
        fileManager: fileManager
      ),
      originalHTML: html
    )
  }

  private static func indexRecipeLinks(from html: String) -> [(href: String, fileName: String)] {
    captures(
      pattern: #"(?is)<a\b(?=[^>]*\bhref\s*=\s*["']Recipes/[^"']+\.html["'])[^>]*>"#,
      in: html
    )
    .compactMap { match in
      guard let tag = match.first else { return nil }
      let href = attributeValue("href", in: tag).map(decodeHTMLEntities) ?? ""
      let fileName = href
        .replacingOccurrences(of: "Recipes/", with: "")
        .removingPercentEncoding
        ?? href.replacingOccurrences(of: "Recipes/", with: "")
      return (href, fileName)
    }
  }

  private static func firstItemText(in html: String, itemprop: String) -> String? {
    firstItemHTML(in: html, itemprop: itemprop).map(textContent)?.nonEmpty
  }

  private static func firstItemBlockText(in html: String, itemprop: String) -> String? {
    guard let itemHTML = firstItemHTML(in: html, itemprop: itemprop) else { return nil }
    let lines = lineTexts(in: itemHTML)
    if !lines.isEmpty {
      return lines.joined(separator: "\n\n").nonEmpty
    }
    return textContent(itemHTML).nonEmpty
  }

  private static func firstItemHTML(in html: String, itemprop: String) -> String? {
    for tag in ["h1", "span", "p", "div", "a"] {
      let pattern = #"(?is)<\#(tag)\b(?=[^>]*\bitemprop\s*=\s*["']\#(itemprop)["'])[^>]*>(.*?)</\#(tag)>"#
      if let match = captures(pattern: pattern, in: html).first, match.count > 1 {
        return match[1]
      }
    }
    return nil
  }

  private static func firstItemAttribute(in html: String, itemprop: String, attribute: String) -> String? {
    let pattern = #"(?is)<[a-z0-9]+\b(?=[^>]*\bitemprop\s*=\s*["']\#(itemprop)["'])[^>]*>"#
    return captures(pattern: pattern, in: html)
      .compactMap { $0.first.flatMap { attributeValue(attribute, in: $0) } }
      .first?
      .nonEmpty
  }

  private static func lineTexts(in html: String, itemprop: String? = nil) -> [String] {
    let itemPredicate = itemprop.map { #"(?=[^>]*\bitemprop\s*=\s*["']\#($0)["'])"# } ?? ""
    let linePattern = #"(?is)<p\b\#(itemPredicate)(?=[^>]*\bclass\s*=\s*["'][^"']*\bline\b[^"']*["'])[^>]*>(.*?)</p>"#
    let lines = captures(pattern: linePattern, in: html)
      .compactMap { match in match.count > 1 ? textContent(match[1]).nonEmpty : nil }
    if !lines.isEmpty || itemprop == nil {
      return lines
    }

    let itemPattern = #"(?is)<p\b(?=[^>]*\bitemprop\s*=\s*["']\#(itemprop!)["'])[^>]*>(.*?)</p>"#
    return captures(pattern: itemPattern, in: html)
      .compactMap { match in match.count > 1 ? textContent(match[1]).nonEmpty : nil }
  }

  private static func photoReferences(
    in html: String,
    recipeDirectoryURL: URL?,
    fileManager: FileManager
  ) -> [PaprikaHTMLPhotoReference] {
    var photos: [PaprikaHTMLPhotoReference] = []
    var seenPaths: Set<String> = []

    func append(path: String, caption: String?, kind: RecipePhotoKind) {
      let decodedPath = decodeHTMLEntities(path)
      guard decodedPath.hasPrefix("Images/"), !seenPaths.contains(decodedPath) else { return }
      seenPaths.insert(decodedPath)
      let isAvailable = recipeDirectoryURL
        .map { fileManager.fileExists(atPath: $0.appendingPathComponent(decodedPath).path) }
        ?? false
      let processedPhoto = recipeDirectoryURL
        .map { $0.appendingPathComponent(decodedPath) }
        .flatMap { try? Data(contentsOf: $0) }
        .map { RecipePhotoProcessor.process(sourceData: $0, sourcePath: decodedPath, kind: kind) }
      photos.append(
        PaprikaHTMLPhotoReference(
          path: decodedPath,
          caption: caption?.nonEmpty,
          isAvailable: isAvailable,
          displayData: processedPhoto?.displayData,
          thumbnailData: processedPhoto?.thumbnailData,
          mediaType: processedPhoto?.mediaType,
          pixelWidth: processedPhoto?.pixelWidth,
          pixelHeight: processedPhoto?.pixelHeight,
          checksum: processedPhoto?.checksum,
          kind: kind
        )
      )
    }

    let galleryItemPattern = #"(?is)\{\s*msrc:\s*'[^']*',\s*src:\s*'([^']+)'[\s\S]*?title:\s*'([^']*)'\s*\}"#
    let galleryMatches = captures(pattern: galleryItemPattern, in: html)
      .filter { $0.count > 2 }
    for (index, match) in galleryMatches.enumerated() {
      append(
        path: unescapeJavaScriptString(match[1]),
        caption: unescapeJavaScriptString(match[2]),
        kind: index == 0 ? .hero : .gallery
      )
    }

    if galleryMatches.isEmpty {
      let imageTagPattern = #"(?is)<img\b(?=[^>]*\bitemprop\s*=\s*["']image["'])[^>]*>"#
      for match in captures(pattern: imageTagPattern, in: html) {
        if let tag = match.first, let src = attributeValue("src", in: tag) {
          append(path: src, caption: nil, kind: .hero)
        }
      }
    }

    return photos
  }

  private static func rating(in html: String) -> Int? {
    let pattern = #"(?is)<[a-z0-9]+\b(?=[^>]*\bitemprop\s*=\s*["']aggregateRating["'])[^>]*>"#
    guard
      let tag = captures(pattern: pattern, in: html).first?.first,
      let value = attributeValue("value", in: tag),
      let rating = Int(value),
      rating > 0
    else { return nil }
    return rating
  }

  private static func difficulty(in html: String) -> RecipeDifficulty? {
    // Paprika has no schema.org itemprop for difficulty; the export renders it (when set)
    // as a `<b>Difficulty: </b>` metadata label, so anchor on the label and read the value
    // up to the next field. Map only the known levels — anything else stays nil and the raw
    // page is preserved in originalImportText (preserve over interpret).
    let pattern = #"(?is)Difficulty:\s*</b>(.*?)(?:<b\b|</p>)"#
    guard let raw = captures(pattern: pattern, in: html).first?.dropFirst().first else { return nil }
    switch textContent(raw).lowercased() {
    case "easy": return .easy
    case "medium": return .medium
    case "hard": return .hard
    default: return nil
    }
  }

  private static func parseDurationMinutes(_ text: String) -> Int? {
    let lowercased = text.lowercased()
    let hours = firstNumber(
      pattern: #"(\d+(?:\.\d+)?)\s*(?:hours?|hrs?|hr|h)\b"#,
      in: lowercased
    ) ?? 0
    let minutes = firstNumber(
      pattern: #"(\d+(?:\.\d+)?)\s*(?:minutes?|mins?|min|m)\b"#,
      in: lowercased
    ) ?? 0
    let total = hours * 60 + minutes
    if total > 0 { return Int(total.rounded()) }

    return firstNumber(pattern: #"^\s*(\d+(?:\.\d+)?)\s*$"#, in: lowercased)
      .map { Int($0.rounded()) }
  }

  private static func firstNumber(pattern: String, in text: String) -> Double? {
    guard
      let value = captures(pattern: pattern, in: text).first?.dropFirst().first,
      let number = Double(value)
    else { return nil }
    return number
  }

  private static func textContent(_ html: String) -> String {
    let withBreaks = html
      .replacingOccurrences(of: #"(?is)<br\s*/?>"#, with: "\n", options: .regularExpression)
      .replacingOccurrences(of: #"(?is)</p\s*>"#, with: "\n", options: .regularExpression)
    let withoutTags = withBreaks.replacingOccurrences(
      of: #"(?is)<[^>]+>"#,
      with: "",
      options: .regularExpression
    )
    return decodeHTMLEntities(withoutTags)
      .components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
  }

  private static func listNames(_ text: String) -> [String] {
    text
      .split(separator: ",")
      .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }

  private static func attributeValue(_ attribute: String, in tag: String) -> String? {
    let doubleQuotePattern = #"(?is)\b\#(attribute)\s*=\s*"([^"]*)""#
    if let value = captures(pattern: doubleQuotePattern, in: tag).first?.dropFirst().first {
      return decodeHTMLEntities(value)
    }

    let singleQuotePattern = #"(?is)\b\#(attribute)\s*=\s*'([^']*)'"#
    return captures(pattern: singleQuotePattern, in: tag)
      .first?
      .dropFirst()
      .first
      .map(decodeHTMLEntities)
  }

  private static func captures(pattern: String, in text: String) -> [[String]] {
    let regex = try! NSRegularExpression(pattern: pattern)
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    return regex.matches(in: text, range: range).map { match in
      (0..<match.numberOfRanges).compactMap { index in
        guard
          match.range(at: index).location != NSNotFound,
          let range = Range(match.range(at: index), in: text)
        else { return nil }
        return String(text[range])
      }
    }
  }

  private static func decodeHTMLEntities(_ text: String) -> String {
    let pattern = #"&(#x[0-9a-fA-F]+|#[0-9]+|[A-Za-z]+);"#
    let regex = try! NSRegularExpression(pattern: pattern)
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    var decoded = ""
    var currentIndex = text.startIndex

    for match in regex.matches(in: text, range: range) {
      guard
        let matchRange = Range(match.range(at: 0), in: text),
        let entityRange = Range(match.range(at: 1), in: text)
      else { continue }
      decoded += text[currentIndex..<matchRange.lowerBound]
      decoded += replacement(forEntity: String(text[entityRange])) ?? String(text[matchRange])
      currentIndex = matchRange.upperBound
    }

    decoded += text[currentIndex..<text.endIndex]
    return decoded
  }

  private static func replacement(forEntity entity: String) -> String? {
    switch entity {
    case "amp": return "&"
    case "apos": return "'"
    case "quot": return "\""
    case "lt": return "<"
    case "gt": return ">"
    case "nbsp": return " "
    default:
      if entity.hasPrefix("#x") {
        return UInt32(entity.dropFirst(2), radix: 16).flatMap(UnicodeScalar.init).map(String.init)
      }
      if entity.hasPrefix("#") {
        return UInt32(entity.dropFirst(), radix: 10).flatMap(UnicodeScalar.init).map(String.init)
      }
      return nil
    }
  }

  private static func unescapeJavaScriptString(_ text: String) -> String {
    text
      .replacingOccurrences(of: #"\\'"#, with: "'", options: .regularExpression)
      .replacingOccurrences(of: #"\\\\"#, with: #"\"#, options: .regularExpression)
  }
}

private extension String {
  var nonEmpty: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}

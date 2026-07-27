import Foundation
import SwiftSoup

/// Harvested shape from GalavantCapture's `PageParser`, retargeted to schema.org
/// Recipe. Pure HTML in, `ParsedRecipePage` out; no fetch, WebKit, or database.
public enum WebRecipePageParser {
  public static func parse(
    html: String,
    sourceURL: URL? = nil,
    capturedAt: Date = Date()
  ) -> ParsedRecipePage {
    var builder = RecipeParseBuilder(sourceURL: sourceURL, originalHTML: html)
    guard let document = try? SwiftSoup.parse(html, sourceURL?.absoluteString ?? "") else {
      return builder.build(capturedAt: capturedAt)
    }

    extractDeterministicRecipeData(from: document, into: &builder)

    var page = builder.build(capturedAt: capturedAt)
    if let cleaned = cleanedBodyText(from: document) {
      page.bodyText = cleaned
      page.textExcerpt = truncate(cleaned, to: summaryLeadLength)
    }
    return page
  }

  /// Kept aligned with Galavant's parser: a short lead for review/summary surfaces;
  /// full `bodyText` remains uncapped for later fallback extraction.
  private static let summaryLeadLength = 1500

  static func merging(
    _ page: ParsedRecipePage,
    with extraction: RecipeExtraction
  ) -> ParsedRecipePage {
    var builder = RecipeParseBuilder(sourceURL: page.sourceURL, originalHTML: page.originalHTML)
    guard let document = try? SwiftSoup.parse(page.originalHTML, page.sourceURL?.absoluteString ?? "") else {
      return page
    }

    extractDeterministicRecipeData(from: document, into: &builder)
    let deterministicPage = builder.build(capturedAt: page.capturedAt)
    let contribution = extraction.suppressingHalvesAlreadyExtracted(in: deterministicPage)
    contribution.apply(to: &builder)
    var mergedPage = builder.build(capturedAt: page.capturedAt)
    if let cleaned = cleanedBodyText(from: document) {
      mergedPage.bodyText = cleaned
      mergedPage.textExcerpt = truncate(cleaned, to: summaryLeadLength)
    }
    mergedPage.processedImages = page.processedImages
    mergedPage.readerFeedbackBlocks = page.readerFeedbackBlocks
    mergedPage.modelExtractedIngredientSections = contribution.parsedIngredientSections
    mergedPage.modelExtractedInstructionSections = contribution.parsedInstructionSections
    return mergedPage
  }

  private static func extractDeterministicRecipeData(from document: Document, into builder: inout RecipeParseBuilder) {
    RecipeJSONLDExtractor.extract(from: document, into: &builder)
    RecipeMetaExtractor.extract(from: document, into: &builder)
    RecipeMicrodataExtractor.extract(from: document, into: &builder)
    RecipeMilkStreetExtractor.extract(from: document, into: &builder)
    RecipeBodyImageExtractor.extract(from: document, into: &builder)
    RecipeEditorialProseExtractor.extract(from: document, into: &builder)
  }

  private static func cleanedBodyText(from document: Document) -> String? {
    RecipePageDocumentCleaner.clean(document)
    guard let raw = try? document.body()?.text(), !raw.isEmpty else { return nil }
    let collapsed = raw.components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
    return collapsed.isEmpty ? nil : collapsed
  }

  private static func truncate(_ text: String, to limit: Int) -> String {
    guard text.count > limit else { return text }
    let clipped = text.prefix(limit)
    if let lastSpace = clipped.lastIndex(of: " ") {
      return String(clipped[..<lastSpace])
    }
    return String(clipped)
  }
}

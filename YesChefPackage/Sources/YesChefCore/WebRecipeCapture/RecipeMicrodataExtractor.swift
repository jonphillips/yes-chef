import Foundation
import SwiftSoup

enum RecipeMicrodataExtractor {
  static func extract(from document: Document, into builder: inout RecipeParseBuilder) {
    for scope in (try? document.select("[itemtype]").array()) ?? [] {
      if let itemtype = try? scope.attr("itemtype") {
        builder.addSchemaType(itemtype)
      }
    }

    for element in (try? document.select("[itemprop]").array()) ?? [] {
      guard let property = try? element.attr("itemprop"), !property.isEmpty else { continue }
      let value = propertyValue(of: element)

      if property == "aggregateRating" {
        builder.votes.add(
          .rating,
          aggregateRatingValue(from: element) ?? value,
          priority: RecipeAttributeVotes.microdataPriority
        )
        continue
      }

      guard let value, !value.isEmpty else { continue }

      if property == "recipeIngredient" {
        builder.addIngredient(value)
      } else if property == "recipeInstructions" {
        for section in instructionSections(in: element) {
          builder.addInstructionSection(name: section.name, steps: section.steps)
        }
      } else if property == "recipeCategory" {
        builder.addCategory(value)
      } else if property == "image" {
        builder.addImage(value)
      } else if let attribute = RecipeSchemaOrg.scalarProperties[property] {
        builder.votes.add(attribute, value, priority: RecipeAttributeVotes.microdataPriority)
      }
    }
  }

  private static func instructionSections(
    in element: Element
  ) -> [ParsedRecipeInstructionSection] {
    let childSections = (try? element.select("section, div").array()) ?? []
    var namedSections: [ParsedRecipeInstructionSection] = []
    for child in childSections {
      guard let heading = firstHeadingText(in: child) else { continue }
      let steps = instructionLines(in: child)
      guard !steps.isEmpty else { continue }
      namedSections.append(ParsedRecipeInstructionSection(name: heading, steps: steps))
    }
    if !namedSections.isEmpty { return namedSections }
    return [ParsedRecipeInstructionSection(steps: instructionLines(in: element))]
  }

  private static func instructionLines(in element: Element) -> [String] {
    let lineElements = (try? element.select("li, p").array()) ?? []
    var lines: [String] = []
    for lineElement in lineElements {
      lines.append(contentsOf: RecipeParseBuilder.lines(try? lineElement.text()))
    }
    if !lines.isEmpty { return lines }
    return RecipeParseBuilder.lines(try? element.text())
  }

  private static func firstHeadingText(in element: Element) -> String? {
    for heading in (try? element.select("h1, h2, h3, h4, h5, h6").array()) ?? [] {
      guard let rawText = try? heading.text() else { continue }
      let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
      if !text.isEmpty { return text }
    }
    return nil
  }

  private static func aggregateRatingValue(from element: Element) -> String? {
    if let value = try? element.attr("ratingValue"), !value.isEmpty { return value }
    if let value = try? element.attr("value"), !value.isEmpty { return value }
    guard let ratingElement = try? element.select("[itemprop=ratingValue]").first() else {
      return nil
    }
    return propertyValue(of: ratingElement)
  }

  private static func propertyValue(of element: Element) -> String? {
    let tag = element.tagName().lowercased()
    switch tag {
    case "meta":
      return try? element.attr("content")
    case "a", "link", "area":
      return try? element.absUrl("href")
    case "img", "audio", "video", "source", "iframe", "embed":
      return try? element.absUrl("src")
    case "object":
      return try? element.absUrl("data")
    case "time":
      let datetime = (try? element.attr("datetime")) ?? ""
      return datetime.isEmpty ? try? element.text() : datetime
    default:
      let content = (try? element.attr("content")) ?? ""
      return content.isEmpty ? try? element.text() : content
    }
  }
}

import Foundation
import SwiftSoup

enum RecipeMilkStreetExtractor {
  private static let hostSuffix = "177milkstreet.com"
  private static let printIngredientAmountSelector = "[class*=RecipePrintTemplate_ingredientAmount]"
  private static let printIngredientDescriptionSelector = "[class*=RecipePrintTemplate_ingredientDescription]"
  private static let printIngredientHeadingSelector = "[class*=RecipePrintTemplate_ingredientHeading]"
  private static let printIngredientItemSelector = "[class*=RecipePrintTemplate_ingredientItem]"
  private static let printIngredientRowSelector = "[class*=RecipePrintTemplate_ingredientRow]"
  private static let bodyIngredientAmountSelector = "[class*=RecipeBodyContent_ingredientItemBlock__amount]"
  private static let bodyIngredientDescriptionSelector = "[class*=RecipeBodyContent_ingredientItemBlock__description]"
  private static let bodyIngredientItemSelector = "[class*=RecipeBodyContent_ingredientItemBlockItem__]"
  private static let bodyIngredientHeadingItemSelector = "[class*=RecipeBodyContent_ingredientSectionHeadingItemContainer__]"
  private static let lineHeadingTitleSelector = "[class*=LineHeading_title__]"
  private static let printInstructionContentSelector = "[class*=RecipePrintTemplate_instructionContent]"
  private static let bodyInstructionContentSelector = "[class*=RecipeBodyContent_instructionContent]"
  private static let summaryBodySelector = "[class*=RecipeSummaryContent_body__]"
  private static let tipSelector = "[role=note][aria-label=Tip]"
  private static let tipDescriptionSelector = "[class*=Tip_description__]"
  private static let itemLabelListItemSelector = "[class*=ItemLabelList_item__]"
  private static let itemLabelSelector = "[class*=ItemLabelList_label__]"
  private static let itemValueSelector = "[class*=ItemLabelList_value__]"

  static func extract(from document: Document, into builder: inout RecipeParseBuilder) {
    guard isMilkStreet(builder.sourceURL) || hasMilkStreetTemplate(in: document) else { return }

    extractSummary(from: document, into: &builder)
    extractSummaryFacts(from: document, into: &builder)
    extractTips(from: document, into: &builder)

    let printSelectors = IngredientExtractionSelectors(
      headingSelector: printIngredientHeadingSelector,
      itemSelector: "\(printIngredientItemSelector), \(printIngredientRowSelector)",
      amountSelector: printIngredientAmountSelector,
      descriptionSelector: printIngredientDescriptionSelector,
      headingText: elementText
    )
    let bodySelectors = IngredientExtractionSelectors(
      headingSelector: bodyIngredientHeadingItemSelector,
      itemSelector: bodyIngredientItemSelector,
      amountSelector: bodyIngredientAmountSelector,
      descriptionSelector: bodyIngredientDescriptionSelector,
      headingText: { element in
        firstDescendantText(in: element, selector: lineHeadingTitleSelector)
      }
    )
    if !extractIngredients(from: document, into: &builder, selectors: printSelectors) {
      _ = extractIngredients(from: document, into: &builder, selectors: bodySelectors)
    }

    let printSteps = instructionLines(in: document, selector: printInstructionContentSelector)
    if !printSteps.isEmpty {
      builder.addInstructionSection(name: nil, steps: printSteps)
    } else {
      let bodySteps = instructionLines(in: document, selector: bodyInstructionContentSelector)
      builder.addInstructionSection(name: nil, steps: bodySteps)
    }
  }

  private static func isMilkStreet(_ url: URL?) -> Bool {
    guard let host = url?.host()?.lowercased() else { return false }
    return host == hostSuffix || host.hasSuffix(".\(hostSuffix)")
  }

  private static func hasMilkStreetTemplate(in document: Document) -> Bool {
    ((try? document.select(printIngredientAmountSelector).isEmpty()) == false)
      || ((try? document.select(bodyIngredientAmountSelector).isEmpty()) == false)
  }

  private static func extractSummary(from document: Document, into builder: inout RecipeParseBuilder) {
    for element in (try? document.select(summaryBodySelector).array()) ?? [] {
      let paragraphs = ((try? element.select("p").array()) ?? []).compactMap(elementText)
      let summary = paragraphs.isEmpty ? elementText(element) : paragraphs.joined(separator: "\n\n")
      builder.votes.add(.summary, summary, priority: RecipeAttributeVotes.jsonLDPriority)
    }
  }

  private static func extractSummaryFacts(from document: Document, into builder: inout RecipeParseBuilder) {
    for element in (try? document.select(itemLabelListItemSelector).array()) ?? [] {
      guard
        let label = firstDescendantText(in: element, selector: itemLabelSelector)?.lowercased(),
        let value = firstDescendantText(in: element, selector: itemValueSelector)
      else { continue }

      switch label {
      case "makes":
        builder.votes.add(.servingsText, value, priority: RecipeAttributeVotes.jsonLDPriority)
      case "prep time":
        builder.votes.add(.prepTime, value, priority: RecipeAttributeVotes.jsonLDPriority)
      case "cook time":
        builder.votes.add(.cookTime, value, priority: RecipeAttributeVotes.jsonLDPriority)
      case "total time":
        builder.votes.add(.totalTime, value, priority: RecipeAttributeVotes.jsonLDPriority)
      default:
        continue
      }
    }
  }

  private static func extractTips(from document: Document, into builder: inout RecipeParseBuilder) {
    for element in (try? document.select(tipSelector).array()) ?? [] {
      let description = firstDescendantText(in: element, selector: tipDescriptionSelector)
        ?? elementText(element)
      if let description {
        builder.addEditorialBlock(label: "Tip", text: description)
      }
    }
  }

  private static func extractIngredients(
    from document: Document,
    into builder: inout RecipeParseBuilder,
    selectors: IngredientExtractionSelectors
  ) -> Bool {
    let selector = "\(selectors.headingSelector), \(selectors.itemSelector)"
    let elements = (try? document.select(selector).array()) ?? []
    var lines: [String] = []
    var foundIngredient = false

    for element in elements {
      if matches(element, selector: selectors.headingSelector) {
        if let heading = selectors.headingText(element) {
          lines.append(heading)
        }
        continue
      }

      guard matches(element, selector: selectors.itemSelector),
        let description = firstDescendantText(in: element, selector: selectors.descriptionSelector)
      else { continue }
      let amount = firstDescendantText(in: element, selector: selectors.amountSelector)
      lines.append(joinedIngredient(amount: amount, description: description))
      foundIngredient = true
    }

    guard foundIngredient else { return false }
    for line in lines {
      builder.addIngredient(line)
    }
    return foundIngredient
  }

  private static func instructionLines(in document: Document, selector: String) -> [String] {
    var lines: [String] = []
    for element in (try? document.select(selector).array()) ?? [] {
      guard let text = elementText(element), !lines.contains(text) else { continue }
      lines.append(text)
    }
    return lines
  }

  private static func joinedIngredient(amount: String?, description: String) -> String {
    guard let amount, !amount.isEmpty else { return description }
    return "\(amount) \(description)"
  }

  private static func elementText(_ element: Element) -> String? {
    guard let text = try? element.text() else { return nil }
    let normalized = text
      .components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
    return normalized.isEmpty ? nil : normalized
  }

  private static func firstDescendantText(in element: Element, selector: String) -> String? {
    guard let descendant = try? element.select(selector).first() else { return nil }
    return elementText(descendant)
  }

  private static func matches(_ element: Element, selector: String) -> Bool {
    let className = (try? element.attr("class")) ?? ""
    return selector.split(separator: ",").contains { selector in
      guard let fragment = classFragment(in: String(selector)) else { return false }
      return className.contains(fragment)
    }
  }

  private static func classFragment(in selector: String) -> String? {
    let selector = selector.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let start = selector.range(of: "[class*=")?.upperBound,
      let end = selector[start...].firstIndex(of: "]")
    else { return nil }
    return String(selector[start..<end])
      .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
  }

  private struct IngredientExtractionSelectors {
    var headingSelector: String
    var itemSelector: String
    var amountSelector: String
    var descriptionSelector: String
    var headingText: (Element) -> String?
  }
}

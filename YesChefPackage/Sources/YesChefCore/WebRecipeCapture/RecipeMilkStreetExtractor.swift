import Foundation
import SwiftSoup

enum RecipeMilkStreetExtractor {
  private static let hostSuffix = "177milkstreet.com"
  private static let printIngredientAmountSelector = "[class*=RecipePrintTemplate_ingredientAmount]"
  private static let printIngredientDescriptionSelector = "[class*=RecipePrintTemplate_ingredientDescription]"
  private static let bodyIngredientAmountSelector = "[class*=RecipeBodyContent_ingredientItemBlock__amount]"
  private static let bodyIngredientDescriptionSelector = "[class*=RecipeBodyContent_ingredientItemBlock__description]"
  private static let printInstructionContentSelector = "[class*=RecipePrintTemplate_instructionContent]"
  private static let bodyInstructionContentSelector = "[class*=RecipeBodyContent_instructionContent]"

  static func extract(from document: Document, into builder: inout RecipeParseBuilder) {
    guard isMilkStreet(builder.sourceURL) || hasMilkStreetTemplate(in: document) else { return }

    if !extractIngredients(
      from: document,
      amountSelector: printIngredientAmountSelector,
      descriptionSelector: printIngredientDescriptionSelector,
      into: &builder
    ) {
      _ = extractIngredients(
        from: document,
        amountSelector: bodyIngredientAmountSelector,
        descriptionSelector: bodyIngredientDescriptionSelector,
        into: &builder
      )
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

  private static func extractIngredients(
    from document: Document,
    amountSelector: String,
    descriptionSelector: String,
    into builder: inout RecipeParseBuilder
  ) -> Bool {
    let amountElements = (try? document.select(amountSelector).array()) ?? []
    var foundIngredient = false
    for amountElement in amountElements {
      guard let description = descriptionElement(for: amountElement, selector: descriptionSelector),
        let descriptionText = elementText(description)
      else { continue }
      let amountText = elementText(amountElement)
      builder.addIngredient(joinedIngredient(amount: amountText, description: descriptionText))
      foundIngredient = true
    }
    return foundIngredient
  }

  private static func descriptionElement(for amountElement: Element, selector: String) -> Element? {
    if let parent = amountElement.parent(),
      let scoped = try? parent.select(selector).first()
    {
      return scoped
    }
    var sibling = nextElementSibling(of: amountElement)
    while let element = sibling {
      if matches(element, selector: selector) { return element }
      if let descendant = try? element.select(selector).first() {
        return descendant
      }
      sibling = nextElementSibling(of: element)
    }
    return nil
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

  private static func nextElementSibling(of element: Element) -> Element? {
    guard let siblings = element.parent()?.children().array(),
      let index = siblings.firstIndex(where: { $0 === element }),
      siblings.indices.contains(index + 1)
    else { return nil }
    return siblings[index + 1]
  }

  private static func matches(_ element: Element, selector: String) -> Bool {
    guard let fragment = classFragment(in: selector) else { return false }
    return ((try? element.attr("class")) ?? "").contains(fragment)
  }

  private static func classFragment(in selector: String) -> String? {
    guard let start = selector.range(of: "[class*=")?.upperBound,
      let end = selector[start...].firstIndex(of: "]")
    else { return nil }
    return String(selector[start..<end])
  }
}

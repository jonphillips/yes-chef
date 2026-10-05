import Foundation
import SwiftSoup

enum RecipeNYTCookingExtractor {
  private static let host = "cooking.nytimes.com"
  private static let groupHeadingSelector = "[class*=ingredientgroup_name__]"
  private static let ingredientSelector = "[class*=ingredient_ingredient__]"

  static func extract(from document: Document, into builder: inout RecipeParseBuilder) {
    guard isNYTCooking(builder.sourceURL) || hasNYTCookingTemplate(in: document) else { return }

    let elements = (try? document.select("\(groupHeadingSelector), \(ingredientSelector)").array()) ?? []
    var sections: [ParsedRecipeIngredientSection] = []
    var lines: [String] = []
    var currentName: String?
    var foundHeading = false

    for element in elements {
      if matches(element, selector: groupHeadingSelector) {
        if !lines.isEmpty {
          sections.append(ParsedRecipeIngredientSection(name: currentName, lines: lines))
          lines = []
        }
        foundHeading = true
        currentName = sectionName(elementText(element))
      } else if matches(element, selector: ingredientSelector), let text = elementText(element) {
        lines.append(text)
      }
    }

    guard foundHeading, !lines.isEmpty else { return }
    sections.append(ParsedRecipeIngredientSection(name: currentName, lines: lines))

    let domLines = sections.flatMap(\.lines)
    guard normalizedLines(domLines) == normalizedLines(builder.ingredients) else { return }
    for section in sections {
      builder.addIngredientSection(name: section.name, lines: section.lines)
    }
  }

  private static func isNYTCooking(_ url: URL?) -> Bool {
    guard let hostName = url?.host()?.lowercased() else { return false }
    return hostName == host || hostName.hasSuffix(".\(host)")
  }

  private static func hasNYTCookingTemplate(in document: Document) -> Bool {
    (try? document.select(groupHeadingSelector).isEmpty()) == false
  }

  private static func sectionName(_ rawName: String?) -> String? {
    guard var name = rawName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
    if name.hasSuffix(":") {
      name.removeLast()
      name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    guard !name.isEmpty else { return nil }
    if !name.contains(where: \.isLowercase) {
      return name.prefix(1).uppercased() + name.dropFirst().lowercased()
    }
    return name
  }

  private static func normalizedLines(_ lines: [String]) -> [String] {
    lines.map {
      $0.components(separatedBy: .whitespacesAndNewlines)
        .filter { !$0.isEmpty }
        .joined(separator: " ")
    }
  }

  private static func elementText(_ element: Element) -> String? {
    guard let text = try? element.text() else { return nil }
    let normalized = text
      .components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
    return normalized.isEmpty ? nil : normalized
  }

  private static func matches(_ element: Element, selector: String) -> Bool {
    let className = (try? element.attr("class")) ?? ""
    guard let start = selector.range(of: "[class*=")?.upperBound,
      let end = selector[start...].firstIndex(of: "]")
    else { return false }
    let fragment = selector[start..<end].trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    return className.contains(fragment)
  }
}

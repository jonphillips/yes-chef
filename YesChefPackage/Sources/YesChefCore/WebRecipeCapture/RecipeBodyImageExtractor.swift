import Foundation
import SwiftSoup

enum RecipeBodyImageExtractor {
  private static let imgURLAttributes = [
    "src", "data-src", "data-lazy-src", "data-original", "data-image", "data-lazy",
  ]

  private static let backgroundAttributes = [
    "data-bg", "data-background", "data-background-image", "data-bg-src",
  ]

  static func extract(from document: Document, into builder: inout RecipeParseBuilder) {
    extractImgElements(document, into: &builder)
    extractSrcsets(document, into: &builder)
    extractInlineBackgrounds(document, into: &builder)
    extractStyleBlocks(document, into: &builder)
    extractBackgroundAttributes(document, into: &builder)
    extractNoscriptFallbacks(document, into: &builder)
  }

  private static func extractImgElements(_ document: Document, into builder: inout RecipeParseBuilder) {
    for img in (try? document.select("img").array()) ?? [] {
      for attribute in imgURLAttributes {
        if let value = try? img.attr(attribute), !value.isEmpty {
          builder.addImage(value)
        }
      }
    }
  }

  private static func extractSrcsets(_ document: Document, into builder: inout RecipeParseBuilder) {
    for element in (try? document.select("img[srcset], source[srcset], img[data-srcset]").array()) ?? [] {
      let srcset = (try? element.attr("srcset")) ?? (try? element.attr("data-srcset")) ?? ""
      if let first = firstSrcsetURL(srcset) { builder.addImage(first) }
    }
  }

  private static func extractInlineBackgrounds(
    _ document: Document,
    into builder: inout RecipeParseBuilder
  ) {
    for element in (try? document.select("[style]").array()) ?? [] {
      guard let style = try? element.attr("style") else { continue }
      for url in cssURLs(in: style) { builder.addImage(url) }
    }
  }

  private static func extractStyleBlocks(_ document: Document, into builder: inout RecipeParseBuilder) {
    for style in (try? document.select("style").array()) ?? [] {
      let css = (try? style.html()) ?? ""
      for url in cssURLs(in: css) { builder.addImage(url) }
    }
  }

  private static func extractBackgroundAttributes(
    _ document: Document,
    into builder: inout RecipeParseBuilder
  ) {
    for attribute in backgroundAttributes {
      for element in (try? document.select("[\(attribute)]").array()) ?? [] {
        if let value = try? element.attr(attribute), !value.isEmpty { builder.addImage(value) }
      }
    }
  }

  private static func extractNoscriptFallbacks(
    _ document: Document,
    into builder: inout RecipeParseBuilder
  ) {
    for noscript in (try? document.select("noscript").array()) ?? [] {
      guard let inner = try? noscript.html(), let fragment = try? SwiftSoup.parseBodyFragment(inner)
      else { continue }
      for img in (try? fragment.select("img[src]").array()) ?? [] {
        if let value = try? img.attr("src"), !value.isEmpty { builder.addImage(value) }
      }
    }
  }

  private static func firstSrcsetURL(_ srcset: String) -> String? {
    guard let firstEntry = srcset.split(separator: ",").first else { return nil }
    let token = firstEntry.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).first
    return token.map(String.init)
  }

  private static func cssURLs(in css: String) -> [String] {
    guard css.contains("url(") else { return [] }
    let pattern = #"url\(\s*['"]?([^'")]+)['"]?\s*\)"#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
      return []
    }
    let range = NSRange(css.startIndex..<css.endIndex, in: css)
    return regex.matches(in: css, range: range).compactMap { match in
      guard let r = Range(match.range(at: 1), in: css) else { return nil }
      return String(css[r]).trimmingCharacters(in: .whitespaces)
    }
  }
}

enum RecipeImageFiltering {
  static func isRelevant(_ url: URL) -> Bool {
    let absolute = url.absoluteString.lowercased()
    if ["logo", "icon", "sprite", "avatar", "placeholder", "blank"].contains(where: absolute.contains) {
      return false
    }
    let pathExtension = url.pathExtension.lowercased()
    if pathExtension.isEmpty { return true }
    return ["jpg", "jpeg", "png", "webp", "heic", "heif"].contains(pathExtension)
  }
}

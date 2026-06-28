import Foundation
import SwiftSoup

enum RecipeMetaExtractor {
  private static let scalarOG: [String: RecipePageAttribute] = [
    "og:title": .title,
    "og:url": .sourceURL,
    "og:description": .summary,
    "article:author": .author,
    "article:publisher": .publisherName,
  ]

  private static let imageOG: Set<String> = [
    "og:image", "og:image:url", "og:image:secure_url",
  ]

  private static let scalarMeta: [String: RecipePageAttribute] = [
    "description": .summary,
    "author": .author,
    "twitter:title": .title,
    "twitter:description": .summary,
  ]

  private static let imageMeta: Set<String> = [
    "twitter:image", "twitter:image:src",
  ]

  static func extract(from document: Document, into builder: inout RecipeParseBuilder) {
    for meta in (try? document.select("meta").array()) ?? [] {
      let content = (try? meta.attr("content")) ?? ""
      if content.isEmpty { continue }

      if let property = try? meta.attr("property"), !property.isEmpty {
        let key = property.lowercased()
        if let attribute = scalarOG[key] {
          builder.votes.add(attribute, content)
        } else if imageOG.contains(key) {
          builder.addImage(content)
        }
      }

      if let name = try? meta.attr("name"), !name.isEmpty {
        let key = name.lowercased()
        if let attribute = scalarMeta[key] {
          builder.votes.add(attribute, content)
        } else if imageMeta.contains(key) {
          builder.addImage(content)
        }
      }
    }

    if let title = try? document.title(), !title.isEmpty {
      builder.votes.add(.title, title)
    }
  }
}

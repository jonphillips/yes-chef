import Foundation
import SQLiteData
import SwiftSoup

@Table("workbenchReferences")
public struct WorkbenchReference: Codable, Identifiable, Equatable, Sendable {
  public let id: UUID
  public var workbenchID: Workbench.ID
  public var sourceURL: String?
  public var label: String
  public var captureKind: WorkbenchReferenceCaptureKind
  public var reducedText: String
  public var reductionStatus: WorkbenchReferenceReductionStatus
  public var dateCreated: Date
  public var dateModified: Date

  public init(
    id: UUID,
    workbenchID: Workbench.ID,
    sourceURL: String? = nil,
    label: String,
    captureKind: WorkbenchReferenceCaptureKind,
    reducedText: String,
    reductionStatus: WorkbenchReferenceReductionStatus,
    dateCreated: Date,
    dateModified: Date
  ) {
    self.id = id
    self.workbenchID = workbenchID
    self.sourceURL = sourceURL
    self.label = label
    self.captureKind = captureKind
    self.reducedText = reducedText
    self.reductionStatus = reductionStatus
    self.dateCreated = dateCreated
    self.dateModified = dateModified
  }
}

public enum WorkbenchReferenceCaptureKind: String, Codable, QueryBindable, QueryDecodable, Sendable {
  case urlFetch
  case browserCapture
}

public enum WorkbenchReferenceReductionStatus: String, Codable, QueryBindable, QueryDecodable, Sendable {
  case complete
  case truncated
}

public enum WorkbenchReferenceContentSource: Equatable, Sendable {
  case url(URL)
  case capturedHTML(html: String, sourceURL: URL?)
}

public struct WorkbenchReferenceReducedContent: Equatable, Sendable {
  public var sourceURL: String?
  public var captureKind: WorkbenchReferenceCaptureKind
  public var reducedText: String
  public var reductionStatus: WorkbenchReferenceReductionStatus
  public var isThin: Bool

  public init(
    sourceURL: String?,
    captureKind: WorkbenchReferenceCaptureKind,
    reducedText: String,
    reductionStatus: WorkbenchReferenceReductionStatus,
    isThin: Bool
  ) {
    self.sourceURL = sourceURL
    self.captureKind = captureKind
    self.reducedText = reducedText
    self.reductionStatus = reductionStatus
    self.isThin = isThin
  }
}

public enum WorkbenchReferenceCaptureError: Error, Equatable, LocalizedError, Sendable {
  case noReadableContent

  public var errorDescription: String? {
    switch self {
    case .noReadableContent:
      "That page did not contain readable reference material."
    }
  }
}

/// Reduces public fetches and authenticated browser captures through one deterministic path. The raw HTML is
/// deliberately transient: `WorkbenchReference` retains only the reduced text that can sync to another device.
public enum WorkbenchReferenceCapture {
  public static func reduce(
    _ source: WorkbenchReferenceContentSource,
    using client: WebRecipeCaptureClient
  ) async throws -> WorkbenchReferenceReducedContent {
    switch source {
    case let .url(url):
      let fetchedHTML = try await client.fetchHTML(url)
      let fetchedReduced = WorkbenchReferenceReadabilityReducer.reduce(html: fetchedHTML)
      if let fetchedReduced, !fetchedReduced.isThin {
        return content(from: fetchedReduced, sourceURL: url, captureKind: .urlFetch)
      }
      let renderedHTML = try await client.renderHTML(url)
      let renderedReduced = renderedHTML.flatMap { html in
        WorkbenchReferenceReadabilityReducer.reduce(html: html)
      }
      if let fetchedReduced, let renderedReduced {
        let preferredReduced = renderedReduced.text.count > fetchedReduced.text.count
          ? renderedReduced
          : fetchedReduced
        return content(from: preferredReduced, sourceURL: url, captureKind: .urlFetch)
      }
      if let renderedReduced {
        return content(from: renderedReduced, sourceURL: url, captureKind: .urlFetch)
      }
      if let fetchedReduced {
        return content(from: fetchedReduced, sourceURL: url, captureKind: .urlFetch)
      }
      throw WorkbenchReferenceCaptureError.noReadableContent
    case let .capturedHTML(capturedHTML, capturedURL):
      guard let reduced = WorkbenchReferenceReadabilityReducer.reduce(html: capturedHTML) else {
        throw WorkbenchReferenceCaptureError.noReadableContent
      }
      return content(from: reduced, sourceURL: capturedURL, captureKind: .browserCapture)
    }
  }

  private static func content(
    from reduced: WorkbenchReferenceReadabilityResult,
    sourceURL: URL?,
    captureKind: WorkbenchReferenceCaptureKind
  ) -> WorkbenchReferenceReducedContent {
    return WorkbenchReferenceReducedContent(
      sourceURL: URLProvenanceNormalization
        .strippingTrackingParametersAndFragment(from: sourceURL)?
        .absoluteString,
      captureKind: captureKind,
      reducedText: reduced.text,
      reductionStatus: reduced.status,
      isThin: reduced.isThin
    )
  }
}

/// Generic page readability extraction for arbitrary reference material. This intentionally does not use the
/// recipe parser, whose schema-specific extraction rules are not valid for technique and food-science writing.
public enum WorkbenchReferenceReadabilityReducer {
  /// Matches the established recipe-page parser heuristic: link-heavy blocks are navigation, not article prose.
  private static let linkDensityThreshold = 0.6
  /// A short raw DOM extract may be a teaser rather than the full reference. URL capture retries rendered DOM
  /// below this threshold, and S3 uses the resulting signal for its browser affordance.
  public static let thinExtractCharacterCount = 1_500
  /// Keeps the stored TEXT payload within the frontier handoff budget. This is measured in UTF-8 bytes so
  /// compound Unicode sequences cannot exceed the character-oriented context budget.
  public static let maximumExtractUTF8ByteCount = 160_000
  private static let truncationSeparator = "\n\n"
  private static let truncationNotice = "[Reference extract truncated. Open the source for the remaining text.]"

  public static func reduce(html: String) -> WorkbenchReferenceReadabilityResult? {
    guard let document = try? SwiftSoup.parse(html) else { return nil }
    let contentRoot = (try? document.select("main, article, [role=main]").array().first)
      ?? document.body()
    guard let contentRoot else { return nil }

    for selector in [
      "script", "style", "noscript", "nav", "header", "footer", "aside", "form",
      "[class*=cookie]", "[class*=consent]", "[class*=breadcrumb]",
    ] {
      _ = try? contentRoot.select(selector).remove()
    }
    removeLinkDenseBlocks(in: contentRoot)

    let blocks = readableBlocks(in: contentRoot)
    guard !blocks.isEmpty else { return nil }
    let text = blocks.joined(separator: "\n\n")
    let truncated = truncatedText(text)
    return WorkbenchReferenceReadabilityResult(
      text: truncated.text,
      status: truncated.didTruncate ? .truncated : .complete,
      isThin: !truncated.didTruncate && text.count < thinExtractCharacterCount
    )
  }

  private static func readableBlocks(in contentRoot: Element) -> [String] {
    readableBlocks(in: contentRoot as Node)
  }

  private static func readableBlocks(in node: Node) -> [String] {
    if let textNode = node as? TextNode {
      let text = normalizedText(textNode.text())
      return text.isEmpty ? [] : [text]
    }
    guard let element = node as? Element else { return [] }
    if readableBlockTags.contains(element.tagName()) {
      guard let text = try? element.text() else { return [] }
      let normalized = normalizedText(text)
      return normalized.isEmpty ? [] : [normalized]
    }
    guard hasReadableBlockDescendant(in: element) else {
      guard let text = try? element.text() else { return [] }
      let normalized = normalizedText(text)
      return normalized.isEmpty ? [] : [normalized]
    }
    return element.getChildNodes().flatMap { readableBlocks(in: $0) }
  }

  private static func hasReadableBlockDescendant(in node: Node) -> Bool {
    if let element = node as? Element, readableBlockTags.contains(element.tagName()) {
      return true
    }
    return node.getChildNodes().contains { hasReadableBlockDescendant(in: $0) }
  }

  private static func normalizedText(_ text: String) -> String {
    return text
      .components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
  }

  private static let readableBlockTags: Set<String> = [
    "h1", "h2", "h3", "h4", "h5", "h6", "p", "li", "blockquote", "pre",
  ]

  private static func truncatedText(_ text: String) -> (text: String, didTruncate: Bool) {
    guard text.utf8.count > maximumExtractUTF8ByteCount else { return (text, false) }
    let byteBudget = maximumExtractUTF8ByteCount
      - truncationSeparator.utf8.count
      - truncationNotice.utf8.count
    let prefix = utf8BoundedPrefix(of: text, byteBudget: byteBudget)
    let wordBoundary = prefix.lastIndex(where: { $0.isWhitespace })
    let readablePrefix = if let wordBoundary, wordBoundary != prefix.startIndex {
      String(prefix[..<wordBoundary])
    } else {
      prefix
    }
    return (readablePrefix + truncationSeparator + truncationNotice, true)
  }

  private static func utf8BoundedPrefix(of text: String, byteBudget: Int) -> String {
    var byteCount = 0
    var endIndex = text.startIndex
    while endIndex < text.endIndex {
      let nextIndex = text.index(after: endIndex)
      let nextCharacterByteCount = text[endIndex..<nextIndex].utf8.count
      guard byteCount + nextCharacterByteCount <= byteBudget else { break }
      byteCount += nextCharacterByteCount
      endIndex = nextIndex
    }
    return String(text[..<endIndex])
  }

  private static func removeLinkDenseBlocks(in contentRoot: Element) {
    guard let candidates = try? contentRoot.select("ul, ol, div") else { return }
    for element in candidates.array() {
      guard element.parent() != nil else { continue }
      guard
        let links = try? element.select("a"), links.size() >= 4,
        let totalText = try? element.text(), !totalText.isEmpty
      else { continue }

      let linkText = links.array().compactMap { try? $0.text() }.joined()
      if Double(linkText.count) / Double(totalText.count) > linkDensityThreshold {
        try? element.remove()
      }
    }
  }
}

public enum WorkbenchReferenceRepository {
  @discardableResult
  public static func store(
    workbenchID: Workbench.ID,
    label: String,
    content: WorkbenchReferenceReducedContent,
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws -> WorkbenchReference.ID {
    guard let label = label.nonEmptyWorkbenchReferenceText else {
      throw WorkbenchReferenceRepositoryError.emptyLabel
    }
    guard var workbench = try Workbench.find(workbenchID).fetchOne(db) else {
      throw WorkbenchRepositoryError.workbenchNotFound(workbenchID)
    }
    if let existing = try existingReference(workbenchID: workbenchID, sourceURL: content.sourceURL, in: db) {
      throw WorkbenchReferenceRepositoryError.duplicateSourceURL(existing.id)
    }
    let reference = WorkbenchReference(
      id: uuid(),
      workbenchID: workbenchID,
      sourceURL: content.sourceURL,
      label: label,
      captureKind: content.captureKind,
      reducedText: content.reducedText,
      reductionStatus: content.reductionStatus,
      dateCreated: now,
      dateModified: now
    )
    try WorkbenchReference.insert { reference }.execute(db)
    workbench.dateModified = now
    try Workbench.upsert { workbench }.execute(db)
    return reference.id
  }

  public static func refresh(
    referenceID: WorkbenchReference.ID,
    content: WorkbenchReferenceReducedContent,
    in db: Database,
    now: Date
  ) throws {
    guard var reference = try WorkbenchReference.find(referenceID).fetchOne(db) else {
      throw WorkbenchReferenceRepositoryError.referenceNotFound(referenceID)
    }
    reference.sourceURL = content.sourceURL ?? reference.sourceURL
    reference.captureKind = content.captureKind
    reference.reducedText = content.reducedText
    reference.reductionStatus = content.reductionStatus
    reference.dateModified = now
    try WorkbenchReference.upsert { reference }.execute(db)

    guard var workbench = try Workbench.find(reference.workbenchID).fetchOne(db) else {
      throw WorkbenchRepositoryError.workbenchNotFound(reference.workbenchID)
    }
    workbench.dateModified = now
    try Workbench.upsert { workbench }.execute(db)
  }

  public static func updateLabel(
    referenceID: WorkbenchReference.ID,
    label: String,
    in db: Database,
    now: Date
  ) throws {
    guard let label = label.nonEmptyWorkbenchReferenceText else {
      throw WorkbenchReferenceRepositoryError.emptyLabel
    }
    guard var reference = try WorkbenchReference.find(referenceID).fetchOne(db) else {
      throw WorkbenchReferenceRepositoryError.referenceNotFound(referenceID)
    }
    guard reference.label != label else { return }

    reference.label = label
    reference.dateModified = now
    try WorkbenchReference.upsert { reference }.execute(db)

    guard var workbench = try Workbench.find(reference.workbenchID).fetchOne(db) else {
      throw WorkbenchRepositoryError.workbenchNotFound(reference.workbenchID)
    }
    workbench.dateModified = now
    try Workbench.upsert { workbench }.execute(db)
  }

  public static func references(
    for workbenchID: Workbench.ID,
    in db: Database
  ) throws -> [WorkbenchReference] {
    return try WorkbenchReference
      .where { $0.workbenchID.eq(workbenchID) }
      .fetchAll(db)
      .sorted(by: areWorkbenchReferencesInIncreasingOrder)
  }

  public static func delete(
    referenceID: WorkbenchReference.ID,
    in db: Database,
    now: Date
  ) throws {
    guard let reference = try WorkbenchReference.find(referenceID).fetchOne(db) else {
      throw WorkbenchReferenceRepositoryError.referenceNotFound(referenceID)
    }
    try WorkbenchReference.find(referenceID).delete().execute(db)
    guard var workbench = try Workbench.find(reference.workbenchID).fetchOne(db) else {
      throw WorkbenchRepositoryError.workbenchNotFound(reference.workbenchID)
    }
    workbench.dateModified = now
    try Workbench.upsert { workbench }.execute(db)
  }

  private static func existingReference(
    workbenchID: Workbench.ID,
    sourceURL: String?,
    in db: Database
  ) throws -> WorkbenchReference? {
    guard let sourceURL else { return nil }
    return try WorkbenchReference
      .where { $0.workbenchID.eq(workbenchID) }
      .fetchAll(db)
      .filter { $0.sourceURL == sourceURL }
      .sorted(by: areWorkbenchReferencesInIncreasingOrder)
      .first
  }

}

public enum WorkbenchReferenceRepositoryError: Error, Equatable, Sendable {
  case emptyLabel
  case duplicateSourceURL(WorkbenchReference.ID)
  case referenceNotFound(WorkbenchReference.ID)
}

private extension String {
  var nonEmptyWorkbenchReferenceText: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}

public struct WorkbenchReferenceReadabilityResult: Equatable, Sendable {
  public var text: String
  public var status: WorkbenchReferenceReductionStatus
  public var isThin: Bool

  public init(text: String, status: WorkbenchReferenceReductionStatus, isThin: Bool) {
    self.text = text
    self.status = status
    self.isThin = isThin
  }
}

private func areWorkbenchReferencesInIncreasingOrder(
  _ lhs: WorkbenchReference,
  _ rhs: WorkbenchReference
) -> Bool {
  if lhs.dateCreated != rhs.dateCreated {
    return lhs.dateCreated < rhs.dateCreated
  }
  return lhs.id.uuidString < rhs.id.uuidString
}

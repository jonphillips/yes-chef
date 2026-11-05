import Foundation
import LLMHandoffKit

/// Pure projections for the file-backed Chat Access inbox.
public enum ChatAccessInbox {
  public enum DownloadState: Equatable, Sendable {
    case current
    case downloading
  }

  public struct MetadataSnapshot: Sendable {
    public let url: URL
    public let name: String
    public let isCurrent: Bool
    public let recipeName: String?

    public init(url: URL, name: String, isCurrent: Bool, recipeName: String? = nil) {
      self.url = url
      self.name = name
      self.isCurrent = isCurrent
      self.recipeName = recipeName
    }
  }

  public struct Row: Equatable, Identifiable, Sendable {
    public let url: URL
    public let name: String
    public let stagedAt: Date
    public let downloadState: DownloadState

    public var id: String { url.path }

    public init(url: URL, name: String, stagedAt: Date, downloadState: DownloadState) {
      self.url = url
      self.name = name
      self.stagedAt = stagedAt
      self.downloadState = downloadState
    }
  }

  public enum ReturnDestination: Equatable, Sendable {
    case openable(AIHandoff)
    case otherDevice
    case capture
    case unreadable
  }

  public struct ReturnRow: Equatable, Identifiable, Sendable {
    public let url: URL
    public let stagedAt: Date
    public let downloadState: DownloadState
    public let destination: ReturnDestination
    public let superseded: [URL]
    public var id: String { url.path }

    public var title: String {
      guard case let .openable(handoff) = destination else {
        if case .unreadable = destination { return "Unreadable hand-off" }
        return "Hand-off return"
      }
      let firstLine = handoff.exportedPrompt.components(separatedBy: .newlines).first ?? ""
      return firstLine.isEmpty ? handoff.taskType.title : firstLine
    }
  }

  public static func returnRows(
    from snapshots: [MetadataSnapshot], resolve: (UUID) -> AIHandoff?
  ) -> [ReturnRow] {
    let candidates: [ReturnRow] = snapshots.compactMap { snapshot in
      guard snapshot.url.pathExtension == "ycreturn", let staged = StagedHandoff(url: snapshot.url) else { return nil }
      let destination: ReturnDestination
      if let id = UUID(uuidString: staged.slug) {
        if let handoff = resolve(id) {
          destination = handoff.sourceType == .capture ? .capture : .openable(handoff)
        } else {
          destination = .otherDevice
        }
      } else {
        destination = .unreadable
      }
      return ReturnRow(url: snapshot.url, stagedAt: staged.stagedAt,
        downloadState: snapshot.isCurrent ? .current : .downloading, destination: destination, superseded: [])
    }.sorted(by: returnRowPrecedes)

    var result: [ReturnRow] = []
    for row in candidates {
      guard case let .openable(handoff) = row.destination, !handoff.taskType.acceptsRepeatReturns else {
        result.append(row)
        continue
      }
      let previous = result.firstIndex {
        guard case let .openable(other) = $0.destination else { return false }
        return other.id == handoff.id
      }
      if let previous {
        let older = result.remove(at: previous)
        result.append(ReturnRow(url: row.url, stagedAt: row.stagedAt, downloadState: row.downloadState,
          destination: row.destination, superseded: older.superseded + [older.url]))
      } else {
        result.append(row)
      }
    }
    return result.sorted(by: returnRowPrecedes)
  }

  private static func returnRowPrecedes(_ lhs: ReturnRow, _ rhs: ReturnRow) -> Bool {
    if lhs.stagedAt != rhs.stagedAt { return lhs.stagedAt < rhs.stagedAt }
    if let left = StagedHandoff(url: lhs.url), let right = StagedHandoff(url: rhs.url), left.slug == right.slug {
      func sequence(_ url: URL) -> Int {
        let name = url.deletingPathExtension().lastPathComponent
        guard let range = name.range(of: #"--\d+$"#, options: .regularExpression) else { return 1 }
        return Int(name[range].dropFirst(2)) ?? 1
      }
      return sequence(lhs.url) < sequence(rhs.url)
    }
    return lhs.id.compare(rhs.id, options: .numeric) == .orderedAscending
  }

  public static func rows(from snapshots: [MetadataSnapshot]) -> [Row] {
    snapshots.compactMap { snapshot in
      guard snapshot.url.pathExtension == "json", let handoff = StagedHandoff(url: snapshot.url) else { return nil }
      return Row(
        url: snapshot.url,
        name: displayName(slug: handoff.slug, recipeName: snapshot.recipeName),
        stagedAt: handoff.stagedAt,
        downloadState: snapshot.isCurrent ? .current : .downloading
      )
    }
    .sorted { $0.stagedAt > $1.stagedAt }
  }

  public static func displayName(slug: String, recipeName: String?) -> String {
    if let recipeName {
      let trimmedName = recipeName.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmedName.isEmpty { return trimmedName }
    }
    return slug.replacingOccurrences(of: "-", with: " ").capitalized
  }

  /// The extraction path walks the supported JSON-LD shapes (including `@graph`) and returns
  /// the recipe's source title without asking the LLM fallback to infer one.
  public static func recipeName(from jsonLDText: String) -> String? {
    guard let title = try? RecipeContractStaging.validate(jsonLDText).title else { return nil }
    let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmedTitle.isEmpty ? nil : trimmedTitle
  }

}

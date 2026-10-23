import Foundation
import LLMHandoffKit

/// Pure projections for the file-backed Chat Access inbox.
public enum ChatAccessInbox {
  /// The dispatched recovery window for mistakenly discarded staged recipes.
  public static let processedRetentionInterval: TimeInterval = 30 * 24 * 60 * 60

  public enum DownloadState: Equatable, Sendable {
    case current
    case downloading
  }

  public struct MetadataSnapshot: Sendable {
    public let url: URL
    public let name: String
    public let isCurrent: Bool

    public init(url: URL, name: String, isCurrent: Bool) {
      self.url = url
      self.name = name
      self.isCurrent = isCurrent
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

  public struct ProcessedSnapshot: Sendable {
    public let url: URL
    public let modifiedAt: Date?

    public init(url: URL, modifiedAt: Date?) {
      self.url = url
      self.modifiedAt = modifiedAt
    }
  }

  public static func rows(from snapshots: [MetadataSnapshot]) -> [Row] {
    snapshots.compactMap { snapshot in
      guard let handoff = StagedHandoff(url: snapshot.url), snapshot.name != "Processed" else { return nil }
      return Row(
        url: snapshot.url,
        name: handoff.slug.replacingOccurrences(of: "-", with: " ").capitalized,
        stagedAt: handoff.stagedAt,
        downloadState: snapshot.isCurrent ? .current : .downloading
      )
    }
    .sorted { $0.stagedAt > $1.stagedAt }
  }

  public static func expired(_ snapshots: [ProcessedSnapshot], now: Date) -> [URL] {
    snapshots.compactMap { snapshot in
      guard let date = StagedHandoff(url: snapshot.url)?.stagedAt ?? snapshot.modifiedAt,
        now.timeIntervalSince(date) > processedRetentionInterval
      else { return nil }
      return snapshot.url
    }
  }
}

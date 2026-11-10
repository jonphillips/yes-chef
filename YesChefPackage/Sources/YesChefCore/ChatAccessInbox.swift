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
    public let menuTitle: String?
    public let menuDayMenuID: UUID?
    public let menuDayOffset: Int?

    public init(url: URL, name: String, isCurrent: Bool, recipeName: String? = nil, menuTitle: String? = nil, menuDayMenuID: UUID? = nil, menuDayOffset: Int? = nil) {
      self.url = url
      self.name = name
      self.isCurrent = isCurrent
      self.recipeName = recipeName
      self.menuTitle = menuTitle
      self.menuDayMenuID = menuDayMenuID
      self.menuDayOffset = menuDayOffset
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

  public enum RecipeReturnDestination: Equatable, Sendable {
    case openable(Recipe)
    case missing
  }

  public struct RecipeReturnRow: Equatable, Identifiable, Sendable {
    public let url: URL
    public let stagedAt: Date
    public let downloadState: DownloadState
    public let destination: RecipeReturnDestination
    public var id: String { url.path }
    public var title: String {
      if case let .openable(recipe) = destination { return "Changes · \(recipe.title)" }
      return "Recipe not found on this device"
    }
  }

  public struct MenuRow: Equatable, Identifiable, Sendable {
    public let url: URL
    public let title: String
    public let stagedAt: Date
    public let downloadState: DownloadState
    public var id: String { url.path }
  }

  public struct MenuDayRow: Equatable, Identifiable, Sendable {
    public let url: URL
    public let menuID: UUID?
    public let dayOffset: Int?
    public let menuTitle: String
    public let dayTitle: String
    public let isMenuAvailable: Bool
    public let isReadable: Bool
    public let stagedAt: Date
    public let downloadState: DownloadState
    public var id: String { url.path }
    public var canOpen: Bool { isReadable ? isMenuAvailable : true }
    public var title: String {
      guard isReadable else { return "Unreadable menu day · \(menuTitle)" }
      return isMenuAvailable ? "Menu day · \(menuTitle), \(dayTitle)" : "Menu not found on this device"
    }

    public init(url: URL, menuID: UUID?, dayOffset: Int?, menuTitle: String, dayTitle: String, isMenuAvailable: Bool, isReadable: Bool = true, stagedAt: Date, downloadState: DownloadState) {
      self.url = url
      self.menuID = menuID
      self.dayOffset = dayOffset
      self.menuTitle = menuTitle
      self.dayTitle = dayTitle
      self.isMenuAvailable = isMenuAvailable
      self.isReadable = isReadable
      self.stagedAt = stagedAt
      self.downloadState = downloadState
    }
  }

  public static func recipeReturnRows(from snapshots: [MetadataSnapshot], resolve: (UUID) -> Recipe?) -> [RecipeReturnRow] {
    snapshots.compactMap { snapshot in
      guard snapshot.url.pathExtension == "ycrecipereturn", let staged = StagedHandoff(url: snapshot.url),
        let recipeID = UUID(uuidString: staged.slug) else { return nil }
      let recipe = resolve(recipeID).flatMap { $0.archived ? nil : $0 }
      return RecipeReturnRow(url: snapshot.url, stagedAt: staged.stagedAt,
        downloadState: snapshot.isCurrent ? .current : .downloading,
        destination: recipe.map(RecipeReturnDestination.openable) ?? .missing)
    }.sorted { $0.stagedAt < $1.stagedAt }
  }

  public static func menuRows(from snapshots: [MetadataSnapshot]) -> [MenuRow] {
    snapshots.compactMap { snapshot in
      guard snapshot.url.pathExtension == "ycmenu", let staged = StagedHandoff(url: snapshot.url) else { return nil }
      let name = snapshot.menuTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
      let title = name.flatMap { $0.isEmpty ? nil : $0 } ?? displayName(slug: staged.slug, recipeName: nil)
      return MenuRow(url: snapshot.url, title: "Menu · \(title)", stagedAt: staged.stagedAt,
        downloadState: snapshot.isCurrent ? .current : .downloading)
    }.sorted { $0.stagedAt > $1.stagedAt }
  }

  public static func menuDayRows(
    from snapshots: [MetadataSnapshot],
    resolve: (UUID, Int) -> (menuExists: Bool, date: Date?)
  ) -> [MenuDayRow] {
    snapshots.compactMap { snapshot in
      guard snapshot.url.pathExtension == "ycmenuday", let staged = StagedHandoff(url: snapshot.url) else { return nil }
      let menuID = snapshot.menuDayMenuID
      let day = snapshot.menuDayOffset
      let availability = menuID.flatMap { id in day.map { resolve(id, $0) } }
      let dateTitle = availability?.date.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? day.map { "Day \($0 + 1)" } ?? "Day"
      let trimmedTitle = snapshot.menuTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
      let menuTitle = trimmedTitle.flatMap { $0.isEmpty ? nil : $0 } ?? displayName(slug: staged.slug, recipeName: nil)
      return MenuDayRow(url: snapshot.url, menuID: menuID, dayOffset: day, menuTitle: menuTitle,
        dayTitle: dateTitle, isMenuAvailable: availability?.menuExists ?? false,
        isReadable: menuID != nil && day != nil, stagedAt: staged.stagedAt,
        downloadState: snapshot.isCurrent ? .current : .downloading)
    }.sorted { $0.stagedAt > $1.stagedAt }
  }

  public static func menuDayMetadata(from text: String) -> (menuID: UUID, menuTitle: String, dayOffset: Int)? {
    guard let data = text.data(using: .utf8),
      let envelope = try? JSONDecoder().decode(ChatAccessStagedMenuDay.self, from: data) else { return nil }
    return (envelope.menuID, envelope.menuTitle, envelope.dayOffset)
  }

  public static func menuTitle(from text: String) -> String? {
    guard let data = text.data(using: .utf8), let envelope = try? JSONDecoder().decode(ChatAccessStagedMenu.self, from: data) else { return nil }
    return envelope.title
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

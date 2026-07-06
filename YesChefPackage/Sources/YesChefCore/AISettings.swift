import Dependencies
import Foundation
import LLMClientKit
import SQLiteData

public let legacyRecipeChatCustomInstructionsKey = "recipeChatCustomInstructions"
public let recipeChatFrontierProviderKey = "recipeChatFrontierProvider"
public let recipeChatUseFrontierKey = "recipeChatUseFrontier"

public enum AIPromptPreferenceKind: String, CaseIterable, Identifiable, Sendable {
  case chefItUp
  case serveWith
  case makeAheadPrepPlan
  case complements

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .chefItUp: "Chef It Up"
    case .serveWith: "Serve With"
    case .makeAheadPrepPlan: "Make-ahead & Prep Plans"
    case .complements: "Complements"
    }
  }
}

public struct AISettingsRequest: FetchKeyRequest {
  public init() {}

  public func fetch(_ db: Database) throws -> [AISettingsRecord] {
    try AISettingsRecord.fetchAll(db)
      .sorted(by: AISettingsRepository.areSettingsInDeterministicOrder)
  }
}

public enum AISettingsRepository {
  public static let singletonID = UUID(uuidString: "00000000-0000-0000-0000-000000000095")!

  public static func defaultSettings(now: Date) -> AISettingsRecord {
    AISettingsRecord(id: singletonID, dateModified: now)
  }

  public static func currentSettings(in db: Database, now: Date = Date()) throws -> AISettingsRecord {
    try AISettingsRecord.fetchAll(db)
      .sorted(by: areSettingsInDeterministicOrder)
      .first ?? defaultSettings(now: now)
  }

  public static func save(_ settings: AISettingsRecord, in db: Database) throws {
    try AISettingsRecord.upsert { settings }.execute(db)
  }

  public static func migrateLegacyTasteProfileIfNeeded(
    _ tasteProfile: String?,
    in db: Database,
    now: Date
  ) throws {
    let trimmed = tasteProfile?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !trimmed.isEmpty else { return }
    var settings = try currentSettings(in: db, now: now)
    guard settings.tasteProfile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return
    }
    settings = AISettingsRecord(
      id: singletonID,
      tasteProfile: trimmed,
      chefItUpPreference: settings.chefItUpPreference,
      serveWithPreference: settings.serveWithPreference,
      makeAheadPrepPlanPreference: settings.makeAheadPrepPlanPreference,
      complementsPreference: settings.complementsPreference,
      dateModified: now
    )
    try save(settings, in: db)
  }

  public static func preference(
    in settings: AISettingsRecord,
    for kind: AIPromptPreferenceKind
  ) -> String {
    switch kind {
    case .chefItUp: settings.chefItUpPreference
    case .serveWith: settings.serveWithPreference
    case .makeAheadPrepPlan: settings.makeAheadPrepPlanPreference
    case .complements: settings.complementsPreference
    }
  }

  public static func setPreference(
    _ value: String,
    for kind: AIPromptPreferenceKind,
    in settings: inout AISettingsRecord
  ) {
    switch kind {
    case .chefItUp: settings.chefItUpPreference = value
    case .serveWith: settings.serveWithPreference = value
    case .makeAheadPrepPlan: settings.makeAheadPrepPlanPreference = value
    case .complements: settings.complementsPreference = value
    }
  }

  public static func areSettingsInDeterministicOrder(
    _ lhs: AISettingsRecord,
    _ rhs: AISettingsRecord
  ) -> Bool {
    if lhs.id == singletonID { return true }
    if rhs.id == singletonID { return false }
    return lhs.id.uuidString < rhs.id.uuidString
  }
}

public struct AIPromptPreferencesClient: Sendable {
  public var current: @Sendable () -> AISettingsRecord

  public init(current: @escaping @Sendable () -> AISettingsRecord) {
    self.current = current
  }
}

extension AIPromptPreferencesClient: DependencyKey {
  public static var liveValue: AIPromptPreferencesClient {
    @Dependency(\.defaultDatabase) var database
    return AIPromptPreferencesClient {
      (try? database.read { db in
        try AISettingsRepository.currentSettings(in: db)
      }) ?? AISettingsRepository.defaultSettings(now: Date())
    }
  }

  public static let testValue = AIPromptPreferencesClient {
    AISettingsRepository.defaultSettings(now: Date(timeIntervalSinceReferenceDate: 0))
  }

  public static let previewValue = testValue
}

extension DependencyValues {
  public var aiPromptPreferences: AIPromptPreferencesClient {
    get { self[AIPromptPreferencesClient.self] }
    set { self[AIPromptPreferencesClient.self] = newValue }
  }
}

public enum YesChefAIPromptPreferences {
  public static func modelPromptPreferences(for request: ModelRequest) -> ModelPromptPreferences {
    @Dependency(\.aiPromptPreferences) var preferences
    let settings = preferences.current()
    return ModelPromptPreferences(
      tasteProfile: settings.tasteProfile,
      taskPreference: request.promptPreferenceKey
        .flatMap(AIPromptPreferenceKind.init(rawValue:))
        .map { AISettingsRepository.preference(in: settings, for: $0) }
    )
  }
}

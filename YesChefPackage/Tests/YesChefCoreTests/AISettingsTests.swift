import CustomDump
import Dependencies
import Foundation
import LLMClientKit
import SQLiteData
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct AISettingsTests {
    @Test
    func legacyCustomInstructionsMigrateToSyncedTasteProfile() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 820_000_000)

      try database.write { db in
        try AISettingsRepository.migrateLegacyTasteProfileIfNeeded(
          "  Bold, high-acid food.  ",
          in: db,
          now: now
        )
      }

      let settings = try database.read { db in
        try AISettingsRepository.currentSettings(in: db)
      }

      expectNoDifference(settings.id, AISettingsRepository.singletonID)
      expectNoDifference(settings.tasteProfile, "Bold, high-acid food.")
      expectNoDifference(settings.dateModified, now)
    }

    @Test
    func modelPromptPreferencesMapProfileAndTaskPreference() {
      let settings = AISettingsRecord(
        id: AISettingsRepository.singletonID,
        tasteProfile: "I like bold flavors.",
        chefItUpPreference: "Favor restaurant technique.",
        serveWithPreference: "",
        makeAheadPrepPlanPreference: "",
        complementsPreference: "",
        dateModified: Date(timeIntervalSinceReferenceDate: 820_100_000)
      )
      let request = ModelRequest(
        prompt: "x",
        promptPreferenceKey: AIPromptPreferenceKind.chefItUp.rawValue
      )

      withDependencies {
        $0.aiPromptPreferences = AIPromptPreferencesClient { settings }
      } operation: {
        expectNoDifference(
          YesChefAIPromptPreferences.modelPromptPreferences(for: request),
          ModelPromptPreferences(
            tasteProfile: "I like bold flavors.",
            taskPreference: "Favor restaurant technique."
          )
        )
      }
    }
  }
}

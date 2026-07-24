import CustomDump
import LLMClientKit
import Testing
import YesChefCore

@Suite
struct ModelTierResolutionTests {
  @Test
  func userSelectedOnDeviceIsPreservedForCompatibleWork() throws {
    let resolved = try resolveTier(
      useFrontier: false,
      preferredProvider: .openai,
      availableProviders: [.openai]
    )

    expectNoDifference(
      resolved,
      ResolvedModelTier(tier: .onDevice, resolution: .userSelectedTier)
    )
  }

  @Test
  func configuredPreferencesChooseTheConfiguredProviderWhenNoTierWasSelected() throws {
    let resolved = try resolveTier(
      useFrontier: nil,
      preferredProvider: .openai,
      availableProviders: [.anthropic, .openai]
    )

    expectNoDifference(
      resolved,
      ResolvedModelTier(tier: .frontier(.openai), resolution: .configuredPreferences)
    )
  }

  @Test
  func configuredPreferencesFallBackToTheFirstAvailableProvider() throws {
    let resolved = try resolveTier(
      useFrontier: nil,
      preferredProvider: .openai,
      availableProviders: [.anthropic]
    )

    expectNoDifference(
      resolved,
      ResolvedModelTier(tier: .frontier(.anthropic), resolution: .configuredPreferences)
    )
  }

  @Test
  func frontierRequiredWorkFailsClearlyWhenNoFrontierIsAvailable() {
    #expect(throws: ModelTierResolutionError.frontierRequired) {
      try resolveTier(
        useFrontier: nil,
        preferredProvider: nil,
        availableProviders: [],
        requirement: .frontierRequired
      )
    }
  }

  @Test
  func frontierRequiredWorkDoesNotOverrideAnExplicitOnDeviceChoice() {
    #expect(throws: ModelTierResolutionError.frontierRequired) {
      try resolveTier(
        useFrontier: false,
        preferredProvider: .anthropic,
        availableProviders: [.anthropic],
        requirement: .frontierRequired
      )
    }
  }

  @Test
  func requestedFrontierTierDegradesHonestlyWhenNoProviderIsAvailable() throws {
    let resolved = try resolveTier(
      useFrontier: true,
      preferredProvider: .openai,
      availableProviders: []
    )

    expectNoDifference(
      resolved,
      ResolvedModelTier(tier: .onDevice, resolution: .degradedToOnDevice)
    )
  }

  @Test
  func requestedUnavailableProviderDoesNotSilentlySubstituteAnotherProvider() throws {
    let resolved = try resolveTier(
      useFrontier: true,
      preferredProvider: .openai,
      availableProviders: [.anthropic]
    )

    expectNoDifference(
      resolved,
      ResolvedModelTier(tier: .onDevice, resolution: .degradedToOnDevice)
    )
  }
}

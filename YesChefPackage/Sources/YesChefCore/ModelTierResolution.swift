import Foundation
import LLMClientKit

/// The capability a model call requires from its serving tier.
public enum ModelTierRequirement: Equatable, Sendable {
  case onDeviceCompatible
  case frontierRequired
}

/// How the shared tier policy selected a model tier for a call.
public struct ResolvedModelTier: Equatable, Sendable {
  public let tier: ModelTier
  public let resolution: ModelCallTierResolution

  public init(tier: ModelTier, resolution: ModelCallTierResolution) {
    self.tier = tier
    self.resolution = resolution
  }
}

public enum ModelTierResolutionError: Error, Equatable, LocalizedError, Sendable {
  case frontierRequired

  public var errorDescription: String? {
    "This task needs a frontier model. Add an API key in AI Settings, then choose a frontier model and try again."
  }
}

/// Resolves the persisted chat preferences into a tier that can serve a call.
///
/// An explicit on-device choice remains on-device for compatible work. Calls that
/// require a frontier backend fail loudly instead of falling through to a smaller
/// on-device model that cannot produce their required structured result.
public func resolveTier(
  useFrontier: Bool?,
  preferredProvider: FrontierProvider?,
  availableProviders: [FrontierProvider],
  requirement: ModelTierRequirement = .onDeviceCompatible
) throws -> ResolvedModelTier {
  let requestedProvider = preferredProvider
  let preferredProvider = requestedProvider.flatMap { preferred in
    availableProviders.contains(preferred) ? preferred : nil
  }

  if useFrontier == false {
    guard requirement == .onDeviceCompatible else {
      throw ModelTierResolutionError.frontierRequired
    }
    return ResolvedModelTier(tier: .onDevice, resolution: .userSelectedTier)
  }

  // An active chat can retain a selected provider after its key is removed. Do
  // not silently send that conversation to a different provider.
  if useFrontier == true, requestedProvider != nil, preferredProvider == nil {
    guard requirement == .onDeviceCompatible else {
      throw ModelTierResolutionError.frontierRequired
    }
    return ResolvedModelTier(tier: .onDevice, resolution: .degradedToOnDevice)
  }

  if let preferredProvider {
    return ResolvedModelTier(
      tier: .frontier(preferredProvider),
      resolution: useFrontier == nil ? .configuredPreferences : .userSelectedTier
    )
  }

  if let provider = availableProviders.first {
    return ResolvedModelTier(
      tier: .frontier(provider),
      resolution: useFrontier == nil ? .configuredPreferences : .userSelectedTier
    )
  }

  guard requirement == .onDeviceCompatible else {
    throw ModelTierResolutionError.frontierRequired
  }
  return ResolvedModelTier(
    tier: .onDevice,
    resolution: useFrontier == true ? .degradedToOnDevice : .configuredPreferences
  )
}

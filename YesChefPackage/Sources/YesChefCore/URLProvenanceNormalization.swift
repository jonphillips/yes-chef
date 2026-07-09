import Foundation

public enum URLProvenanceNormalization {
  public static func strippingTrackingParametersAndFragment(from url: URL?) -> URL? {
    guard let url, var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
      return url
    }
    if let queryItems = components.queryItems {
      let meaningfulQueryItems = queryItems.filter { !isTrackingParameter($0.name) }
      components.queryItems = meaningfulQueryItems.isEmpty ? nil : meaningfulQueryItems
    }
    components.fragment = nil
    return components.url ?? url
  }

  private static func isTrackingParameter(_ name: String) -> Bool {
    let normalizedName = name.lowercased()
    return normalizedName.hasPrefix("utm_")
      || Self.trackingParameterNames.contains(normalizedName)
  }

  private static let trackingParameterNames: Set<String> = [
    "_hsenc",
    "_hsmi",
    "dclid",
    "fbclid",
    "gbraid",
    "gclid",
    "igshid",
    "li_fat_id",
    "mc_cid",
    "mc_eid",
    "mkt_tok",
    "msclkid",
    "s_cid",
    "ttclid",
    "twclid",
    "wbraid"
  ]
}

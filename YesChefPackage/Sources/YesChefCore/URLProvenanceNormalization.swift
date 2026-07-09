import Foundation

public enum URLProvenanceNormalization {
  public static func strippingQueryAndFragment(from url: URL?) -> URL? {
    guard let url, var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
      return url
    }
    components.query = nil
    components.fragment = nil
    return components.url ?? url
  }
}

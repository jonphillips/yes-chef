import Dependencies
import Foundation

public struct WebRecipeCaptureDraft: Equatable, Sendable {
  public var page: ParsedRecipePage
  public var usedRenderedFallback: Bool

  public init(page: ParsedRecipePage, usedRenderedFallback: Bool = false) {
    self.page = page
    self.usedRenderedFallback = usedRenderedFallback
  }
}

public struct WebRecipeSharePayload: Equatable, Sendable {
  public var sourceURL: URL?
  public var renderedHTML: String?

  public init(sourceURL: URL?, renderedHTML: String?) {
    self.sourceURL = sourceURL
    self.renderedHTML = renderedHTML
  }
}

public enum WebRecipeCaptureClientError: Error, Equatable, LocalizedError, Sendable {
  case invalidHTTPStatus(Int)
  case missingHTTPResponse
  case unimplementedFetch

  public var errorDescription: String? {
    switch self {
    case let .invalidHTTPStatus(statusCode):
      "Could not fetch that recipe page (HTTP \(statusCode))."
    case .missingHTTPResponse:
      "Could not read a valid response from that recipe page."
    case .unimplementedFetch:
      "Recipe page fetching is not configured."
    }
  }
}

public struct WebRecipeCaptureClient: Sendable {
  public var fetchHTML: @Sendable (URL) async throws -> String
  public var renderHTML: @Sendable (URL) async throws -> String?

  public init(
    fetchHTML: @escaping @Sendable (URL) async throws -> String,
    renderHTML: @escaping @Sendable (URL) async throws -> String?
  ) {
    self.fetchHTML = fetchHTML
    self.renderHTML = renderHTML
  }

  public func capture(
    url: URL,
    capturedAt: Date
  ) async throws -> WebRecipeCaptureDraft {
    let fetchedHTML = try await fetchHTML(url)
    var page = WebRecipePageParser.parse(html: fetchedHTML, sourceURL: url, capturedAt: capturedAt)
    var usedRenderedFallback = false

    if page.isEmpty, let renderedHTML = try await renderHTML(url), !renderedHTML.isEmpty {
      page = WebRecipePageParser.parse(html: renderedHTML, sourceURL: url, capturedAt: capturedAt)
      usedRenderedFallback = true
    }

    return WebRecipeCaptureDraft(page: page, usedRenderedFallback: usedRenderedFallback)
  }

  public func capture(
    sharePayload payload: WebRecipeSharePayload,
    capturedAt: Date
  ) async throws -> WebRecipeCaptureDraft {
    if let renderedHTML = payload.renderedHTML,
       !renderedHTML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      return WebRecipeCaptureDraft(
        page: WebRecipePageParser.parse(
          html: renderedHTML,
          sourceURL: payload.sourceURL,
          capturedAt: capturedAt
        )
      )
    }

    guard let sourceURL = payload.sourceURL else {
      throw WebRecipeSharePayloadError.missingURL
    }
    return try await capture(url: sourceURL, capturedAt: capturedAt)
  }

  public static func decodedHTML(data: Data, response: URLResponse) -> String {
    if let encodingName = response.textEncodingName ?? contentTypeCharset(response),
       let encoding = stringEncoding(named: encodingName),
       let html = String(data: data, encoding: encoding)
    {
      return html
    }
    return String(decoding: data, as: UTF8.self)
  }

  private static func contentTypeCharset(_ response: URLResponse) -> String? {
    guard let httpResponse = response as? HTTPURLResponse else { return nil }
    for (field, value) in httpResponse.allHeaderFields {
      guard
        String(describing: field).localizedCaseInsensitiveCompare("Content-Type") == .orderedSame,
        let contentType = value as? String
      else { continue }
      for component in contentType.split(separator: ";").dropFirst() {
        let pieces = component.split(separator: "=", maxSplits: 1).map {
          $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard pieces.count == 2, pieces[0].localizedCaseInsensitiveCompare("charset") == .orderedSame else {
          continue
        }
        return pieces[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
      }
    }
    return nil
  }

  private static func stringEncoding(named name: String) -> String.Encoding? {
    let normalized = name
      .trimmingCharacters(in: CharacterSet(charactersIn: "\"'").union(.whitespacesAndNewlines))
      .lowercased()
    switch normalized {
    case "utf-8", "utf8":
      return .utf8
    case "iso-8859-1", "iso_8859-1", "latin1", "latin-1", "iso-latin-1":
      return .isoLatin1
    case "windows-1252", "cp1252":
      return .windowsCP1252
    default:
      let cfEncoding = CFStringConvertIANACharSetNameToEncoding(normalized as CFString)
      guard cfEncoding != kCFStringEncodingInvalidId else { return nil }
      return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))
    }
  }
}

public enum WebRecipeSharePayloadError: Error, Equatable, LocalizedError, Sendable {
  case missingURL

  public var errorDescription: String? {
    switch self {
    case .missingURL:
      "The shared item did not include a recipe page URL."
    }
  }
}

extension WebRecipeCaptureClient: DependencyKey {
  public static var liveValue: Self {
    Self(
      fetchHTML: { url in
        var request = URLRequest(url: url)
        request.setValue(
          "Mozilla/5.0 AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
          forHTTPHeaderField: "User-Agent"
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
          throw WebRecipeCaptureClientError.missingHTTPResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
          throw WebRecipeCaptureClientError.invalidHTTPStatus(httpResponse.statusCode)
        }
        return Self.decodedHTML(data: data, response: response)
      },
      renderHTML: { _ in nil }
    )
  }

  public static var testValue: Self {
    Self(
      fetchHTML: { _ in throw WebRecipeCaptureClientError.unimplementedFetch },
      renderHTML: { _ in nil }
    )
  }
}

extension DependencyValues {
  public var webRecipeCaptureClient: WebRecipeCaptureClient {
    get { self[WebRecipeCaptureClient.self] }
    set { self[WebRecipeCaptureClient.self] = newValue }
  }
}

extension RecipeRepository {
  @discardableResult
  public static func importCapturedRecipe(
    _ draft: WebRecipeCaptureDraft,
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws -> RecipeImportBundleResult {
    let bundle = try draft.page.makeRecipeBundle(now: now, uuid: uuid)
    return try importBundle(bundle, in: db, now: now, uuid: uuid)
  }
}

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
        return String(decoding: data, as: UTF8.self)
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

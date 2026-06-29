import Foundation
import WebKit

enum RenderedDOMFetcher {
  @MainActor
  static func renderedHTML(of url: URL) async -> String? {
    let page = WebPage()
    do {
      for try await event in page.load(URLRequest(url: url)) {
        if event == .finished { break }
      }
      return try await page.callJavaScript("return document.documentElement.outerHTML") as? String
    } catch {
      return nil
    }
  }
}

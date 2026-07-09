import Dependencies
import WebKit
import Foundation
import Observation
import WebExtractorKit
import YesChefCore

@Observable
@MainActor
final class BrowserModel {
  @ObservationIgnored
  @Dependency(\.readerFeedbackCurationClient) private var readerFeedbackCurationClient

  let page = WebPage.browser()
  var recents: [URL] = []
  var notice: String?
  var isCapturing = false
  var isLoadingComments = false
  private var readerFeedbackTips: [ReaderFeedbackTip] = []
  private var readerFeedbackComments: [RawComment] = []

  func recordRecent(_ url: URL) {
    if recents.first?.absoluteString != url.absoluteString {
      readerFeedbackTips = []
      readerFeedbackComments = []
    }
    recents.removeAll { $0.absoluteString == url.absoluteString }
    recents.insert(url, at: 0)
    if recents.count > 12 {
      recents.removeSubrange(12...)
    }
  }

  func captureButtonTapped(
    page: WebPage,
    ingest: (String, URL?) async -> WebExtractionOutcome
  ) async -> WebExtractionOutcome {
    isCapturing = true
    notice = nil
    defer { isCapturing = false }

    guard let html = await page.currentDOM(), !html.isEmpty else {
      let message = "Couldn't read this page - try again once it's loaded."
      notice = message
      return .notFound(message: message)
    }

    let outcome = await ingest(html, page.url)
    switch outcome {
    case .extracted:
      notice = nil
    case .notFound(let message):
      notice = message
    }
    return outcome
  }

  func loadCommentsButtonTapped(page: WebPage) async {
    guard let playbook = BrowserCommentLoadingPlaybook.playbook(for: page.url) else {
      notice = "Comment loading is only available for NYT Cooking."
      return
    }

    isLoadingComments = true
    notice = nil
    defer { isLoadingComments = false }

    do {
      let result = try await playbook.load(on: page)
      switch result.status {
      case .loaded:
        guard let html = await page.currentDOM(), !html.isEmpty else {
          notice = "Loaded \(result.commentCount) comments, but couldn't read the page."
          return
        }
        let comments = RecipeReaderCommentExtractor.extract(html: html, sourceURL: page.url)
        guard !comments.isEmpty else {
          notice = "Loaded comments, but couldn't extract reader feedback."
          return
        }
        let tips = try await readerFeedbackCurationClient(comments: comments, sourceURL: page.url)
        readerFeedbackComments = comments
        readerFeedbackTips = tips
        if tips.isEmpty {
          notice = "Loaded \(comments.count) comments. No useful reader tips found. Capture to promote one manually."
        } else {
          notice = "Loaded \(comments.count) comments and found \(tips.count) reader tips. Capture to review them."
        }
      case .notFound:
        notice = "Couldn't find NYT comments on this page."
      }
    } catch ReaderFeedbackCurationError.responseTruncated {
      notice = "Loaded comments, but couldn't finish curating them. Try again."
    } catch {
      notice = "Couldn't load comments - try again once the page settles."
    }
  }

  func noticeDismissButtonTapped() {
    notice = nil
  }

  func takeReaderFeedbackDraft() -> (tips: [ReaderFeedbackTip], comments: [RawComment]) {
    defer {
      readerFeedbackTips = []
      readerFeedbackComments = []
    }
    return (readerFeedbackTips, readerFeedbackComments)
  }

  func reloadAfterExternalChange() async {
  }
}

enum BrowserCommentLoadingPlaybook: Equatable {
  case nytCooking

  static func playbook(for url: URL?) -> Self? {
    guard let host = url?.host()?.lowercased() else { return nil }
    if host == "cooking.nytimes.com" {
      return .nytCooking
    }
    return nil
  }

  func load(on page: WebPage) async throws -> BrowserCommentLoadingResult {
    switch self {
    case .nytCooking:
      return try await loadNYTCookingComments(on: page)
    }
  }

  private func loadNYTCookingComments(on page: WebPage) async throws -> BrowserCommentLoadingResult {
    let value = try await page.callJavaScript(Self.nytCookingScript)
    guard let json = value as? String else {
      throw BrowserCommentLoadingError.invalidResult
    }
    return try JSONDecoder().decode(BrowserCommentLoadingResult.self, from: Data(json.utf8))
  }

  private static let nytCookingScript = #"""
  const sleep = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds));
  const classStartsWith = (element, prefix) =>
    Array.from(element.classList || []).some((className) => className.startsWith(prefix));
  const section = document.querySelector("#notes_section");

  if (!section) {
    return JSON.stringify({ status: "notFound", commentCount: 0, loadMoreClicks: 0 });
  }

  const noteCount = () =>
    Array.from(section.querySelectorAll("[class]"))
      .filter((element) => classStartsWith(element, "note_note__"))
      .length;
  const visibleButton = (button) =>
    !button.disabled && button.offsetParent !== null && getComputedStyle(button).visibility !== "hidden";
  const buttonText = (button) => (button.innerText || button.textContent || "").replace(/\s+/g, " ").trim();
  const buttons = () => Array.from(section.querySelectorAll("button, [role='tab']"));

  const helpfulTab = buttons().find((button) => buttonText(button).includes("Most Helpful"));
  if (helpfulTab && helpfulTab.getAttribute("aria-selected") !== "true") {
    helpfulTab.click();
    await sleep(1200);
  }

  let loadMoreClicks = 0;
  for (let index = 0; index < 4; index += 1) {
    const loadMore = buttons().find((button) =>
      visibleButton(button) &&
      (buttonText(button).includes("Show more comments") ||
        classStartsWith(button, "showmorebutton_showMoreButton__"))
    );
    if (!loadMore) { break; }

    const before = noteCount();
    loadMore.click();
    loadMoreClicks += 1;
    await sleep(1400);
    if (noteCount() <= before) {
      await sleep(900);
    }
  }

  return JSON.stringify({
    status: "loaded",
    commentCount: noteCount(),
    loadMoreClicks
  });
  """#
}

struct BrowserCommentLoadingResult: Decodable, Equatable {
  enum Status: String, Decodable {
    case loaded
    case notFound
  }

  var status: Status
  var commentCount: Int
  var loadMoreClicks: Int
}

enum BrowserCommentLoadingError: Error {
  case invalidResult
}

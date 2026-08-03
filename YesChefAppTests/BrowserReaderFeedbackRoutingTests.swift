import CustomDump
import Dependencies
import Testing
import YesChefCore
@testable import YesChef

@Suite
@MainActor
struct BrowserReaderFeedbackRoutingTests {
  @Test
  func loadingCommentsStagesRawCommentsWithoutInvokingCuration() async {
    let calls = ReaderFeedbackCurationCallRecorder()
    let comments = [RawComment(text: "Use a wide skillet.", helpfulCount: 8)]

    await withDependencies {
      $0.readerFeedbackCurationClient = ReaderFeedbackCurationClient { _, _ in
        await calls.recordCall()
        return []
      }
    } operation: {
      let browser = BrowserModel()

      browser.stageLoadedReaderFeedbackComments(comments)

      expectNoDifference(browser.takeReaderFeedbackDraft(), comments)
      let curationCallCount = await calls.count()
      expectNoDifference(curationCallCount, 0)
    }
  }

  @Test
  func rawCommentsRemainStagedWhenFrontierCurationIsUnavailable() async {
    let comments = [RawComment(text: "Use a wide skillet.", helpfulCount: 8)]

    await withDependencies {
      $0.readerFeedbackCurationClient = ReaderFeedbackCurationClient { _, _ in
        throw ModelTierResolutionError.frontierRequired
      }
    } operation: {
      let browser = BrowserModel()
      browser.stageLoadedReaderFeedbackComments(comments)

      let capture = RecipeCaptureModel()
      capture.draft = WebRecipeCaptureDraft(page: ParsedRecipePage(title: "Tomato Pasta"))
      capture.stageReaderFeedback(tips: [], comments: browser.takeReaderFeedbackDraft())

      let curated = await capture.curateReaderFeedbackButtonTapped(sourceURL: nil)
      #expect(!curated)
      expectNoDifference(capture.readerFeedbackComments, comments)
      expectNoDifference(capture.readerFeedbackProposals, [])
      #expect(capture.isShowingError)
    }
  }
}

private actor ReaderFeedbackCurationCallRecorder {
  private var calls = 0

  func recordCall() {
    calls += 1
  }

  func count() -> Int {
    calls
  }
}

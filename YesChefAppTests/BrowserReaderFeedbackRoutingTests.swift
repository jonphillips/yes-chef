import CustomDump
import Dependencies
import Foundation
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
      // `RecipeCaptureModel.init` mints its reader-feedback capture ID eagerly.
      $0.uuid = .incrementing
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

  @Test
  func tokenlessJSONRequiresConfirmationBeforeItStagesIntoTheCurrentCapture() async throws {
    let now = Date(timeIntervalSinceReferenceDate: 840_200_000)
    let comments = [
      RawComment(text: "A lower rack browned the bottom well.", helpfulCount: 9),
      RawComment(text: "Another vote for the lower rack.", helpfulCount: 4),
    ]

    try await withDependencies {
      try $0.bootstrapDatabase()
      $0.date.now = now
      $0.uuid = .incrementing
    } operation: {
      @Dependency(\.defaultDatabase) var database
      let capture = RecipeCaptureModel()
      let captureID = capture.readerFeedbackCaptureID
      let source = readerFeedbackSource(captureID: captureID, comments: comments)
      let transport = HandoffInAppTransport()
      var reviews: [AIHandoffReaderFeedbackResult] = []

      await transport.pastedReaderFeedbackResults(
        [readerFeedbackJSON],
        source: source,
        receive: { reviews.append($0) }
      )

      #expect(transport.isShowingUnmatchedConfirmation)
      #expect(reviews.isEmpty)
      #expect(transport.unmatchedMessage.contains("Backing-comment numbering"))

      await transport.reviewUnmatchedResult()

      #expect(!transport.isShowingUnmatchedConfirmation)
      expectNoDifference(reviews.map(\.review.tips), [expectedTips(for: comments)])
      #expect(reviews.first?.warning != nil)
      let handoffs = try await database.read { db in
        try AIHandoff.fetchAll(db).first {
          $0.sourceID == captureID && $0.status == .imported
        }
      }
      let imported = try #require(handoffs)
      #expect(imported.taskType == .readerFeedbackCuration)
    }
  }

  @Test
  func staleReaderFeedbackTokenWarnsThenImportsAgainstCurrentComments() async throws {
    let now = Date(timeIntervalSinceReferenceDate: 840_200_000)
    let staleHandoffID = UUID(uuidString: "00000000-0000-0000-0000-000000004210")!
    let staleCaptureID = UUID(uuidString: "00000000-0000-0000-0000-000000004211")!
    let comments = [
      RawComment(text: "A lower rack browned the bottom well.", helpfulCount: 9),
      RawComment(text: "Another vote for the lower rack.", helpfulCount: 4),
    ]

    try await withDependencies {
      try $0.bootstrapDatabase()
      $0.date.now = now
      $0.uuid = .incrementing
    } operation: {
      @Dependency(\.defaultDatabase) var database
      try await database.write { db in
        try AIHandoffRepository.create(
          AIHandoff(
            id: staleHandoffID,
            sourceType: .capture,
            sourceID: staleCaptureID,
            taskType: .readerFeedbackCuration,
            createdAt: now,
            exportedPrompt: ""
          ),
          in: db
        )
      }

      let capture = RecipeCaptureModel()
      let captureID = capture.readerFeedbackCaptureID
      let source = readerFeedbackSource(captureID: captureID, comments: comments)
      let transport = HandoffInAppTransport()
      var reviews: [AIHandoffReaderFeedbackResult] = []
      let staleResult = """
      YC-HANDOFF: \(staleHandoffID.uuidString)
      YC-CONTRACT: v2.1
      \(readerFeedbackJSON)
      """

      await transport.pastedReaderFeedbackResults(
        [staleResult],
        source: source,
        receive: { reviews.append($0) }
      )

      #expect(transport.isShowingUnmatchedConfirmation)
      #expect(reviews.isEmpty)

      await transport.reviewUnmatchedResult()

      expectNoDifference(reviews.map(\.review.tips), [expectedTips(for: comments)])
      #expect(reviews.first?.warning != nil)
      let handoffs = try await database.read { db in try AIHandoff.fetchAll(db) }
      #expect(handoffs.first { $0.id == staleHandoffID }?.status == .awaitingReturn)
      #expect(handoffs.contains {
        $0.sourceID == captureID && $0.status == .imported
      })
    }
  }

  @Test
  func matchingReaderFeedbackJSONImportsWithoutConfirmation() async throws {
    let now = Date(timeIntervalSinceReferenceDate: 840_200_000)
    let handoffID = UUID(uuidString: "00000000-0000-0000-0000-000000004220")!
    let comments = [
      RawComment(text: "A lower rack browned the bottom well.", helpfulCount: 9),
      RawComment(text: "Another vote for the lower rack.", helpfulCount: 4),
    ]

    try await withDependencies {
      try $0.bootstrapDatabase()
      $0.date.now = now
      $0.uuid = .incrementing
    } operation: {
      @Dependency(\.defaultDatabase) var database
      let capture = RecipeCaptureModel()
      let captureID = capture.readerFeedbackCaptureID
      let source = readerFeedbackSource(captureID: captureID, comments: comments)
      try await database.write { db in
        try AIHandoffRepository.create(
          AIHandoff(
            id: handoffID,
            sourceType: .capture,
            sourceID: captureID,
            taskType: .readerFeedbackCuration,
            createdAt: now,
            exportedPrompt: ""
          ),
          in: db
        )
      }
      let transport = HandoffInAppTransport()
      var reviews: [AIHandoffReaderFeedbackResult] = []

      await transport.pastedReaderFeedbackResults(
        ["""
        YC-HANDOFF: \(handoffID.uuidString)
        \(AIHandoffReturnContract.marker)
        \(readerFeedbackJSON)
        """],
        source: source,
        receive: { reviews.append($0) }
      )

      #expect(!transport.isShowingUnmatchedConfirmation)
      expectNoDifference(reviews.map(\.review.tips), [expectedTips(for: comments)])
      #expect(reviews.first?.warning == nil)
      #expect(try await database.read { db in
        try AIHandoffRepository.handoff(id: handoffID, in: db)?.status == .imported
      })
    }
  }
}

private func readerFeedbackSource(
  captureID: UUID,
  comments: [RawComment]
) -> HandoffExportSource {
  .readerFeedback(
    ReaderFeedbackHandoffContext(
      captureID: captureID,
      comments: comments,
      sourceURL: URL(string: "https://cooking.nytimes.com/recipes/example")
    )
  )
}

private let readerFeedbackJSON = """
[
  {
    "text": "Bake on the lower rack for a well-browned bottom.",
    "kind": "consensusDistilled",
    "supportCount": 2,
    "commentNumbers": [1, 2]
  }
]
"""

private func expectedTips(for comments: [RawComment]) -> [ReaderFeedbackTip] {
  [
    ReaderFeedbackTip(
      text: "Bake on the lower rack for a well-browned bottom.",
      provenanceKind: .consensusDistilled,
      supportCount: 2,
      backingComments: comments.enumerated().map { index, comment in
        ReaderFeedbackBackingComment(
          commentNumber: index + 1,
          text: comment.text,
          helpfulCount: comment.helpfulCount
        )
      }
    )
  ]
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

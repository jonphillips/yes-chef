import Foundation
import YesChefCore

extension RecipeCaptureModel {
  func curateReaderFeedbackButtonTapped(sourceURL: URL?) async -> Bool {
    guard !readerFeedbackComments.isEmpty, !isCuratingReaderFeedback else { return false }
    isCuratingReaderFeedback = true
    defer { isCuratingReaderFeedback = false }

    do {
      let tips = try await readerFeedbackCurationClient(
        comments: readerFeedbackComments,
        sourceURL: sourceURL
      )
      stageReaderFeedback(tips: tips, comments: readerFeedbackComments)
      return !tips.isEmpty
    } catch is CancellationError {
      return false
    } catch {
      errorMessage = RecipeChatErrorText.describe(error)
      isShowingError = true
      return false
    }
  }

  func stageReaderFeedback(
    tips: [ReaderFeedbackTip],
    comments: [RawComment],
    unparsedLines: [String] = []
  ) {
    readerFeedbackComments = comments
    readerFeedbackHandoffEvidence = unparsedLines
    guard !tips.isEmpty else { return }
    let acceptedKeys = Set(readerFeedbackBlocks.map { $0.text.lowercased() })
    var seen = Set(readerFeedbackProposals.map { $0.text.lowercased() })
    readerFeedbackProposals.append(
      contentsOf: tips.filter { tip in
        let key = tip.text.lowercased()
        return !acceptedKeys.contains(key) && seen.insert(key).inserted
      }
    )
  }

  func promoteReaderFeedbackComment(_ comment: RawComment, commentNumber: Int) -> ReaderFeedbackTip {
    let tip = ReaderFeedbackTip(
      text: comment.text,
      provenanceKind: .singularPreserved,
      supportCount: 1,
      backingComments: [
        ReaderFeedbackBackingComment(
          commentNumber: commentNumber,
          text: comment.text,
          helpfulCount: comment.helpfulCount
        )
      ]
    )
    stageReaderFeedback(tips: [tip], comments: readerFeedbackComments)
    return tip
  }

  func acceptReaderFeedbackTip(_ tip: ReaderFeedbackTip, approvedText: String) {
    let trimmed = approvedText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    var blocks = readerFeedbackBlocks
    blocks.append(ParsedRecipeReaderFeedbackBlock(text: trimmed))
    readerFeedbackBlocks = blocks
    discardReaderFeedbackTip(tip)
  }

  func discardReaderFeedbackTip(_ tip: ReaderFeedbackTip) {
    readerFeedbackProposals.removeAll { $0.id == tip.id }
  }

  func updateReaderFeedbackBlockText(_ text: String, at index: Int) {
    guard readerFeedbackBlocks.indices.contains(index) else { return }
    var blocks = readerFeedbackBlocks
    blocks[index].text = text
    readerFeedbackBlocks = blocks
  }

  func removeReaderFeedbackBlocks(atOffsets offsets: IndexSet) {
    var blocks = readerFeedbackBlocks
    blocks.remove(atOffsets: offsets)
    readerFeedbackBlocks = blocks
  }
}

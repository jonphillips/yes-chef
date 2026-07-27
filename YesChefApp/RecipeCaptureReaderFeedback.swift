import Foundation
import YesChefCore

extension RecipeCaptureModel {
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
}

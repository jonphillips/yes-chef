public struct AIHandoffReviewResult: Equatable, Sendable {
  public let review: AIHandoffReview
  public let warning: String?

  public init(review: AIHandoffReview, warning: String?) {
    self.review = review
    self.warning = warning
  }
}

public struct AIHandoffReaderFeedbackResult: Equatable, Sendable {
  public let review: AIHandoffReaderFeedbackReview
  public let warning: String?

  public init(review: AIHandoffReaderFeedbackReview, warning: String?) {
    self.review = review
    self.warning = warning
  }
}

public extension RecipeNoteType {
  var displayTitle: String {
    switch self {
    case .general: "General"
    case .adaptation: "Adaptation"
    case .readerFeedback: "Reader Feedback"
    case .makeAhead: "Make-ahead"
    case .freezing: "Freezing"
    case .thawing: "Thawing"
    case .shopping: "Shopping"
    case .serving: "Serving"
    case .equipment: "Equipment"
    case .scaling: "Scaling"
    case .wine: "Wine"
    case .retrospective: "Retrospective"
    case .warning: "Warning"
    }
  }
}

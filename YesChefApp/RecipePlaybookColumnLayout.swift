import SwiftUI

enum RecipePlaybookColumnPreferences {
  static let visibilityStorageKey = "RecipeReader.isPlaybookColumnVisible"
  static let detentStorageKey = "RecipeReader.playbookColumnDetent"
}

enum MenuPlaybookColumnPreferences {
  static let visibilityStorageKey = "MenuReader.isPlaybookColumnVisible"
  static let detentStorageKey = "MenuReader.playbookColumnDetent"
}

enum RecipePlaybookColumnDetent: String, CaseIterable {
  case comfortable
  case wide

  var title: String {
    switch self {
    case .comfortable: "Comfortable"
    case .wide: "Wide"
    }
  }

  var next: Self {
    let index = Self.allCases.firstIndex(of: self) ?? 0
    return Self.allCases[(index + 1) % Self.allCases.count]
  }

  var previous: Self {
    let index = Self.allCases.firstIndex(of: self) ?? 0
    return Self.allCases[(index + Self.allCases.count - 1) % Self.allCases.count]
  }
}

enum RecipeWideColumnMetrics {
  // Matches the established chat-workspace resize affordance, including the
  // control's VoiceOver-adjustable action and visual grip dimensions below.
  static let resizeHandleWidth: CGFloat = 22
  static let separatorWidth: CGFloat = 1
  static let resizeGripWidth: CGFloat = 5
  static let resizeGripHeight: CGFloat = 48
}

struct RecipeWideColumnLayout {
  // The device pass tuned Ingredients to 90% of its prior 30% share while
  // preserving the Directions floor. The detents evenly divide only the
  // remaining width, so no device-specific Playbook width is encoded here.
  private static let ingredientsColumnFraction: CGFloat = 0.27
  private static let directionsMinimumFraction: CGFloat = 0.30

  let width: CGFloat
  let isPlaybookVisible: Bool

  var ingredientsWidth: CGFloat {
    width * Self.ingredientsColumnFraction
  }

  private var directionsMinimumWidth: CGFloat {
    width * Self.directionsMinimumFraction
  }

  private var maximumPlaybookWidth: CGFloat {
    guard isPlaybookVisible else { return 0 }
    return max(
      0,
      width
        - ingredientsWidth
        - directionsMinimumWidth
        - RecipeWideColumnMetrics.separatorWidth
        - RecipeWideColumnMetrics.resizeHandleWidth
    )
  }

  func playbookWidth(for detent: RecipePlaybookColumnDetent) -> CGFloat {
    let index = RecipePlaybookColumnDetent.allCases.firstIndex(of: detent) ?? 0
    let fraction = CGFloat(index + 1) / CGFloat(RecipePlaybookColumnDetent.allCases.count)
    return maximumPlaybookWidth * fraction
  }

  func directionsWidth(playbookWidth: CGFloat) -> CGFloat {
    width
      - ingredientsWidth
      - RecipeWideColumnMetrics.separatorWidth
      - (isPlaybookVisible ? RecipeWideColumnMetrics.resizeHandleWidth + playbookWidth : 0)
  }

  func proposedPlaybookWidth(base: CGFloat, translation: CGFloat) -> CGFloat {
    min(max(base - translation, 0), maximumPlaybookWidth)
  }

  func nearestDetent(to playbookWidth: CGFloat) -> RecipePlaybookColumnDetent {
    RecipePlaybookColumnDetent.allCases.min { lhs, rhs in
      abs(self.playbookWidth(for: lhs) - playbookWidth)
        < abs(self.playbookWidth(for: rhs) - playbookWidth)
    } ?? .comfortable
  }
}

struct MenuWideColumnLayout {
  // Match the recipe's Directions readability floor. The detents divide only
  // the remaining width, keeping this a relative layout rather than a device-
  // specific menu width decision.
  private static let bodyMinimumFraction: CGFloat = 0.30

  let width: CGFloat
  let isPlaybookVisible: Bool

  var bodyMinimumWidth: CGFloat {
    width * Self.bodyMinimumFraction
  }

  private var maximumPlaybookWidth: CGFloat {
    guard isPlaybookVisible else { return 0 }
    return max(
      0,
      width
        - bodyMinimumWidth
        - RecipeWideColumnMetrics.resizeHandleWidth
    )
  }

  func playbookWidth(for detent: RecipePlaybookColumnDetent) -> CGFloat {
    let index = RecipePlaybookColumnDetent.allCases.firstIndex(of: detent) ?? 0
    let fraction = CGFloat(index + 1) / CGFloat(RecipePlaybookColumnDetent.allCases.count)
    return maximumPlaybookWidth * fraction
  }

  func bodyWidth(playbookWidth: CGFloat) -> CGFloat {
    width - (isPlaybookVisible ? RecipeWideColumnMetrics.resizeHandleWidth + playbookWidth : 0)
  }

  func proposedPlaybookWidth(base: CGFloat, translation: CGFloat) -> CGFloat {
    min(max(base - translation, 0), maximumPlaybookWidth)
  }

  func nearestDetent(to playbookWidth: CGFloat) -> RecipePlaybookColumnDetent {
    RecipePlaybookColumnDetent.allCases.min { lhs, rhs in
      abs(self.playbookWidth(for: lhs) - playbookWidth)
        < abs(self.playbookWidth(for: rhs) - playbookWidth)
    } ?? .comfortable
  }
}

struct RecipeWideColumnSeparator: View {
  var body: some View {
    Rectangle()
      .fill(.separator)
      .frame(width: RecipeWideColumnMetrics.separatorWidth)
  }
}

struct RecipePlaybookResizeHandle: View {
  let detent: RecipePlaybookColumnDetent
  let cycle: () -> Void
  let decrement: () -> Void
  let increment: () -> Void

  var body: some View {
    Button(action: cycle) {
      ZStack {
        Rectangle()
          .fill(.separator)
          .frame(width: RecipeWideColumnMetrics.separatorWidth)
        Capsule()
          .fill(.secondary.opacity(0.55))
          .frame(
            width: RecipeWideColumnMetrics.resizeGripWidth,
            height: RecipeWideColumnMetrics.resizeGripHeight
          )
      }
      .frame(
        minWidth: RecipeWideColumnMetrics.resizeHandleWidth,
        maxWidth: RecipeWideColumnMetrics.resizeHandleWidth,
        maxHeight: .infinity
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Text("Directions and Playbook split"))
    .accessibilityValue(Text(detent.title))
    .accessibilityHint(Text("Cycles between comfortable and wide Playbook widths."))
    .accessibilityAdjustableAction { direction in
      switch direction {
      case .increment:
        increment()
      case .decrement:
        decrement()
      @unknown default:
        break
      }
    }
  }
}

import SwiftUI

enum RecipePlaybookColumnPreferences {
  static let visibilityStorageKey = "RecipeReader.isPlaybookColumnVisible"
  static let detentStorageKey = "RecipeReader.playbookColumnDetent"
}

enum RecipePlaybookColumnDetent: String, CaseIterable {
  case peek
  case comfortable
  case wide

  var title: String {
    switch self {
    case .peek: "Peek"
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
  // Ingredients yield some width to the method column; Directions keeps the same
  // minimum. The three detents evenly divide only the remaining width, so no
  // device-specific Playbook width is being decided before the device pass.
  private static let contentColumnFraction: CGFloat = 0.30

  let width: CGFloat
  let isPlaybookVisible: Bool

  var ingredientsWidth: CGFloat {
    width * Self.contentColumnFraction
  }

  private var directionsMinimumWidth: CGFloat {
    width * Self.contentColumnFraction
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
    .accessibilityHint(Text("Cycles between peek, comfortable, and wide Playbook widths."))
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

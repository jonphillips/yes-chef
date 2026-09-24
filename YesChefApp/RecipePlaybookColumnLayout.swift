import Foundation
import SwiftUI

enum MenuPlaybookColumnPreferences {
  static let visibilityStorageKey = "MenuReader.isPlaybookColumnVisible"
  static let detentsStorageKey = "MenuReader.playbookColumnDetents"

  static func detents(from data: Data) -> [String: RecipePlaybookColumnDetent] {
    (try? JSONDecoder().decode([String: RecipePlaybookColumnDetent].self, from: data)) ?? [:]
  }

  static func encodedDetents(_ detents: [String: RecipePlaybookColumnDetent]) -> Data {
    (try? JSONEncoder().encode(detents)) ?? Data()
  }
}

enum MenuPlaybookColumnMetrics {
  // Starts above the observed ~700pt multitasking pane so the optional
  // Playbook column never forces a cramped two-column reader. Device-pass tune knob.
  static let twoColumnThreshold: CGFloat = 820
}

enum RecipePlaybookColumnDetent: String, CaseIterable, Codable, Equatable {
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

enum PlaybookColumnMetrics {
  // Matches the established chat-workspace resize affordance, including the
  // control's VoiceOver-adjustable action and visual grip dimensions below.
  static let resizeHandleWidth: CGFloat = 22
  static let separatorWidth: CGFloat = 1
  static let resizeGripWidth: CGFloat = 5
  static let resizeGripHeight: CGFloat = 48
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
        - PlaybookColumnMetrics.resizeHandleWidth
    )
  }

  func playbookWidth(for detent: RecipePlaybookColumnDetent) -> CGFloat {
    let index = RecipePlaybookColumnDetent.allCases.firstIndex(of: detent) ?? 0
    let fraction = CGFloat(index + 1) / CGFloat(RecipePlaybookColumnDetent.allCases.count)
    return maximumPlaybookWidth * fraction
  }

  func bodyWidth(playbookWidth: CGFloat) -> CGFloat {
    width - (isPlaybookVisible ? PlaybookColumnMetrics.resizeHandleWidth + playbookWidth : 0)
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
      .frame(width: PlaybookColumnMetrics.separatorWidth)
  }
}

struct RecipePlaybookResizeHandle: View {
  let detent: RecipePlaybookColumnDetent
  let splitAccessibilityLabel: String
  let cycle: () -> Void
  let decrement: () -> Void
  let increment: () -> Void

  init(
    detent: RecipePlaybookColumnDetent,
    splitAccessibilityLabel: String = "Directions and Playbook split",
    cycle: @escaping () -> Void,
    decrement: @escaping () -> Void,
    increment: @escaping () -> Void
  ) {
    self.detent = detent
    self.splitAccessibilityLabel = splitAccessibilityLabel
    self.cycle = cycle
    self.decrement = decrement
    self.increment = increment
  }

  var body: some View {
    Button(action: cycle) {
      ZStack {
        Rectangle()
          .fill(.separator)
          .frame(width: PlaybookColumnMetrics.separatorWidth)
        Capsule()
          .fill(.secondary.opacity(0.55))
          .frame(
            width: PlaybookColumnMetrics.resizeGripWidth,
            height: PlaybookColumnMetrics.resizeGripHeight
          )
      }
      .frame(
        minWidth: PlaybookColumnMetrics.resizeHandleWidth,
        maxWidth: PlaybookColumnMetrics.resizeHandleWidth,
        maxHeight: .infinity
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Text(splitAccessibilityLabel))
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

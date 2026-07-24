import SwiftUI
import YesChefCore

/// The section-picking control shared by the playbook's Ask ▾ launcher and the open chat panel's
/// title (ADR-0045 Amd 2). One affordance, two placements: pick a Playbook section to open a chat
/// scoped to it, or move an already-open discussion there.
struct ChatSectionMenu: View {
  let activeSection: PlaybookSectionKind?
  let select: (PlaybookSectionKind) -> Void

  var body: some View {
    Menu {
      ForEach(PlaybookSectionKind.allCases) { section in
        Button {
          select(section)
        } label: {
          Text(section.chatMenuTitle)
          if section == activeSection {
            Image(systemName: "checkmark")
          }
        }
      }
    } label: {
      HStack(spacing: 3) {
        Text(activeSection?.chatMenuTitle ?? "Discuss")
          .font(.headline)
        Image(systemName: "chevron.down")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
      .foregroundStyle(.primary)
    }
    .accessibilityLabel(Text("Discuss section"))
    .accessibilityHint(Text("Move this discussion to another Playbook section."))
  }
}

extension PlaybookSectionKind {
  var chatMenuTitle: String {
    switch self {
    case .makeAhead: "Make-ahead"
    case .chefItUp: "Chef It Up"
    case .serveWith: "Serve With"
    }
  }
}

import SwiftUI
import YesChefCore

/// The panel's section-picking control. The playbook's Ask opens an unseeded panel; Discuss ▾ then
/// starts or moves a section-scoped discussion (ADR-0045 Amd 3).
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

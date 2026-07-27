import SwiftUI
import YesChefCore

/// The panel's discussion-starter picker. Hosts decide which prompts they offer; the playbook's
/// Ask opens an unseeded panel and Discuss ▾ starts or moves a guided discussion (ADR-0045 Amd 3).
struct ChatStarterMenu: View {
  let starters: [ChatSurface.ChatStarter]
  let activeStarterID: ChatSurface.ChatStarter.ID?
  let select: (ChatSurface.ChatStarter.ID) -> Void

  private var activeStarter: ChatSurface.ChatStarter? {
    starters.first { $0.id == activeStarterID }
  }

  var body: some View {
    Menu {
      ForEach(starters) { starter in
        Button {
          select(starter.id)
        } label: {
          Text(starter.title)
          if starter.id == activeStarterID {
            Image(systemName: "checkmark")
          }
        }
      }
    } label: {
      HStack(spacing: 3) {
        Text(activeStarter?.title ?? "Discuss")
          .font(.headline)
        Image(systemName: "chevron.down")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
      .foregroundStyle(.primary)
    }
    .accessibilityLabel(Text("Discuss"))
    .accessibilityHint(Text("Choose a starter for a guided discussion."))
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

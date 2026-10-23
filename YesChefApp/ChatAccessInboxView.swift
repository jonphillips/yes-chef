import SwiftUI
import YesChefCore

struct ChatAccessInboxSection: View {
  let model: ChatAccessInboxModel

  var body: some View {
    if model.inboxCount > 0 || model.message != nil {
      Section {
        if let message = model.message {
          Label(message, systemImage: "exclamationmark.icloud")
            .foregroundStyle(.orange)
        }
        ForEach(model.rows) { row in
          VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
              Text(row.name)
                .font(.headline)
              Spacer()
              if row.downloadState == .downloading {
                Text("Downloading…")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
            Text(row.stagedAt.formatted(date: .omitted, time: .shortened))
              .font(.caption)
              .foregroundStyle(.secondary)
            if let error = model.rowErrors[row.id] {
              Label(error, systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(.orange)
            }
            HStack {
              Button("Open") {
                Task { await model.open(row) }
              }
              .disabled(row.downloadState != .current || model.workingIDs.contains(row.id))

              Button("Discard", role: .destructive) {
                Task { await model.discard(row) }
              }
              .disabled(model.workingIDs.contains(row.id))
            }
          }
          .accessibilityElement(children: .contain)
        }
      } header: {
        Text("From Chat")
      } footer: {
        Text("Open a staged recipe to review and save it, or discard it.")
      }
    }
  }
}

import SwiftUI
import YesChefCore

struct ChatAccessInboxSection: View {
  let model: ChatAccessInboxModel

  var body: some View {
    if model.inboxCount > 0 || !model.returnRows.isEmpty || model.message != nil {
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
              .buttonStyle(.bordered)

              Button("Discard", role: .destructive) {
                Task { await model.discard(row) }
              }
              .disabled(model.workingIDs.contains(row.id))
              .buttonStyle(.bordered)
            }
          }
          .accessibilityElement(children: .contain)
        }
        ForEach(model.returnRows.filter { if case .openable = $0.destination { true } else { false } }) { row in
          returnRow(row)
        }
        if model.returnRows.contains(where: { if case .openable = $0.destination { false } else { true } }) {
          Text("Started on another device")
            .font(.headline)
          ForEach(model.returnRows.filter { if case .openable = $0.destination { false } else { true } }) { row in
            returnRow(row)
          }
        }
      } header: {
        Text("From Chat")
      } footer: {
        Text("Open a staged recipe to review and save it, or discard it.")
      }
    }
  }

  private func returnRow(_ row: ChatAccessInbox.ReturnRow) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(row.title).font(.headline)
        Spacer()
        if row.downloadState == .downloading { Text("Downloading…").font(.caption).foregroundStyle(.secondary) }
      }
      Text(row.stagedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
      if case .capture = row.destination {
        Text("This return can only be opened in the capture editor that started it.")
          .font(.footnote).foregroundStyle(.secondary)
      }
      if let error = model.rowErrors[row.id] {
        Label(error, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.orange)
      }
      HStack {
        if case .openable = row.destination {
          Button("Open") { Task { await model.open(row) } }
            .disabled(row.downloadState != .current || model.workingIDs.contains(row.id))
            .buttonStyle(.bordered)
        }
        Button("Copy") { Task { await model.copy(row) } }
          .disabled(row.downloadState != .current || model.workingIDs.contains(row.id))
          .buttonStyle(.bordered)
        if case .openable = row.destination {
          Button("Discard", role: .destructive) { Task { await model.discard(row) } }
            .disabled(model.workingIDs.contains(row.id))
            .buttonStyle(.bordered)
        }
      }
    }
    .attentionCard()
    .accessibilityElement(children: .contain)
  }
}

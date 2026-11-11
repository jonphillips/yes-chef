import SwiftUI
import YesChefCore

struct ChatAccessInboxSection: View {
  let model: ChatAccessInboxModel

  var body: some View {
    @Bindable var model = model
    if model.hasContent {
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
        ForEach(model.recipeReturnRows) { row in
          VStack(alignment: .leading, spacing: 8) {
            Text(row.title).font(.headline)
            Text(row.stagedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
            if row.downloadState == .downloading { Text("Downloading…").font(.caption).foregroundStyle(.secondary) }
            if let error = model.rowErrors[row.id] {
              Label(error, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.orange)
            }
            HStack {
              if case .openable = row.destination {
                Button("Open") { Task { await model.open(row) } }
                  .disabled(row.downloadState != .current || model.workingIDs.contains(row.id))
                  .buttonStyle(.bordered)
              }
              Button("Discard", role: .destructive) { Task { await model.discard(row) } }
                .disabled(model.workingIDs.contains(row.id))
                .buttonStyle(.bordered)
            }
          }
          .accessibilityElement(children: .contain)
        }
        ForEach(model.menuRows) { row in
          VStack(alignment: .leading, spacing: 8) {
            Text(row.title).font(.headline)
            Text(row.stagedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
            if row.downloadState == .downloading { Text("Downloading…").font(.caption).foregroundStyle(.secondary) }
            if let error = model.rowErrors[row.id] {
              Label(error, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.orange)
            }
            HStack {
              Button("Open") { Task { await model.open(row) } }
                .disabled(row.downloadState != .current || model.workingIDs.contains(row.id))
                .buttonStyle(.bordered)
              Button("Discard", role: .destructive) { Task { await model.discard(row) } }
                .disabled(model.workingIDs.contains(row.id))
                .buttonStyle(.bordered)
            }
          }
          .accessibilityElement(children: .contain)
        }
        ForEach(model.menuDayRows) { row in
          VStack(alignment: .leading, spacing: 8) {
            Text(row.title).font(.headline)
            Text(row.stagedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
            if row.downloadState == .downloading { Text("Downloading…").font(.caption).foregroundStyle(.secondary) }
            if let error = model.rowErrors[row.id] {
              Label(error, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.orange)
            }
            HStack {
              if row.canOpen {
                Button("Open") { Task { await model.open(row) } }
                  .disabled(row.downloadState != .current || model.workingIDs.contains(row.id))
                  .buttonStyle(.bordered)
              }
              Button("Discard", role: .destructive) { Task { await model.discard(row) } }
                .disabled(model.workingIDs.contains(row.id))
                .buttonStyle(.bordered)
            }
          }
          .accessibilityElement(children: .contain)
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
        Text("Open a staged recipe return, menu or menu day to review it, or discard it.")
      }
      .sheet(item: $model.review) { review in
        switch review {
        case let .menu(menuReview):
          ChatMenuReviewSheet(
            model: menuReview,
            isCreating: model.workingIDs.contains(menuReview.row.id),
            create: { await model.createMenu(from: menuReview) }
          )
        case let .menuDay(menuDayReview):
          ChatMenuDayReviewSheet(
            model: menuDayReview,
            isApplying: model.workingIDs.contains(menuDayReview.row.id),
            apply: { await model.applyMenuDay(from: menuDayReview) }
          )
        }
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

struct FromChatView: View {
  let model: ChatAccessInboxModel

  var body: some View {
    Form {
      ChatAccessInboxSection(model: model)
      if !model.hasContent {
        ContentUnavailableView(
          "Nothing from Chat",
          systemImage: "tray.and.arrow.down",
          description: Text("Recipes, returns and menus that ChatGPT stages show up here for you to review.")
        )
      }
    }
    .navigationTitle(AppSection.fromChat.title)
  }
}

import CloudSyncKit
import SwiftUI
import YesChefCore
#if DEBUG
import UIKit
#endif

/// The sync-health row in Settings (jon-platform ADR-0003): a colored dot + one line
/// saying whether CloudKit sync is live, local-only, or broken — tappable to a small
/// detail with the reason, pending count, and a "Try again". When the gate is off, the
/// row is the enable affordance. This closes the silent-degradation gap Yes Chef still
/// carried after the CloudSyncKit lift.
struct SyncStatusSection: View {
  let model: SyncHealthModel
  @State private var showingDetail = false

  var body: some View {
    Section {
      Button {
        showingDetail = true
      } label: {
        HStack(spacing: 12) {
          SyncStatusDot(status: model.displayStatus)
          Text(model.displayStatus.summary)
            .foregroundStyle(.primary)
          Spacer(minLength: 8)
          Image(systemName: "chevron.right")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.tertiary)
        }
      }
    } header: {
      Text("Sync")
    }
    .sheet(isPresented: $showingDetail) {
      SyncStatusDetailView(model: model)
    }
  }
}

/// The colored dot — the one glanceable "is sync healthy?" signal. Color is pure
/// presentation, so it lives here rather than on the domain-free `SyncDisplayStatus`.
private struct SyncStatusDot: View {
  let status: SyncDisplayStatus

  var body: some View {
    Circle()
      .fill(color)
      .frame(width: 10, height: 10)
      .accessibilityHidden(true)
  }

  private var color: Color {
    switch status {
    case .disabled: .secondary
    case .localOnly: .orange
    case .syncing, .downloading: .blue
    case .needsAttention: .orange
    case .upToDate: .green
    case .error: .red
    }
  }
}

/// The tap-through detail: the human summary, the reason / pending count, and the
/// primary action — "Turn on sync" when the gate is off, "Try again" otherwise.
struct SyncStatusDetailView: View {
  let model: SyncHealthModel
  @Environment(\.dismiss) private var dismiss
  @State private var isConfirmingRestoreSyncEnablement = false
  @State private var isConfirmingLeftoverDelete = false

  var body: some View {
    NavigationStack {
      Form {
        Section {
          LabeledContent("Status", value: model.displayStatus.summary)
          if let detail = detailLine {
            LabeledContent("Details", value: detail)
          }
        } footer: {
          Text(explanation)
        }

        if !model.notUploadedRows.isEmpty {
          Section {
            ForEach(model.notUploadedRows) { row in
              HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                  Text(row.title)
                    .foregroundStyle(.primary)
                  Text(row.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if !row.primaryKeys.isEmpty {
                  Button {
                    Task { await model.retry(row) }
                  } label: {
                    if model.isRetrying(row) {
                      ProgressView()
                        .controlSize(.small)
                    } else {
                      Text("Retry")
                    }
                  }
                  .accessibilityLabel("Retry \(row.title)")
                  .disabled(model.isRetrying(row))
                }
              }
            }
            if let retryError = model.retryError {
              Text(retryError)
                .font(.footnote)
                .foregroundStyle(.red)
            }
          } header: {
            Text("Not uploaded")
          } footer: {
            Text("Retry asks iCloud to send these records again. If a record still cannot sync, it will remain here.")
          }
        }

        Section {
          Button {
            Task { await model.checkForLeftovers() }
          } label: {
            HStack {
              Text("Check iCloud for leftovers")
              if model.isCheckingLeftovers {
                Spacer()
                ProgressView()
              }
            }
          }
          .disabled(model.isCheckingLeftovers || model.isDeletingLeftovers)

          if let error = model.leftoverCheckError {
            Text(error)
              .font(.footnote)
              .foregroundStyle(.red)
          }

          if let summary = model.leftoverDeleteSummary {
            Text(summary)
              .font(.footnote)
              .textSelection(.enabled)
          }

          if let report = model.leftoverReport {
            if report.leftovers.isEmpty {
              Text("No leftover records found.")
                .foregroundStyle(.secondary)
            }
            ForEach(model.leftoverDisplayGroups) { group in
              VStack(alignment: .leading, spacing: 7) {
                Text(group.title)
                  .font(.headline)
                ForEach(group.rows) { row in
                  Text("\(row.kind): \(row.detail)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(.leading, 8)
                }
              }
              .padding(.vertical, 4)
            }

            if !report.unregisteredTypeCounts.isEmpty {
              VStack(alignment: .leading, spacing: 4) {
                Text("Other iCloud record types")
                  .font(.subheadline.weight(.medium))
                ForEach(report.unregisteredTypeCounts.keys.sorted(), id: \.self) { type in
                  LabeledContent(type, value: report.unregisteredTypeCounts[type, default: 0].formatted())
                    .font(.footnote)
                }
              }
            }

            if !report.fetchFailures.isEmpty {
              Text("Couldn’t fetch the details for \(report.fetchFailures.count) possible records. Those records weren’t offered for deletion.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            if model.leftoverCount > 0 {
              Button {
                isConfirmingLeftoverDelete = true
              } label: {
                HStack {
                  Text("Delete from iCloud…")
                  if model.isDeletingLeftovers {
                    Spacer()
                    ProgressView()
                  }
                }
              }
              .foregroundStyle(.red)
              .disabled(model.isDeletingLeftovers || model.isCheckingLeftovers)
            }
          }
        } header: {
          Text("Lost deletes")
        } footer: {
          Text("This on-demand check compares iCloud with this device after fetching changes. Review every record before deleting; other devices will remove the copies after they sync.")
        }

        Section {
          Button {
            Task { await primaryAction() }
          } label: {
            HStack {
              Text(primaryActionTitle)
              if model.isStarting {
                Spacer()
                ProgressView()
              }
            }
          }
          .disabled(model.isStarting)
        }

        Section {
          if model.recordCounts.isEmpty {
            ProgressView()
          } else {
            ForEach(model.recordCounts) { row in
              LabeledContent(row.name, value: row.count.formatted())
                .monospacedDigit()
            }
          }
        } header: {
          Text("Local record counts")
        } footer: {
          Text("Rows in this device's database, per synced table. Compare across devices to see which records actually arrived.")
        }

        #if DEBUG
        Section {
          Button {
            Task { await model.diagnoseSyncFailure() }
          } label: {
            if model.isDiagnosingSyncFailure {
              HStack {
                Text("Diagnosing…")
                Spacer()
                ProgressView()
              }
            } else {
              Text("Diagnose")
            }
          }
          .disabled(model.isDiagnosingSyncFailure)

          if let error = model.syncFailureDiagnosisError {
            Text(error)
              .font(.footnote)
              .foregroundStyle(.red)
          }
          if let readout = model.syncFailureDiagnosisReadout {
            Button("Copy diagnosis") {
              UIPasteboard.general.string = readout
            }
            Text(readout)
              .font(.system(.caption, design: .monospaced))
              .textSelection(.enabled)
          }
        } header: {
          Text("Sync diagnosis")
        } footer: {
          Text("Read-only details for troubleshooting. Copy the report to share it with the architect.")
        }
        #endif
      }
      .task {
        await model.refresh()
        await model.loadRecordCounts()
      }
      .navigationTitle("Sync")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
      .alert("Turn On iCloud Sync?", isPresented: $isConfirmingRestoreSyncEnablement) {
        Button("Turn On Sync") {
          Task { await model.enableSyncButtonTapped() }
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text(
          "This device was restored from a backup. Turning sync on uploads that restored library to iCloud and every other device, overwriting what is there — and recipes you deleted since the backup will come back.\n\nIf you only wanted this device restored, keep sync off."
        )
      }
      .confirmationDialog(
        "Delete \(model.leftoverCount) records from iCloud?",
        isPresented: $isConfirmingLeftoverDelete
      ) {
        Button("Delete \(model.leftoverCount) Records", role: .destructive) {
          Task { await model.deleteConfirmedLeftovers() }
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("This permanently deletes these records from iCloud. Copies on Jon’s other devices will be removed after they sync.")
      }
    }
  }

  /// The reason string / pending count, when there is one to show.
  private var detailLine: String? {
    switch model.displayStatus {
    case let .localOnly(reason): reason
    case let .syncing(pending): "\(pending) change\(pending == 1 ? "" : "s") uploading"
    case .downloading: "Downloading changes from iCloud"
    case let .needsAttention(notUploaded, notApplied):
      [
        notUploaded > 0 ? "\(notUploaded) not uploaded" : nil,
        notApplied > 0 ? "\(notApplied) couldn’t be saved here" : nil,
      ].compactMap(\.self).joined(separator: " · ")
    case let .error(message): message
    case .upToDate: "Check iCloud for leftover deletes"
    case .disabled: nil
    }
  }

  private var explanation: String {
    switch model.displayStatus {
    case .disabled:
      "Sync is off, so your recipes stay on this device. Turn it on to share the same recipe box across your devices and household over iCloud."
    case .localOnly:
      "Changes stay on this device until iCloud can sync. Your other devices won’t see each other’s updates yet."
    case .syncing:
      "Uploading recent changes to iCloud."
    case .downloading:
      "Downloading changes from iCloud. A first sync of a large library can take a while — iCloud drip-feeds it and it will finish on its own; keep this device on Wi-Fi and power."
    case .needsAttention:
      "Some changes haven’t reached iCloud, or changes from iCloud couldn’t be saved on this device. This clears once they sync; if it stays, something is stuck."
    case .upToDate:
      "Your recipes are synced across your devices over iCloud. Use Check iCloud for leftovers to look for deletes that did not reach the server."
    case .error:
      "Sync hit an error. Try again — if it persists, check your iCloud account and network."
    }
  }

  private var primaryActionTitle: String {
    switch model.displayStatus {
    case .disabled: "Turn on iCloud sync"
    default: "Try again"
    }
  }

  private func primaryAction() async {
    switch model.displayStatus {
    case .disabled:
      if YesChefCloudSync.isDisabledByRestore() {
        isConfirmingRestoreSyncEnablement = true
      } else {
        await model.enableSyncButtonTapped()
      }
    default: await model.tryAgainButtonTapped()
    }
  }
}

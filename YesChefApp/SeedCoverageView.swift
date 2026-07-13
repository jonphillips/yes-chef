import SwiftUI
import UIKit
import YesChefCore

struct SeedCoverageView: View {
  @State private var model = SeedCoverageModel()

  var body: some View {
    List {
      Section {
        gapRows(model.report.uncovered, emptyMessage: "Every uncovered name has a seed.")
      } header: {
        Text("Uncovered (\(model.report.uncovered.count))")
      }

      Section {
        gapRows(model.report.coveredElsewhere, emptyMessage: "No existing placements need a seed.")
      } header: {
        Text("Covered elsewhere (\(model.report.coveredElsewhere.count))")
      } footer: {
        Text("Tap an entry to copy its seed literal. Add the copied entries to GroceryStoreArea.seedAreas, then rebuild to remove them from this queue.")
      }
    }
    .navigationTitle("Seed Coverage")
    .overlay {
      if let errorMessage = model.errorMessage {
        ContentUnavailableView(
          "Seed coverage unavailable",
          systemImage: "exclamationmark.triangle",
          description: Text(errorMessage)
        )
      }
    }
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Menu("Copy seed entries", systemImage: "doc.on.doc") {
          Button("Copy uncovered (\(model.report.uncovered.count))") {
            copy(model.report.uncovered)
          }
          .disabled(model.report.uncovered.isEmpty)

          Button("Copy covered elsewhere (\(model.report.coveredElsewhere.count))") {
            copy(model.report.coveredElsewhere)
          }
          .disabled(model.report.coveredElsewhere.isEmpty)
        }
      }
    }
    .task { await model.refresh() }
    .task {
      for await _ in NotificationCenter.default.notifications(named: DatabaseChangeBeacon.didChange) {
        await model.refresh()
      }
    }
  }

  @ViewBuilder private func gapRows(
    _ gaps: [SeedCoverageReport.Gap],
    emptyMessage: String
  ) -> some View {
    if gaps.isEmpty {
      Text(emptyMessage)
        .foregroundStyle(.secondary)
    } else {
      ForEach(gaps) { gap in
        Button {
          copy([gap])
        } label: {
          SeedCoverageGapRow(gap: gap)
        }
        .accessibilityLabel(accessibilityLabel(for: gap))
        .accessibilityHint("Copies this seed entry")
      }
    }
  }

  private func copy(_ gaps: [SeedCoverageReport.Gap]) {
    UIPasteboard.general.string = SeedCoverageReport.swiftLiteralEntries(for: gaps)
  }

  private func accessibilityLabel(for gap: SeedCoverageReport.Gap) -> String {
    var label = "\(gap.canonicalName), \(gap.occurrences) occurrence\(gap.occurrences == 1 ? "" : "s")"
    if let suggestedArea = gap.suggestedArea {
      label += ", suggested area \(suggestedArea.title)"
    }
    return label
  }
}

private struct SeedCoverageGapRow: View {
  let gap: SeedCoverageReport.Gap

  var body: some View {
    HStack(spacing: 8) {
      Text(gap.canonicalName)
        .foregroundStyle(.primary)
      Text("×\(gap.occurrences)")
        .foregroundStyle(.secondary)
        .monospacedDigit()
      if let suggestedArea = gap.suggestedArea {
        Text(suggestedArea.title)
          .foregroundStyle(.secondary)
      }
      Spacer(minLength: 8)
      Image(systemName: "doc.on.doc")
        .foregroundStyle(.tertiary)
        .accessibilityHidden(true)
    }
  }
}

import Foundation
import SQLiteData
import SwiftUI
import UIKit
import YesChefCore

struct SeedCoverageView: View {
  @Fetch(SeedCoverageReportRequest(), animation: .default) private var report = SeedCoverageReport()
  @State private var model = SeedCoverageModel()
  @State private var reviewScope: LearnedAreaAuditScope = .unreviewed

  private var scopedAssignments: [GroceryAreaAssignment] {
    switch reviewScope {
    case .unreviewed:
      report.unreviewedModelAssignments
    case .confirmed:
      report.confirmedModelAssignments
    }
  }

  var body: some View {
    @Bindable var model = model

    List {
      Section {
        Picker("Review status", selection: $reviewScope) {
          ForEach(LearnedAreaAuditScope.allCases) { scope in
            Text("\(scope.title) (\(scope.count(in: report)))").tag(scope)
          }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Placement review status")
      }

      Section {
        if scopedAssignments.isEmpty {
          Text("No \(reviewScope.title.lowercased()) model placements.")
            .foregroundStyle(.secondary)
        } else {
          ForEach(scopedAssignments) { assignment in
            NavigationLink {
              LearnedAreaAuditDetail(assignment: assignment, model: model)
            } label: {
              LearnedAreaAuditRow(assignment: assignment)
            }
          }
        }
      } header: {
        Text("\(reviewScope.title) model placements (\(scopedAssignments.count))")
      } footer: {
        Text("Model placements already persist. Confirming records your review; correcting one creates a user placement that wins permanently. Promoting confirmed placements into the reviewed seed floor is optional.")
      }
    }
    .navigationTitle("Learned Areas")
    .alert("Couldn't save correction", isPresented: $model.isShowingError) {
      Button("OK") {}
    } message: {
      Text(model.errorMessage ?? "Unknown error")
    }
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Menu("Promote confirmed to seed", systemImage: "doc.on.doc") {
          Button("Copy confirmed placements as seed entries") {
            UIPasteboard.general.string = SeedCoverageReport.swiftLiteralEntries(
              for: report.confirmedModelAssignments
            )
          }
          .disabled(report.confirmedModelAssignments.isEmpty)
        }
      }
    }
  }
}

private struct LearnedAreaAuditDetail: View {
  @Environment(\.dismiss) private var dismiss
  @State private var correctedArea: String

  let assignment: GroceryAreaAssignment
  let model: SeedCoverageModel

  init(assignment: GroceryAreaAssignment, model: SeedCoverageModel) {
    self.assignment = assignment
    self.model = model
    _correctedArea = State(initialValue: assignment.area)
  }

  var body: some View {
    Form {
      Section("Model placement") {
        LabeledContent("Ingredient", value: assignment.canonicalName)
        LabeledContent("Aisle", value: assignment.area)
      }

      Section {
        Button("Confirm model placement") {
          if model.confirmButtonTapped(assignment: assignment) {
            dismiss()
          }
        }
      } header: {
        Text("Audit")
      } footer: {
        Text("Confirmation records this placement as reviewed and moves it to Confirmed.")
      }

      Section {
        StackedFormField(title: "Aisle") {
          Picker("Aisle", selection: $correctedArea) {
            ForEach(GroceryStoreArea.canonicalAreas, id: \.self) { area in
              Text(area.title).tag(area.title)
            }
          }
          .labelsHidden()
        }

        Button("Save correction") {
          if model.correctionButtonTapped(assignment: assignment, area: correctedArea) {
            dismiss()
          }
        }
        .disabled(correctedArea == assignment.area)
      } header: {
        Text("Correct placement")
      } footer: {
        Text("A correction becomes a user placement and replaces this model placement.")
      }
    }
    .navigationTitle(assignment.canonicalName)
    .navigationBarTitleDisplayMode(.inline)
  }
}

private struct LearnedAreaAuditRow: View {
  let assignment: GroceryAreaAssignment

  var body: some View {
    LabeledContent(assignment.canonicalName, value: assignment.area)
      .accessibilityLabel("\(assignment.canonicalName), model placement \(assignment.area)")
  }
}

private enum LearnedAreaAuditScope: String, CaseIterable, Hashable, Identifiable {
  case unreviewed
  case confirmed

  var id: Self { self }

  var title: String {
    switch self {
    case .unreviewed: "Unreviewed"
    case .confirmed: "Confirmed"
    }
  }

  func count(in report: SeedCoverageReport) -> Int {
    switch self {
    case .unreviewed: report.unreviewedModelAssignments.count
    case .confirmed: report.confirmedModelAssignments.count
    }
  }
}

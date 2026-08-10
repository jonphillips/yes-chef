import Foundation
import SQLiteData
import SwiftUI
import UIKit
import YesChefCore

struct SeedCoverageView: View {
  @Fetch(SeedCoverageReportRequest(), animation: .default) private var report = SeedCoverageReport()
  @State private var model = SeedCoverageModel()

  var body: some View {
    @Bindable var model = model

    List {
      Section {
        if report.modelAssignments.isEmpty {
          Text("No model placements need review.")
            .foregroundStyle(.secondary)
        } else {
          ForEach(report.modelAssignments) { assignment in
            NavigationLink {
              LearnedAreaAuditDetail(assignment: assignment, model: model)
            } label: {
              LearnedAreaAuditRow(assignment: assignment)
            }
          }
        }
      } header: {
        Text("Model placements (\(report.modelAssignments.count))")
      } footer: {
        Text("Model placements already persist. Keep a correct placement unchanged; correcting one creates a user placement that wins permanently. Promoting a well-worn placement into the reviewed seed floor is optional.")
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
        Menu("Promote to seed", systemImage: "doc.on.doc") {
          Button("Copy model placements as seed entries") {
            UIPasteboard.general.string = SeedCoverageReport.swiftLiteralEntries(for: report.modelAssignments)
          }
          .disabled(report.modelAssignments.isEmpty)
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
          dismiss()
        }
      } header: {
        Text("Audit")
      } footer: {
        Text("Confirmation is a no-op: this learned placement is already durable.")
      }

      Section {
        StackedTextField(title: "Aisle", text: $correctedArea, prompt: "Spices")

        Button("Save correction") {
          if model.correctionButtonTapped(assignment: assignment, area: correctedArea) {
            dismiss()
          }
        }
        .disabled(correctedArea.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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

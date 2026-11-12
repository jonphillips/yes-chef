import SwiftUI

struct KitchenKnowledgeExportView: View {
  @State private var model = KitchenKnowledgeExportModel()

  var body: some View {
    List {
      Section {
        Text("Export your ingredient name fixes, confirmed store areas, and grocery trip switches. Pantry items are never included.")
          .foregroundStyle(.secondary)
        Button {
          Task { await model.exportWhatIveTaught() }
        } label: {
          if model.isExporting {
            Label("Exporting…", systemImage: "arrow.clockwise")
          } else {
            Label("Export What I've Taught", systemImage: "square.and.arrow.up")
          }
        }
        .disabled(model.isExporting)
      }

      if let export = model.export {
        Section("Exported rows") {
          LabeledContent("Name fixes", value: "\(export.nameFixes.count)")
          LabeledContent("Store areas", value: "\(export.areas.count)")
          LabeledContent("Trip switches", value: "\(export.trips.count)")
          LabeledContent("Build", value: export.variant.rawValue.capitalized)
          if let fileURL = model.fileURL {
            ShareLink(item: fileURL) {
              Label("Share Export File", systemImage: "square.and.arrow.up.on.square")
            }
          }
        }
      }
    }
    .navigationTitle("Kitchen Knowledge")
    .alert("Couldn't export knowledge", isPresented: Binding(
      get: { model.errorMessage != nil },
      set: { if !$0 { model.errorMessage = nil } }
    )) {
      Button("OK") { model.errorMessage = nil }
    } message: {
      Text(model.errorMessage ?? "Unknown error")
    }
  }
}

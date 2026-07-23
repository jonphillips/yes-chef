#if DEBUG
import Dependencies
import Observation
import SwiftUI
import YesChefCore

struct ModelCallInventoryView: View {
  @State private var model = ModelCallInventoryModel()

  var body: some View {
    List(model.inventory.entries) { entry in
      ModelCallInventoryRow(entry: entry)
    }
    .navigationTitle("Model Calls")
    .overlay {
      if model.inventory.entries.isEmpty {
        ContentUnavailableView(
          "No Model Calls",
          systemImage: "sparkles",
          description: Text("Calls made during this app run appear here.")
        )
      }
    }
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button("Refresh", systemImage: "arrow.clockwise") {
          Task { await model.refresh() }
        }
      }
    }
    .task { await model.refresh() }
    .refreshable { await model.refresh() }
  }
}

@MainActor
@Observable
final class ModelCallInventoryModel {
  private(set) var inventory = ModelCallInventory()

  @ObservationIgnored @Dependency(\.modelCallRecordCollector) private var collector

  func refresh() async {
    let records = await collector.records()
    inventory.appendNewRecords(from: records)
  }
}

private extension ModelCallInventory.Entry {
  var tierDescription: String {
    switch record.tier {
    case .onDevice:
      "on-device"
    case let .frontier(provider):
      "frontier/\(provider.rawValue)"
    case .frontierPreferred:
      "frontier-preferred"
    }
  }

  var includedLayers: String {
    Self.layersDescription(record.contextLayers.included)
  }

  var omittedLayers: String {
    Self.layersDescription(record.contextLayers.omitted)
  }

  private static func layersDescription(_ layers: Set<ModelCallContextLayer>) -> String {
    guard !layers.isEmpty else { return "None" }
    return layers.map(\.rawValue).sorted().joined(separator: ", ")
  }
}

private struct ModelCallInventoryRow: View {
  let entry: ModelCallInventory.Entry

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline) {
        Text("\(entry.record.surface.rawValue) / \(entry.record.task.rawValue)")
          .font(.headline)
        Spacer()
      }

      LabeledContent("Tier requested", value: entry.tierDescription)
      LabeledContent("Tier resolution", value: entry.record.tierResolution.rawValue)
      LabeledContent("Included context", value: entry.includedLayers)
      LabeledContent("Omitted context", value: entry.omittedLayers)
      LabeledContent("Input", value: "\(entry.record.inputCharacterCount) characters")
      LabeledContent("Budget", value: "\(entry.record.maxTokens) tokens")
      LabeledContent("Effort", value: entry.record.reasoningEffort?.rawValue ?? "default")
    }
    .padding(.vertical, 4)
  }
}
#endif

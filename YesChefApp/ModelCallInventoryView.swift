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

  /// The concrete model a `.frontier` tier *requests*, derived from the
  /// provider's package default (Yes Chef never overrides it). Like
  /// `tierDescription`, this is the requested value, not the resolved one — a
  /// `.frontier` tier degrades to on-device when its key is absent, and
  /// `.frontierPreferred` picks its provider at the boundary. Resolved-model
  /// reporting is S3's job, alongside resolved tier.
  var modelDescription: String {
    switch record.tier {
    case .onDevice:
      "on-device (Apple)"
    case let .frontier(provider):
      provider.defaultModel
    case .frontierPreferred:
      "frontier default (resolved at call)"
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
      Text("\(entry.record.surface.rawValue) / \(entry.record.task.rawValue)")
        .font(.headline)

      LabeledContent("Tier requested", value: entry.tierDescription)
      LabeledContent("Model requested", value: entry.modelDescription)
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

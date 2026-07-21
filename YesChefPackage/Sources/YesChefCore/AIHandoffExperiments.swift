import Foundation

public struct WorkbenchExperiment: Equatable, Sendable, Identifiable {
  public let id: Int
  public var hypothesis: String
  public var change: String
  public var rationale: String

  public init(id: Int, hypothesis: String, change: String, rationale: String) {
    self.id = id
    self.hypothesis = hypothesis
    self.change = change
    self.rationale = rationale
  }
}

public struct AIHandoffWorkbenchExperimentsReview: Equatable, Sendable {
  public let handoffID: AIHandoff.ID
  public let workbenchID: Workbench.ID
  public let experiments: [WorkbenchExperiment]

  public init(
    handoffID: AIHandoff.ID,
    workbenchID: Workbench.ID,
    experiments: [WorkbenchExperiment]
  ) {
    self.handoffID = handoffID
    self.workbenchID = workbenchID
    self.experiments = experiments
  }
}

public extension AIHandoffReturn {
  struct WorkbenchExperimentsReturn: Equatable, Sendable {
    public var experiments: [WorkbenchExperiment]
    public var unparsedBlocks: [String]
  }

  static func workbenchExperiments(from text: String) -> WorkbenchExperimentsReturn {
    let deliverable = splitting(text).deliverable
    var experiments: [WorkbenchExperiment] = []
    var unparsedBlocks: [String] = []
    var currentBlock: [String] = []
    var leadingLines: [String] = []

    func finishCurrentBlock() {
      guard !currentBlock.isEmpty else { return }
      defer { currentBlock = [] }
      guard let fields = experimentFields(in: currentBlock) else {
        unparsedBlocks.append(currentBlock.joined(separator: "\n"))
        return
      }
      experiments.append(
        WorkbenchExperiment(
          id: experiments.count,
          hypothesis: fields.hypothesis,
          change: fields.change,
          rationale: fields.rationale
        )
      )
    }

    for rawLine in deliverable.components(separatedBy: .newlines) {
      if experimentField(in: rawLine)?.label == .hypothesis {
        finishCurrentBlock()
        if !leadingLines.isEmpty {
          unparsedBlocks.append(leadingLines.joined(separator: "\n"))
          leadingLines = []
        }
        currentBlock = [rawLine]
      } else if currentBlock.isEmpty {
        if !rawLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          leadingLines.append(rawLine)
        }
      } else {
        currentBlock.append(rawLine)
      }
    }
    finishCurrentBlock()
    if !leadingLines.isEmpty {
      unparsedBlocks.append(leadingLines.joined(separator: "\n"))
    }
    return WorkbenchExperimentsReturn(experiments: experiments, unparsedBlocks: unparsedBlocks)
  }
}

private enum ExperimentLabel: String, CaseIterable {
  case hypothesis = "Hypothesis"
  case change = "Change"
  case rationale = "Rationale"
}

private func experimentFields(
  in block: [String]
) -> (hypothesis: String, change: String, rationale: String)? {
  let fields = block.compactMap(experimentField(in:))
  let nonBlankLineCount = block.filter {
    !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }.count
  guard nonBlankLineCount == fields.count,
    fields.count == ExperimentLabel.allCases.count,
    fields.map(\.label) == [.hypothesis, .change, .rationale],
    fields.allSatisfy({ !$0.value.isEmpty })
  else {
    return nil
  }
  return (fields[0].value, fields[1].value, fields[2].value)
}

private func experimentField(
  in rawLine: String
) -> (label: ExperimentLabel, value: String)? {
  let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
  for label in ExperimentLabel.allCases {
    let prefix = "\(label.rawValue):"
    guard line.count >= prefix.count,
      line.prefix(prefix.count).caseInsensitiveCompare(prefix) == .orderedSame
    else { continue }
    return (
      label,
      String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    )
  }
  return nil
}

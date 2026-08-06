import SwiftUI
import YesChefCore

struct IngredientLineRow: View {
  let display: IngredientLineDisplay
  let scaledText: String

  private var line: IngredientLine { display.line }

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      if line.isHeader {
        Text(line.originalText.trimmingCharacters(in: CharacterSet(charactersIn: ":").union(.whitespacesAndNewlines)))
          .font(.headline)
      } else {
        Text("•")
          .foregroundStyle(.secondary)
        IngredientLineText(scaledText)
          .font(.body)
          .strikethrough(display.highlight == .removed)
      }
    }
    .foregroundStyle(display.highlight == .removed ? .secondary : .primary)
    .variationHighlightChip(highlightColor)
  }

  private var highlightColor: Color? {
    switch display.highlight {
    case .added: VariationHighlightChip.added
    case .changed: VariationHighlightChip.changed
    case .removed: VariationHighlightChip.removed
    case nil: nil
    }
  }
}

/// A numbered instruction step in the reader. An inserted step reads as an addition in the same
/// grammar as an added ingredient, and a step the variation removes stays visible struck through
/// rather than vanishing — the base procedure is legible underneath the overlay (ADR-0021 D3).
struct InstructionStepRow: View {
  let display: InstructionStepDisplay

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      marker
      Text(display.step.text)
        .strikethrough(display.highlight == .removed)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .foregroundStyle(display.highlight == .removed ? .secondary : .primary)
    .variationHighlightChip(highlightColor)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(accessibilityLabel)
  }

  @ViewBuilder
  private var marker: some View {
    if let number = display.number {
      Text("\(number)")
        .font(.caption.bold())
        .foregroundStyle(.white)
        .frame(width: 26, height: 26)
        .background(Circle().fill(Color.accentColor))
    } else {
      Image(systemName: "minus")
        .font(.caption.bold())
        .foregroundStyle(.white)
        .frame(width: 26, height: 26)
        .background(Circle().fill(Color.secondary))
    }
  }

  private var highlightColor: Color? {
    switch display.highlight {
    case .inserted: VariationHighlightChip.added
    case .removed: VariationHighlightChip.removed
    case nil: nil
    }
  }

  private var accessibilityLabel: String {
    switch display.highlight {
    case .inserted:
      "Step \(display.number.map(String.init) ?? ""), added by this variation. \(display.step.text)"
    case .removed:
      "Removed by this variation. \(display.step.text)"
    case nil:
      "Step \(display.number.map(String.init) ?? ""). \(display.step.text)"
    }
  }
}

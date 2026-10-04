import SwiftUI
import YesChefCore

struct SourceMetadataView: View {
  let source: RecipeSource

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Image(systemName: "book")
        .foregroundStyle(.secondary)
      if let urlString = source.url, let url = URL(string: urlString) {
        Link(source.displayName, destination: url)
      } else {
        Text(source.displayName)
      }
      if let detail = source.compactDetail {
        Text(detail)
          .foregroundStyle(.secondary)
      }
    }
    .lineLimit(1)
    .font(.caption)
  }
}

struct RecipeVariationSelector: View {
  let variations: [RecipeVariation]
  let activeVariationID: RecipeVariation.ID?
  let select: (RecipeVariation.ID?) -> Void
  let manage: () -> Void

  @ViewBuilder
  var body: some View {
    if !variations.isEmpty {
      Menu {
        Button { select(nil) } label: {
          choiceLabel("Base Recipe", isSelected: activeVariationID == nil)
        }
        ForEach(variations) { variation in
          Button { select(variation.id) } label: {
            choiceLabel(variation.name, isSelected: variation.id == activeVariationID)
          }
        }
        Divider()
        Button("Manage Variations", systemImage: "slider.horizontal.3", action: manage)
      } label: {
        HStack(spacing: 6) {
          Image(systemName: "square.stack.3d.up")
          Text(activeVariationName)
            .lineLimit(1)
          Image(systemName: "chevron.up.chevron.down")
            .font(.caption2.weight(.semibold))
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 10)
        .frame(minHeight: 36)
        .background(.quaternary.opacity(0.55), in: Capsule())
      }
      .accessibilityLabel("Recipe variation")
      .accessibilityValue(activeVariationName)
      .accessibilityHint("Choose the recipe version to read or manage variations.")
    }
  }

  private var activeVariationName: String {
    variations.first(where: { $0.id == activeVariationID })?.name ?? "Base Recipe"
  }

  private func choiceLabel(_ title: String, isSelected: Bool) -> some View {
    Label(title, systemImage: isSelected ? "checkmark.circle.fill" : "circle")
      .accessibilityValue(isSelected ? "Selected" : "Not selected")
  }
}

enum RecipeDurationText {
  static func readable(_ minutes: Int) -> String {
    guard minutes >= 60 else { return "\(minutes) min" }
    let hours = minutes / 60
    let remainder = minutes % 60
    return remainder == 0 ? "\(hours) hr" : "\(hours) hr \(remainder) min"
  }
}

private extension RecipeSource {
  var displayName: String {
    firstNonEmpty([name, publicationName, bookTitle, url]) ?? "Source"
  }

  var compactDetail: String? {
    firstNonEmpty([author, publicationName, bookTitle, pageNumber])
  }
}

private func firstNonEmpty(_ values: [String?]) -> String? {
  values
    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
    .first { !$0.isEmpty }
}

struct WorkbenchCandidateLinksView: View {
  let links: [WorkbenchCandidateLink]
  let onRecipeSelected: (RecipeDetailPresentation) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label("Drafted From", systemImage: "arrow.triangle.branch")
        .font(.subheadline.weight(.semibold))
      ForEach(links) { link in
        if let recipeID = link.recipeID {
          Button {
            onRecipeSelected(RecipeDetailPresentation(recipeID: recipeID))
          } label: {
            linkLabel(link)
          }
          .buttonStyle(.plain)
        } else {
          linkLabel(link)
            .foregroundStyle(.secondary)
        }
      }
    }
    .font(.subheadline)
  }

  private func linkLabel(_ link: WorkbenchCandidateLink) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Image(systemName: link.recipeID == nil ? "book.closed" : "arrow.up.right.square")
        .foregroundStyle(.secondary)
      VStack(alignment: .leading, spacing: 2) {
        Text(link.title)
        if let sourceName = link.sourceName {
          Text(sourceName)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
  }
}

extension View {
  func recipeChip() -> some View {
    modifier(RecipeChip())
  }

  @ViewBuilder
  func adjustmentReviewPresentation<Item: Identifiable, Content: View>(
    item: Binding<Item?>,
    usesFullScreenCover: Bool,
    @ViewBuilder content: @escaping (Item) -> Content
  ) -> some View {
    if usesFullScreenCover {
      fullScreenCover(item: item, content: content)
    } else {
      sheet(item: item, content: content)
    }
  }
}

private struct RecipeChip: ViewModifier {
  func body(content: Content) -> some View {
    content
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .overlay {
        Capsule()
          .stroke(.quaternary, lineWidth: 1)
      }
  }
}

struct ScalePanel: View {
  let model: RecipeDetailModel

  var body: some View {
    @Bindable var model = model

    VStack(alignment: .leading, spacing: 16) {
      Label("Scale Ingredients", systemImage: "slider.horizontal.3")
        .font(.headline)

      if let recipe = model.recipe {
        LabeledContent("Original", value: recipe.servingsText ?? recipe.yieldText ?? "Unknown")
          .font(.subheadline)
      }

      VStack(alignment: .leading, spacing: 8) {
        Text("Multiplier")
          .font(.subheadline.bold())

        HStack(spacing: 0) {
          Picker("Whole multiplier", selection: $model.scaleWholePart) {
            ForEach(0...ScaleFraction.maximumWholeMultiplier, id: \.self) { whole in
              Text("\(whole)")
                .tag(whole)
            }
          }
          .pickerStyle(.wheel)
          .frame(width: 96, height: 128)
          .clipped()

          Picker("Fraction", selection: $model.scaleFraction) {
            ForEach(ScaleFraction.allCases) { fraction in
              Text(fraction.label)
                .tag(fraction)
            }
          }
          .pickerStyle(.wheel)
          .frame(width: 112, height: 128)
          .clipped()
        }
      }
      .frame(maxWidth: .infinity, alignment: .center)
      .onChange(of: model.scaleWholePart) { _, _ in
        model.scalePickerChanged()
      }
      .onChange(of: model.scaleFraction) { _, _ in
        model.scalePickerChanged()
      }

      LabeledContent("Multiplier", value: ScaleText.factor(model.scaleFactor))
        .font(.subheadline)
      if let scaledServingsSummary = model.scaledServingsSummary {
        LabeledContent("Makes", value: "~\(scaledServingsSummary)")
          .font(.subheadline)
      }

      HStack {
        LabeledContent("Units", value: "Default")
          .font(.subheadline)
          .foregroundStyle(.secondary)
        Spacer()
        Button("Reset") {
          model.resetScaleButtonTapped()
        }
        .disabled(model.scaleFactor == 1)
      }
    }
    .padding()
    .frame(width: 300)
  }
}

struct WrappingLabels: View {
  let labels: [String]
  let systemImage: String

  var body: some View {
    FlowLayout(spacing: 8) {
      chips
    }
    .font(.caption)
    .foregroundStyle(.secondary)
  }

  @ViewBuilder
  private var chips: some View {
    ForEach(labels, id: \.self) { label in
      Label(label, systemImage: systemImage)
        .recipeChip()
    }
  }
}

struct FlowLayout: Layout {
  var spacing: CGFloat = 8

  func sizeThatFits(
    proposal: ProposedViewSize,
    subviews: Subviews,
    cache: inout Void
  ) -> CGSize {
    let maximumWidth = proposal.width ?? .greatestFiniteMagnitude
    let rows = rows(for: subviews, maximumWidth: maximumWidth)
    return CGSize(
      width: proposal.width ?? rows.map(\.width).max() ?? 0,
      height: rows.reduce(0) { $0 + $1.height } + CGFloat(max(rows.count - 1, 0)) * spacing
    )
  }

  func placeSubviews(
    in bounds: CGRect,
    proposal: ProposedViewSize,
    subviews: Subviews,
    cache: inout Void
  ) {
    var y = bounds.minY
    for row in rows(for: subviews, maximumWidth: bounds.width) {
      var x = bounds.minX
      for item in row.items {
        item.view.place(
          at: CGPoint(x: x, y: y + (row.height - item.size.height) / 2),
          proposal: item.proposal
        )
        x += item.size.width + spacing
      }
      y += row.height + spacing
    }
  }

  private func rows(for subviews: Subviews, maximumWidth: CGFloat) -> [FlowRow] {
    var rows: [FlowRow] = []
    var row = FlowRow()
    for subview in subviews {
      let intrinsicSize = subview.sizeThatFits(.unspecified)
      let proposal = ProposedViewSize(width: min(intrinsicSize.width, maximumWidth), height: nil)
      let size = subview.sizeThatFits(proposal)
      let proposedWidth = row.items.isEmpty ? size.width : row.width + spacing + size.width
      if !row.items.isEmpty, proposedWidth > maximumWidth {
        rows.append(row)
        row = FlowRow()
      }
      row.append(subview, size: size, proposal: proposal, spacing: spacing)
    }
    if !row.items.isEmpty { rows.append(row) }
    return rows
  }

  private struct FlowRow {
    var items: [(view: LayoutSubview, size: CGSize, proposal: ProposedViewSize)] = []
    var width: CGFloat = 0
    var height: CGFloat = 0

    mutating func append(
      _ view: LayoutSubview,
      size: CGSize,
      proposal: ProposedViewSize,
      spacing: CGFloat
    ) {
      width += items.isEmpty ? size.width : spacing + size.width
      height = max(height, size.height)
      items.append((view, size, proposal))
    }
  }
}

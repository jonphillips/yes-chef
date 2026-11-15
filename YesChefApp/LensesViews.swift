import SwiftUI
import YesChefCore

private struct LensRoute: Hashable {
  var id: RecipeLens.ID
  var context: CookbookContext?
}

struct LensesTab: View {
  let model: LensesModel
  let copyModel: CookbookCopyModel
  let cookbookLibraryModel: CookbookLibraryModel
  let contexts: [CookbookContext]
  let onRecipeSelected: (RecipeDetailPresentation) -> Void
  let onBrowseAll: (RecipeBrowserQuery, CookbookContext?) -> Void
  @State private var path: [LensRoute] = []

  @ViewBuilder var body: some View {
    @Bindable var model = model
    NavigationStack(path: $path) {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 24) {
          if model.lensLibrary.lenses.isEmpty {
            ContentUnavailableView {
              Label("No Lenses yet", symbol: .category)
            } description: {
              Text("Build a Lens from one of your recipe labels, then add shelves to organize what fits.")
            } actions: {
              Button("New Lens") { model.destination = .newLens }
                .buttonStyle(.borderedProminent)
            }
          }
          LensGallerySection(title: "My Lenses", model: model, context: nil, onOpen: { path.append($0) })
          ForEach(contexts, id: \.zoneOwnerName) { context in
            LensGallerySection(
              title: context.ownerName,
              model: cookbookLibraryModel.libraryModels(for: context).lenses,
              context: context,
              onOpen: { path.append($0) }
            )
          }
        }
        .padding(.vertical)
      }
      .navigationTitle("Lenses")
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button("New Lens", systemImage: "plus") { model.destination = .newLens }
        }
      }
      .navigationDestination(for: LensRoute.self) { route in
        if let context = route.context {
          LensDetailContent(model: cookbookLibraryModel.libraryModels(for: context).lenses,
            lensID: route.id, onRecipeSelected: onRecipeSelected, context: context,
            copyModel: copyModel, onBrowseAll: { query in onBrowseAll(query, context) })
        } else {
          LensesDetailView(model: model, lensID: route.id, onRecipeSelected: onRecipeSelected,
            copyModel: copyModel,
            onBrowseAll: { query in onBrowseAll(query, nil) })
        }
      }
    }
    .sheet(item: $model.destination) { destination in
      switch destination {
      case .newLens:
        NewLensView(model: model)
      case let .query(context):
        LensQuerySheet(model: model, context: context)
      }
    }
    .onChange(of: model.openLensID, initial: true) { _, id in
      guard let id, path.last?.id != id else { return }
      path.append(LensRoute(id: id, context: nil))
    }
    .onChange(of: model.lensLibrary.lenses) { _, lenses in
      guard let id = model.openLensID, let lens = lenses.first(where: { $0.id == id }) else { return }
      model.open(lens, editing: model.isEditing)
    }
    .alert("Lens Error", isPresented: Binding(
      get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } }
    )) {
      Button("OK") { model.errorMessage = nil }
    } message: { Text(model.errorMessage ?? "") }
  }
}

struct CookbookLensesView: View {
  let context: CookbookContext
  let model: LensesModel
  let copyModel: CookbookCopyModel
  let onRecipeSelected: (RecipeDetailPresentation) -> Void
  let onBrowseAll: (RecipeBrowserQuery) -> Void
  @State private var path: [LensRoute] = []

  var body: some View {
    NavigationStack(path: $path) {
      ScrollView {
        LensGallerySection(title: context.ownerName, model: model, context: context,
          onOpen: { path.append($0) })
          .padding(.vertical)
      }
      .navigationTitle("Lenses")
      .navigationDestination(for: LensRoute.self) { route in
        LensDetailContent(model: model, lensID: route.id, onRecipeSelected: onRecipeSelected,
          context: context, copyModel: copyModel, onBrowseAll: onBrowseAll)
      }
    }
    .environment(\.recipeImageDatabase, context.mirror.database)
  }
}

private struct LensGallerySection: View {
  let title: String
  let model: LensesModel
  let context: CookbookContext?
  let onOpen: (LensRoute) -> Void
  @State private var isEditing = false

  var body: some View {
    @Bindable var model = model
    let lenses = model.lensLibrary.lenses.sorted { $0.sortOrder < $1.sortOrder }
    if !lenses.isEmpty {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Text(title).font(.title2.bold())
          Spacer()
          if context == nil, !lenses.isEmpty {
            Button(isEditing ? "Done" : "Reorder") { isEditing.toggle() }
          }
        }
        if isEditing {
          Text("Drag your Lenses into order.").font(.caption).foregroundStyle(.secondary)
        }
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), alignment: .top)], spacing: 12) {
          ForEach(lenses) { lens in
            LensGalleryCard(lens: lens, model: model, context: context,
              onOpen: { onOpen(LensRoute(id: lens.id, context: context)) })
          }
          .reorderable()
        }
        .reorderContainer(for: RecipeLens.self) { difference in
          guard context == nil, isEditing else { return }
          let before: RecipeLens.ID? = switch difference.destination.position {
          case let .before(id): id
          case .end: nil
          }
          model.applyLensReorder(sources: difference.sources, before: before)
        }
      }
      .padding(.horizontal)
      .confirmationDialog(
        "Delete \(model.pendingDelete?.name ?? "Lens")?", isPresented: Binding(
          get: { model.pendingDelete != nil }, set: { if !$0 { model.pendingDelete = nil } }
        ), titleVisibility: .visible
      ) {
        if let lens = model.pendingDelete {
          Button("Delete", role: .destructive) { model.deleteLens(lens) }
        }
      }
      .alert("Rename Lens", isPresented: Binding(
        get: { model.lensBeingRenamed != nil }, set: { if !$0 { model.lensBeingRenamed = nil } }
      )) {
        TextField("Name", text: $model.lensRenameDraft)
        Button("Save") {
          if let lens = model.lensBeingRenamed { model.renameLens(lens, to: model.lensRenameDraft) }
          model.lensBeingRenamed = nil
        }
        Button("Cancel", role: .cancel) { model.lensBeingRenamed = nil }
      }
    }
  }
}

private struct LensGalleryCard: View {
  let lens: RecipeLens
  let model: LensesModel
  let context: CookbookContext?
  let onOpen: () -> Void

  var body: some View {
    Button(action: onOpen) {
      LensCard(lens: lens, model: model)
    }
    .buttonStyle(.plain)
    .contextMenu {
      if context == nil {
        Button("Rename") { model.lensBeingRenamed = lens }
        Button("Delete Lens", role: .destructive) { model.pendingDelete = lens }
      }
    }
  }
}

private struct LensCard: View {
  let lens: RecipeLens
  let model: LensesModel

  private var evaluation: RecipeLensEvaluation? {
    model.evaluation(for: lens)
  }

  var body: some View {
    let query = (try? RecipeLensQueryCodec.decode(lens.baseQuery)) ?? RecipeBrowserQuery()
    let baseIDs = evaluation?.baseRecipeIDs ?? []
    let recipeResult = RecipeBrowserResult(matchingRecipeIDs: baseIDs, availableFacets: [])
    let rowsByID = Dictionary(uniqueKeysWithValues: model.browser.recipeRows(for: recipeResult).map { ($0.recipe.id, $0) })
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        VStack(alignment: .leading, spacing: 5) {
          Text(lens.name).font(.headline)
          ChipRow(labels: model.browser.selectionLabels(for: query))
        }
        Spacer(minLength: 0)
        Text("\(model.lensLibrary.shelves.filter { $0.lensID == lens.id }.count) shelves")
          .font(.caption).foregroundStyle(.secondary)
      }
      let photoIDs = (evaluation?.shelves.compactMap { shelfResult -> [Recipe.ID]? in
        guard case let .ready(ids) = shelfResult.state else { return nil }
        return ids
      }.first ?? baseIDs).prefix(4)
      LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
        ForEach(Array(photoIDs), id: \.self) { id in
          RecipeThumbnail(data: rowsByID[id]?.thumbnailData)
            .frame(height: 80)
        }
        if photoIDs.count < 4 {
          ForEach(0..<(4 - photoIDs.count), id: \.self) { _ in
            RecipeThumbnail(data: nil).frame(height: 80)
          }
        }
      }
    }
    .padding(12)
    .background(.background, in: RoundedRectangle(cornerRadius: 16))
    .overlay(RoundedRectangle(cornerRadius: 16).stroke(.quaternary))
  }
}

private struct NewLensView: View {
  let model: LensesModel
  @Environment(\.dismiss) private var dismiss
  @State private var search = ""

  var body: some View {
    let availability = model.newLensAvailability
    NavigationStack {
      List {
        ForEach(availability) { facetAvailability in
          Section(facetAvailability.facet.name) {
            ForEach(facetAvailability.values.filter { $0.category.name.localizedCaseInsensitiveContains(search) }) { value in
              Button {
                model.createFromValue(value.category, facet: facetAvailability.facet)
                dismiss()
              } label: {
                HStack {
                  Text(value.category.name)
                  Spacer()
                  Text(value.matchingRecipeCount, format: .number).foregroundStyle(.secondary)
                }
              }
            }
          }
        }
        Section {
          Button("Build a custom base") {
            model.destination = .query(.newBase)
          }
        }
      }
      .searchable(text: $search)
      .navigationTitle("New Lens")
      .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
    }
  }
}

private struct LensesDetailView: View {
  let model: LensesModel
  let lensID: RecipeLens.ID
  let onRecipeSelected: (RecipeDetailPresentation) -> Void
  let copyModel: CookbookCopyModel
  let onBrowseAll: (RecipeBrowserQuery) -> Void

  var body: some View {
    LensDetailContent(model: model, lensID: lensID, onRecipeSelected: onRecipeSelected,
      copyModel: copyModel, onBrowseAll: onBrowseAll)
  }
}

private struct LensDetailContent: View {
  let model: LensesModel
  let lensID: RecipeLens.ID
  let onRecipeSelected: (RecipeDetailPresentation) -> Void
  var context: CookbookContext?
  let copyModel: CookbookCopyModel
  let onBrowseAll: (RecipeBrowserQuery) -> Void
  @State private var shelfTitles: [RecipeLensShelf.ID: String] = [:]
  @State private var remainder = true
  @State private var renameLens = false
  @State private var lensName = ""

  var body: some View {
    @Bindable var model = model
    let lens = model.lensLibrary.lenses.first { $0.id == lensID }
    ScrollView {
      if let lens {
        VStack(alignment: .leading, spacing: 20) {
          if model.isEditing {
            HStack {
              TextField("Lens name", text: $lensName)
                .font(.largeTitle.bold())
                .onSubmit { model.renameLens(lens, to: lensName) }
              Button("Edit base") { model.destination = .query(.editBase(lens.id)) }
            }.padding(.horizontal)
          } else {
            Text(lens.name).font(.largeTitle.bold()).padding(.horizontal)
          }
          ChipRow(labels: model.browser.selectionLabels(for: (try? RecipeLensQueryCodec.decode(lens.baseQuery)) ?? RecipeBrowserQuery()))
            .padding(.horizontal)
          if let evaluation = model.evaluation, case let .unresolved(reasons) = evaluation.baseState {
            ContentUnavailableView {
              Label("Lens base needs repair", systemImage: "exclamationmark.triangle")
            } description: {
              Text(reasons.joined(separator: " "))
            } actions: {
              if model.scope == .mine {
                Button("Fix") { model.destination = .query(.editBase(lens.id)) }
              }
            }
          }
          ForEach(model.visibleShelves(for: lens).map(\.shelf)) { shelf in
            LensShelfView(model: model, shelf: shelf, context: context, copyModel: copyModel,
              onRecipeSelected: onRecipeSelected)
          }
          .reorderable()
          if model.visibleShelves(for: lens).isEmpty, let evaluation = model.evaluation {
            LensBaseRecipesView(model: model, recipeIDs: evaluation.baseRecipeIDs,
              onRecipeSelected: onRecipeSelected)
          }
          if model.isEditing {
            if let evaluation = model.evaluation {
              LensRemainderEditor(model: model, evaluation: evaluation, isOn: $remainder)
            }
            LensSuggestionTray(model: model)
            Button("Add custom shelf") { model.destination = .query(.addShelf(lens.id)) }
              .padding(.horizontal)
          } else if lens.showsRemainder, let evaluation = model.evaluation,
            !evaluation.remainderRecipeIDs.isEmpty {
            LensBaseRecipesView(model: model, recipeIDs: evaluation.remainderRecipeIDs,
              title: "Everything else", onRecipeSelected: onRecipeSelected)
          }
        }
        .padding(.vertical)
        .reorderContainer(for: RecipeLensShelf.self) { difference in
          guard model.isEditing else { return }
          let before: RecipeLensShelf.ID? = switch difference.destination.position {
          case let .before(id): id
          case .end: nil
          }
          model.applyShelfReorder(sources: difference.sources, before: before)
        }
      }
    }
    .navigationTitle(lens?.name ?? "Lens")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItemGroup(placement: .primaryAction) {
        if model.scope == .mine {
          if model.isEditing {
            Button("Done") { model.isEditing = false }
          } else {
            Button("Edit") { model.isEditing = true }
          }
        }
        Button("Browse all") {
          onBrowseAll(model.browseAll())
        }
      }
    }
    .onAppear {
      if model.openLensID != lensID { model.open(id: lensID) }
      if model.openLensID == lensID, let lens, model.activeLens == nil { model.open(lens, editing: model.isEditing) }
      if lensName.isEmpty { lensName = lens?.name ?? "" }
      remainder = lens?.showsRemainder ?? true
    }
    .onChange(of: model.lensLibrary.lenses) { _, lenses in
      guard let lens = lenses.first(where: { $0.id == lensID }) else { return }
      if model.activeLens?.id != lensID { model.open(lens, editing: model.isEditing) }
      if lensName.isEmpty { lensName = lens.name }
    }
    .modifier(CookbookCopyPrompts(copyModel: copyModel, isActive: context != nil, onRecipeSelected: onRecipeSelected))
  }
}

private struct LensShelfView: View {
  let model: LensesModel
  let shelf: RecipeLensShelf
  let context: CookbookContext?
  let copyModel: CookbookCopyModel
  let onRecipeSelected: (RecipeDetailPresentation) -> Void
  @State private var title = ""
  @State private var confirmsShelfCopy = false
  @State private var shelfCopyReport: String?
  @State private var showsAll = false

  @ViewBuilder var body: some View {
    let result = model.evaluation?.shelves.first { $0.shelf.id == shelf.id }
    let ids: [Recipe.ID] = if case let .ready(values) = result?.state { values } else { [] }
    let rows = model.browser.recipeRows(for: RecipeBrowserResult(matchingRecipeIDs: ids, availableFacets: []))
    let isBroken: Bool = if case .unresolved? = result?.state { true } else { false }
    let isEmpty: Bool = if case .empty? = result?.state { true } else { false }
    if isEmpty && !model.isEditing {
      EmptyView()
    } else {
      let copiedIDs = context.flatMap { copyModel.copiedSourceIDsByCookbook[$0.zoneOwnerName] } ?? []
      let uncopiedIDs = ids.filter { !copiedIDs.contains($0) }
      VStack(alignment: .leading, spacing: 10) {
      HStack {
        if model.isEditing {
          TextField("Shelf title", text: $title)
            .font(.title2.bold()).onSubmit { model.renameShelf(shelf, to: title) }
          Text("\(ids.count)").foregroundStyle(.secondary)
          Button { model.destination = .query(.editShelf(shelf.id, lensID: shelf.lensID)) } label: { Image(systemName: "slider.horizontal.3") }
          Button(role: .destructive) { model.deleteShelf(shelf) } label: { Image(symbol: .delete) }
        } else {
          Text(shelf.title).font(.title2.bold())
          Text(isBroken ? "Fix" : String(ids.count)).foregroundStyle(.secondary)
          Spacer()
          if context != nil, !uncopiedIDs.isEmpty {
            Menu {
              Button("Copy \(uncopiedIDs.count) to My Recipes") { confirmsShelfCopy = true }
            } label: { Image(systemName: "ellipsis.circle") }
          }
          if !rows.isEmpty { Button("See all") { showsAll = true } }
        }
      }.padding(.horizontal)
      if isBroken, case let .unresolved(reasons)? = result?.state {
        ContentUnavailableView {
          Label("Shelf needs repair", systemImage: "exclamationmark.triangle")
        } description: {
          Text(reasons.joined(separator: " "))
        } actions: {
          if model.scope == .mine {
            Button("Fix") { model.destination = .query(.editShelf(shelf.id, lensID: shelf.lensID)) }
          }
        }
        .padding(.horizontal)
      }
      if let progress = copyModel.shelfCopyProgress, progress.shelfID == shelf.id, context != nil {
        Text(progress.message).font(.caption).foregroundStyle(.secondary).padding(.horizontal)
      }
      if rows.isEmpty {
        if model.isEditing { Text("0 recipes").font(.caption).foregroundStyle(.secondary).padding(.horizontal) }
      } else {
        ScrollView(.horizontal) {
          LazyHStack(spacing: 12) {
            ForEach(rows) { row in
              Button { onRecipeSelected(model.recipeTapped(row.recipe.id)) } label: {
                RecipeListRow(row: row, options: .init(density: .rich, showsSourceMetadata: true, showsCategoryMetadata: true))
                  .frame(width: 340).contentShape(Rectangle())
              }
              .buttonStyle(.plain)
              .contextMenu {
                if let context {
                  if copiedIDs.contains(row.recipe.id) {
                    Button("Open Mine") {
                      Task {
                        if let copyID = await copyModel.existingCopyID(context: context, sourceID: row.recipe.id) {
                          onRecipeSelected(RecipeDetailPresentation(recipeID: copyID))
                        }
                      }
                    }
                  } else {
                    Button("Copy to My Recipes") {
                      Task { await copyModel.copyButtonTapped(context: context, sourceID: row.recipe.id) }
                    }
                  }
                }
              }
            }
          }.padding(.horizontal)
        }
      }
    }
    .onAppear { if title.isEmpty { title = shelf.title } }
    .confirmationDialog("Copy shelf", isPresented: $confirmsShelfCopy, titleVisibility: .visible) {
      Button("Copy \(uncopiedIDs.count) to My Recipes") {
        guard let context else { return }
        Task {
          let report = await copyModel.copyShelf(context: context, shelfID: shelf.id, sourceIDs: uncopiedIDs)
          let failures = report.failures.isEmpty ? "" : "\n\nFailed:\n" + report.failures.joined(separator: "\n")
          let warnings = report.warnings.isEmpty ? "" : "\n\nWarnings:\n" + report.warnings.joined(separator: "\n")
          shelfCopyReport = "Copied \(report.copied) recipes.\(failures)\(warnings)"
        }
      }
      Button("Cancel", role: .cancel) {}
    }
    .alert("Shelf copy finished", isPresented: Binding(
      get: { shelfCopyReport != nil }, set: { if !$0 { shelfCopyReport = nil } }
    )) {
      Button("OK") { shelfCopyReport = nil }
    } message: { Text(shelfCopyReport ?? "") }
      .sheet(isPresented: $showsAll) {
        LensSeeAllView(title: shelf.title, rows: rows, scope: model.scope,
          onRecipeSelected: onRecipeSelected,
          onCopyShelf: context != nil && !uncopiedIDs.isEmpty ? { confirmsShelfCopy = true } : nil)
      }
    }
  }
}

private struct LensBaseRecipesView: View {
  let model: LensesModel
  let recipeIDs: [Recipe.ID]
  var title = "Recipes"
  let onRecipeSelected: (RecipeDetailPresentation) -> Void

  var body: some View {
    let rows = model.browser.recipeRows(for: RecipeBrowserResult(matchingRecipeIDs: recipeIDs, availableFacets: []))
    VStack(alignment: .leading, spacing: 10) {
      Text(title).font(.title2.bold()).padding(.horizontal)
      if rows.isEmpty {
        ContentUnavailableView {
          Label("No recipes in this Lens", symbol: .recipe)
        }
      } else {
        ScrollView(.horizontal) {
          LazyHStack(spacing: 12) {
            ForEach(rows) { row in
              Button { onRecipeSelected(model.recipeTapped(row.recipe.id)) } label: {
                RecipeListRow(row: row, options: .init(density: .rich, showsSourceMetadata: true, showsCategoryMetadata: true))
                  .frame(width: 340).contentShape(Rectangle())
              }.buttonStyle(.plain)
            }
          }.padding(.horizontal)
        }
      }
    }
  }
}

private struct LensRemainderEditor: View {
  let model: LensesModel
  let evaluation: RecipeLensEvaluation
  @Binding var isOn: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("Everything else").font(.title2.bold())
        Text(evaluation.remainderRecipeIDs.count, format: .number).foregroundStyle(.secondary)
        Spacer()
        Toggle("Show", isOn: $isOn).labelsHidden()
          .onChange(of: isOn) { _, value in model.setShowsRemainder(value) }
      }
      Text("Recipes in the base not covered by a shelf.")
        .font(.caption).foregroundStyle(.secondary)
    }
    .padding(.horizontal)
  }
}

private struct LensSuggestionTray: View {
  let model: LensesModel

  private var suggestions: [RecipeBrowserResult.FacetAvailability] { model.suggestions }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Suggestions").font(.title2.bold())
      ForEach(suggestions) { facet in
        ForEach(facet.values.filter { value in
          !model.alreadyShelvedFacetValues.contains("\(facet.facet.id.uuidString):\(value.category.id.uuidString)")
        }) { value in
          Button { model.addSuggestedShelf(value, facet: facet.facet) } label: {
            HStack {
              Text(value.category.name)
              Spacer()
              Text(value.matchingRecipeCount, format: .number).foregroundStyle(.secondary)
              Image(systemName: "plus.circle")
            }
          }
        }
      }
    }
    .padding(.horizontal)
  }
}

private struct LensQuerySheet: View {
  let model: LensesModel
  let context: LensesModel.Destination.QueryContext
  @Environment(\.dismiss) private var dismiss
  @State private var queryModel: PowerBrowserModel
  @State private var title = ""
  @State private var hasTypedTitle = false
  @FocusState private var isTitleFocused: Bool

  init(model: LensesModel, context: LensesModel.Destination.QueryContext) {
    self.model = model
    self.context = context
    _queryModel = State(initialValue: PowerBrowserModel(scope: model.scope))
  }

  var body: some View {
    @Bindable var queryModel = queryModel
    NavigationStack {
      VStack(spacing: 0) {
        if context.isShelf { Text("\(queryModel.result.matchingRecipeIDs.count) recipes in this Lens").font(.subheadline).padding() }
        PowerBrowserFacetsView(model: queryModel, result: queryModel.result)
        if context.isShelf {
          TextField("Shelf title", text: $title)
            .textFieldStyle(.roundedBorder)
            .focused($isTitleFocused)
            .padding()
        }
      }
      .navigationTitle(context.isBase ? "Edit Base" : "Shelf Query")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            model.saveQuery(queryModel.query, target: context, title: title)
            dismiss()
          }
        }
      }
      .onAppear { loadQuery() }
      .onChange(of: queryModel.query) { _, query in
        guard !hasTypedTitle, context.isShelf else { return }
        title = model.defaultShelfTitle(for: query)
      }
      .onChange(of: title) { _, _ in
        if isTitleFocused { hasTypedTitle = true }
      }
    }
  }

  private func loadQuery() {
    switch context {
    case .newBase: queryModel.query = RecipeBrowserQuery()
    case let .editBase(id):
      if let lens = model.lensLibrary.lenses.first(where: { $0.id == id }) { queryModel.query = (try? RecipeLensQueryCodec.decode(lens.baseQuery)) ?? RecipeBrowserQuery() }
    case let .addShelf(id):
      if let lens = model.lensLibrary.lenses.first(where: { $0.id == id }) {
        let draft = model.customShelfDraft(for: lens)
        queryModel.query = draft.query
        queryModel.restrictedRecipeIDs = draft.restrictedRecipeIDs
        title = draft.title
      }
    case let .editShelf(id, lensID):
      if let shelf = model.lensLibrary.shelves.first(where: { $0.id == id }) {
        queryModel.query = (try? RecipeLensQueryCodec.decode(shelf.query)) ?? RecipeBrowserQuery()
        if let lens = model.lensLibrary.lenses.first(where: { $0.id == lensID }),
          let base = try? RecipeLensQueryCodec.decode(lens.baseQuery) {
          queryModel.restrictedRecipeIDs = Set(model.browser.browserEngine().matchingRecipeIDs(for: base))
        }
        title = shelf.title
      }
    }
  }
}

private extension LensesModel.Destination.QueryContext {
  var isShelf: Bool {
    switch self { case .addShelf, .editShelf: true; case .newBase, .editBase: false }
  }
  var isBase: Bool {
    switch self { case .newBase, .editBase: true; case .addShelf, .editShelf: false }
  }
}

/// Presents `CookbookCopyModel`'s prompts for copies started from a cookbook Lens's shelves. The Lenses tab and a
/// cookbook's Lenses surface both show `LensDetailContent`, so the prompts live with it.
private struct CookbookCopyPrompts: ViewModifier {
  let copyModel: CookbookCopyModel
  let isActive: Bool
  let onRecipeSelected: (RecipeDetailPresentation) -> Void

  func body(content: Content) -> some View {
    content
      .confirmationDialog("Already in My Recipes", isPresented: existingCopiesPresented, titleVisibility: .visible) {
        if case let .existingCopies(_, _, ids)? = copyModel.prompt {
          Button("Open Mine") {
            Task {
              if let id = await copyModel.newestCopy(of: ids) { onRecipeSelected(RecipeDetailPresentation(recipeID: id)) }
              copyModel.clearPrompt()
            }
          }
          Button("Copy Anyway") { Task { await copyModel.copyAnywayButtonTapped() } }
        }
        Button("Cancel", role: .cancel) { copyModel.clearPrompt() }
      } message: { Text("This recipe already has a copy in your library.") }
      .alert("Cookbook Copy", isPresented: copyResultPresented) {
        if case let .copyResult(result)? = copyModel.prompt, !result.uncopiedTargets.isEmpty {
          Button("Copy Them Too") { Task { await copyModel.copyThemTooButtonTapped(result) } }
          Button("Cancel", role: .cancel) { copyModel.clearPrompt() }
        } else if case let .missingTargets(result)? = copyModel.prompt, !result.uncopiedTargets.isEmpty {
          Button("Copy Them Too") { Task { await copyModel.copyThemTooButtonTapped(result) } }
          Button("OK", role: .cancel) { copyModel.clearPrompt() }
        } else {
          Button("OK", role: .cancel) { copyModel.clearPrompt() }
        }
      } message: { Text(copyPromptMessage) }
  }

  private var existingCopiesPresented: Binding<Bool> {
    Binding(get: { if isActive, case .existingCopies? = copyModel.prompt { true } else { false } },
      set: { if !$0 { copyModel.promptDismissed() } })
  }

  private var copyResultPresented: Binding<Bool> {
    Binding(get: {
      guard isActive else { return false }
      return switch copyModel.prompt {
      case .copyResult?, .missingTargets?, .failure?: true
      default: false
      }
    }, set: { if !$0 { copyModel.promptDismissed() } })
  }

  private var copyPromptMessage: String {
    switch copyModel.prompt {
    case let .copyResult(result), let .missingTargets(result):
      let related = result.unlinkedRelated.isEmpty ? [] : ["Related recipes not in your library: " + result.unlinkedRelated.joined(separator: ", ")]
      let serves = result.textOnlyServeWith.isEmpty ? [] : ["Kept as text: " + result.textOnlyServeWith.joined(separator: ", ")]
      return (related + serves + result.warnings).joined(separator: "\n")
    case let .failure(message): return message
    default: return ""
    }
  }
}

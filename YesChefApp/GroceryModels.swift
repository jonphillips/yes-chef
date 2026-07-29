import CasePaths
import Dependencies
import Foundation
import Observation
import SQLiteData
import YesChefCore

typealias CoreGroceryList = YesChefCore.GroceryList

struct GroceryIngredientSelectionPresentation: Identifiable, Sendable {
  let context: GroceryIngredientSelectionContext
  let choices: [GroceryIngredientChoice]

  var id: GroceryIngredientSelectionContext { context }
}

@Observable
@MainActor
final class GroceryLibraryModel {
  @CasePathable
  enum Destination {
    case addCustomItem(GroceryItemEditorDraft)
    case addList(GroceryListEditorDraft)
    case addPantryItem
    case clearAll(CoreGroceryList.ID)
    case clearPurchased(CoreGroceryList.ID)
    case deleteList(CoreGroceryList.ID)
    case editItem(GroceryItemEditorDraft)
    case editList(GroceryListEditorDraft)
    case editPantryItem(PantryItem.ID)
    case selectIngredients(GroceryIngredientSelectionPresentation)
  }

  @ObservationIgnored
  @Dependency(\.date.now) private var now
  @ObservationIgnored
  @Dependency(\.defaultDatabase) private var database
  @ObservationIgnored
  @Dependency(\.uuid) private var uuid
  @ObservationIgnored
  @Dependency(\.continuousClock) private var continuousClock
  @ObservationIgnored
  @Fetch(GroceryListRequest(), animation: .default) var listRows: [GroceryListRowData] = []
  @ObservationIgnored
  @Fetch(GroceryItemListRequest(), animation: .default) var itemRows: [GroceryItemRowData] = []
  @ObservationIgnored
  @Fetch(PantryItemListRequest(), animation: .default) var pantryItems: [PantryItem] = []
  @ObservationIgnored
  @Fetch(MenuListRequest(), animation: .default) var menuRows: [MenuRowData] = []

  var destination: Destination?
  var selectedListID: CoreGroceryList.ID?
  var errorMessage: String?
  var isShowingError = false
  var toastCenter: AppToastCenter?
  var pantryAddBackItemIDsByListID: [CoreGroceryList.ID: Set<GroceryItem.ID>] = [:]
  @ObservationIgnored
  var groceryCategorizationAttemptCache = GroceryCategorizationAttemptCache()
  @ObservationIgnored
  private var categorizationDebounceTask: Task<Void, Never>?
  @ObservationIgnored
  private var categorizationSweepTask: Task<Void, Never>?

  /// Two seconds is the top of the product-approved 1.5–2s quiet window: it keeps rapid
  /// entry responsive while reliably batching a short run of adds into one classifier pass.
  private static let categorizationDebounce = Duration.seconds(2)

  init(toastCenter: AppToastCenter? = nil) {
    self.toastCenter = toastCenter
  }

  var selectedListRow: GroceryListRowData? {
    if let selectedListID,
       let row = listRows.first(where: { $0.id == selectedListID }) {
      return row
    }
    return listRows.first
  }

  var selectedItemRows: [GroceryItemRowData] {
    guard let listID = selectedListRow?.id else { return [] }
    return itemRows.filter { $0.item.groceryListID == listID }
  }

  var pantryStapleNames: [String] {
    pantryItems.map(\.title)
  }

  var selectedDisplaySections: GroceryDisplaySections {
    guard let selectedListID = selectedListRow?.id else {
      return GroceryDisplaySections()
    }
    let evaluation = PantrySuppression.evaluate(
      list: selectedItemRows,
      policies: pantryItems
    )
    return GroceryDisplaySections(
      suppression: PantrySuppression.addBack(
        itemIDs: pantryAddBackItemIDsByListID[selectedListID] ?? [],
        to: evaluation
      )
    )
  }

  var availableMenuRows: [MenuRowData] {
    menuRows.sorted {
      $0.menu.title.localizedStandardCompare($1.menu.title) == .orderedAscending
    }
  }

  func setPrimaryListButtonTapped(listID: CoreGroceryList.ID) {
    do {
      try database.write { db in
        try GroceryRepository.setDefaultList(
          listID: listID,
          in: db,
          now: now
        )
      }
      selectedListID = listID
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
    }
  }

  func deleteListButtonTapped(listID: CoreGroceryList.ID) {
    destination = .deleteList(listID)
  }

  func confirmDeleteListButtonTapped(listID: CoreGroceryList.ID) {
    do {
      let selectedListID = try database.write { db in
        try GroceryRepository.deleteList(
          listID: listID,
          in: db,
          now: now
        )
      }
      self.selectedListID = selectedListID
      destination = nil
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
    }
  }

  func addToPantryButtonTapped(itemID: GroceryItem.ID) {
    guard let row = itemRows.first(where: { $0.item.id == itemID }) else { return }

    do {
      _ = try database.write { db in
        try PantryRepository.addItem(
          title: row.item.title,
          notes: row.item.notes,
          in: db,
          now: now,
          uuid: { uuid() }
        )
      }
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
    }
  }

  func savePantryItemButtonTapped(
    itemID: PantryItem.ID? = nil,
    title: String,
    notes: String,
    policy: PantryPolicy
  ) -> Bool {
    do {
      try database.write { db in
        if let itemID {
          try PantryRepository.updateItem(
            itemID: itemID,
            title: title,
            notes: notes,
            policy: policy,
            in: db,
            now: now
          )
        } else {
          try PantryRepository.addItem(
            title: title,
            notes: notes,
            policy: policy,
            in: db,
            now: now,
            uuid: { uuid() }
          )
        }
      }
      destination = nil
      return true
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
      return false
    }
  }

  func editPantryItemButtonTapped(itemID: PantryItem.ID) {
    destination = .editPantryItem(itemID)
  }

  func deletePantryItemButtonTapped(itemID: PantryItem.ID) {
    do {
      try database.write { db in
        try PantryRepository.deleteItem(itemID: itemID, in: db)
      }
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
    }
  }

  func resetPantryButtonTapped() {
    do {
      _ = try database.write { db in
        try PantryRepository.resetToDefaults(
          in: db,
          now: now,
          uuid: { uuid() }
        )
      }
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
    }
  }

  func togglePurchasedButtonTapped(itemID: GroceryItem.ID) {
    guard let row = itemRows.first(where: { $0.item.id == itemID }) else { return }

    do {
      try database.write { db in
        try GroceryRepository.updatePurchasedState(
          itemID: itemID,
          isPurchased: !row.item.isPurchased,
          in: db,
          now: now
        )
      }
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
    }
  }

  func clearPurchasedButtonTapped(listID: CoreGroceryList.ID) {
    destination = .clearPurchased(listID)
  }

  func confirmClearPurchasedButtonTapped(listID: CoreGroceryList.ID) {
    do {
      _ = try database.write { db in
        try GroceryRepository.clearPurchasedItems(
          groceryListID: listID,
          in: db
        )
      }
      destination = nil
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
    }
  }

  func clearAllButtonTapped(listID: CoreGroceryList.ID) {
    destination = .clearAll(listID)
  }

  func confirmClearAllButtonTapped(listID: CoreGroceryList.ID) {
    do {
      _ = try database.write { db in
        try GroceryRepository.clearAllItems(
          groceryListID: listID,
          in: db
        )
      }
      destination = nil
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
    }
  }

  func deleteButtonTapped(itemID: GroceryItem.ID) {
    do {
      try database.write { db in
        try GroceryRepository.deleteItem(itemID: itemID, in: db)
      }
      removePantryAddBack(itemID: itemID)
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
    }
  }

  func addBackAssumedPantryItemButtonTapped(itemID: GroceryItem.ID) {
    guard let listID = selectedListRow?.id else { return }
    pantryAddBackItemIDsByListID[listID, default: []].insert(itemID)
  }

  func deleteSourceButtonTapped(sourceID: GroceryItemSource.ID) {
    do {
      try database.write { db in
        try GroceryRepository.deleteSource(
          sourceID: sourceID,
          in: db,
          now: now
        )
      }
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
    }
  }

  func deleteContributionButtonTapped(sourceID: GroceryItemSource.ID) {
    do {
      try database.write { db in
        try GroceryRepository.deleteContribution(
          containingSourceID: sourceID,
          in: db,
          now: now
        )
      }
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
    }
  }

  func addSelectedMealRowsButtonTapped(_ rows: [MealPlanItemRowData]) {
    selectMealRowsButtonTapped(rows)
  }

  func selectMealRowsButtonTapped(_ rows: [MealPlanItemRowData]) {
    let recipeRows = rows.filter { $0.item.kind == .recipe && $0.item.recipeID != nil }
    guard !recipeRows.isEmpty else { return }
    let date = recipeRows.first?.item.scheduledDate
    loadIngredientSelection(
      source: .mealPlanRows(recipeRows.map(\.item.id)),
      title: date?.formatted(.dateTime.month(.abbreviated).day()) ?? "Meal Plan",
      subtitle: "Meal Calendar",
      recipeIDs: Set(recipeRows.compactMap(\.item.recipeID))
    )
  }

  func selectMenuButtonTapped(menuID: CoreMenu.ID) {
    guard let menu = menuRows.first(where: { $0.menu.id == menuID })?.menu else { return }
    Task {
      do {
        let presentation = try await database.read { db in
          let recipeIDs = try GroceryMenuRecipeIDsRequest(menuID: menu.id).fetch(db)
          let choices = try GroceryIngredientChoiceRequest(recipeIDs: recipeIDs).fetch(db)
          let title = try Menu.find(menu.id).fetchOne(db)?.title ?? menu.title
          return GroceryIngredientSelectionPresentation(
            context: GroceryIngredientSelectionContext(
              source: .menu(menu.id),
              title: title,
              subtitle: "Menu"
            ),
            choices: choices
          )
        }
        destination = .selectIngredients(presentation)
      } catch {
        errorMessage = String(describing: error)
        isShowingError = true
      }
    }
  }

  func selectRecipeButtonTapped(
    recipeID: Recipe.ID,
    scaleContext: ScaleContext? = nil
  ) {
    let scaleContext = scaleContext ?? .recipe(recipeID)
    loadIngredientSelection(
      source: .recipe(recipeID, scaleContext),
      title: "Recipe",
      subtitle: "Recipe",
      recipeIDs: [recipeID],
      recipeTitleID: recipeID,
      scaleContext: scaleContext
    )
  }

  private func loadIngredientSelection(
    source: GroceryIngredientSelectionContext.Source,
    title: String,
    subtitle: String?,
    recipeIDs: Set<Recipe.ID>,
    recipeTitleID: Recipe.ID? = nil,
    scaleContext: ScaleContext? = nil
  ) {
    Task {
      do {
        let presentation = try await database.read { db in
          var resolvedTitle = title
          if let recipeTitleID,
             let recipe = try Recipe.find(recipeTitleID).fetchOne(db) {
            resolvedTitle = recipe.title
          }
          let displayScale: Double
          if let scaleContext {
            displayScale = try RecipeScaleRepository.scale(for: scaleContext, in: db) ?? 1
          } else {
            displayScale = 1
          }
          return GroceryIngredientSelectionPresentation(
            context: GroceryIngredientSelectionContext(
              source: source,
              title: resolvedTitle,
              subtitle: subtitle,
              displayScale: displayScale
            ),
            choices: try GroceryIngredientChoiceRequest(recipeIDs: recipeIDs).fetch(db)
          )
        }
        destination = .selectIngredients(presentation)
      } catch {
        errorMessage = String(describing: error)
        isShowingError = true
      }
    }
  }

  func confirmIngredientSelectionButtonTapped(
    context: GroceryIngredientSelectionContext,
    selectedIngredientLineIDs: Set<IngredientLine.ID>,
    mealRows: [MealPlanItemRowData]
  ) -> Bool {
    guard !selectedIngredientLineIDs.isEmpty else {
      errorMessage = "Select at least one ingredient."
      isShowingError = true
      return false
    }

    do {
      let selectedListID = selectedListID
      let listID = try database.write { db in
        let listID = try selectedOrDefaultGroceryListID(
          selectedListID,
          in: db,
          now: now,
          uuid: { uuid() }
        )
        switch context.source {
        case let .recipe(recipeID, scaleContext):
          switch scaleContext {
          case .recipe:
            try GroceryRepository.addRecipe(
              recipeID: recipeID,
              groceryListID: listID,
              in: db,
              now: now,
              uuid: { uuid() },
              includedIngredientLineIDs: selectedIngredientLineIDs
            )

          case let .mealPlanItem(itemID):
            try GroceryRepository.addMealPlanItem(
              itemID: itemID,
              groceryListID: listID,
              in: db,
              now: now,
              uuid: { uuid() },
              includedIngredientLineIDs: selectedIngredientLineIDs
            )

          case let .menuItem(itemID):
            try GroceryRepository.addMenuItem(
              itemID: itemID,
              groceryListID: listID,
              in: db,
              now: now,
              uuid: { uuid() },
              includedIngredientLineIDs: selectedIngredientLineIDs
            )
          }

        case let .mealPlanRows(itemIDs):
          let rows = mealRows.filter { itemIDs.contains($0.item.id) }
          try GroceryRepository.addMealPlanRows(
            rows,
            groceryListID: listID,
            in: db,
            now: now,
            uuid: { uuid() },
            includedIngredientLineIDs: selectedIngredientLineIDs
          )

        case let .menu(menuID):
          try GroceryRepository.addMenu(
            menuID: menuID,
            groceryListID: listID,
            in: db,
            now: now,
            uuid: { uuid() },
            includedIngredientLineIDs: selectedIngredientLineIDs
          )
        }
        return listID
      }
      self.selectedListID = listID
      toastCenter?.postSuccess(
        GroceryAddConfirmation(
          sourceTitle: context.title,
          sourceSubtitle: context.subtitle,
          listTitle: title(forList: listID),
          ingredientCount: selectedIngredientLineIDs.count
        ).message
      )
      scheduleCategorization()
      return true
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
      return false
    }
  }

  func addMenuButtonTapped(menuID: CoreMenu.ID) {
    selectMenuButtonTapped(menuID: menuID)
  }

  func addMenuImmediately(menuID: CoreMenu.ID) {
    do {
      let selectedListID = selectedListID
      let listID = try database.write { db in
        let listID = try selectedOrDefaultGroceryListID(
          selectedListID,
          in: db,
          now: now,
          uuid: { uuid() }
        )
        try GroceryRepository.addMenu(
          menuID: menuID,
          groceryListID: listID,
          in: db,
          now: now,
          uuid: { uuid() }
        )
        return listID
      }
      self.selectedListID = listID
      scheduleCategorization()
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
    }
  }

  func addRecipeButtonTapped(
    recipeID: Recipe.ID,
    scaleContext: ScaleContext? = nil
  ) {
    selectRecipeButtonTapped(recipeID: recipeID, scaleContext: scaleContext)
  }

  func addRecipeImmediately(recipeID: Recipe.ID) {
    do {
      let selectedListID = selectedListID
      let listID = try database.write { db in
        let listID = try selectedOrDefaultGroceryListID(
          selectedListID,
          in: db,
          now: now,
          uuid: { uuid() }
        )
        try GroceryRepository.addRecipe(
          recipeID: recipeID,
          groceryListID: listID,
          in: db,
          now: now,
          uuid: { uuid() }
        )
        return listID
      }
      self.selectedListID = listID
      scheduleCategorization()
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
    }
  }

  func title(forList listID: CoreGroceryList.ID) -> String {
    listRows.first { $0.id == listID }?.list.title ?? "Grocery List"
  }

  func title(forPantryItem itemID: PantryItem.ID) -> String {
    pantryItems.first { $0.id == itemID }?.title ?? "Pantry Item"
  }

}

extension GroceryLibraryModel {
  func reloadAfterExternalChange() async {
    try? await $listRows.load()
    try? await $itemRows.load()
    try? await $pantryItems.load()
    try? await $menuRows.load()
  }

  func ensureDefaultListIfNeeded() {
    do {
      let listID = try database.write { db in
        try GroceryRepository.ensureDefaultList(
          in: db,
          now: now,
          uuid: { uuid() }
        )
      }
      if selectedListID == nil {
        selectedListID = listID
      }
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
    }
  }

  func addListButtonTapped() {
    destination = .addList(GroceryListEditorDraft())
  }

  func addPantryItemButtonTapped() {
    destination = .addPantryItem
  }

  func addCustomItemButtonTapped() {
    destination = .addCustomItem(GroceryItemEditorDraft())
  }

  func editItemButtonTapped(itemID: GroceryItem.ID) {
    guard let item = itemRows.first(where: { $0.id == itemID })?.item else { return }
    destination = .editItem(GroceryItemEditorDraft(item: item))
  }

  func editListButtonTapped(listID: CoreGroceryList.ID) {
    guard let list = listRows.first(where: { $0.id == listID })?.list else { return }
    destination = .editList(GroceryListEditorDraft(list: list))
  }

  func saveListButtonTapped(
    listID: CoreGroceryList.ID? = nil,
    title: String,
    remindersListName: String
  ) -> Bool {
    do {
      let listID = try database.write { db in
        if let listID {
          try GroceryRepository.updateList(
            listID: listID,
            title: title,
            remindersListName: remindersListName,
            in: db,
            now: now
          )
          return listID
        } else {
          return try GroceryRepository.addList(
            title: title,
            remindersListName: remindersListName,
            in: db,
            now: now,
            uuid: { uuid() }
          )
        }
      }
      selectedListID = listID
      destination = nil
      return true
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
      return false
    }
  }

  func saveCustomItemButtonTapped(
    title: String,
    quantityText: String,
    unit: String,
    aisle: String,
    notes: String
  ) -> Bool {
    addCustomItem(
      title: title,
      quantityText: quantityText,
      unit: unit,
      aisle: aisle,
      notes: notes
    )
  }

  func saveItemButtonTapped(
    itemID: GroceryItem.ID,
    title: String,
    quantityText: String,
    unit: String,
    aisle: String,
    notes: String
  ) -> Bool {
    do {
      try database.write { db in
        try GroceryRepository.updateItem(
          itemID: itemID,
          title: title,
          quantityText: quantityText,
          unit: unit,
          aisle: aisle,
          notes: notes,
          in: db,
          now: now
        )
      }
      destination = nil
      return true
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
      return false
    }
  }

  var selectedListShareText: String {
    guard let selectedListRow else { return "Grocery List\n\nNo grocery items." }
    return GroceryListPlainTextRenderer.render(
      list: selectedListRow.list,
      rows: selectedDisplaySections.shoppingRows
    )
  }

  func categorizeUncachedItems() async {
    @Dependency(\.groceryCategorizationClient) var groceryCategorizationClient

    do {
      try Task.checkCancellation()
      try await database.write { db in
        try GroceryStoreAreaCache.backfill(in: db)
      }
      try? await $itemRows.load()

      try Task.checkCancellation()
      let uncategorizedNames = try await database.read { db in
        try GroceryStoreAreaCache.uncategorizedCanonicalNames(in: db)
      }
      let names = groceryCategorizationAttemptCache.namesToClassify(from: uncategorizedNames)
      guard !names.isEmpty else { return }

      let classified = try await groceryCategorizationClient(names: names, tier: .onDevice)
      guard !classified.isEmpty else { return }

      // Deliberately no cancellation check here. `namesToClassify` above has already recorded
      // these names as attempted, so a classification that made it back must be applied — the
      // on-appear caller is cancelled on disappear, and bailing out would discard a paid-for
      // result while leaving the names permanently unclassifiable for this model's lifetime.
      try await database.write { db in
        try GroceryStoreAreaCache.applyClassified(classified, in: db)
      }
      try? await $itemRows.load()
    } catch {
      return
    }
  }

  func addItemLine(_ text: String) -> Bool {
    guard let item = GroceryRapidAddItem(line: text) else { return false }
    return addCustomItem(
      title: item.title,
      quantityText: item.quantityText ?? "",
      unit: item.unit ?? "",
      aisle: "",
      notes: item.notes ?? ""
    )
  }

  private func addCustomItem(
    title: String,
    quantityText: String,
    unit: String,
    aisle: String,
    notes: String
  ) -> Bool {
    do {
      let selectedListID = selectedListID
      let listID = try database.write { db in
        let listID = try selectedOrDefaultGroceryListID(
          selectedListID,
          in: db,
          now: now,
          uuid: { uuid() }
        )
        try GroceryRepository.addCustomItem(
          title: title,
          quantityText: quantityText,
          unit: unit,
          aisle: aisle,
          notes: notes,
          groceryListID: listID,
          in: db,
          now: now,
          uuid: { uuid() }
        )
        return listID
      }
      self.selectedListID = listID
      destination = nil
      scheduleCategorization()
      return true
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
      return false
    }
  }

  private func scheduleCategorization() {
    categorizationDebounceTask?.cancel()
    let clock = continuousClock
    categorizationDebounceTask = Task { [weak self, clock] in
      do {
        try await clock.sleep(for: Self.categorizationDebounce)
        try Task.checkCancellation()
      } catch is CancellationError {
        return
      } catch {
        return
      }

      self?.enqueueCategorizationSweep()
    }
  }

  private func enqueueCategorizationSweep() {
    // A sweep records attempted names before it calls the client, so it must never be cancelled
    // after starting. Queue a subsequent burst behind it instead of discarding its result.
    let previousSweepTask = categorizationSweepTask
    categorizationSweepTask = Task { [weak self, previousSweepTask] in
      await previousSweepTask?.value
      await self?.categorizeUncachedItems()
    }
  }

  private func removePantryAddBack(itemID: GroceryItem.ID) {
    for listID in Array(pantryAddBackItemIDsByListID.keys) {
      pantryAddBackItemIDsByListID[listID]?.remove(itemID)
      if pantryAddBackItemIDsByListID[listID]?.isEmpty == true {
        pantryAddBackItemIDsByListID[listID] = nil
      }
    }
  }
}

@Observable
@MainActor
final class GroceryItemEditorDraft: Identifiable {
  let id = UUID()
  let itemID: GroceryItem.ID?
  var title: String
  var quantityText: String
  var unit: String
  var aisle: String
  var notes: String

  init(item: GroceryItem? = nil) {
    itemID = item?.id
    title = item?.title ?? ""
    quantityText = item?.quantityText ?? ""
    unit = item?.unit ?? ""
    aisle = item?.aisle ?? ""
    notes = item?.notes ?? ""
  }

  var isSaveDisabled: Bool {
    title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
}

@Observable
@MainActor
final class GroceryListEditorDraft: Identifiable {
  let id = UUID()
  let listID: CoreGroceryList.ID?
  var title: String
  var remindersListName: String

  init(list: CoreGroceryList? = nil) {
    listID = list?.id
    title = list?.title ?? ""
    remindersListName = list?.remindersListName ?? ""
  }

  var isSaveDisabled: Bool {
    title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
}

struct GroceryDisplaySections: Equatable {
  var needsReviewRows: [GroceryItemRowData] = []
  var toBuyRows: [GroceryItemRowData] = []
  var purchasedRows: [GroceryItemRowData] = []
  var assumedInPantryRows: [GroceryItemRowData] = []

  init() {}

  init(suppression: PantrySuppression.Evaluation) {
    needsReviewRows = suppression.needsReview.filter { !$0.item.isPurchased }
    toBuyRows = suppression.shown.filter { !$0.item.isPurchased }
    purchasedRows = suppression.shoppingRows.filter(\.item.isPurchased)
    assumedInPantryRows = suppression.assumedInPantry
  }

  var shoppingRows: [GroceryItemRowData] {
    needsReviewRows + toBuyRows + purchasedRows
  }

  var isEmpty: Bool {
    needsReviewRows.isEmpty
      && toBuyRows.isEmpty
      && purchasedRows.isEmpty
      && assumedInPantryRows.isEmpty
  }
}

struct GroceryIngredientSelectionContext: Hashable, Sendable {
  enum Source: Hashable, Sendable {
    case recipe(Recipe.ID, ScaleContext)
    case mealPlanRows([MealPlanItem.ID])
    case menu(CoreMenu.ID)
  }

  var source: Source
  var title: String
  var subtitle: String?
  var displayScale: Double = 1
}

struct GroceryAddConfirmation: Identifiable, Hashable, Sendable {
  var sourceTitle: String
  var sourceSubtitle: String?
  var listTitle: String
  var ingredientCount: Int?

  var id: String {
    [
      sourceSubtitle,
      sourceTitle,
      listTitle,
      ingredientCount.map { String($0) }
    ]
      .compactMap(\.self)
      .joined(separator: "|")
  }

  var message: String {
    if let ingredientCount {
      return "Added \(ingredientCount.formatted()) \(ingredientNoun(for: ingredientCount)) from \"\(sourceTitle)\" to \"\(listTitle)\"."
    } else {
      return "Added \"\(sourceTitle)\" to \"\(listTitle)\"."
    }
  }

  private func ingredientNoun(for count: Int) -> String {
    count == 1 ? "ingredient" : "ingredients"
  }
}

private func selectedOrDefaultGroceryListID(
  _ selectedListID: CoreGroceryList.ID?,
  in db: Database,
  now: Date,
  uuid: () -> UUID
) throws -> CoreGroceryList.ID {
  if let selectedListID,
     try GroceryList.find(selectedListID).fetchOne(db) != nil {
    return selectedListID
  }

  return try GroceryRepository.ensureDefaultList(
    in: db,
    now: now,
    uuid: uuid
  )
}

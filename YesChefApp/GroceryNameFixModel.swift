import YesChefCore

extension GroceryLibraryModel {
  func nameFixesButtonTapped() {
    destination = .nameFixes
  }

  func consolidateListButtonTapped(listID: GroceryList.ID) {
    do {
      _ = try database.write { db in
        try GroceryRepository.consolidate(listID: listID, in: db, now: now)
      }
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
    }
  }

  func sameAsButtonTapped(itemID: GroceryItem.ID) {
    destination = .sameAs(itemID)
  }

  func saveIngredientNameFix(from: String, to: String, replacing oldFromName: String? = nil) -> Bool {
    do {
      let saved = try database.write { db in
        let saved = try IngredientNameFixRepository.save(from: from, to: to, in: db, now: now)
        if saved, let oldFromName,
           CanonicalIngredient.baseName(oldFromName) != CanonicalIngredient.baseName(from) {
          try IngredientNameFixRepository.delete(fromName: oldFromName, in: db)
        }
        return saved
      }
      if !saved {
        errorMessage = "Those names already resolve to the same ingredient, or one side is empty."
        isShowingError = true
        return false
      }
      return true
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
      return false
    }
  }

  func deleteIngredientNameFixButtonTapped(fromName: String) {
    do {
      try database.write { db in
        try IngredientNameFixRepository.delete(fromName: fromName, in: db)
      }
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
    }
  }

  func confirmSameAsButtonTapped(itemID: GroceryItem.ID, targetItemID: GroceryItem.ID) {
    do {
      try database.write { db in
        try GroceryRepository.sameAs(itemID: itemID, targetItemID: targetItemID, in: db, now: now)
      }
      destination = nil
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
    }
  }
}

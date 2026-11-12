import YesChefCore

extension GroceryLibraryModel {
  var selectedDisplaySections: GroceryDisplaySections {
    guard let selectedListID = selectedListRow?.id else {
      return GroceryDisplaySections()
    }
    let evaluation = PantrySuppression.evaluate(
      list: selectedItemRows,
      policies: pantryItems,
      fixes: ingredientFixes
    )
    return GroceryDisplaySections(
      suppression: PantrySuppression.addBack(
        itemIDs: pantryAddBackItemIDsByListID[selectedListID] ?? [],
        to: evaluation
      )
    )
  }
}

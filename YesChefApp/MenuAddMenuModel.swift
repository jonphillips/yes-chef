import YesChefCore

struct MenuAddMenuPresentation: Identifiable {
  var offer: MenuAddMenuOffer

  var id: CoreMenu.ID { offer.targetMenuID }
}

@MainActor
extension MenuLibraryModel {
  func addMenuToMenuButtonTapped(targetMenuID: CoreMenu.ID) {
    do {
      let offer = try database.read { db in try MenuRepository.addMenuOffer(targetMenuID: targetMenuID, in: db) }
      destination = .addMenuToMenu(MenuAddMenuPresentation(offer: offer))
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
    }
  }

  func confirmAddMenuToMenu(
    _ presentation: MenuAddMenuPresentation,
    sourceMenuID: CoreMenu.ID,
    startDayOffset: Int
  ) {
    do {
      try database.write { db in
        try MenuRepository.addMenu(
          sourceMenuID: sourceMenuID,
          into: presentation.offer.targetMenuID,
          startDayOffset: startDayOffset,
          in: db,
          now: now,
          uuid: { uuid() }
        )
      }
      destination = nil
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
    }
  }
}

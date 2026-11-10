import SwiftUI

struct MenuEditDestinationModifier: ViewModifier {
  let menuModel: MenuLibraryModel

  func body(content: Content) -> some View {
    @Bindable var menuModel = menuModel
    return content.sheet(item: $menuModel.destination.editMenu, id: \.menuID) { context in
      NavigationStack {
        MenuEditView(model: menuModel, context: context)
      }
    }
  }
}

extension View {
  func menuEditDestination(model: MenuLibraryModel) -> some View {
    modifier(MenuEditDestinationModifier(menuModel: model))
  }
}

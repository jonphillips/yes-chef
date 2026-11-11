import SwiftUI
import YesChefCore

struct AppHelpSheet: View {
  @Environment(\.dismiss) private var dismiss

  let page: AppHelpPage

  var body: some View {
    List {
      ForEach(page.sections, id: \.heading) { section in
        Section(section.heading) {
          ForEach(Array(section.bullets.enumerated()), id: \.offset) { _, bullet in
            Text(LocalizedStringKey(bullet))
          }
        }
      }
    }
    .navigationTitle(page.title)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .confirmationAction) {
        Button("Done") { dismiss() }
      }
    }
  }
}

import SwiftUI
import YesChefCore

struct IngredientFractionPillRow: View {
  let onSelect: (ScaleFraction) -> Void

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        ForEach(ScaleFraction.ingredientInputCases) { fraction in
          Button {
            onSelect(fraction)
          } label: {
            Text(verbatim: fraction.label)
              .font(.title3)
              .frame(minWidth: 44, minHeight: 36)
          }
          .buttonStyle(.bordered)
          .buttonBorderShape(.capsule)
          .accessibilityLabel(Text(verbatim: "Insert " + fraction.label))
          .accessibilityHint(Text("Appends this fraction to the ingredient text."))
        }
      }
      .padding(.horizontal, 2)
    }
    .padding(.vertical, 2)
  }
}

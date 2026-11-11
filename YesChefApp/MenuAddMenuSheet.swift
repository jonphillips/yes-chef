import SwiftUI
import YesChefCore

struct MenuAddMenuSheet: View {
  @Environment(\.dismiss) private var dismiss
  @State private var selectedMenuID: CoreMenu.ID?
  @State private var startDayOffset = 0

  let model: MenuLibraryModel
  let presentation: MenuAddMenuPresentation

  private var selectedSource: MenuAddMenuSourceOffer? {
    presentation.offer.sources.first { $0.menuID == selectedMenuID }
  }

  var body: some View {
    List {
      Section {
        ForEach(presentation.offer.sources) { source in
          Button {
            selectedMenuID = source.menuID
            startDayOffset = 0
          } label: {
            HStack {
              VStack(alignment: .leading, spacing: 4) {
                Text(source.title)
                  .foregroundStyle(.primary)
                Text("\(source.dayCount) \(source.dayCount == 1 ? "day" : "days") · \(source.dishCount) \(source.dishCount == 1 ? "dish" : "dishes")")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
              Spacer()
              if !source.fits {
                Text("Needs \(source.dayCount) days")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              } else if selectedMenuID == source.menuID {
                Image(systemName: "checkmark")
                  .foregroundStyle(.tint)
              }
            }
          }
          .disabled(!source.fits)
        }
      }

      if let source = selectedSource {
        if presentation.offer.targetDayCount > 1 {
          Section("Start on") {
            Picker("Start on", selection: $startDayOffset) {
              ForEach(0...(presentation.offer.targetDayCount - source.dayCount), id: \.self) { dayOffset in
                if let startDate = presentation.offer.targetPlacementStartDate,
                  let date = Calendar.autoupdatingCurrent.date(byAdding: .day, value: dayOffset, to: startDate)
                {
                  Text("Day \(dayOffset + 1) · \(date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())")
                    .tag(dayOffset)
                } else {
                  Text("Day \(dayOffset + 1)")
                    .tag(dayOffset)
                }
              }
            }
          }
        }

        if let overlapDate = source.overlappingPlacementStartDate {
          Section {
            Text("\(source.title) is also on the calendar on \(overlapDate, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day()). Its dishes will show twice there. To move it in instead, use Edit › Bring In Calendar Items…")
              .font(.callout)
          }
        }
      }
    }
    .navigationTitle("Add Menu")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") { dismiss() }
      }
      ToolbarItem(placement: .confirmationAction) {
        Button("Add") {
          guard let source = selectedSource else { return }
          model.confirmAddMenuToMenu(
            presentation,
            sourceMenuID: source.menuID,
            startDayOffset: presentation.offer.targetDayCount == 1 ? 0 : startDayOffset
          )
        }
        .disabled(selectedSource == nil)
      }
    }
  }
}

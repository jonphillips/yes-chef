import SwiftUI
import UIKit
import YesChefCore

struct CookingModeView: View {
  @State private var model: CookingModeModel

  init(model: CookingModeModel) {
    _model = State(wrappedValue: model)
  }

  var body: some View {
    @Bindable var model = model

    ScrollView {
      VStack(alignment: .leading, spacing: 28) {
        if let recipe = model.detail?.recipe {
          Text(recipe.title)
            .font(.largeTitle.bold())
        }

        if !model.ingredientLines.isEmpty {
          VStack(alignment: .leading, spacing: 12) {
            Text("Ingredients")
              .font(.title2.bold())
            ForEach(model.ingredientLines) { line in
              Button {
                model.ingredientToggleButtonTapped(line.id)
              } label: {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                  Image(systemName: model.checkedIngredientIDs.contains(line.id) ? "checkmark.circle.fill" : "circle")
                  Text(line.originalText)
                    .font(.title3)
                }
              }
              .buttonStyle(.bordered)
            }
          }
        }

        if let step = model.currentStep {
          VStack(alignment: .leading, spacing: 16) {
            HStack {
              Text("Step \(model.focusedStepIndex + 1) of \(model.instructionSteps.count)")
                .font(.title2.bold())
              Spacer()
              Stepper("Step", value: $model.focusedStepIndex, in: 0...(model.instructionSteps.count - 1))
                .labelsHidden()
            }

            Text(step.text)
              .font(.title)
              .lineSpacing(6)

            Button {
              model.stepToggleButtonTapped(step.id)
            } label: {
              Label(
                model.checkedStepIDs.contains(step.id) ? "Step Done" : "Mark Step Done",
                systemImage: model.checkedStepIDs.contains(step.id) ? "checkmark.circle.fill" : "circle"
              )
            }
            .buttonStyle(.borderedProminent)
          }
        }

        if !model.visibleNotes.isEmpty {
          VStack(alignment: .leading, spacing: 10) {
            Text("Notes")
              .font(.title2.bold())
            ForEach(model.visibleNotes) { note in
              Text(note.text)
                .font(.body)
            }
          }
        }
      }
      .padding()
      .frame(maxWidth: 860, alignment: .leading)
    }
    .navigationTitle("Cooking")
    .onAppear {
      model.detailChanged(model.detail)
      UIApplication.shared.isIdleTimerDisabled = true
    }
    .onChange(of: model.detail) { _, detail in
      model.detailChanged(detail)
    }
    .onDisappear {
      UIApplication.shared.isIdleTimerDisabled = false
    }
  }
}

import SwiftUI
import YesChefCore

struct RecipeUnfiledReviewSheet: View {
  let coordinator: HandoffReviewCoordinator
  let handoffID: UUID
  let recipeID: UUID
  @State private var text: String
  @State private var label: String?
  @State private var error: String?
  @State private var isFiling = false

  init(coordinator: HandoffReviewCoordinator, handoffID: UUID, recipeID: UUID, text: String) {
    self.coordinator = coordinator
    self.handoffID = handoffID
    self.recipeID = recipeID
    _text = State(initialValue: text)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Returned text") { TextEditor(text: $text).frame(minHeight: 180) }
        Picker("File as…", selection: $label) {
          Text("Choose a destination").tag(String?.none)
          Text("New recipe").tag(Optional("YC-NEW-RECIPE:"))
          Text("Make-ahead").tag(Optional("YC-MAKE-AHEAD:"))
          Text("Chef It Up").tag(Optional("YC-CHEF-IT-UP:"))
          Text("Serve With").tag(Optional("YC-SERVE-WITH:"))
          Text("Revision brief").tag(Optional("YC-REVISION:"))
          Text("Learnings").tag(Optional("YC-LEARNINGS:"))
        }
      }
      .navigationTitle("File returned text")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Discard", role: .destructive) {
            if let review = coordinator.review { coordinator.discard(review) }
          }
          .disabled(isFiling)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Review") {
            guard let label, !isFiling else { return }
            isFiling = true
            Task {
              defer { isFiling = false }
              do { try await coordinator.fileUnlabeled(text, label: label, handoffID: handoffID, recipeID: recipeID) }
              catch { self.error = error.localizedDescription }
            }
          }
          .disabled(isFiling || label == nil || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
      .alert("Could Not File", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
        Button("OK") { error = nil }
      } message: { Text(error ?? "") }
    }
  }
}


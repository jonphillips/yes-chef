#if DEBUG
import CloudKit
import SwiftUI
import YesChefCore

struct FamilyCookbookSettingsView: View {
  @Bindable var model: CookbookPublishModel
  @State private var isPresentingShare = false
  @State private var isConfirmingStop = false

  var body: some View {
    Form {
      Section("Name shown to family") {
        TextField("Your name", text: $model.displayName)
          .textContentType(.name)
          .textInputAutocapitalization(.words)
      }

      Section("Sharing") {
        Button("Share My Recipes", systemImage: "person.2") {
          model.shareButtonTapped()
        }
        .disabled(model.isSharing || model.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

        if model.hasShare {
          ForEach(model.participants) { participant in
            Text(participant.description)
          }
          if let profile = model.publishedProfile,
            profile.payloadVersion >= RecipeBundleCoding.currentVersion,
            let publishedAt = profile.publishedAt
          {
            LabeledContent("Recipes", value: "\(profile.recipeCount)")
            LabeledContent("Status", value: "Published \(publishedAt.formatted(.relative(presentation: .named)))")
          } else if let progress = model.progressText {
            LabeledContent("Status", value: progress)
          } else {
            LabeledContent("Status", value: "Not published yet")
          }
          if let progress = model.progressText {
            Text(progress).foregroundStyle(.secondary)
          }
          Button("Publish Now", systemImage: "arrow.clockwise.icloud") {
            model.publishNowTapped()
          }
          .disabled(model.isPublishing)
          if model.isPublishing { ProgressView() }
          Button("Stop Sharing", role: .destructive) { isConfirmingStop = true }
        }

        if let error = model.errorMessage {
          Text(error).foregroundStyle(.red)
        }
      }
    }
    .navigationTitle("Family Cookbook")
    .onChange(of: model.sharePresentationRequest) { _, _ in isPresentingShare = model.share != nil }
    .sheet(isPresented: $isPresentingShare, onDismiss: {
      Task { await model.refreshShareStatus() }
    }) {
      if let share = model.share {
        CookbookSharingController(share: share, container: model.shareContainer)
      }
    }
    .confirmationDialog("Stop sharing your cookbook?", isPresented: $isConfirmingStop, titleVisibility: .visible) {
      Button("Stop Sharing", role: .destructive) {
        Task { await model.stopSharing() }
      }
    } message: {
      Text("This removes the cookbook and its shared recipes from iCloud.")
    }
  }
}
#endif

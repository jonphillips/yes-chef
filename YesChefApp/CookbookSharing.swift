import CloudKit
import SwiftUI
import SQLiteData
import UIKit
import YesChefCore

extension Notification.Name {
  static let cookbookShareAccepted = Notification.Name("CookbookShareAccepted")
}

func cookbookDisplayImageLoader(
  fetchClient: CookbookFetchClient, mirror: CookbookMirror, zoneOwnerName: String
) -> @Sendable (RecipePhoto.ID) async -> Data? {
  return { photoID in
    guard let result = try? await mirror.database.read({ db -> (Recipe.ID, RecipePhoto.ID)? in
      guard let photo = try RecipePhoto.find(photoID).fetchOne(db),
        let recipe = try Recipe.find(photo.recipeID).fetchOne(db)
      else { return nil }
      let photos = try RecipePhoto.where { $0.recipeID.eq(recipe.id) }.fetchAll(db)
      guard CookbookPayload.displayPhotoID(for: recipe, photos: photos) == photoID else { return nil }
      return (recipe.id, photoID)
    }) else { return nil }
    let (recipeID, _) = result
    do {
      let zoneID = CKRecordZone.ID(zoneName: "Cookbook", ownerName: zoneOwnerName)
      let data = try await fetchClient.fetchDisplayImage(zoneID, recipeID.uuidString)
      try mirror.cacheDisplayImage(data, photoID: photoID)
      return data
    } catch { return nil }
  }
}

struct CookbookAcceptanceAlert: ViewModifier {
  let model: CookbookLibraryModel
  @State private var isPresented = false

  func body(content: Content) -> some View {
    content
      .onChange(of: model.acceptanceErrorMessage) { _, message in isPresented = message != nil }
      .alert("Couldn’t accept cookbook invitation", isPresented: $isPresented) {
        Button("OK") { model.acceptanceErrorMessage = nil }
      } message: {
        Text(model.acceptanceErrorMessage ?? "")
      }
  }
}

struct CookbookSharingController: UIViewControllerRepresentable {
  let share: CKShare
  let container: CKContainer

  func makeCoordinator() -> Coordinator {
    Coordinator(title: share[CKShare.SystemFieldKey.title] as? String)
  }

  func makeUIViewController(context: Context) -> UICloudSharingController {
    let controller = UICloudSharingController(share: share, container: container)
    controller.availablePermissions = [.allowPrivate, .allowReadOnly]
    controller.delegate = context.coordinator
    return controller
  }

  func updateUIViewController(_ controller: UICloudSharingController, context: Context) {}

  final class Coordinator: NSObject, UICloudSharingControllerDelegate {
    let title: String?

    init(title: String?) { self.title = title }

    func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
      AppLog.sync.error("Cookbook sharing failed: \(error.localizedDescription, privacy: .public)")
    }

    func itemTitle(for csc: UICloudSharingController) -> String? { title }

    func cloudSharingController(
      _ csc: UICloudSharingController, share: CKShare,
      willSaveShareWithPreparationHandler handler: @escaping (CKShare?, (any Error)?) -> Void
    ) {
      share.publicPermission = .none
      handler(share, nil)
    }

    func cloudSharingController(_ csc: UICloudSharingController, shouldPresentShare: CKShare) -> Bool { true }

    func cloudSharingController(_ csc: UICloudSharingController, didSaveShare share: CKShare) {}

    func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {}

    func cloudSharingController(
      _ csc: UICloudSharingController, allowedSharingOptionsForShare share: CKShare
    ) -> UICloudSharingController.PermissionOptions { [.allowPrivate, .allowReadOnly] }
  }
}

@MainActor
final class CookbookAppDelegate: NSObject, UIApplicationDelegate {
  func application(
    _ application: UIApplication,
    configurationForConnecting connectingSceneSession: UISceneSession,
    options: UIScene.ConnectionOptions
  ) -> UISceneConfiguration {
    let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
    configuration.delegateClass = CookbookSceneDelegate.self
    return configuration
  }
}

@MainActor
final class CookbookSceneDelegate: NSObject, UIWindowSceneDelegate {
  func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
    if let metadata = connectionOptions.cloudKitShareMetadata { accept(metadata) }
  }

  func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
    accept(metadata)
  }

  private func accept(_ metadata: CKShare.Metadata) {
    guard metadata.containerIdentifier == CookbookCloudKitClientFactory.containerIdentifier else {
      AppLog.sync.error("Ignored share invitation for unexpected container \(metadata.containerIdentifier, privacy: .public)")
      return
    }
    Task { @MainActor in
      do {
        _ = try await CKContainer(identifier: CookbookCloudKitClientFactory.containerIdentifier).accept(metadata)
        NotificationCenter.default.post(name: .cookbookShareAccepted, object: nil)
      } catch {
        NotificationCenter.default.post(
          name: .cookbookShareAccepted, object: nil, userInfo: ["error": error.localizedDescription]
        )
      }
    }
  }
}

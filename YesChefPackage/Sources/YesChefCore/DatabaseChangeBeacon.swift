import Foundation

public enum DatabaseChangeBeacon {
  public static let didChange = Notification.Name("YesChefDatabaseDidChange")

  public static func notificationName(appGroupIdentifier: String) -> String {
    "\(appGroupIdentifier).databaseDidChange"
  }

  public static func post(appGroupIdentifier: String) {
    CFNotificationCenterPostNotification(
      CFNotificationCenterGetDarwinNotifyCenter(),
      CFNotificationName(notificationName(appGroupIdentifier: appGroupIdentifier) as CFString),
      nil,
      nil,
      true
    )
  }

  public static func startObserving(appGroupIdentifier: String) {
    CFNotificationCenterAddObserver(
      CFNotificationCenterGetDarwinNotifyCenter(),
      nil,
      { _, _, _, _, _ in
        NotificationCenter.default.post(name: DatabaseChangeBeacon.didChange, object: nil)
      },
      notificationName(appGroupIdentifier: appGroupIdentifier) as CFString,
      nil,
      .deliverImmediately
    )
  }
}

import Foundation

public enum DatabaseChangeBeacon {
  private static let darwinName = "group.com.jonphillips.yeschef.databaseDidChange"

  public static let didChange = Notification.Name("YesChefDatabaseDidChange")

  public static func post() {
    CFNotificationCenterPostNotification(
      CFNotificationCenterGetDarwinNotifyCenter(),
      CFNotificationName(darwinName as CFString),
      nil,
      nil,
      true
    )
  }

  public static func startObserving() {
    CFNotificationCenterAddObserver(
      CFNotificationCenterGetDarwinNotifyCenter(),
      nil,
      { _, _, _, _, _ in
        NotificationCenter.default.post(name: DatabaseChangeBeacon.didChange, object: nil)
      },
      darwinName as CFString,
      nil,
      .deliverImmediately
    )
  }
}

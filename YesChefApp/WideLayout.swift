import SwiftUI
import UIKit

@MainActor
enum WideLayout {
  /// The single seam for a future macOS-specific wide-layout rule: `UIDevice` reports a non-pad idiom there,
  /// so do not broaden this check until macOS has its own deliberate behavior.
  static func isEnabled(horizontalSizeClass: UserInterfaceSizeClass?) -> Bool {
    UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass != .compact
  }
}

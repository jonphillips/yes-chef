import Foundation
import OSLog

/// Unified logging for diagnostics that need to be readable during a device pass.
///
/// This is a single-user app, so the payloads in these categories are intentionally
/// public: the prompts and model responses are the diagnostic signal.
public enum AppLog {
  public static let applyAction = Logger(subsystem: subsystem, category: "applyAction")
  public static let llm = Logger(subsystem: subsystem, category: "llm")

  private static let subsystem = Bundle.main.bundleIdentifier ?? "com.jonphillips.yeschef"
}

import Foundation
import OSLog

/// Unified logging for diagnostics that need to be readable during a device pass.
///
/// This is a single-user app, so the payloads in these categories are intentionally
/// public: the prompts and model responses are the diagnostic signal.
public enum AppLog {
  public static let applyAction = Logger(subsystem: subsystem, category: "applyAction")
  public static let llm = Logger(subsystem: subsystem, category: "llm")

  /// Interactive-latency diagnostics (ADR-0029). Paired with `performanceSignposter`
  /// so a plain console capture is enough — no Instruments run required.
  public static let performance = Logger(subsystem: subsystem, category: "performance")
  public static let performanceSignposter = OSSignposter(
    subsystem: subsystem,
    category: "performance"
  )

  private static let subsystem = Bundle.main.bundleIdentifier ?? "com.jonphillips.yeschef"
}

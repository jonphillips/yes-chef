import IssueReporting
import Testing
@testable import YesChef

@Suite
struct YesChefIssueReporterTests {
  @Test
  func installationAppendsOnceAndReportsIssues() {
    let originalReporters = IssueReporters.current
    let originalIDs = originalReporters.map { ObjectIdentifier($0 as AnyObject) }
    var received: (String, String, UInt)?
    let reporter = YesChefIssueReporter { message, fileID, line in
      received = (message, String(describing: fileID), line)
    }
    defer { IssueReporters.current = originalReporters }

    YesChefIssueReporter.install(reporter)
    YesChefIssueReporter.install(reporter)

    #expect(IssueReporters.current.count == originalReporters.count + 1)
    #expect(originalIDs.allSatisfy { id in
      IssueReporters.current.contains { ObjectIdentifier($0 as AnyObject) == id }
    })
    withIssueReporters(IssueReporters.current) {
      reportIssue("sync diagnostic", fileID: "ReporterTests.swift", line: 42)
    }
    #expect(received?.0 == "sync diagnostic")
    #expect(received?.1 == "ReporterTests.swift")
    #expect(received?.2 == 42)
  }
}

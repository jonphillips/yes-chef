import IssueReporting
import Testing
@testable import YesChef

@Suite
struct YesChefIssueReporterTests {
  @Test
  func installationAppendsOnceAndReportsIssues() {
    let originalReporters = IssueReporters.current
    IssueReporters.current.removeAll { $0 is YesChefIssueReporter }
    let existingReporters = IssueReporters.current
    let originalIDs = existingReporters.map { ObjectIdentifier($0 as AnyObject) }
    var received: (String, String, UInt)?
    let reporter = YesChefIssueReporter { message, fileID, line in
      received = (message, String(describing: fileID), line)
    }
    defer { IssueReporters.current = originalReporters }

    YesChefIssueReporter.install(reporter)
    YesChefIssueReporter.install(reporter)

    #expect(IssueReporters.current.count == existingReporters.count + 1)
    #expect(originalIDs.allSatisfy { id in
      IssueReporters.current.contains { ObjectIdentifier($0 as AnyObject) == id }
    })
    withIssueReporters([reporter]) {
      reportIssue("sync diagnostic", fileID: "YesChefTests/ReporterTests.swift", line: 42)
    }
    #expect(received?.0 == "sync diagnostic")
    #expect(received?.1 == "YesChefTests/ReporterTests.swift")
    #expect(received?.2 == 42)
  }
}

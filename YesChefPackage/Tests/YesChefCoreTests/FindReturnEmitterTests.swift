import Dependencies
import Foundation
import Testing
import YesChefCore

/// Pins the frozen return *shape* (the set-valued verdict) and demonstrates the recording-emitter
/// pattern S-y2's coordinator tests should use: inject a spy `FindReturnEmitter`, drive admit/decline,
/// assert on the captured verdict. No transport is exercised — that seam is decided later.
struct FindReturnEmitterTests {
  /// A referral can yield N admitted + M declined in one verdict.
  @Test
  func verdictExposesAdmittedAndDeclinedPartitions() {
    let admittedA = FindRecipeRef(SampleUUIDSequence.uuid(1))
    let admittedB = FindRecipeRef(SampleUUIDSequence.uuid(2))
    let verdict = FindVerdict(
      referralID: "referral-abc",
      outcomes: [
        .admitted(admittedA),
        .admitted(admittedB),
        .declined(.duplicate),
      ]
    )

    #expect(verdict.admitted == [admittedA, admittedB])
    #expect(verdict.declines == [.duplicate])
    #expect(verdict.referralID == "referral-abc")
  }

  /// The 0-recipe path is a clean whole-referral decline, not a thrown failure.
  @Test
  func noRecipeFoundIsAWholeReferralDecline() {
    let verdict = FindVerdict.declined(referralID: "referral-empty", .noRecipeFound)

    #expect(verdict.admitted.isEmpty)
    #expect(verdict.declines == [.noRecipeFound])
  }

  /// The recording-emitter pattern: a spy conformance captures every emitted verdict for assertions.
  @Test
  func recordingEmitterCapturesEmittedVerdict() async throws {
    let recorder = FindReturnRecorder()
    let emitter = FindReturnEmitter { await recorder.record($0) }

    try await emitter(FindVerdict.declined(referralID: "referral-1", .dismissed))
    try await emitter(
      FindVerdict(
        referralID: "referral-2",
        outcomes: [.admitted(FindRecipeRef(SampleUUIDSequence.uuid(3)))]
      )
    )

    let captured = await recorder.verdicts
    #expect(captured.map(\.referralID) == ["referral-1", "referral-2"])
    #expect(captured.last?.admitted.count == 1)
  }

  /// The seam is reachable through the dependency system exactly like `RecipeExtractionClient`.
  @Test
  func emitterResolvesFromDependencyOverride() async throws {
    let recorder = FindReturnRecorder()
    try await withDependencies {
      $0.findReturnEmitter = FindReturnEmitter { await recorder.record($0) }
    } operation: {
      @Dependency(\.findReturnEmitter) var emitter
      try await emitter(FindVerdict.declined(referralID: "referral-di", .noRecipeFound))
    }

    #expect(await recorder.verdicts.map(\.referralID) == ["referral-di"])
  }
}

/// Minimal spy the coordinator tests reuse. An `actor` because the emit closure is `@Sendable`.
private actor FindReturnRecorder {
  private(set) var verdicts: [FindVerdict] = []

  func record(_ verdict: FindVerdict) {
    verdicts.append(verdict)
  }
}

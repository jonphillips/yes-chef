import Foundation
import Testing
import YesChefCore

struct FindReferralTransportTests {
  @Test
  func decodesPinnedReferralFixtureWithISO8601DateAndOpaqueToken() throws {
    let referral = try JSONDecoder().decode(FindReferral.self, from: fixture("find-referral-v1"))

    #expect(referral.referralID == "11111111-1111-4111-8111-111111111111")
    #expect(referral.rawText == "A newsletter with two recipes.\nIngredients and method follow.")
    #expect(referral.provenance.contentPieceToken == "22222222-2222-4222-8222-222222222222")
    #expect(referral.provenance.arrivalDate == ISO8601DateFormatter().date(from: "2026-09-24T12:00:00Z"))
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    #expect(try normalizedJSON(encoder.encode(referral)) == normalizedJSON(fixture("find-referral-v1")))
  }

  @Test
  func encodesVerdictAsPinnedWireFixtureAndRoundTripsEveryDeclineReason() throws {
    let verdict = FindVerdict(
      referralID: "11111111-1111-4111-8111-111111111111",
      outcomes: [
        .admitted(FindRecipeRef(rawValue: "33333333-3333-4333-8333-333333333333")),
        .declined(.noRecipeFound),
        .declined(.extractionFailed("diagnostic only")),
      ]
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let encoded = try encoder.encode(verdict)
    #expect(try normalizedJSON(encoded) == normalizedJSON(fixture("find-verdict-v1")))

    let decoded = try JSONDecoder().decode(FindVerdict.self, from: fixture("find-verdict-v1"))
    #expect(decoded == verdict)

    let reasons: [FindDeclineReason] = [.noRecipeFound, .duplicate, .dismissed, .extractionFailed("diagnostic")]
    for reason in reasons {
      let encoded = try JSONEncoder().encode(FindVerdict.declined(referralID: "ref", reason))
      let decoded = try JSONDecoder().decode(FindVerdict.self, from: encoded)
      #expect(decoded == .declined(referralID: "ref", reason))
    }
  }

  @Test
  func mailboxReadsDeletesAndAtomicallyWritesMessages() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let mailbox = FindReferralMailbox(rootURL: root)
    let referral = FindReferral(referralID: "ref-1", rawText: "text", provenance: FindProvenance())
    let referralURL = root.appendingPathComponent("find-referrals", isDirectory: true).appendingPathComponent("ref-1.json")
    try FileManager.default.createDirectory(at: referralURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONEncoder().encode(referral).write(to: referralURL)

    #expect(try mailbox.readReferral(id: "ref-1") == referral)
    try mailbox.deleteReferral(id: "ref-1")
    #expect(try mailbox.readReferral(id: "ref-1") == nil)

    let verdict = FindVerdict.declined(referralID: "ref-1", .dismissed)
    try mailbox.write(verdict: verdict)
    let data = try Data(contentsOf: root.appendingPathComponent("find-verdicts/ref-1.json"))
    #expect(try JSONDecoder().decode(FindVerdict.self, from: data) == verdict)
  }

  @Test
  func doorAcceptsOnlyTheSingleReferralForm() throws {
    #expect(FindReferralDoor.referralID(from: try #require(URL(string: "yeschef://find-referral?id=ref-123"))) == "ref-123")
    #expect(FindReferralDoor.referralID(from: URL(string: "yeschef://other?id=ref-123")!) == nil)
    #expect(FindReferralDoor.referralID(from: URL(string: "yeschef://find-referral?id=ref-123&extra=x")!) == nil)
    #expect(FindReferralDoor.referralID(from: URL(string: "yeschef://find-referral?id=../escape")!) == nil)
  }

  private func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json"))
    return try Data(contentsOf: url)
  }

  private func normalizedJSON(_ data: Data) throws -> Data {
    let object = try JSONSerialization.jsonObject(with: data)
    return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
  }
}

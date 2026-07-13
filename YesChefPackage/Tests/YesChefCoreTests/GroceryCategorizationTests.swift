import CustomDump
import Dependencies
import Foundation
import LLMClientKit
import SQLiteData
import Testing
@testable import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct GroceryCategorizationTests {
    @Test
    func clientClassifiesOnDeviceWithNormalizedAreas() async throws {
      let recorder = GroceryCategorizationRequestRecorder()

      try await withDependencies {
        $0.modelClient = StubModelClient { request in
          await recorder.append(request)
          return ModelResponse(text: #"{"harissa":"condiment","miso":"canned dry"}"#)
        }
      } operation: {
        let classified = try await GroceryCategorizationClient.liveValue(
          names: ["harissa", "miso"],
          tier: .onDevice
        )

        expectNoDifference(
          classified,
          ["harissa": .condimentsAndOils, "miso": .cannedAndDry]
        )
      }

      let request = await recorder.first()
      expectNoDifference(request?.tier, .onDevice)
      expectNoDifference(request?.reasoningEffort, .low)
      expectNoDifference(request?.promptPreferenceKey, nil)
      #expect(request?.messages.first?.text.contains("harissa\nmiso") == true)
    }

    @Test
    func clientBatchesLargeNameSets() async throws {
      let recorder = GroceryCategorizationRequestRecorder()
      let names = (0..<9).map { "ingredient \($0)" }
      let completeResponse = ModelResponse(
        text: "{" + names.map { "\"\($0)\":\"Other\"" }.joined(separator: ",") + "}"
      )

      try await withDependencies {
        $0.modelClient = StubModelClient { request in
          await recorder.append(request)
          return completeResponse
        }
      } operation: {
        _ = try await GroceryCategorizationClient.liveValue(names: names, tier: .onDevice)
      }

      let requests = await recorder.allRequests()
      expectNoDifference(requests.map { $0.messages.first?.text }, [
        "Classify these exact canonical ingredient names:\n\n" + names.prefix(8).joined(separator: "\n"),
        "Classify these exact canonical ingredient names:\n\ningredient 8",
      ])
    }

    @Test
    func clientRetriesOnlyNamesOmittedFromTheFirstResponse() async throws {
      let recorder = GroceryCategorizationRequestRecorder()

      try await withDependencies {
        $0.modelClient = StubModelClient { request in
          await recorder.append(request)
          return ModelResponse(
            text: request.messages.first?.text.contains("harissa\nmiso") == true
              ? #"{"harissa":"Condiments & Oils"}"#
              : #"{"miso":"Canned & Dry"}"#
          )
        }
      } operation: {
        let classified = try await GroceryCategorizationClient.liveValue(
          names: ["harissa", "miso"],
          tier: .onDevice
        )
        expectNoDifference(
          classified,
          ["harissa": .condimentsAndOils, "miso": .cannedAndDry]
        )
      }

      let requests = await recorder.allRequests()
      expectNoDifference(requests.count, 2)
      expectNoDifference(requests.last?.messages.first?.text, "Classify these exact canonical ingredient names:\n\nmiso")
    }

    @Test
    func parserToleratesMalformedJson() {
      expectNoDifference(GroceryCategorizationClient.parse("not json"), [:])
      expectNoDifference(GroceryCategorizationClient.parse(#"{"harissa":12}"#), [:])
    }

    @Test
    func cacheClassifiesOnlyUncachedNamesAndNeverOverwritesAnAisle() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 881_000_000)
      let listID = SampleUUIDSequence.uuid(88_301)
      let harissaID = SampleUUIDSequence.uuid(88_302)
      let misoID = SampleUUIDSequence.uuid(88_303)

      try database.write { db in
        try GroceryList.insert {
          GroceryList(
            id: listID,
            title: "Shopping",
            sortOrder: 0,
            isDefault: true,
            dateCreated: now,
            dateModified: now
          )
        }
        .execute(db)
        try GroceryItem.insert {
          GroceryItem(
            id: harissaID,
            groceryListID: listID,
            title: "Harissa",
            canonicalName: "harissa",
            sortOrder: 0,
            dateCreated: now,
            dateModified: now
          )
        }
        .execute(db)
        try GroceryItem.insert {
          GroceryItem(
            id: misoID,
            groceryListID: listID,
            title: "Miso",
            canonicalName: "miso",
            aisle: "My Japanese Market",
            sortOrder: 1,
            dateCreated: now,
            dateModified: now
          )
        }
        .execute(db)

        expectNoDifference(
          try GroceryStoreAreaCache.uncategorizedCanonicalNames(in: db),
          ["harissa"]
        )

        try GroceryStoreAreaCache.applyClassified(
          ["harissa": .condimentsAndOils, "miso": .cannedAndDry],
          in: db
        )
        try GroceryStoreAreaCache.applyClassified(
          ["harissa": .frozen, "miso": .frozen],
          in: db
        )

        let harissa = try #require(try GroceryItem.find(harissaID).fetchOne(db))
        let miso = try #require(try GroceryItem.find(misoID).fetchOne(db))
        expectNoDifference(harissa.aisle, "Condiments & Oils")
        expectNoDifference(miso.aisle, "My Japanese Market")
      }
    }

    @Test
    func unavailableClientLeavesTheCacheUntouched() async throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 881_100_000)
      let listID = SampleUUIDSequence.uuid(88_401)
      let itemID = SampleUUIDSequence.uuid(88_402)
      let client = GroceryCategorizationClient { _, _ in
        throw ModelClientError.onDeviceUnavailable
      }

      try await database.write { db in
        try GroceryList.insert {
          GroceryList(
            id: listID,
            title: "Shopping",
            sortOrder: 0,
            isDefault: false,
            dateCreated: now,
            dateModified: now
          )
        }
        .execute(db)
        try GroceryItem.insert {
          GroceryItem(
            id: itemID,
            groceryListID: listID,
            title: "Gochujang",
            canonicalName: "gochujang",
            sortOrder: 0,
            dateCreated: now,
            dateModified: now
          )
        }
        .execute(db)
      }

      await #expect(throws: ModelClientError.onDeviceUnavailable) {
        try await client(names: ["gochujang"], tier: .onDevice)
      }

      try await database.read { db in
        let item = try #require(try GroceryItem.find(itemID).fetchOne(db))
        expectNoDifference(item.aisle, nil)
      }
    }

    @Test
    func attemptCacheSkipsPriorMissesButSendsNewNames() async throws {
      let recorder = GroceryCategorizationNamesRecorder()
      let client = GroceryCategorizationClient { names, _ in
        await recorder.append(names)
        return [:]
      }
      var attemptCache = GroceryCategorizationAttemptCache()

      let firstNames = attemptCache.namesToClassify(from: ["harissa"])
      _ = try await client(names: firstNames, tier: .onDevice)

      let repeatedNames = attemptCache.namesToClassify(from: ["harissa"])
      #expect(repeatedNames.isEmpty)

      let newNames = attemptCache.namesToClassify(from: ["harissa", "miso"])
      _ = try await client(names: newNames, tier: .onDevice)

      let requests = await recorder.allNames()
      expectNoDifference(requests, [["harissa"], ["miso"]])
    }
  }
}

private actor GroceryCategorizationRequestRecorder {
  private var requests: [ModelRequest] = []

  func append(_ request: ModelRequest) {
    requests.append(request)
  }

  func first() -> ModelRequest? {
    requests.first
  }

  func allRequests() -> [ModelRequest] {
    requests
  }
}

private actor GroceryCategorizationNamesRecorder {
  private var names: [[String]] = []

  func append(_ names: [String]) {
    self.names.append(names)
  }

  func allNames() -> [[String]] {
    names
  }
}

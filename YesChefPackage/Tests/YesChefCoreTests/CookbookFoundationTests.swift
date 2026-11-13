import Foundation
import Testing
import YesChefCore

struct CookbookFoundationTests {
  @Test func migrationIdentifiersMatchShippedOrder() {
    #expect(YesChefSchema.migrator().migrations == [
      "Create MVP recipe library schema",
      "Add library placement and category hierarchy",
      "Loosen category parent reference for CloudKit sync",
      "Create meal calendar schema",
      "Create menu schema",
      "Create grocery schema",
      "Create pantry schema",
      "Create recipe import ref schema",
      "Add recipe make-ahead field",
      "Add per-placement recipe scale",
      "Add recipe enrichment and ingredient substitutions",
      "Add pantry policy and cached canonical names",
      "Add menu prep plan",
      "Add recipe cover photo pointer",
      "Create local chat persistence",
      "Remove ingredient substitutions",
      "Create synced AI settings",
      "Create workbench schema",
      "Create workbench log",
      "Create recipe variations",
      "Add reader feedback curation preference",
      "Add capture to note preference",
      "Add local chat response continuity",
      "Backfill grocery store areas",
      "Create local AI handoffs",
      "Add external ChatGPT project to menus",
      "Create synced learnings",
      "Add sparse learning ordering",
      "Move menu prep plans into editable step rows",
      "Add typed workbench experiment fields",
      "Create recipe deliberation log",
      "Remove legacy menu prep plan BLOB",
      "Add local chat message tier provenance",
      "Add day scope to local AI handoffs",
      "Add workbench completion date",
      "Create workbench references",
      "Move recipe Serve With into editable rows",
      "Add regenerate intent to local AI handoffs",
      "Add color to categories",
      "Create synced category seed state",
      "Create synced category seed tombstones",
      "Promote category namespaces to facets",
      "Add variation scope to local AI handoffs",
      "Backfill captureKind column on workbench references",
      "Reconcile late-added workbench references columns",
      "Drop orphaned kind column from workbench references",
      "Drop all non-model columns from workbench references",
      "Create learned grocery area assignments",
      "Create related recipe edges",
      "Add review timestamp to learned grocery area assignments",
      "Drop legacy recipe cooking columns",
      "Drop raw import HTML",
      "Create local recipe sync repair queue",
      "Drop never-set columns and retired tag and equipment tables",
      "Create recipe lenses and shelves",
      "Create local data pass state",
      "Add Serve With recipe link",
      "Add prep plan work day offset",
      "Add prep plan make-ahead window",
      "Add prep plan time of day",
      "Create grocery trip assignments",
      "Add prep plan completion",
      "Add ingredient name fixes",
    ])
  }

  @Test func fileSkipsNewerPayloadsButRejectsMalformedData() throws {
    let recipe = Recipe(id: UUID(), title: "Soup", dateCreated: .distantPast, dateModified: .distantPast)
    let bundle = RecipeBundleCoding.RecipeBundle(recipe: recipe)
    var future = bundle
    future.version = RecipeBundleCoding.currentVersion + 1
    let file = CookbookFile(ownerName: "Jon", generatedAt: .distantPast, payloads: [
      try CookbookPayload.encodedPayload(bundle), try JSONEncoder().encode(future)
    ])
    let decoded = try JSONDecoder().decode(CookbookFile.self, from: JSONEncoder().encode(file))
    let result = try decoded.decodedPayloads()
    #expect(result.bundles == [bundle])
    #expect(result.newerVersionCount == 1)
    var malformed = file
    malformed.payloads.append(Data("invalid".utf8))
    #expect(throws: (any Error).self) { try malformed.decodedPayloads() }
  }
}

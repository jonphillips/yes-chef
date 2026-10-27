import Foundation
import LLMHandoffKit
import MCPServerKit
import Testing
import YesChefCore
import YesChefMCPServer

struct YesChefMCPTests {
  @Test func listsOnlyStageRecipeAndStagesAValidatedColonFreeFile() async throws {
    let temporary = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let container = temporary.appending(path: "container", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporary) }

    let fixedDate = ISO8601DateFormatter().date(from: "2026-10-21T12:00:00Z")!
    let server = YesChefMCPServer.make(containerURL: container) { fixedDate }
    let list = try #require(await server.handle(line: request("tools/list")))
    let tools = try object(list)["result"]?.objectValue?["tools"]?.arrayValue ?? []
    #expect(Set(tools.compactMap { $0.objectValue?["name"]?.stringValue }) == Set(["stage_recipe", "search_recipes", "get_recipe", "list_menus", "get_menu", "get_meal_plan"]))

    let response = try #require(await server.handle(line: toolCall("stage_recipe", recipe: validRecipe)))
    let responseObject = try object(response)["result"]?.objectValue ?? [:]
    #expect(responseObject["isError"] != .bool(true))
    let content = responseObject["content"]?.arrayValue?.first?.objectValue?["text"]?.stringValue
    #expect(content?.contains("\"staged\":\"Braised Beans\"") == true)
    #expect(content?.contains("\"next\":\"Jon reviews and saves it in Yes Chef → Create Recipe.\"") == true)
    #expect(!content.orEmpty.contains(container.path))

    let inboxURL = ChatAccessFolder(containerURL: container).inboxURL
    let inbox = HandoffInbox(root: inboxURL, fileExtension: "json")
    let staged = try #require(try inbox.list().first)
    #expect(!staged.url.lastPathComponent.contains(":"))
    #expect(staged.url.pathExtension == "json")
    let stagedText = try inbox.read(staged)
    let parsed = try RecipeContractStaging.validate(stagedText)
    #expect(parsed.title == "Braised Beans")
    #expect(try inbox.list().count == 1)
  }

  @Test func readToolsServeTextOnlyResultsAndRejectOldRefs() async throws {
    let temporary = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let container = temporary.appending(path: "container", directoryHint: .isDirectory)
    let exportFolder = ChatAccessFolder(containerURL: container).exportsURL
    try FileManager.default.createDirectory(at: exportFolder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporary) }
    let fixedDate = ISO8601DateFormatter().date(from: "2026-10-21T12:00:00Z")!
    let recipeID = UUID()
    let mealCalendar = Calendar.current
    let firstMealDay = mealCalendar.startOfDay(for: fixedDate)
    let lastMealDay = mealCalendar.date(byAdding: .day, value: 1, to: firstMealDay)!
    let outsideMealDay = mealCalendar.date(byAdding: .day, value: 2, to: firstMealDay)!
    let recipe = Recipe(id: recipeID, title: "Braised Beans", servingsText: "4", totalTimeMinutes: 90, cuisine: "Italian", course: "Dinner", dateCreated: fixedDate, dateModified: fixedDate)
    let otherRecipeID = UUID()
    let otherRecipe = Recipe(id: otherRecipeID, title: "Apple Cake", dateCreated: fixedDate, dateModified: fixedDate)
    let sectionID = UUID()
    let bundle = RecipeBundleCoding.RecipeBundle(recipe: recipe, ingredientSections: [IngredientSection(id: sectionID, recipeID: recipeID, name: "Main", sortOrder: 0)], ingredientLines: [IngredientLine(id: UUID(), recipeID: recipeID, sectionID: sectionID, originalText: "1 cup beans", sortOrder: 0)], tagNames: ["Harvest tag"], categoryNames: ["Weeknight"])
    let otherBundle = RecipeBundleCoding.RecipeBundle(recipe: otherRecipe)
    let menu = ChatAccessExport.MenuRecord(id: UUID(), title: "Sunday", notes: nil, dayCount: 1, modified: fixedDate, items: [
      ChatAccessExport.MenuItemRecord(kind: .recipe, title: "Beans special", recipeID: recipeID, dayOffset: 0, slot: .dinner, note: nil, scale: 1),
    ])
    let mealPlanRows = [firstMealDay, lastMealDay, outsideMealDay].enumerated().map { index, day in
      ChatAccessExport.MealPlanRecord(kind: .note, title: "Day \(index)", recipeID: nil, scheduledDate: day, slot: .dinner, note: nil, scale: 1)
    }
    let export = ChatAccessExport(generatedAt: fixedDate, device: "iPad", recipes: [otherBundle, bundle], menus: [menu], mealPlan: mealPlanRows)
    let exportURL = exportFolder.appending(path: "install.json")
    try ChatAccessExportCoding.encode(export).write(to: exportURL)
    let clock = TestClock(fixedDate.addingTimeInterval(600))
    let server = YesChefMCPServer.make(containerURL: container) { clock.now() }

    let search = try #require(await server.handle(line: genericToolCall("search_recipes", args: ["query": .string("beans")])))
    let searchText = try toolText(search)
    #expect(searchText.contains("Braised Beans"))
    #expect(searchText.contains("ageMinutes"))
    #expect(searchText.contains("90 min"))
    #expect(!containsUUID(searchText))
    let parsed = try object(searchText)
    let ref = try #require(parsed["recipes"]?.arrayValue?.first?.objectValue?["ref"]?.stringValue)
    let searchRow = try #require(parsed["recipes"]?.arrayValue?.first?.objectValue)
    #expect(searchRow["categories"]?.arrayValue == [.string("Weeknight")])
    #expect(searchRow["tags"] == nil)
    let categorySearch = try #require(await server.handle(line: genericToolCall("search_recipes", args: ["query": .string("weeknight")])))
    let categoryRows = try object(toolText(categorySearch))["recipes"]?.arrayValue ?? []
    #expect(categoryRows.count == 1)
    let tagSearch = try #require(await server.handle(line: genericToolCall("search_recipes", args: ["query": .string("Harvest tag")])))
    #expect(try object(toolText(tagSearch))["recipes"]?.arrayValue?.isEmpty == true)
    #expect(ref.hasSuffix(".r1"))
    let detail = try #require(await server.handle(line: genericToolCall("get_recipe", args: ["ref": .string(ref)])))
    let detailText = try toolText(detail)
    #expect(detailText.contains("Braised Beans"))
    #expect(detailText.contains("1 cup beans"))
    #expect(detailText.contains("90 min"))
    let detailRecipe = try #require(try object(detailText)["recipe"]?.objectValue)
    #expect(detailRecipe["categories"]?.arrayValue == [.string("Weeknight")])
    #expect(detailRecipe["tags"] == nil)
    #expect(!containsUUID(detailText))

    clock.advance(by: 50 * 60)
    let agedSearch = try #require(await server.handle(line: genericToolCall("search_recipes", args: ["query": .string("beans")])))
    let agedText = try toolText(agedSearch)
    #expect(try object(agedText)["export"]?.objectValue?["ageMinutes"] == .integer(60))

    let menus = try #require(await server.handle(line: genericToolCall("list_menus", args: [:])))
    #expect(!containsUUID(try toolText(menus)))
    let menuRef = try #require(object(toolText(menus))["menus"]?.arrayValue?.first?.objectValue?["ref"]?.stringValue)
    let menuDetail = try #require(await server.handle(line: genericToolCall("get_menu", args: ["ref": .string(menuRef)])))
    let menuText = try toolText(menuDetail)
    #expect(menuText.contains("Sunday"))
    #expect(menuText.contains("Braised Beans"))
    #expect(!containsUUID(menuText))
    let mealPlanResult = try #require(await server.handle(line: genericToolCall("get_meal_plan", args: ["from": .string("2026-10-21"), "to": .string("2026-10-22")])))
    let mealPlanText = try toolText(mealPlanResult)
    let mealPlanOutput = try object(mealPlanText)
    #expect(mealPlanOutput["items"]?.arrayValue?.count == 2)
    #expect(mealPlanText.contains("2026-10-21"))
    #expect(mealPlanText.contains("2026-10-22"))
    #expect(!mealPlanText.contains("2026-10-23"))
    #expect(!containsUUID(mealPlanText))
    try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: 60)], ofItemAtPath: exportURL.path)
    let stale = try #require(await server.handle(line: genericToolCall("get_recipe", args: ["ref": .string(ref)])))
    #expect(try object(stale)["result"]?.objectValue?["isError"] == .bool(true))
    #expect(try toolText(stale).contains("older export; search again"))
    let wrongRecipeKind = try #require(await server.handle(line: genericToolCall("get_recipe", args: ["ref": .string(menuRef)])))
    #expect(try toolText(wrongRecipeKind).contains("isn't a recipe"))
    let wrongMenuKind = try #require(await server.handle(line: genericToolCall("get_menu", args: ["ref": .string(ref)])))
    #expect(try toolText(wrongMenuKind).contains("isn't a menu"))
  }

  @Test func materializerSeamSuccessResolvesRecipeNamesInMenu() async throws {
    let temporary = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let container = temporary.appending(path: "container", directoryHint: .isDirectory)
    let exports = ChatAccessFolder(containerURL: container).exportsURL
    try FileManager.default.createDirectory(at: exports, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporary) }
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    let recipeID = UUID()
    let bundle = RecipeBundleCoding.RecipeBundle(recipe: Recipe(id: recipeID, title: "Chicken Soup", dateCreated: date, dateModified: date))
    let menu = ChatAccessExport.MenuRecord(id: UUID(), title: "Weeknight", notes: nil, dayCount: 1, modified: date, items: [
      ChatAccessExport.MenuItemRecord(kind: .recipe, title: "Soup", recipeID: recipeID, dayOffset: 0, slot: .dinner, note: nil, scale: 1),
    ])
    let data = try ChatAccessExportCoding.encode(ChatAccessExport(generatedAt: date, device: "iPhone", recipes: [bundle], menus: [menu], mealPlan: []))
    try data.write(to: exports.appending(path: "install.json"))
    let server = YesChefMCPServer.make(
      containerURL: container,
      now: { date },
      exportMaterializer: { _ in data }
    )
    let menuList = try #require(await server.handle(line: genericToolCall("list_menus", args: [:])))
    let menuRef = try #require(object(toolText(menuList))["menus"]?.arrayValue?.first?.objectValue?["ref"]?.stringValue)
    let detail = try #require(await server.handle(line: genericToolCall("get_menu", args: ["ref": .string(menuRef)])))
    #expect(try toolText(detail).contains("Chicken Soup"))
  }

  @Test func readToolsExplainWhenNoExportExists() async throws {
    let container = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let server = YesChefMCPServer.make(containerURL: container)
    let response = try #require(await server.handle(line: genericToolCall("search_recipes", args: ["query": .string("soup")])))
    #expect(try toolText(response).contains("No Yes Chef export yet"))
    try? FileManager.default.removeItem(at: container)
  }

  @Test func materializerSeamReturnsTimeoutErrorWithoutWaitingSixtySeconds() async throws {
    let temporary = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let container = temporary.appending(path: "container", directoryHint: .isDirectory)
    let exports = ChatAccessFolder(containerURL: container).exportsURL
    try FileManager.default.createDirectory(at: exports, withIntermediateDirectories: true)
    try Data("placeholder".utf8).write(to: exports.appending(path: "install.json"))
    defer { try? FileManager.default.removeItem(at: temporary) }
    let server = YesChefMCPServer.make(
      containerURL: container,
      exportMaterializer: { _ in try await Task.sleep(for: .seconds(1)); return Data() },
      materializationDeadline: .milliseconds(10)
    )
    let response = try #require(await server.handle(line: genericToolCall("search_recipes", args: ["query": .string("soup")])))
    #expect(try toolText(response).contains("still downloading from iCloud"))
  }

  @Test func recipeSearchUsesTwentyDefaultAndFiftyMaximum() async throws {
    let temporary = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let container = temporary.appending(path: "container", directoryHint: .isDirectory)
    let exports = ChatAccessFolder(containerURL: container).exportsURL
    try FileManager.default.createDirectory(at: exports, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporary) }
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    let bundles = (0..<51).map { index in
      RecipeBundleCoding.RecipeBundle(recipe: Recipe(id: UUID(), title: "Recipe \(index)", dateCreated: date, dateModified: date))
    }
    let export = ChatAccessExport(generatedAt: date, device: "iPhone", recipes: bundles, menus: [], mealPlan: [])
    try ChatAccessExportCoding.encode(export).write(to: exports.appending(path: "install.json"))
    let server = YesChefMCPServer.make(containerURL: container) { date }

    let defaults = try #require(await server.handle(line: genericToolCall("search_recipes", args: ["query": .string("")])))
    #expect(try object(toolText(defaults))["recipes"]?.arrayValue?.count == 20)
    let capped = try #require(await server.handle(line: genericToolCall("search_recipes", args: ["query": .string(""), "limit": .integer(100)])))
    #expect(try object(toolText(capped))["recipes"]?.arrayValue?.count == 50)
  }

  @Test func invalidRecipeReturnsErrorAndStagesNothing() async throws {
    let temporary = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let container = temporary.appending(path: "container", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporary) }
    let server = YesChefMCPServer.make(containerURL: container)

    let response = try #require(await server.handle(line: toolCall("stage_recipe", recipe: .object(["@type": .string("Recipe")]))))
    let responseObject = try object(response)["result"]?.objectValue ?? [:]
    #expect(responseObject["isError"] == .bool(true))
    #expect(responseObject["content"]?.arrayValue?.first?.objectValue?["text"]?.stringValue?.contains("ingredients and instructions") == true)
    #expect(!FileManager.default.fileExists(atPath: ChatAccessFolder(containerURL: container).inboxURL.path))
  }

  @Test func missingContainerReturnsErrorWithoutCreatingIt() async throws {
    let container = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let server = YesChefMCPServer.make(containerURL: container)

    let response = try #require(await server.handle(line: toolCall("stage_recipe", recipe: validRecipe)))
    #expect(try object(response)["result"]?.objectValue?["isError"] == .bool(true))
    #expect(try object(response)["result"]?.objectValue?["content"]?.arrayValue?.first?.objectValue?["text"]?.stringValue?.contains(container.path) == true)
    #expect(!FileManager.default.fileExists(atPath: container.path))
  }

  private var validRecipe: MCPValue {
    .object([
      "@context": .string("https://schema.org"),
      "@type": .string("Recipe"),
      "name": .string("Braised Beans"),
      "recipeIngredient": .array([.string("1 cup beans")]),
      "recipeInstructions": .array([.object(["@type": .string("HowToStep"), "text": .string("Cook the beans.")])]),
    ])
  }

  private func request(_ method: String) -> String {
    String(decoding: try! JSONEncoder().encode(MCPValue.object(["jsonrpc": .string("2.0"), "id": .integer(1), "method": .string(method)])), as: UTF8.self)
  }

  private func toolCall(_ name: String, recipe: MCPValue) -> String {
    String(decoding: try! JSONEncoder().encode(MCPValue.object([
      "jsonrpc": .string("2.0"),
      "id": .integer(1),
      "method": .string("tools/call"),
      "params": .object(["name": .string(name), "arguments": .object(["recipe": recipe])]),
    ])), as: UTF8.self)
  }

  private func genericToolCall(_ name: String, args: [String: MCPValue]) -> String {
    String(decoding: try! JSONEncoder().encode(MCPValue.object([
      "jsonrpc": .string("2.0"), "id": .integer(1), "method": .string("tools/call"),
      "params": .object(["name": .string(name), "arguments": .object(args)]),
    ])), as: UTF8.self)
  }

  private func toolText(_ response: String) throws -> String {
    let responseObject = try object(response)["result"]?.objectValue ?? [:]
    return try #require(responseObject["content"]?.arrayValue?.first?.objectValue?["text"]?.stringValue)
  }

  private func containsUUID(_ text: String) -> Bool {
    text.range(of: #"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"#, options: .regularExpression) != nil
  }

  private func object(_ json: String) throws -> [String: MCPValue] {
    try JSONDecoder().decode(MCPValue.self, from: Data(json.utf8)).objectValue ?? [:]
  }
}

private extension MCPValue {
  var arrayValue: [MCPValue]? {
    guard case let .array(value) = self else { return nil }
    return value
  }
}

private extension Optional where Wrapped == String {
  var orEmpty: String { self ?? "" }
}

private final class TestClock: @unchecked Sendable {
  private let lock = NSLock()
  private var date: Date

  init(_ date: Date) { self.date = date }

  func now() -> Date {
    lock.lock()
    defer { lock.unlock() }
    return date
  }

  func advance(by interval: TimeInterval) {
    lock.lock()
    date.addTimeInterval(interval)
    lock.unlock()
  }
}

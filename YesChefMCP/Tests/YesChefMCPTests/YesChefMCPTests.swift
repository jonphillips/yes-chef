import ChatAccessKit
import Foundation
import LLMHandoffKit
import MCPServerKit
import Testing
import YesChefCore
import YesChefMCPServer

struct YesChefMCPTests {
  @Test func unchangedExportKeepsRecipeRefsAcrossToolCalls() async throws {
    let temporary = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let container = ChatAccessHelperFolder.containerURL(for: "iCloud.com.jonphillips.yeschef", home: temporary)
    let exports = ChatAccessFolder(containerURL: container, isDevelopment: false).exportsURL
    try FileManager.default.createDirectory(at: exports, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporary) }
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    let bundle = RecipeBundleCoding.RecipeBundle(recipe: Recipe(id: UUID(), title: "Stable Soup", dateCreated: date, dateModified: date))
    let export = ChatAccessExport(generatedAt: date, device: "iPhone", recipes: [bundle], menus: [], mealPlan: [])
    let data = try ChatAccessExportCoding.encode(export)
    try data.write(to: exports.appending(path: "install.json"))
    let materializer = ExportMaterializationCounter(data: data)
    let server = YesChefMCPServer.make(home: temporary, now: { date }, exportMaterializer: { _ in await materializer.materialize() })

    let first = try #require(await server.handle(line: genericToolCall("search_recipes", args: ["query": .string("soup")])))
    let second = try #require(await server.handle(line: genericToolCall("search_recipes", args: ["query": .string("soup")])))
    let firstRef = try #require(object(toolText(first))["recipes"]?.arrayValue?.first?.objectValue?["ref"]?.stringValue)
    let secondRef = try #require(object(toolText(second))["recipes"]?.arrayValue?.first?.objectValue?["ref"]?.stringValue)
    #expect(firstRef == secondRef)
    #expect(await materializer.count == 1)
  }

  @Test func listsToolsAndStagesAValidatedColonFreeRecipe() async throws {
    let temporary = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let container = ChatAccessHelperFolder.containerURL(for: "iCloud.com.jonphillips.yeschef", home: temporary)
    try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporary) }

    let fixedDate = ISO8601DateFormatter().date(from: "2026-10-21T12:00:00Z")!
    let server = YesChefMCPServer.make(home: temporary) { fixedDate }
    let list = try #require(await server.handle(line: request("tools/list")))
    let tools = try object(list)["result"]?.objectValue?["tools"]?.arrayValue ?? []
    #expect(Set(tools.compactMap { $0.objectValue?["name"]?.stringValue }) == Set(["stage_recipe", "stage_handoff_return", "stage_recipe_return", "stage_menu", "stage_menu_day", "search_recipes", "get_recipe", "list_menus", "get_menu", "get_meal_plan"]))

    let response = try #require(await server.handle(line: toolCall("stage_recipe", recipe: validRecipe)))
    let responseObject = try object(response)["result"]?.objectValue ?? [:]
    #expect(responseObject["isError"] != .bool(true))
    let content = responseObject["content"]?.arrayValue?.first?.objectValue?["text"]?.stringValue
    #expect(content?.contains("\"staged\":\"Braised Beans\"") == true)
    #expect(content?.contains("\"next\":\"Jon reviews and saves it in Yes Chef → Create Recipe.\"") == true)
    #expect(!content.orEmpty.contains(container.path))

    let inboxURL = ChatAccessFolder(containerURL: container, isDevelopment: false).inboxURL
    let inbox = HandoffInbox(root: inboxURL, fileExtension: "json")
    let staged = try #require(try inbox.list().first)
    #expect(!staged.url.lastPathComponent.contains(":"))
    #expect(staged.url.pathExtension == "json")
    let stagedText = try inbox.read(staged)
    let parsed = try RecipeContractStaging.validate(stagedText)
    #expect(parsed.title == "Braised Beans")
    #expect(try inbox.list().count == 1)
  }

  @Test func developmentVariantStagesSeparately() async throws {
    let temporary = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let container = ChatAccessHelperFolder.containerURL(for: "iCloud.com.jonphillips.yeschef", home: temporary)
    try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporary) }
    let server = YesChefMCPServer.make(home: temporary, isDevelopment: true)
    let response = try #require(await server.handle(line: toolCall("stage_recipe", recipe: validRecipe)))
    #expect(try object(response)["result"]?.objectValue?["isError"] != .bool(true))
    let token = UUID().uuidString
    let text = "YC-HANDOFF: \(token)\nYC-CONTRACT: v3\nDev return"
    let returned = try #require(await server.handle(line: genericToolCall("stage_handoff_return", args: ["text": .string(text)])))
    #expect(try object(returned)["result"]?.objectValue?["isError"] != .bool(true))
    let devFolder = ChatAccessFolder(containerURL: container, isDevelopment: true)
    let productionFolder = ChatAccessFolder(containerURL: container, isDevelopment: false)
    #expect(try HandoffInbox(root: devFolder.inboxURL, fileExtension: "json").list().count == 1)
    #expect(try HandoffInbox(root: devFolder.inboxURL, fileExtension: "ycreturn").list().count == 1)
    #expect(!FileManager.default.fileExists(atPath: productionFolder.inboxURL.path))

    let date = Date(timeIntervalSince1970: 1_800_000_000)
    let recipe = Recipe(id: UUID(), title: "Dev-only beans", dateCreated: date, dateModified: date)
    let export = ChatAccessExport(generatedAt: date, device: "Dev", recipes: [RecipeBundleCoding.RecipeBundle(recipe: recipe)], menus: [], mealPlan: [])
    try FileManager.default.createDirectory(at: devFolder.exportsURL, withIntermediateDirectories: true)
    try ChatAccessExportCoding.encode(export).write(to: devFolder.exportsURL.appending(path: "install.json"))
    let search = try #require(await server.handle(line: genericToolCall("search_recipes", args: ["query": .string("beans")])))
    #expect(try toolText(search).contains("Dev-only beans"))
    let production = YesChefMCPServer.make(home: temporary)
    let noExport = try #require(await production.handle(line: genericToolCall("search_recipes", args: ["query": .string("beans")])))
    #expect(try toolText(noExport).contains("No Yes Chef export yet"))
  }

  @Test func readToolsServeTextOnlyResultsAndRejectOldRefs() async throws {
    let temporary = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let container = ChatAccessHelperFolder.containerURL(for: "iCloud.com.jonphillips.yeschef", home: temporary)
    let exportFolder = ChatAccessFolder(containerURL: container, isDevelopment: false).exportsURL
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
    let server = YesChefMCPServer.make(home: temporary) { clock.now() }

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
    let container = ChatAccessHelperFolder.containerURL(for: "iCloud.com.jonphillips.yeschef", home: temporary)
    let exports = ChatAccessFolder(containerURL: container, isDevelopment: false).exportsURL
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
      home: temporary,
      now: { date },
      exportMaterializer: { _ in data }
    )
    let menuList = try #require(await server.handle(line: genericToolCall("list_menus", args: [:])))
    let menuRef = try #require(object(toolText(menuList))["menus"]?.arrayValue?.first?.objectValue?["ref"]?.stringValue)
    let detail = try #require(await server.handle(line: genericToolCall("get_menu", args: ["ref": .string(menuRef)])))
    #expect(try toolText(detail).contains("Chicken Soup"))
  }

  @Test func readToolsExplainWhenNoExportExists() async throws {
    let temporary = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let server = YesChefMCPServer.make(home: temporary)
    let response = try #require(await server.handle(line: genericToolCall("search_recipes", args: ["query": .string("soup")])))
    #expect(try toolText(response).contains("No Yes Chef export yet"))
    try? FileManager.default.removeItem(at: temporary)
  }

  @Test func materializerSeamReturnsTimeoutErrorWithoutWaitingSixtySeconds() async throws {
    let temporary = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let container = ChatAccessHelperFolder.containerURL(for: "iCloud.com.jonphillips.yeschef", home: temporary)
    let exports = ChatAccessFolder(containerURL: container, isDevelopment: false).exportsURL
    try FileManager.default.createDirectory(at: exports, withIntermediateDirectories: true)
    try Data("placeholder".utf8).write(to: exports.appending(path: "install.json"))
    defer { try? FileManager.default.removeItem(at: temporary) }
    let server = YesChefMCPServer.make(
      home: temporary,
      exportMaterializer: { _ in try await Task.sleep(for: .seconds(1)); return Data() },
      materializationDeadline: .milliseconds(10)
    )
    let response = try #require(await server.handle(line: genericToolCall("search_recipes", args: ["query": .string("soup")])))
    #expect(try toolText(response).contains("still downloading from iCloud"))
  }

  @Test func recipeSearchUsesTwentyDefaultAndFiftyMaximum() async throws {
    let temporary = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let container = ChatAccessHelperFolder.containerURL(for: "iCloud.com.jonphillips.yeschef", home: temporary)
    let exports = ChatAccessFolder(containerURL: container, isDevelopment: false).exportsURL
    try FileManager.default.createDirectory(at: exports, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporary) }
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    let bundles = (0..<51).map { index in
      RecipeBundleCoding.RecipeBundle(recipe: Recipe(id: UUID(), title: "Recipe \(index)", dateCreated: date, dateModified: date))
    }
    let export = ChatAccessExport(generatedAt: date, device: "iPhone", recipes: bundles, menus: [], mealPlan: [])
    try ChatAccessExportCoding.encode(export).write(to: exports.appending(path: "install.json"))
    let server = YesChefMCPServer.make(home: temporary) { date }

    let defaults = try #require(await server.handle(line: genericToolCall("search_recipes", args: ["query": .string("")])))
    #expect(try object(toolText(defaults))["recipes"]?.arrayValue?.count == 20)
    let capped = try #require(await server.handle(line: genericToolCall("search_recipes", args: ["query": .string(""), "limit": .integer(100)])))
    #expect(try object(toolText(capped))["recipes"]?.arrayValue?.count == 50)
  }

  @Test func invalidRecipeReturnsErrorAndStagesNothing() async throws {
    let temporary = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let container = ChatAccessHelperFolder.containerURL(for: "iCloud.com.jonphillips.yeschef", home: temporary)
    try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporary) }
    let server = YesChefMCPServer.make(home: temporary)

    let response = try #require(await server.handle(line: toolCall("stage_recipe", recipe: .object(["@type": .string("Recipe")]))))
    let responseObject = try object(response)["result"]?.objectValue ?? [:]
    #expect(responseObject["isError"] == .bool(true))
    #expect(responseObject["content"]?.arrayValue?.first?.objectValue?["text"]?.stringValue?.contains("ingredients and instructions") == true)
    #expect(!FileManager.default.fileExists(atPath: ChatAccessFolder(containerURL: container, isDevelopment: false).inboxURL.path))
  }

  @Test func missingContainerReturnsErrorWithoutCreatingIt() async throws {
    let temporary = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let container = ChatAccessHelperFolder.containerURL(for: "iCloud.com.jonphillips.yeschef", home: temporary)
    let server = YesChefMCPServer.make(home: temporary)

    let response = try #require(await server.handle(line: toolCall("stage_recipe", recipe: validRecipe)))
    #expect(try object(response)["result"]?.objectValue?["isError"] == .bool(true))
    #expect(try object(response)["result"]?.objectValue?["content"]?.arrayValue?.first?.objectValue?["text"]?.stringValue?.contains(container.path) == true)
    #expect(!FileManager.default.fileExists(atPath: container.path))
  }

  @Test func stagingToolDescriptionsCarryTheHandoffRouting() async throws {
    // ChatGPT doesn't put server instructions in front of the model, so the tool descriptions must route on their own.
    let server = YesChefMCPServer.make(home: FileManager.default.temporaryDirectory)
    let list = try #require(await server.handle(line: request("tools/list")))
    let tools = try object(list)["result"]?.objectValue?["tools"]?.arrayValue ?? []
    func tool(_ name: String) -> [String: MCPValue] {
      tools.compactMap(\.objectValue).first { $0["name"]?.stringValue == name } ?? [:]
    }
    let recipe = tool("stage_recipe")["description"]?.stringValue ?? ""
    #expect(recipe.contains("Only for a conversation with no `YC-HANDOFF:` line"))
    #expect(recipe.contains("`stage_handoff_return`"))
    #expect(recipe.contains("`stage_recipe_return`"))
    let recipeReturn = tool("stage_recipe_return")["description"]?.stringValue ?? ""
    #expect(recipeReturn.contains("search_recipes"))
    #expect(recipeReturn.contains("YC-HANDOFF:"))
    #expect(recipeReturn.contains("YC-NEW-RECIPE:"))
    #expect(recipeReturn.contains(RecipeReturnLabels.deliverableLines))
    let menu = tool("stage_menu")["description"]?.stringValue ?? ""
    #expect(menu.contains("stage_recipe"))
    #expect(menu.contains("search again"))
    #expect(menu.contains("stage_menu_day"))
    let menuDay = tool("stage_menu_day")["description"]?.stringValue ?? ""
    #expect(menuDay.contains("get_menu"))
    #expect(menuDay.contains("whole day") || menuDay.contains("every dish for that day"))
    #expect(menuDay.contains("anything not sent is removed"))
    #expect(menuDay.contains("stage_recipe_return"))
    let menuDayItemProperties = tool("stage_menu_day")["inputSchema"]?.objectValue?["properties"]?.objectValue?["items"]?.objectValue?["items"]?.objectValue?["properties"]?.objectValue ?? [:]
    #expect(menuDayItemProperties["day"] == nil)

    let handoff = tool("stage_handoff_return")
    let description = handoff["description"]?.stringValue ?? ""
    #expect(description.hasPrefix("Call this instead of printing the return when the cook asks to finalize"))
    #expect(description.contains("line 1 is the exact `YC-HANDOFF:` line from the prompt, line 2 is `YC-CONTRACT: v3`"))
    let text = handoff["inputSchema"]?.objectValue?["properties"]?.objectValue?["text"]?.objectValue
    #expect(text?["description"]?.stringValue == "The whole return: the `YC-HANDOFF:` line, then `YC-CONTRACT: v3`, then the deliverable.")
  }

  @Test func stageMenuDayResolvesMenuAndStagesOnlyTheSelectedDaySnapshot() async throws {
    let temporary = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: temporary) }
    let container = ChatAccessHelperFolder.containerURL(for: "iCloud.com.jonphillips.yeschef", home: temporary)
    let folder = ChatAccessFolder(containerURL: container, isDevelopment: false)
    try FileManager.default.createDirectory(at: folder.exportsURL, withIntermediateDirectories: true)
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let recipe = Recipe(id: UUID(), title: "Souvlaki", dateCreated: now, dateModified: now)
    let menuID = UUID()
    let menu = ChatAccessExport.MenuRecord(id: menuID, title: "Thanksgiving Week", notes: nil, dayCount: 7, modified: now, items: [
      .init(kind: .recipe, title: "Souvlaki", recipeID: recipe.id, dayOffset: 3, slot: .dinner, note: "Sauce on the side", scale: 2),
      .init(kind: .note, title: "Pie", recipeID: nil, dayOffset: 1, slot: .breakfast, note: nil, scale: 1),
    ])
    try ChatAccessExportCoding.encode(.init(generatedAt: now, device: "iPhone", recipes: [RecipeBundleCoding.RecipeBundle(recipe: recipe)], menus: [menu], mealPlan: []))
      .write(to: folder.exportsURL.appending(path: "install.json"))
    let server = YesChefMCPServer.make(home: temporary, now: { now })
    let listing = try #require(await server.handle(line: genericToolCall("list_menus", args: [:])))
    let menuRef = try #require(object(toolText(listing))["menus"]?.arrayValue?.first?.objectValue?["ref"]?.stringValue)
    let search = try #require(await server.handle(line: genericToolCall("search_recipes", args: ["query": .string("souvlaki")])))
    let recipeRef = try #require(object(toolText(search))["recipes"]?.arrayValue?.first?.objectValue?["ref"]?.stringValue)
    let response = try #require(await server.handle(line: genericToolCall("stage_menu_day", args: [
      "menu": .string(menuRef), "day": .integer(3),
      "items": .array([.object(["ref": .string(recipeRef), "note": .string("Serve sauce separately"), "scale": .number(2)])]),
    ])))
    let resultText = try toolText(response)
    let result = try object(resultText)
    #expect(!containsUUID(resultText))
    #expect(result["staged"]?.stringValue == "Thanksgiving Week, day 4")
    #expect(result["dishes"] == .integer(1))
    let file = try #require(HandoffInbox(root: folder.inboxURL, fileExtension: "ycmenuday").list().first)
    let envelope = try JSONDecoder().decode(ChatAccessStagedMenuDay.self, from: Data(try HandoffInbox(root: folder.inboxURL, fileExtension: "ycmenuday").read(file).utf8))
    #expect(envelope.menuID == menuID)
    #expect(envelope.items.count == 1)
    #expect(envelope.dayAtStage.map(\.title) == ["Souvlaki"])
  }

  @Test func stageMenuDayRejectsEveryInvalidCallWithoutStaging() async throws {
    let temporary = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: temporary) }
    let folder = ChatAccessFolder(containerURL: ChatAccessHelperFolder.containerURL(for: "iCloud.com.jonphillips.yeschef", home: temporary), isDevelopment: false)
    try FileManager.default.createDirectory(at: folder.exportsURL, withIntermediateDirectories: true)
    let now = Date(timeIntervalSince1970: 1_800_000_050)
    let live = Recipe(id: UUID(), title: "Soup", dateCreated: now, dateModified: now)
    let archived = Recipe(id: UUID(), title: "Old stew", archived: true, dateCreated: now, dateModified: now)
    let menu = ChatAccessExport.MenuRecord(id: UUID(), title: "Week", notes: nil, dayCount: 2, modified: now, items: [])
    try ChatAccessExportCoding.encode(.init(generatedAt: now, device: "iPhone", recipes: [
      RecipeBundleCoding.RecipeBundle(recipe: live), RecipeBundleCoding.RecipeBundle(recipe: archived),
    ], menus: [menu], mealPlan: [])).write(to: folder.exportsURL.appending(path: "install.json"))
    let server = YesChefMCPServer.make(home: temporary, now: { now })
    let listed = try #require(await server.handle(line: genericToolCall("list_menus", args: [:])))
    let menuRef = try #require(object(toolText(listed))["menus"]?.arrayValue?.first?.objectValue?["ref"]?.stringValue)
    let recipes = try #require(await server.handle(line: genericToolCall("search_recipes", args: ["query": .string("")])))
    let refs = try #require(object(toolText(recipes))["recipes"]?.arrayValue)
    let archivedRef = try #require(refs.first?.objectValue?["ref"]?.stringValue)
    let liveRef = try #require(refs.last?.objectValue?["ref"]?.stringValue)
    let invalid: [[String: MCPValue]] = [
      ["menu": .string("0.m0"), "day": .integer(0), "items": .array([.object(["title": .string("Soup")])])],
      ["menu": .string(liveRef), "day": .integer(0), "items": .array([.object(["title": .string("Soup")])])],
      ["menu": .string(menuRef), "day": .integer(2), "items": .array([.object(["title": .string("Soup")])])],
      ["menu": .string(menuRef), "day": .number(1.5), "items": .array([.object(["title": .string("Soup")])])],
      ["menu": .string(menuRef), "day": .integer(0), "items": .array([])],
      ["menu": .string(menuRef), "day": .integer(0), "items": .array(Array(repeating: .object(["title": .string("Soup")]), count: 41))],
      ["menu": .string(menuRef), "day": .integer(0), "items": .array([.object(["ref": .string(archivedRef)])])],
    ]
    for args in invalid {
      let response = try #require(await server.handle(line: genericToolCall("stage_menu_day", args: args)))
      #expect(try object(response)["result"]?.objectValue?["isError"] == .bool(true))
    }
    #expect(try HandoffInbox(root: folder.inboxURL, fileExtension: "ycmenuday").list().isEmpty)
  }

  @Test func chatStartedRecipeReturnAndMenuResolveAgainstOneExport() async throws {
    let temporary = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let container = ChatAccessHelperFolder.containerURL(for: "iCloud.com.jonphillips.yeschef", home: temporary)
    let folder = ChatAccessFolder(containerURL: container, isDevelopment: false)
    try FileManager.default.createDirectory(at: folder.exportsURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporary) }
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let recipeID = UUID()
    let recipe = Recipe(id: recipeID, title: "Braised Beans", dateCreated: now, dateModified: now,
      makeAhead: "Soak overnight", chefItUp: "Brown the aromatics")
    let bundle = RecipeBundleCoding.RecipeBundle(recipe: recipe)
    try ChatAccessExportCoding.encode(.init(generatedAt: now, device: "iPhone", recipes: [bundle], menus: [], mealPlan: []))
      .write(to: folder.exportsURL.appending(path: "install.json"))
    let server = YesChefMCPServer.make(home: temporary, now: { now })
    let search = try #require(await server.handle(line: genericToolCall("search_recipes", args: ["query": .string("beans")])))
    let ref = try #require(object(toolText(search))["recipes"]?.arrayValue?.first?.objectValue?["ref"]?.stringValue)

    let returnedText = "YC-REVISION:\nToast the spices"
    let returned = try #require(await server.handle(line: genericToolCall("stage_recipe_return", args: ["ref": .string(ref), "text": .string(returnedText)])))
    let returnResult = try toolText(returned)
    #expect(!containsUUID(returnResult))
    #expect(returnResult.contains("Braised Beans"))
    let stagedReturn = try #require(HandoffInbox(root: folder.inboxURL, fileExtension: "ycrecipereturn").list().first)
    let returnEnvelope = try JSONDecoder().decode(ChatAccessStagedRecipeReturn.self, from: Data(try HandoffInbox(root: folder.inboxURL, fileExtension: "ycrecipereturn").read(stagedReturn).utf8))
    #expect(returnEnvelope.recipeID == recipeID)
    #expect(returnEnvelope.text == returnedText)

    let menuCall = genericToolCall("stage_menu", args: [
      "title": .string("Sunday Supper"), "days": .integer(2),
      "items": .array([
        .object(["ref": .string(ref), "day": .integer(0), "slot": .string("dinner"), "scale": .number(1.5)]),
        .object(["title": .string("Green salad"), "day": .integer(1), "slot": .string("lunch"), "note": .string("Dress just before serving")]),
      ]),
    ])
    let stagedMenu = try #require(await server.handle(line: menuCall))
    let menuResult = try toolText(stagedMenu)
    #expect(!containsUUID(menuResult))
    #expect(menuResult.contains("\"recipes\":1"))
    #expect(menuResult.contains("\"newDishes\":1"))
    let menuFile = try #require(HandoffInbox(root: folder.inboxURL, fileExtension: "ycmenu").list().first)
    let menu = try JSONDecoder().decode(ChatAccessStagedMenu.self, from: Data(try HandoffInbox(root: folder.inboxURL, fileExtension: "ycmenu").read(menuFile).utf8))
    #expect(menu.items.map(\.recipeID) == [recipeID, nil])

    let get = try #require(await server.handle(line: genericToolCall("get_recipe", args: ["ref": .string(ref)])))
    let recipeValue = try object(toolText(get))["recipe"]?.objectValue
    #expect(recipeValue?["makeAhead"]?.stringValue == "Soak overnight")
    #expect(recipeValue?["chefItUp"]?.stringValue == "Brown the aromatics")
  }

  @Test func recipeReturnAndMenuValidationRejectBadInputsWithoutStaging() async throws {
    let temporary = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let container = ChatAccessHelperFolder.containerURL(for: "iCloud.com.jonphillips.yeschef", home: temporary)
    let folder = ChatAccessFolder(containerURL: container, isDevelopment: false)
    try FileManager.default.createDirectory(at: folder.exportsURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporary) }
    let now = Date(timeIntervalSince1970: 1_800_000_100)
    let recipe = Recipe(id: UUID(), title: "Soup", dateCreated: now, dateModified: now)
    let archived = Recipe(id: UUID(), title: "Old stew", archived: true, dateCreated: now, dateModified: now)
    let menu = ChatAccessExport.MenuRecord(id: UUID(), title: "Existing menu", notes: nil, dayCount: 1, modified: now, items: [])
    try ChatAccessExportCoding.encode(.init(generatedAt: now, device: "iPhone", recipes: [
      RecipeBundleCoding.RecipeBundle(recipe: recipe), RecipeBundleCoding.RecipeBundle(recipe: archived),
    ], menus: [menu], mealPlan: []))
      .write(to: folder.exportsURL.appending(path: "install.json"))
    let server = YesChefMCPServer.make(home: temporary, now: { now })
    let search = try #require(await server.handle(line: genericToolCall("search_recipes", args: ["query": .string("soup")])))
    let ref = try #require(object(toolText(search))["recipes"]?.arrayValue?.first?.objectValue?["ref"]?.stringValue)
    let oldRecipeReference = "0.r0"
    let menuList = try #require(await server.handle(line: genericToolCall("list_menus", args: [:])))
    let menuRef = try #require(object(toolText(menuList))["menus"]?.arrayValue?.first?.objectValue?["ref"]?.stringValue)
    for text in ["", "YC-HANDOFF: token\nYC-REVISION:\nChange it", "YC-NEW-RECIPE:\n{}"] {
      let result = try #require(await server.handle(line: genericToolCall("stage_recipe_return", args: ["ref": .string(ref), "text": .string(text)])))
      #expect(try object(result)["result"]?.objectValue?["isError"] == .bool(true))
    }
    for badRef in [oldRecipeReference, menuRef] {
      let result = try #require(await server.handle(line: genericToolCall("stage_recipe_return", args: ["ref": .string(badRef), "text": .string("YC-REVISION:\nChange it")])))
      #expect(try object(result)["result"]?.objectValue?["isError"] == .bool(true))
    }
    let archivedSearch = try #require(await server.handle(line: genericToolCall("search_recipes", args: ["query": .string("old stew")])))
    let archivedRef = try #require(object(toolText(archivedSearch))["recipes"]?.arrayValue?.first?.objectValue?["ref"]?.stringValue)
    let archivedReturn = try #require(await server.handle(line: genericToolCall("stage_recipe_return", args: ["ref": .string(archivedRef), "text": .string("YC-REVISION:\nChange it")])))
    #expect(try object(archivedReturn)["result"]?.objectValue?["isError"] == .bool(true))
    let invalidMenu = try #require(await server.handle(line: genericToolCall("stage_menu", args: [
      "title": .string("Dinner"), "items": .array([
        .object(["title": .string(""), "day": .integer(4), "slot": .string("brunch")]),
        .object(["ref": .string(ref), "scale": .number(0)]),
      ]),
    ])))
    let response = try object(invalidMenu)["result"]?.objectValue ?? [:]
    #expect(response["isError"] == .bool(true))
    let message = response["content"]?.arrayValue?.first?.objectValue?["text"]?.stringValue ?? ""
    #expect(message.contains("item 1"))
    #expect(message.contains("item 2"))
    #expect(try HandoffInbox(root: folder.inboxURL, fileExtension: "ycrecipereturn").list().isEmpty)
    #expect(try HandoffInbox(root: folder.inboxURL, fileExtension: "ycmenu").list().isEmpty)

    let invalidMenus: [[String: MCPValue]] = [
      ["title": .string(" "), "items": .array([.object(["title": .string("Salad")])])],
      ["title": .string("Dinner"), "items": .array([])],
      ["title": .string("Dinner"), "days": .integer(0), "items": .array([.object(["title": .string("Salad")])])],
      ["title": .string("Dinner"), "days": .integer(15), "items": .array([.object(["title": .string("Salad")])])],
      ["title": .string("Dinner"), "items": .array([.object(["title": .string("Salad"), "day": .integer(1)])])],
      ["title": .string("Dinner"), "days": .string("2"), "items": .array([.object(["title": .string("Salad")])])],
      ["title": .string("Dinner"), "items": .array([.object(["title": .string("Salad"), "day": .string("0")])])],
      ["title": .string("Dinner"), "items": .array([.object(["title": .string("Salad"), "slot": .string("brunch")])])],
      ["title": .string("Dinner"), "items": .array([.object(["title": .string("Salad"), "note": .string(String(repeating: "x", count: 501))])])],
      ["title": .string("Dinner"), "items": .array([.object(["title": .string("Salad"), "scale": .number(2)])])],
      ["title": .string("Dinner"), "items": .array([.object(["title": .string("Salad")]), .object(["ref": .string("0.r0")])])],
    ]
    for args in invalidMenus {
      let invalid = try #require(await server.handle(line: genericToolCall("stage_menu", args: args)))
      #expect(try object(invalid)["result"]?.objectValue?["isError"] == .bool(true))
    }
    #expect(try HandoffInbox(root: folder.inboxURL, fileExtension: "ycmenu").list().isEmpty)
  }

  @Test func handoffReturnsPreserveTextAndAllowRepeatedTokens() async throws {
    let temporary = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let container = ChatAccessHelperFolder.containerURL(for: "iCloud.com.jonphillips.yeschef", home: temporary)
    try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporary) }
    let date = ISO8601DateFormatter().date(from: "2026-10-21T12:00:00Z")!
    let server = YesChefMCPServer.make(home: temporary) { date }
    let id = UUID()
    let text = "YC-HANDOFF: \(id.uuidString)\nYC-CONTRACT: v3\nCrème brûlée\n"
    for _ in 0..<2 {
      let response = try #require(await server.handle(line: genericToolCall("stage_handoff_return", args: ["text": .string(text)])))
      #expect(try object(response)["result"]?.objectValue?["isError"] != .bool(true))
      let result = try object(toolText(response))
      #expect(result["warning"] == nil)
      #expect(result["next"]?.stringValue == "Staged for review on the device that started this hand-off. Jon opens it from From Chat there.")
    }
    let inbox = HandoffInbox(root: ChatAccessFolder(containerURL: container, isDevelopment: false).inboxURL, fileExtension: "ycreturn")
    let files = try inbox.list()
    #expect(files.count == 2)
    for file in files {
      #expect(file.slug == id.uuidString.lowercased())
      #expect(!file.url.lastPathComponent.contains(":"))
      #expect(try Data(contentsOf: file.url) == Data(text.utf8))
    }
  }

  @Test func invalidHandoffEnvelopesStageNothing() async throws {
    let temporary = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let container = ChatAccessHelperFolder.containerURL(for: "iCloud.com.jonphillips.yeschef", home: temporary)
    try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporary) }
    let server = YesChefMCPServer.make(home: temporary)
    let id = UUID().uuidString
    let cases = [
      ("YC-CONTRACT: v3\nBody", "first line"),
      ("YC-HANDOFF: invalid\nYC-CONTRACT: v3\nBody", "first line"),
      ("YC-HANDOFF: \(id)\nYC-CONTRACT: v3\n  \n", "no content"),
      ("YC-HANDOFF: \(id)\nYC-CONTRACT: v4\nBody", "contract v3"),
    ]
    for (text, message) in cases {
      let response = try #require(await server.handle(line: genericToolCall("stage_handoff_return", args: ["text": .string(text)])))
      #expect(try object(response)["result"]?.objectValue?["isError"] == .bool(true))
      #expect(try toolText(response).contains(message))
    }
    #expect(!FileManager.default.fileExists(atPath: ChatAccessFolder(containerURL: container, isDevelopment: false).inboxURL.path))
  }

  @Test func olderAndMissingMarkersStageWithWarnings() async throws {
    let temporary = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let container = ChatAccessHelperFolder.containerURL(for: "iCloud.com.jonphillips.yeschef", home: temporary)
    try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporary) }
    let server = YesChefMCPServer.make(home: temporary)
    let id = UUID().uuidString
    for text in ["YC-HANDOFF: \(id)\nYC-CONTRACT: v2\nBody", "YC-HANDOFF: \(id)\nBody"] {
      let response = try #require(await server.handle(line: genericToolCall("stage_handoff_return", args: ["text": .string(text)])))
      #expect(try object(response)["result"]?.objectValue?["isError"] != .bool(true))
      #expect(try object(toolText(response))["warning"]?.stringValue != nil)
    }
    let inbox = HandoffInbox(root: ChatAccessFolder(containerURL: container, isDevelopment: false).inboxURL, fileExtension: "ycreturn")
    #expect(try inbox.list().count == 2)
  }

  @Test func handoffReturnDoesNotCreateMissingContainer() async throws {
    let temporary = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let container = ChatAccessHelperFolder.containerURL(for: "iCloud.com.jonphillips.yeschef", home: temporary)
    let server = YesChefMCPServer.make(home: temporary)
    let text = "YC-HANDOFF: \(UUID().uuidString)\nYC-CONTRACT: v3\nBody"
    let response = try #require(await server.handle(line: genericToolCall("stage_handoff_return", args: ["text": .string(text)])))
    #expect(try object(response)["result"]?.objectValue?["isError"] == .bool(true))
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

private actor ExportMaterializationCounter {
  private let data: Data
  private(set) var count = 0

  init(data: Data) { self.data = data }

  func materialize() -> Data {
    count += 1
    return data
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

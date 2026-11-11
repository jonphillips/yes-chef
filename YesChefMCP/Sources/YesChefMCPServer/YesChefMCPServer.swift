import ChatAccessKit
import Foundation
import LLMHandoffKit
import MCPServerKit
import YesChefCore

private struct StageRecipeInput: Decodable, Sendable {
  var recipe: MCPValue
}

private struct StageReturnInput: Decodable, Sendable {
  var text: String
}

private struct StageReturnResult: Encodable, Sendable {
  var staged: String
  var next: String
  var warning: String?
}

private struct StageRecipeResult: Encodable, Sendable {
  var staged: String
  var next: String
}

private struct StageRecipeReturnResult: Encodable, Sendable {
  var staged: String
  var next: String
}

private struct StageMenuResult: Encodable, Sendable {
  var staged: String
  var recipes: Int
  var newDishes: Int
  var next: String
}

private struct StageMenuDayResult: Encodable, Sendable {
  var staged: String
  var dishes: Int
  var next: String
}

private struct StagePrepPlanResult: Encodable, Sendable {
  var staged: String
  var dishes: Int
  var steps: Int
  var next: String
}

private struct StageContext: Sendable {
  let home: URL
  let now: @Sendable () -> Date
  let isDevelopment: Bool

  func stage(_ recipe: MCPValue) throws -> StageRecipeResult {
    let data = try JSONEncoder().encode(recipe)
    let text = String(decoding: data, as: UTF8.self)
    let extraction = try RecipeContractStaging.validate(text)
    let folder = try stagingFolder()
    let name = extraction.title?.trimmingCharacters(in: .whitespacesAndNewlines)
    let recipeName = name.flatMap { $0.isEmpty ? nil : $0 } ?? "Recipe"
    let inbox = HandoffInbox(root: folder.inboxURL, fileExtension: "json")
    _ = try inbox.stage(text, slug: recipeName, now: now())
    return StageRecipeResult(
      staged: recipeName,
      next: "Jon reviews and saves it in Yes Chef → Create Recipe."
    )
  }

  func stageReturn(_ text: String) throws -> StageReturnResult {
    let marked: AIHandoffReturnContract.Result
    do {
      marked = try AIHandoffReturnContract.strippingMarker(from: text)
    } catch AIHandoffReturnContractError.instructionsOutOfDate {
      throw StageReturnError.newerContract
    }
    guard let routed = AIHandoffToken.stripping(from: marked.text) else {
      throw StageReturnError.missingToken
    }
    guard !routed.payload.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw StageReturnError.emptyBody
    }
    let folder = try stagingFolder()
    let inbox = HandoffInbox(root: folder.inboxURL, fileExtension: "ycreturn")
    _ = try inbox.stage(text, slug: routed.handoffID.uuidString, now: now())
    return StageReturnResult(
      staged: "Hand-off return",
      next: "Staged for review on the device that started this hand-off. Jon opens it from From Chat there.",
      warning: marked.warning
    )
  }

  func stageRecipeReturn(recipeID: UUID, title: String, text: String) throws -> StageRecipeReturnResult {
    let envelope = ChatAccessStagedRecipeReturn(recipeID: recipeID, recipeTitle: title, text: text)
    let data = try JSONEncoder().encode(envelope)
    let inbox = HandoffInbox(root: try stagingFolder().inboxURL, fileExtension: "ycrecipereturn")
    _ = try inbox.stage(String(decoding: data, as: UTF8.self), slug: recipeID.uuidString, now: now())
    return StageRecipeReturnResult(staged: title, next: "Jon reviews it in Yes Chef → From Chat.")
  }

  func stageMenu(_ envelope: ChatAccessStagedMenu, recipeCount: Int, newDishCount: Int) throws -> StageMenuResult {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(envelope)
    let inbox = HandoffInbox(root: try stagingFolder().inboxURL, fileExtension: "ycmenu")
    _ = try inbox.stage(String(decoding: data, as: UTF8.self), slug: envelope.title, now: now())
    return StageMenuResult(staged: envelope.title, recipes: recipeCount, newDishes: newDishCount, next: "Jon reviews it in Yes Chef → From Chat.")
  }

  func stageMenuDay(_ envelope: ChatAccessStagedMenuDay) throws -> StageMenuDayResult {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(envelope)
    let inbox = HandoffInbox(root: try stagingFolder().inboxURL, fileExtension: "ycmenuday")
    _ = try inbox.stage(String(decoding: data, as: UTF8.self), slug: "\(envelope.menuTitle)-day-\(envelope.dayOffset + 1)", now: now())
    return StageMenuDayResult(staged: "\(envelope.menuTitle), day \(envelope.dayOffset + 1)", dishes: envelope.items.count,
      next: "Jon reviews it in Yes Chef → From Chat.")
  }

  func stagePrepPlan(_ envelope: ChatAccessStagedPrepPlan) throws -> StagePrepPlanResult {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(envelope)
    let inbox = HandoffInbox(root: try stagingFolder().inboxURL, fileExtension: "ycprepplan")
    _ = try inbox.stage(String(decoding: data, as: UTF8.self), slug: envelope.menuTitle, now: now())
    return StagePrepPlanResult(staged: "\(envelope.menuTitle) prep plan", dishes: envelope.dishes.count,
      steps: envelope.dishes.reduce(0) { $0 + $1.steps.count }, next: "Jon reviews it in Yes Chef → From Chat.")
  }

  private func stagingFolder() throws -> ChatAccessFolder {
    try ChatAccessHelperFolder.existing(
      containerIdentifier: "iCloud.com.jonphillips.yeschef", isDevelopment: isDevelopment, home: home
    )
  }
}

private enum StageReturnError: LocalizedError {
  case missingToken
  case emptyBody
  case newerContract

  var errorDescription: String? {
    switch self {
    case .missingToken:
      "The first line must be the exact YC-HANDOFF: line from the prompt. A conversation with no token uses stage_recipe."
    case .emptyBody:
      "The hand-off return has no content to stage."
    case .newerContract:
      "This Yes Chef build reads contract v\(AIHandoffReturnContract.version); this return uses a newer contract."
    }
  }
}

public enum YesChefMCPServer {
  public static func make(
    home: URL = FileManager.default.homeDirectoryForCurrentUser,
    isDevelopment: Bool = false,
    now: @escaping @Sendable () -> Date = { Date() },
    exportMaterializer: (@Sendable (URL) async throws -> Data)? = nil,
    materializationDeadline: Duration = .seconds(60)
  ) -> MCPServer {
    let context = StageContext(home: home, now: now, isDevelopment: isDevelopment)
    let containerURL = ChatAccessHelperFolder.containerURL(for: "iCloud.com.jonphillips.yeschef", home: home)
    let recipeSchema: MCPValue = .object([
      "type": .string("object"),
      "additionalProperties": .bool(true),
    ])
    let exportStore = ChatAccessReadTools.makeStore(containerURL: containerURL, isDevelopment: isDevelopment, now: now, materialize: exportMaterializer, materializationDeadline: materializationDeadline)
    return MCPServer(
      name: "yeschef",
      version: "0.1.0",
      instructions: ChatAccessServerInstructions.text,
      tools: [
        MCPTool(
          name: "stage_recipe",
          description: "Stage one schema.org Recipe in Yes Chef for review and saving. Only for a conversation with no `\(AIHandoffToken.prefix)` line; a hand-off conversation finalizes through `stage_handoff_return`. Changes to a recipe already in your library go through `stage_recipe_return`.",
          inputSchema: .object([
            "type": .string("object"),
            "properties": .object(["recipe": recipeSchema]),
            "required": .array([.string("recipe")]),
            "additionalProperties": .bool(false),
          ]),
          annotations: .init(readOnly: false, destructive: false, openWorld: false)
        ) { input in
          guard let data = try? JSONEncoder().encode(input),
            let payload = try? JSONDecoder().decode(StageRecipeInput.self, from: data)
          else {
            return .error("Provide one schema.org Recipe object in `recipe`.")
          }
          do {
            return .json(try context.stage(payload.recipe))
          } catch {
            return .error(error.localizedDescription)
          }
        },
        MCPTool(
          name: "stage_handoff_return",
          description: "Call this instead of printing the return when the cook asks to finalize a conversation that began with a Yes Chef hand-off prompt (one with a `\(AIHandoffToken.prefix)` line), including a riff into a new recipe. `text` is the whole return: line 1 is the exact `\(AIHandoffToken.prefix)` line from the prompt, line 2 is `\(AIHandoffReturnContract.marker)`, then the deliverable the prompt asked for. Jon reviews it in Yes Chef.",
          inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
              "text": .object([
                "type": .string("string"),
                "description": .string("The whole return: the `\(AIHandoffToken.prefix)` line, then `\(AIHandoffReturnContract.marker)`, then the deliverable."),
              ])
            ]),
            "required": .array([.string("text")]),
            "additionalProperties": .bool(false),
          ]),
          annotations: .init(readOnly: false, destructive: false, openWorld: false)
        ) { input in
          guard let data = try? JSONEncoder().encode(input),
            let payload = try? JSONDecoder().decode(StageReturnInput.self, from: data)
          else {
            return .error("Provide the whole hand-off return block in `text`.")
          }
          do {
            return .json(try context.stageReturn(payload.text))
          } catch {
            return .error(error.localizedDescription)
          }
        },
      ] + Self.stagingTools(context: context, exportStore: exportStore) + ChatAccessReadTools.make(store: exportStore)
    )
  }

  private static func stagingTools(context: StageContext, exportStore: ChatAccessExportStore) -> [MCPTool] {
    let string: MCPValue = .object(["type": .string("string")])
    let integer: MCPValue = .object(["type": .string("integer")])
    let itemProperties: [String: MCPValue] = [
      "ref": string, "title": string, "day": integer,
      "slot": .object(["type": .string("string"), "enum": .array(MealPlanItemSlot.allCases.map { .string($0.rawValue) })]),
      "note": string, "scale": .object(["type": .string("number")]),
    ]
    let itemSchema: MCPValue = .object(["type": .string("object"), "properties": .object(itemProperties), "additionalProperties": .bool(false)])
    let menuDayItemProperties = itemProperties.filter { $0.key != "day" }
    let menuDayItemSchema: MCPValue = .object(["type": .string("object"), "properties": .object(menuDayItemProperties), "additionalProperties": .bool(false)])
    return [
      MCPTool(
        name: "stage_recipe_return",
        description: "Use this to send changes to a recipe found with `search_recipes`. Do not use it in a conversation with a `YC-HANDOFF:` line; use `stage_handoff_return`. Do not use it for `YC-NEW-RECIPE:`; a new dish goes through `stage_recipe`. Then add these deliverable lines exactly:\n\(RecipeReturnLabels.deliverableLines)\nOne call per recipe; several calls are fine.",
        inputSchema: .object(["type": .string("object"), "properties": .object(["ref": string, "text": string]), "required": .array([.string("ref"), .string("text")]), "additionalProperties": .bool(false)]),
        annotations: .init(readOnly: false, destructive: false, openWorld: false)
      ) { input in
        let args = input.objectValue ?? [:]
        let ref = args["ref"]?.stringValue
        let text = args["text"]?.stringValue ?? ""
        do {
          let recipe = try await exportStore.resolveRecipe(ref)
          guard !recipe.archived else { return .error("That recipe is archived in Yes Chef.") }
          guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .error("There's nothing to stage.") }
          let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
          guard !lines.contains(where: { $0.hasPrefix("YC-HANDOFF:") }) else { return .error("This conversation has a hand-off token; finalize with `stage_handoff_return`.") }
          guard !lines.contains(where: { $0.hasPrefix("YC-NEW-RECIPE:") }) else { return .error("A new dish goes through `stage_recipe`, not `stage_recipe_return`.") }
          return .json(try context.stageRecipeReturn(recipeID: recipe.id, title: recipe.title, text: text))
        } catch { return .error(error.localizedDescription) }
      },
      MCPTool(
        name: "stage_menu",
        description: "Stage a new menu for Jon to review. An item with a recipe ref from `search_recipes` is a library recipe; one without a ref is a new dish, shown as a note row. `day` is 0-based, as in `get_menu`. To put a new recipe on the menu as a recipe, stage it with `stage_recipe`, wait for Jon to save it, search again, then stage the menu with its ref. This creates a new menu. To change one day of a menu that already exists, use `stage_menu_day`.",
        inputSchema: .object(["type": .string("object"), "properties": .object([
          "title": string, "days": integer, "items": .object(["type": .string("array"), "items": itemSchema]),
        ]), "required": .array([.string("title"), .string("items")]), "additionalProperties": .bool(false)]),
        annotations: .init(readOnly: false, destructive: false, openWorld: false)
      ) { input in
        do { return .json(try await Self.decodeAndStageMenu(input, context: context, exportStore: exportStore)) }
        catch { return .error(error.localizedDescription) }
      },
      MCPTool(
        name: "stage_menu_day",
        description: "Replace one day of a menu found with `list_menus`. Read the menu with `get_menu` first and send every dish for that day, with each note and scale that should stay; anything not sent is removed, including a note or scale that is not carried over. A note is for this dish on this menu only. A change to the recipe itself goes through `stage_recipe_return`. The day must already exist. To stage its prep plan, use `stage_prep_plan`.",
        inputSchema: .object(["type": .string("object"), "properties": .object([
          "menu": string, "day": integer,
          "items": .object(["type": .string("array"), "items": menuDayItemSchema]),
        ]), "required": .array([.string("menu"), .string("day"), .string("items")]), "additionalProperties": .bool(false)]),
        annotations: .init(readOnly: false, destructive: false, openWorld: false)
      ) { input in
        do { return .json(try await Self.decodeAndStageMenuDay(input, context: context, exportStore: exportStore)) }
        catch { return .error(error.localizedDescription) }
      },
      MCPTool(
        name: "stage_prep_plan",
        description: "Replace the whole prep plan for each named dish; anything not sent for a named dish is removed, while unnamed dishes stay untouched. Read the menu with `get_menu` first. Send every separable task for each dish, not cooking instructions woven across recipes. Don't put the schedule in dish notes. A step serving several dishes goes under the dish it mostly serves and its task can name the others. `workDay` carries the day, so `session` is only the time within it (\"Afternoon\", \"About 6:45 PM\"); don't repeat the date. Nothing is saved until Jon reviews it.",
        inputSchema: .object(["type": .string("object"), "properties": .object([
          "menu": string,
          "dishes": .object(["type": .string("array"), "minItems": .integer(1), "maxItems": .integer(20), "items": .object([
            "type": .string("object"), "properties": .object([
              "day": integer, "ref": string, "title": string,
              "steps": .object(["type": .string("array"), "maxItems": .integer(40), "items": .object([
                "type": .string("object"), "properties": .object(["workDay": integer, "session": string, "task": string]),
                "required": .array([.string("session"), .string("task")]), "additionalProperties": .bool(false),
              ])]),
            ]), "required": .array([.string("day"), .string("steps")]), "additionalProperties": .bool(false),
          ])]),
        ]), "required": .array([.string("menu"), .string("dishes")]), "additionalProperties": .bool(false)]),
        annotations: .init(readOnly: false, destructive: false, openWorld: false)
      ) { input in
        do { return .json(try await Self.decodeAndStagePrepPlan(input, context: context, exportStore: exportStore)) }
        catch { return .error(error.localizedDescription) }
      },
    ]
  }

  private static func decodeAndStagePrepPlan(_ input: MCPValue, context: StageContext, exportStore: ChatAccessExportStore) async throws -> StagePrepPlanResult {
    guard let args = input.objectValue, let ref = args["menu"]?.stringValue, let raw = args["dishes"]?.arrayValue else {
      throw StageInputError("Provide a menu ref and 1 to 20 dishes.")
    }
    guard (1...20).contains(raw.count) else { throw StageInputError("dishes must contain 1 to 20 entries.") }
    let menu = try await exportStore.resolveMenu(ref)
    var dishes: [ChatAccessStagedPrepPlan.Dish] = []; var problems: [String] = []; var totalSteps = 0; var selectedRows = Set<Int>()
    for (i, value) in raw.enumerated() {
      let row = value.objectValue ?? [:], label = "dish \(i + 1)"
      guard let day = row["day"]?.integerValue else { problems.append("\(label): day must be a whole number"); continue }
      if !(0..<menu.dayCount).contains(day) { problems.append("\(label): day must be from 0 to \(menu.dayCount - 1)") }
      let ref = row["ref"]?.stringValue, title = row["title"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
      if (ref == nil) == (title == nil) { problems.append("\(label): provide exactly one of ref or title"); continue }
      let matches: [(Int, ChatAccessExport.MenuItemRecord)]
      if let ref {
        do {
          let recipe = try await exportStore.resolveRecipe(ref)
          matches = menu.items.enumerated().filter { $0.element.dayOffset == day && $0.element.kind == .recipe && $0.element.recipeID == recipe.id }
        } catch { problems.append("\(label): \(error.localizedDescription)"); continue }
      } else {
        matches = menu.items.enumerated().filter { $0.element.dayOffset == day && ($0.element.kind == .note || $0.element.kind == .reservation) && $0.element.title.trimmingCharacters(in: .whitespacesAndNewlines).localizedCaseInsensitiveCompare(title ?? "") == .orderedSame }
      }
      guard matches.count == 1 else { problems.append("\(label): dish must identify exactly one row on that day"); continue }
      guard selectedRows.insert(matches[0].0).inserted else { problems.append("\(label): this dish is already named"); continue }
      guard let steps = row["steps"]?.arrayValue, steps.count <= 40 else { problems.append("\(label): steps must contain at most 40 entries"); continue }
      totalSteps += steps.count
      var decoded: [ChatAccessStagedPrepPlan.Dish.Step] = []
      for (j, rawStep) in steps.enumerated() {
        let step = rawStep.objectValue ?? [:], session = step["session"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "", task = step["task"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var workDay: Int? = step["workDay"]?.integerValue
        if step["workDay"] != nil && workDay == nil { problems.append("\(label), step \(j + 1): workDay must be a whole number") }
        if menu.dayCount == 1 {
          if let workDay, workDay != 0 { problems.append("\(label), step \(j + 1): workDay must be absent or 0 on a one-day menu") }
          workDay = nil
        } else if let workDay, !(-7...(menu.dayCount - 1)).contains(workDay) { problems.append("\(label), step \(j + 1): workDay must be from -7 to \(menu.dayCount - 1)") }
        if session.isEmpty { problems.append("\(label), step \(j + 1): session must not be empty") }
        if task.isEmpty || task.count > 500 { problems.append("\(label), step \(j + 1): task must contain 1 to 500 characters") }
        decoded.append(.init(workDayOffset: workDay, session: session, task: task))
      }
      let item = matches[0].1
      dishes.append(.init(dayOffset: day, recipeID: item.recipeID, title: item.title, steps: decoded))
    }
    if totalSteps > 80 { problems.append("There may be at most 80 steps across all dishes.") }
    guard problems.isEmpty else { throw StageInputError("Fix these prep plan items and retry: \(problems.joined(separator: "; "))") }
    let staged = ChatAccessStagedPrepPlan(menuID: menu.id, menuTitle: menu.title, dishes: dishes, planAtStage: menu.prepPlan)
    return try context.stagePrepPlan(staged)
  }

  private static func decodeAndStageMenu(_ input: MCPValue, context: StageContext, exportStore: ChatAccessExportStore) async throws -> StageMenuResult {
    guard let args = input.objectValue, let title = args["title"]?.stringValue,
      let rawItems = args["items"]?.arrayValue else { throw StageInputError("Provide a title and at least one menu item.") }
    let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanTitle.isEmpty else { throw StageInputError("The menu title cannot be empty.") }
    guard (1...40).contains(rawItems.count) else { throw StageInputError("Items must contain 1 to 40 entries.") }
    guard args["days"] == nil || args["days"]?.integerValue != nil else { throw StageInputError("Days must be a whole number from 1 to 14.") }
    let days = args["days"]?.integerValue ?? 1
    guard (1...14).contains(days) else { throw StageInputError("Days must be between 1 and 14.") }
    let resolutions = try await exportStore.resolveRecipes(rawItems.map { $0.objectValue?["ref"]?.stringValue })
    let decoded = decodeMenuItems(rawItems, resolutions: resolutions, dayCount: days)
    guard decoded.problems.isEmpty else { throw StageInputError("Fix these menu items and retry: \(decoded.problems.joined(separator: "; "))") }
    return try context.stageMenu(ChatAccessStagedMenu(title: cleanTitle, dayCount: days, items: decoded.items), recipeCount: decoded.recipes, newDishCount: decoded.newDishes)
  }

  private static func decodeAndStageMenuDay(_ input: MCPValue, context: StageContext, exportStore: ChatAccessExportStore) async throws -> StageMenuDayResult {
    guard let args = input.objectValue, let ref = args["menu"]?.stringValue,
      let rawItems = args["items"]?.arrayValue
    else { throw StageInputError("Provide a menu ref, a whole-number day, and at least one menu item.") }
    guard (1...40).contains(rawItems.count) else { throw StageInputError("Items must contain 1 to 40 entries.") }
    let menu = try await exportStore.resolveMenu(ref)
    guard let day = args["day"]?.integerValue else { throw StageInputError("day must be from 0 to \(menu.dayCount - 1)") }
    guard (0..<menu.dayCount).contains(day) else { throw StageInputError("day must be from 0 to \(menu.dayCount - 1)") }
    let resolutions = try await exportStore.resolveRecipes(rawItems.map { $0.objectValue?["ref"]?.stringValue })
    let decoded = decodeMenuItems(rawItems, resolutions: resolutions, dayCount: menu.dayCount, fixedDay: day)
    guard decoded.problems.isEmpty else { throw StageInputError("Fix these menu items and retry: \(decoded.problems.joined(separator: "; "))") }
    let dayAtStage = menu.items.filter { $0.dayOffset == day }.map {
      ChatAccessStagedMenuDay.LiveItem(kind: $0.kind, title: $0.title, recipeID: $0.recipeID, slot: $0.slot, note: $0.note, scale: $0.scale)
    }
    return try context.stageMenuDay(ChatAccessStagedMenuDay(menuID: menu.id, menuTitle: menu.title, dayOffset: day, items: decoded.items, dayAtStage: dayAtStage))
  }

  private static func decodeMenuItems(
    _ rawItems: [MCPValue],
    resolutions: [ChatAccessExportStore.RecipeResolution],
    dayCount: Int,
    fixedDay: Int? = nil
  ) -> (items: [ChatAccessStagedMenu.Item], recipes: Int, newDishes: Int, problems: [String]) {
    var problems: [String] = []
    var items: [ChatAccessStagedMenu.Item] = []
    var recipes = 0
    var newDishes = 0
    for (index, value) in rawItems.enumerated() {
      let row = value.objectValue ?? [:]
      let day = fixedDay ?? row["day"]?.integerValue ?? 0
      let slotText = row["slot"]?.stringValue ?? MealPlanItemSlot.dinner.rawValue
      let slot = MealPlanItemSlot(rawValue: slotText)
      let note = row["note"]?.stringValue
      let scale = row["scale"]?.doubleValue
      let ref = row["ref"]?.stringValue
      let rowTitle = row["title"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
      if fixedDay == nil && row["day"] != nil && row["day"]?.integerValue == nil { problems.append("item \(index + 1): day must be a whole number") }
      else if !(0..<dayCount).contains(day) { problems.append("item \(index + 1): day must be from 0 to \(dayCount - 1)") }
      if slot == nil { problems.append("item \(index + 1): slot must be breakfast, lunch, dinner, or snack") }
      if let note, note.count > 500 { problems.append("item \(index + 1): note must be at most 500 characters") }
      if let scale, scale <= 0 { problems.append("item \(index + 1): scale must be greater than 0") }
      if scale != nil && ref == nil { problems.append("item \(index + 1): scale applies to a library recipe") }
      if ref == nil && (rowTitle?.isEmpty != false) { problems.append("item \(index + 1): a new dish needs a title") }
      if ref != nil {
        let resolution = resolutions[index]
        if let error = resolution.error {
          problems.append("item \(index + 1): \(error)")
        } else if let recipe = resolution.recipe {
          if recipe.archived { problems.append("item \(index + 1): That recipe is archived in Yes Chef.") }
          else {
            recipes += 1
            items.append(.init(recipeID: recipe.id, title: recipe.title, dayOffset: day, slot: slot ?? .dinner, note: note, scale: scale))
          }
        } else {
          problems.append("item \(index + 1): That reference is from an older export; search again.")
        }
      } else {
        newDishes += 1
        items.append(.init(recipeID: nil, title: rowTitle ?? "", dayOffset: day, slot: slot ?? .dinner, note: note, scale: nil))
      }
    }
    return (items, recipes, newDishes, problems)
  }
}

private struct StageInputError: LocalizedError {
  var errorDescription: String?
  init(_ message: String) { errorDescription = message }
}

private extension MCPValue {
  var integerValue: Int? { if case let .integer(value) = self { value } else { nil } }
  var arrayValue: [MCPValue]? { if case let .array(value) = self { value } else { nil } }
  var doubleValue: Double? {
    switch self { case let .number(value): value; case let .integer(value): Double(value); default: nil }
  }
}

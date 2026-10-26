import Foundation
import MCPServerKit
import YesChefCore

private struct ExportSnapshot: Sendable {
  var value: ChatAccessExport
  var generatedAt: Date
  var ageMinutes: Int
  var device: String
  var generation: Int64
}

private actor ChatAccessExportStore {
  let directory: URL
  let now: @Sendable () -> Date
  let materialize: @Sendable (URL) async throws -> Data
  let materializationDeadline: Duration
  private var cachedKey: String?
  private var cachedSnapshot: ExportSnapshot?

  init(containerURL: URL, now: @escaping @Sendable () -> Date, materialize: @escaping @Sendable (URL) async throws -> Data, materializationDeadline: Duration) {
    self.directory = ChatAccessFolder(containerURL: containerURL).exportsURL
    self.now = now
    self.materialize = materialize
    self.materializationDeadline = materializationDeadline
  }

  func load() async throws -> ExportSnapshot {
    let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
    let candidates = files.compactMap { url -> (URL, Date)? in
      guard url.pathExtension == "json",
        let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
      else { return nil }
      return (url, date)
    }.sorted { $0.1 > $1.1 }
    guard let (url, modified) = candidates.first else {
      throw ReadToolError("No Yes Chef export yet. Open Yes Chef on the iPhone or iPad, or tap Refresh in Settings → Chat Access.")
    }
    let key = "\(url.path)|\(modified.timeIntervalSince1970)"
    if key == cachedKey, let cachedSnapshot {
      var refreshed = cachedSnapshot
      refreshed.ageMinutes = max(0, Int(now().timeIntervalSince(refreshed.generatedAt) / 60))
      self.cachedSnapshot = refreshed
      return refreshed
    }

    let materialize = self.materialize
    let deadline = self.materializationDeadline
    let data = try await readWithDeadline(url, deadline: deadline, materialize: materialize)
    let export = try ChatAccessExportCoding.decode(data)
    let age = max(0, Int(now().timeIntervalSince(export.generatedAt) / 60))
    let snapshot = ExportSnapshot(value: export, generatedAt: export.generatedAt, ageMinutes: age, device: export.device, generation: Int64(modified.timeIntervalSince1970 * 1_000_000))
    cachedKey = key
    cachedSnapshot = snapshot
    return snapshot
  }

  fileprivate static func coordinatedRead(_ url: URL) throws -> Data {
    let clock = ContinuousClock()
    let values = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
    let materializeStart = clock.now
    if let status = values?.ubiquitousItemDownloadingStatus, status != URLUbiquitousItemDownloadingStatus.current {
      try FileManager.default.startDownloadingUbiquitousItem(at: url)
    }
    let materializeRequestDuration = materializeStart.duration(to: clock.now)
    let coordinator = NSFileCoordinator(filePresenter: nil)
    var coordinationError: NSError?
    var data: Data?
    let readStart = clock.now
    var dataReadDuration: Duration = .zero
    coordinator.coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinationError) { readURL in
      let start = clock.now
      data = try? Data(contentsOf: readURL)
      dataReadDuration = start.duration(to: clock.now)
    }
    if let coordinationError { throw coordinationError }
    guard let data else { throw CocoaError(.fileReadUnknown) }
    fputs("yeschef-mcp export materializeRequest=\(materializeRequestDuration) coordinatedRead=\(readStart.duration(to: clock.now)) dataRead=\(dataReadDuration)\n", stderr)
    return data
  }

  private func readWithDeadline(
    _ url: URL,
    deadline: Duration,
    materialize: @escaping @Sendable (URL) async throws -> Data
  ) async throws -> Data {
    try await withCheckedThrowingContinuation { continuation in
      let gate = ReadRaceGate(continuation)
      let work = Task.detached(priority: .utility) {
        do { gate.resolve(.success(try await materialize(url))) }
        catch { gate.resolve(.failure(error)) }
      }
      let timer = Task.detached(priority: .utility) {
        do {
          try await Task.sleep(for: deadline)
          gate.resolve(.failure(ReadToolError("The Yes Chef export is still downloading from iCloud. Try again in a minute.")))
        } catch {}
      }
      gate.setTasks(work: work, timer: timer)
    }
  }
}

private final class ReadRaceGate: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<Data, any Error>?
  private var work: Task<Void, Never>?
  private var timer: Task<Void, Never>?

  init(_ continuation: CheckedContinuation<Data, any Error>) {
    self.continuation = continuation
  }

  func setTasks(work: Task<Void, Never>, timer: Task<Void, Never>) {
    lock.lock()
    if continuation == nil {
      lock.unlock()
      work.cancel()
      timer.cancel()
    } else {
      self.work = work
      self.timer = timer
      lock.unlock()
    }
  }

  func resolve(_ result: Result<Data, any Error>) {
    lock.lock()
    guard let continuation else { lock.unlock(); return }
    self.continuation = nil
    let timer = self.timer
    let work = self.work
    self.timer = nil
    self.work = nil
    lock.unlock()
    timer?.cancel()
    if case .failure = result { work?.cancel() }
    continuation.resume(with: result)
  }
}

private struct ReadToolError: LocalizedError {
  var errorDescription: String?
  init(_ message: String) { errorDescription = message }
}

enum ChatAccessReadTools {
  static func make(
    containerURL: URL,
    now: @escaping @Sendable () -> Date,
    materialize: (@Sendable (URL) async throws -> Data)? = nil,
    materializationDeadline: Duration = .seconds(60)
  ) -> [MCPTool] {
    let reader = materialize ?? { url in try await Task.detached(priority: .utility) { try ChatAccessExportStore.coordinatedRead(url) }.value }
    let store = ChatAccessExportStore(containerURL: containerURL, now: now, materialize: reader, materializationDeadline: materializationDeadline)
    return [
      tool("search_recipes", "Search recipes by name, ingredients, tags, categories, and notes.", schema: objectSchema(["query": stringSchema, "limit": integerSchema], required: ["query"])) { input in
        let args = arguments(input)
        let query = args["query"]?.stringValue ?? ""
        let limit = max(1, min(50, args["limit"]?.intValue ?? 20))
        let snapshot = try await store.load()
        let rows = snapshot.value.recipes.enumerated().filter { _, bundle in
          RecipeSearchMatcher.matches(query: query, in: [bundle.recipe.title, bundle.recipe.subtitle, bundle.recipe.summary].compactMap { $0 } + bundle.ingredients + bundle.tagNames + bundle.categoryNames + bundle.recipeNotes.map(\.text))
        }.sorted { $0.element.recipe.title.localizedCaseInsensitiveCompare($1.element.recipe.title) == .orderedAscending }.prefix(limit).map { index, bundle in
          MCPValue.object(["ref": ref(snapshot, index), "name": .string(bundle.recipe.title), "cuisine": optional(bundle.recipe.cuisine), "course": optional(bundle.recipe.course), "tags": .array(bundle.tagNames.map(MCPValue.string)), "totalTime": optional(bundle.recipe.totalTimeMinutes.map(String.init)), "yield": optional(bundle.recipe.yieldText ?? bundle.recipe.servingsText)])
        }
        return .json(["export": exportMeta(snapshot), "recipes": .array(rows)])
      },
      tool("get_recipe", "Read a recipe from the latest Yes Chef export.", schema: objectSchema(["ref": stringSchema], required: ["ref"])) { input in
        let snapshot = try await store.load()
        let index = try resolveIndex(arguments(input)["ref"]?.stringValue, snapshot: snapshot, count: snapshot.value.recipes.count)
        let bundle = snapshot.value.recipes[index]
        return .json(["export": exportMeta(snapshot), "recipe": .object([
          "name": .string(bundle.recipe.title), "description": optional(bundle.recipe.summary), "yield": optional(bundle.recipe.yieldText ?? bundle.recipe.servingsText),
          "prepTime": optional(bundle.recipe.prepTimeMinutes.map(String.init)), "cookTime": optional(bundle.recipe.cookTimeMinutes.map(String.init)), "totalTime": optional(bundle.recipe.totalTimeMinutes.map(String.init)),
          "ingredientSections": .array(bundle.ingredientSections.sorted { $0.sortOrder < $1.sortOrder }.map { section in .object(["name": optional(section.name), "ingredients": .array(bundle.ingredientLines.filter { $0.sectionID == section.id }.sorted { $0.sortOrder < $1.sortOrder }.map { .string($0.originalText) })]) }),
          "instructionSections": .array(bundle.instructionSections.sorted { $0.sortOrder < $1.sortOrder }.map { section in .object(["name": optional(section.name), "steps": .array(bundle.instructionSteps.filter { $0.sectionID == section.id }.sorted { $0.sortOrder < $1.sortOrder }.map { .string($0.text) })]) }),
          "notes": .array(bundle.recipeNotes.sorted { $0.dateCreated < $1.dateCreated }.map { .string($0.text) }), "tags": .array(bundle.tagNames.map(MCPValue.string)), "categories": .array(bundle.categoryNames.map(MCPValue.string)), "sourceURL": optional(bundle.source?.url)
        ])])
      },
      tool("list_menus", "List menus from the latest Yes Chef export.", schema: objectSchema(["limit": integerSchema], required: [])) { input in
        let snapshot = try await store.load()
        let limit = max(1, min(50, arguments(input)["limit"]?.intValue ?? 20))
        let rows = snapshot.value.menus.enumerated().sorted { $0.element.title.localizedCaseInsensitiveCompare($1.element.title) == .orderedAscending }.prefix(limit).map { index, menu in
          MCPValue.object(["ref": ref(snapshot, index), "title": .string(menu.title), "dayCount": .integer(menu.dayCount), "itemCount": .integer(menu.items.count), "modified": .string(iso(menu.modified))])
        }
        return .json(["export": exportMeta(snapshot), "menus": .array(rows)])
      },
      tool("get_menu", "Read a menu from the latest Yes Chef export.", schema: objectSchema(["ref": stringSchema], required: ["ref"])) { input in
        let snapshot = try await store.load()
        let index = try resolveIndex(arguments(input)["ref"]?.stringValue, snapshot: snapshot, count: snapshot.value.menus.count)
        let menu = snapshot.value.menus[index]
        let recipes = Dictionary(uniqueKeysWithValues: snapshot.value.recipes.map { ($0.recipe.id, $0.recipe.title) })
        let items = menu.items.map { item in MCPValue.object(["kind": .string(item.kind.rawValue), "title": .string(item.title), "recipe": optional(item.recipeID.flatMap { recipes[$0] }), "day": .integer(item.dayOffset), "slot": .string(item.slot.rawValue), "note": optional(item.note), "scale": .number(item.scale)]) }
        return .json(["export": exportMeta(snapshot), "menu": .object(["title": .string(menu.title), "notes": optional(menu.notes), "items": .array(items)])])
      },
      tool("get_meal_plan", "Read scheduled items in a date window of up to 31 days.", schema: objectSchema(["from": stringSchema, "to": stringSchema], required: ["from", "to"])) { input in
        let snapshot = try await store.load()
        let args = arguments(input)
        guard let from = parseDate(args["from"]?.stringValue), let to = parseDate(args["to"]?.stringValue), to >= from,
          to.timeIntervalSince(from) <= 31 * 86_400,
          from >= (Calendar.current.date(byAdding: .day, value: -30, to: snapshot.generatedAt) ?? snapshot.generatedAt),
          to <= (Calendar.current.date(byAdding: .day, value: 60, to: snapshot.generatedAt) ?? snapshot.generatedAt)
        else { throw ReadToolError("Choose a valid date window of at most 31 days within the export's 90-day window.") }
        let rows = snapshot.value.mealPlan.filter { $0.scheduledDate >= from && $0.scheduledDate <= to }.map { item in
          MCPValue.object(["kind": .string(item.kind.rawValue), "title": .string(item.title), "date": .string(iso(item.scheduledDate)), "slot": .string(item.slot.rawValue), "note": optional(item.note), "scale": .number(item.scale)])
        }
        return .json(["export": exportMeta(snapshot), "items": .array(rows)])
      },
    ]
  }

  private static let stringSchema: MCPValue = .object(["type": .string("string")])
  private static let integerSchema: MCPValue = .object(["type": .string("integer")])
  private static func objectSchema(_ properties: [String: MCPValue], required: [String]) -> MCPValue {
    .object(["type": .string("object"), "properties": .object(properties), "required": .array(required.map(MCPValue.string)), "additionalProperties": .bool(false)])
  }
  private static func tool(_ name: String, _ description: String, schema: MCPValue, handler: @escaping @Sendable (MCPValue) async throws -> MCPToolResult) -> MCPTool {
    MCPTool(name: name, description: description, inputSchema: schema, annotations: .init(readOnly: true, openWorld: false), handler: handler)
  }
  private static func arguments(_ input: MCPValue) -> [String: MCPValue] { input.objectValue ?? [:] }
  private static func ref(_ snapshot: ExportSnapshot, _ index: Int) -> MCPValue { .string("\(snapshot.generation).\(index)") }
  private static func resolveIndex(_ ref: String?, snapshot: ExportSnapshot, count: Int) throws -> Int {
    guard let ref else { throw ReadToolError("That reference is from an older export; search again.") }
    let pieces = ref.split(separator: ".")
    guard pieces.count == 2, let generation = Int64(pieces[0]), let index = Int(pieces[1]), generation == snapshot.generation, index >= 0, index < count else {
      throw ReadToolError("That reference is from an older export; search again.")
    }
    return index
  }
  private static func exportMeta(_ snapshot: ExportSnapshot) -> MCPValue {
    .object(["generatedAt": .string(iso(snapshot.generatedAt)), "ageMinutes": .integer(snapshot.ageMinutes), "device": .string(snapshot.device)])
  }
  private static func optional(_ value: String?) -> MCPValue { value.map(MCPValue.string) ?? .null }
  private static func iso(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
  private static func parseDate(_ value: String?) -> Date? {
    guard let value else { return nil }
    if let date = ISO8601DateFormatter().date(from: value) { return date }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withFullDate]
    return formatter.date(from: value)
  }
}

private extension MCPValue {
  var intValue: Int? {
    guard case let .integer(value) = self else { return nil }
    return value
  }
}

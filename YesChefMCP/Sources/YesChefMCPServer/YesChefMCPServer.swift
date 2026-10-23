import Foundation
import LLMHandoffKit
import MCPServerKit
import YesChefCore

private struct StageRecipeInput: Decodable, Sendable {
  var recipe: MCPValue
}

private struct StageRecipeResult: Encodable, Sendable {
  var staged: String
  var next: String
}

private struct StageRecipeContext: Sendable {
  let containerURL: URL
  let now: @Sendable () -> Date

  func stage(_ recipe: MCPValue) throws -> StageRecipeResult {
    let data = try JSONEncoder().encode(recipe)
    let text = String(decoding: data, as: UTF8.self)
    let extraction = try RecipeContractStaging.validate(text)
    try requireContainer()

    let folder = ChatAccessFolder(containerURL: containerURL)
    try FileManager.default.createDirectory(at: folder.inboxURL, withIntermediateDirectories: true)
    let name = extraction.title?.trimmingCharacters(in: .whitespacesAndNewlines)
    let recipeName = name.flatMap { $0.isEmpty ? nil : $0 } ?? "Recipe"
    let inbox = HandoffInbox(root: folder.inboxURL, fileExtension: "json")
    _ = try inbox.stage(text, slug: recipeName, now: now())
    return StageRecipeResult(
      staged: recipeName,
      next: "Jon reviews and saves it in Yes Chef → Create Recipe."
    )
  }

  private func requireContainer() throws {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: containerURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
      throw StageContainerUnavailable(path: containerURL.path)
    }
  }
}

private struct StageContainerUnavailable: LocalizedError {
  let path: String
  var errorDescription: String? { "The Yes Chef iCloud container is not present at \(path). The helper will not create it." }
}

public enum YesChefMCPServer {
  public static func make(
    containerURL: URL = FileManager.default.homeDirectoryForCurrentUser
      .appending(path: "Library/Mobile Documents/iCloud~com~jonphillips~yeschef", directoryHint: .isDirectory),
    now: @escaping @Sendable () -> Date = { Date() }
  ) -> MCPServer {
    let context = StageRecipeContext(containerURL: containerURL, now: now)
    let recipeSchema: MCPValue = .object([
      "type": .string("object"),
      "additionalProperties": .bool(true),
    ])
    return MCPServer(
      name: "yeschef",
      version: "0.1.0",
      instructions: ChatAccessServerInstructions.text,
      tools: [
        MCPTool(
          name: "stage_recipe",
          description: "Stage one schema.org Recipe in Yes Chef for review and saving.",
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
      ]
    )
  }
}

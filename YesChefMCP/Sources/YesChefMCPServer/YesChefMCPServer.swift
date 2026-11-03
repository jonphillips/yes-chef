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

private struct StageContext: Sendable {
  let containerURL: URL
  let now: @Sendable () -> Date

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

  private func stagingFolder() throws -> ChatAccessFolder {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: containerURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
      throw StageContainerUnavailable(path: containerURL.path)
    }
    return ChatAccessFolder(containerURL: containerURL)
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

private struct StageContainerUnavailable: LocalizedError {
  let path: String
  var errorDescription: String? { "The Yes Chef iCloud container is not present at \(path). The helper will not create it." }
}

public enum YesChefMCPServer {
  public static func make(
    containerURL: URL = FileManager.default.homeDirectoryForCurrentUser
      .appending(path: "Library/Mobile Documents/iCloud~com~jonphillips~yeschef", directoryHint: .isDirectory),
    now: @escaping @Sendable () -> Date = { Date() },
    exportMaterializer: (@Sendable (URL) async throws -> Data)? = nil,
    materializationDeadline: Duration = .seconds(60)
  ) -> MCPServer {
    let context = StageContext(containerURL: containerURL, now: now)
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
          description: "Stage one schema.org Recipe in Yes Chef for review and saving. Only for a conversation with no `\(AIHandoffToken.prefix)` line; a hand-off conversation finalizes through `stage_handoff_return`.",
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
      ] + ChatAccessReadTools.make(containerURL: containerURL, now: now, materialize: exportMaterializer, materializationDeadline: materializationDeadline)
    )
  }
}

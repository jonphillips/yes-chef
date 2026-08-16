import LLMHandoffKit

/// The single, pasteable return contract for the external Yes Chef project. It deliberately lives outside
/// each hand-off payload: the payload carries only a title, routing token, context, and the verb's ask.
public enum AIHandoffReturnContract {
  public static let version = "3"
  private static let contractMarker = HandoffContractMarker(prefix: "YC-CONTRACT", version: "v\(version)")
  public static let marker = contractMarker.marker

  public static let projectInstructions = """
    Yes Chef hand-off return contract — v\(version). (If Yes Chef reports these instructions are out of date, re-copy them from AI Settings.)

    You are helping with Yes Chef hand-offs. You may discuss the supplied cooking context freely.

    The opening `<Task>: <Object>` line is the suggested conversation title. Use it if the host supports setting a title, but it is advisory only.

    When the user asks to finalize, or a hand-off asks for an immediate result, stop conversing and return the requested deliverable as a terminal response. Its first line must be the exact `YC-HANDOFF:` token from the prompt. Its second line must be `\(marker)`. Then return the requested deliverable. Include a `YC-LEARNINGS:` section with distinct durable learnings unless the hand-off expressly asks you to omit it.

    For an Experiments hand-off, return each experiment as exactly three lines, in this order: `Hypothesis: <one sentence>`, `Change: <one sentence>`, and `Rationale: <one sentence>`. Repeat that labeled cycle for each distinct experiment. Do not include `YC-LEARNINGS:` for Experiments; an experiment is untested until its outcome is recorded. Some other hand-offs may also expressly suppress learnings when they return untested suggestions or curated source evidence; follow that task-specific instruction.

    Whenever a hand-off asks for strict JSON, use straight ASCII double-quote characters (`"`) for every JSON key and string delimiter. Never substitute typographic/smart quotes (`“` or `”`).

    Return no preamble, sign-off, headings, or nesting. Do not assess what is already good. Keep distinct requested items distinct rather than merging them into a summary. If a requested field cannot be filled confidently, omit that item rather than inventing it. Do not use a Markdown code fence.
    """

  public struct Result: Equatable, Sendable {
    public let text: String
    public let warning: String?

    public init(text: String, warning: String?) {
      self.text = text
      self.warning = warning
    }
  }

  /// Removes the echoed version marker before the existing hand-off router sees the return payload.
  /// Missing or older markers remain importable, with the package warning carried to the review
  /// surface. A newer marker still fails because this build cannot safely decode its contract.
  public static func strippingMarker(from text: String) throws -> Result {
    do {
      let result = try contractMarker.strippingMarker(from: text)
      return Result(text: result.text, warning: result.warning)
    } catch is HandoffContractError {
      throw AIHandoffReturnContractError.instructionsOutOfDate
    }
  }
}

import Foundation

/// The single home of the ingredient section-heading heuristic, shared by web capture
/// and Paprika import (the M2/M1 constants register pins this rule once). A line that
/// carries **no parsed quantity** and is either colon-terminated (`For the sauce:`) or
/// all-caps (`SAUCE`) is a section heading, not an ingredient. Anything ambiguous stays
/// a plain ingredient line — preserve over interpret.
enum IngredientSectionHeading {
  static func isHeading(_ line: String) -> Bool {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, IngredientParser.parse(trimmed).quantity == nil else { return false }
    if trimmed.hasSuffix(":") { return true }
    let letters = trimmed.filter(\.isLetter)
    guard !letters.isEmpty else { return false }
    return String(letters).uppercased() == String(letters)
  }

  static func name(_ line: String) -> String {
    line.trimmingCharacters(in: CharacterSet(charactersIn: ":").union(.whitespacesAndNewlines))
  }
}

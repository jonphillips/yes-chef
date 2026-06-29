import Foundation

/// The single home of the ingredient section-heading heuristic, shared by web capture
/// and Paprika import (the M2/M1 constants register pins this rule once). A line that
/// carries **no parsed quantity** and is either colon-terminated (`For the sauce:`) or
/// all-caps (`SAUCE`) is a section heading, not an ingredient. Anything ambiguous stays
/// a plain ingredient line — preserve over interpret.
enum IngredientSectionHeading {
  /// A grouped run of ingredient lines, optionally introduced by a heading.
  struct Section: Equatable {
    var name: String?
    var lines: [String]
  }

  static func isHeading(_ line: String) -> Bool {
    isHeading(line, allowAllCaps: true)
  }

  static func name(_ line: String) -> String {
    line.trimmingCharacters(in: CharacterSet(charactersIn: ":").union(.whitespacesAndNewlines))
  }

  /// Group ingredient `lines` into sections by promoting heading lines.
  ///
  /// Lines before the first heading form a leading unnamed section. A heading with no
  /// following lines is dropped (an empty section is never emitted). When **every** line
  /// is all-caps the casing carries no signal — a fully-uppercased recipe (real Paprika
  /// exports exist) would otherwise promote ordinary ingredients like
  /// `KOSHER SALT AND GROUND BLACK PEPPER` — so the all-caps branch is suppressed and
  /// only colon-terminated headings count. Preserve over interpret.
  static func sections(in lines: [String]) -> [Section] {
    let allowAllCaps = lines.contains { line in line.contains(where: \.isLowercase) }

    var sections: [Section] = []
    var currentName: String?
    var currentLines: [String] = []

    func flush() {
      guard !currentLines.isEmpty else { return }
      sections.append(Section(name: currentName, lines: currentLines))
      currentLines = []
    }

    for line in lines {
      if isHeading(line, allowAllCaps: allowAllCaps) {
        flush()
        currentName = name(line)
      } else {
        currentLines.append(line)
      }
    }
    flush()

    if sections.isEmpty, !lines.isEmpty {
      return [Section(lines: lines)]
    }
    return sections
  }

  private static func isHeading(_ line: String, allowAllCaps: Bool) -> Bool {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, IngredientParser.parse(trimmed).quantity == nil else { return false }
    if trimmed.hasSuffix(":") { return true }
    guard allowAllCaps else { return false }
    let letters = trimmed.filter(\.isLetter)
    guard !letters.isEmpty else { return false }
    return String(letters).uppercased() == String(letters)
  }
}

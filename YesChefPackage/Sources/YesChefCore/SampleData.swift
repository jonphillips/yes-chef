import Dependencies
import Foundation
import SQLiteData

extension DependencyValues {
  public func seedSampleDataIfNeeded() throws {
    try defaultDatabase.write { db in
      guard try Recipe.fetchCount(db) == 0 else { return }

      let now = Date(timeIntervalSinceReferenceDate: 802_000_000)
      var uuids = SampleUUIDSequence(start: 100)

      for draft in SampleRecipes.all {
        try RecipeRepository.save(
          draft: draft,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
      }
    }
  }
}

public enum SampleRecipes {
  public static let all: [RecipeEditorDraft] = [
    RecipeEditorDraft(
      id: SampleUUIDSequence.uuid(1),
      title: "Korean Bavette",
      subtitle: "Galbi-style marinade, grilled and sliced",
      summary: "A make-ahead-friendly steak for dinner parties or beach week.",
      sourceName: "Personal adaptation",
      servingsText: "Serves 6",
      prepTimeMinutes: 25,
      cookTimeMinutes: 12,
      cuisine: "Korean",
      course: "Main",
      favorite: true,
      ingredientText: """
      2 pounds bavette steak
      1/2 cup soy sauce
      1/4 cup brown sugar
      2 tablespoons sesame oil
      4 cloves garlic, grated
      1 tablespoon grated ginger
      2 scallions, thinly sliced
      """,
      instructionText: """
      Whisk soy sauce, brown sugar, sesame oil, garlic, ginger, and scallions.
      Add steak and marinate at least 4 hours, preferably overnight.
      Grill over high heat until deeply browned and medium-rare.
      Rest 10 minutes, then slice thinly across the grain.
      """,
      noteText: "Good beach-house main. Freeze marinade separately and combine with steak while thawing.",
      tagNames: "grill, make-ahead, beach",
      categoryNames: "Beef, Mains"
    ),
    RecipeEditorDraft(
      id: SampleUUIDSequence.uuid(2),
      title: "Lime-Cumin Slaw",
      subtitle: "Bright cabbage slaw for tacos or grilled meat",
      summary: "Crunchy, acidic side that can mostly be prepped ahead.",
      sourceName: "Personal",
      servingsText: "Serves 8",
      prepTimeMinutes: 20,
      cuisine: "Mexican",
      course: "Side",
      ingredientText: """
      1 head green cabbage, thinly sliced
      1/2 red onion, thinly sliced
      1/2 cup cilantro leaves
      1/4 cup lime juice
      2 teaspoons ground cumin
      1/3 cup olive oil
      Kosher salt, to taste
      """,
      instructionText: """
      Whisk lime juice, cumin, olive oil, and salt.
      Toss cabbage and onion with dressing shortly before serving.
      Fold in cilantro at the end.
      """,
      noteText: "Dressing can be made ahead. Do not dress cabbage before travel.",
      tagNames: "make-ahead, beach, side",
      categoryNames: "Sides, Salads"
    ),
    RecipeEditorDraft(
      id: SampleUUIDSequence.uuid(3),
      title: "Creole Chicken Tray Bake",
      subtitle: "Chicken thighs with trinity and smoky spices",
      summary: "A low-fuss oven dinner with enough flavor for company.",
      sourceName: "Personal adaptation",
      servingsText: "Serves 4",
      prepTimeMinutes: 30,
      cookTimeMinutes: 45,
      cuisine: "Creole",
      course: "Main",
      ingredientText: """
      2 pounds bone-in chicken thighs
      1 onion, sliced
      1 bell pepper, sliced
      2 celery ribs, sliced
      2 tablespoons Creole seasoning
      1 tablespoon olive oil
      """,
      instructionText: """
      Heat oven to 425°F.
      Toss vegetables with oil and spread on a sheet pan.
      Season chicken generously and nestle over vegetables.
      Roast until chicken is browned and cooked through.
      """,
      noteText: "Works well for family cooking. Watch oven conflicts for dinner-party menus.",
      tagNames: "oven, weeknight",
      categoryNames: "Chicken, Mains"
    ),
    RecipeEditorDraft(
      id: SampleUUIDSequence.uuid(4),
      title: "Best Fresh Margaritas",
      summary: "A tart, clean margarita template for batching.",
      sourceName: "Personal",
      servingsText: "Makes 4 drinks",
      prepTimeMinutes: 10,
      course: "Cocktail",
      favorite: true,
      ingredientText: """
      8 ounces blanco tequila
      4 ounces lime juice
      3 ounces Cointreau
      1 ounce agave syrup
      Kosher salt, for rims
      """,
      instructionText: """
      Combine tequila, lime juice, Cointreau, and agave syrup.
      Shake individual drinks with ice or batch and chill.
      Salt rims if desired.
      """,
      noteText: "Batch no more than 24 hours ahead for best lime flavor.",
      tagNames: "cocktail, dinner-party",
      categoryNames: "Cocktails"
    ),
    RecipeEditorDraft(
      id: SampleUUIDSequence.uuid(5),
      title: "Roasted Cabbage with Anchovy Butter",
      subtitle: "Deeply browned wedges with a savory finish",
      summary: "A strong side dish, but check guest tolerance for anchovy-forward flavors.",
      sourceName: "Adapted from restaurant notes",
      servingsText: "Serves 4",
      prepTimeMinutes: 10,
      cookTimeMinutes: 35,
      course: "Side",
      ingredientText: """
      1 head cabbage, cut into wedges
      3 tablespoons butter
      4 anchovy fillets, minced
      1 tablespoon lemon juice
      Black pepper
      """,
      instructionText: """
      Roast cabbage wedges at 450°F until charred at the edges.
      Melt butter with anchovies until dissolved.
      Spoon anchovy butter over hot cabbage and finish with lemon.
      """,
      noteText: "Great for me, less safe for guests who dislike anchovy-forward dishes.",
      tagNames: "oven, company, warning",
      categoryNames: "Vegetables, Sides"
    ),
  ]
}

public struct SampleUUIDSequence: Sendable {
  private var value: Int

  public init(start: Int) {
    self.value = start
  }

  public mutating func next() -> UUID {
    defer { value += 1 }
    return Self.uuid(value)
  }

  public static func uuid(_ value: Int) -> UUID {
    UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012d", value))")!
  }
}


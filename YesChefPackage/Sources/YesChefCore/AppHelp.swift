import Foundation

public struct AppHelpPage: Equatable, Sendable {
  public struct Section: Equatable, Sendable {
    public var heading: String
    public var bullets: [String]

    public init(heading: String, bullets: [String]) {
      self.heading = heading
      self.bullets = bullets
    }
  }

  public var title: String
  public var sections: [Section]

  public init(title: String, sections: [Section]) {
    self.title = title
    self.sections = sections
  }

  public var plainText: String {
    ([title] + sections.flatMap { section in
      [section.heading] + section.bullets.map { "- \($0)" }
    }).joined(separator: "\n")
  }

  public func appending(to prompt: String) -> String {
    prompt + "\n\nHow this screen works. Answer questions about using the app from this. If it doesn't cover something, say so instead of guessing.\n\n\(plainText)"
  }

  public static let menus = AppHelpPage(
    title: "How Menus Work",
    sections: [
      Section(heading: "A menu", bullets: [
        "A menu plans an event: one dinner or a whole week. Dishes sit on Day 1, Day 2 and so on, not on dates.",
        "Tap **+** on a day to add a dish. Long-press a dish to edit it, move it to another day, or make a note into a recipe."
      ]),
      Section(heading: "Dates", bullets: [
        "To give a menu real dates, tap **Edit** (the pencil), then **Place on Calendar…**. Its dishes then show on the Calendar.",
        "A menu can be placed more than once, such as the same dinner party twice."
      ]),
      Section(heading: "Combining menus", bullets: [
        "**⋯ › Add Menu…** copies another menu's dishes and prep steps into this one, starting on the day you pick. The other menu doesn't change.",
        "**Edit › Bring In Calendar Items…** moves what's already on the calendar during this menu's dates into it, including any menu placed wholly inside them. It shows only when this menu is on the calendar once and there's something to bring in."
      ]),
      Section(heading: "Prep plan", bullets: [
        "The **Prep Plan** column lists work to do ahead. Build it from the **AI** menu: **Ask now** to work with the in-app chat, or **Hand off** to ChatGPT and **Paste** the reply. Tap a step to edit it.",
        "On a menu longer than one day, steps are grouped by the day you do the work."
      ]),
      Section(heading: "Cooking", bullets: [
        "**Cook these** opens the menu's recipes together for cooking."
      ])
    ]
  )

  public static let groceries = AppHelpPage(
    title: "How Groceries Work",
    sections: [
      Section(heading: "Adding ingredients", bullets: [
        "**Add Ingredients** adds a calendar day or a menu to this list. You pick which lines to add first.",
        "Lines matching a pantry item set to **Always have it** start unchecked under **Skipped Pantry Staples**. Check one to buy it anyway.",
        "Turn on **Split into two trips** to send each line to an **Advance** list or a **Fresh** list. Tap a line's **Advance** or **Fresh** tag to switch it. The app remembers your switch next time."
      ]),
      Section(heading: "Merging", bullets: [
        "The same ingredient from different recipes becomes one item with the amounts added up, when the units can be added (cups with cups, grams with grams). Otherwise it stays a separate item.",
        "Long-press an item to see where it came from, or remove one recipe's share."
      ]),
      Section(heading: "Pantry", bullets: [
        "Pantry items say what you usually have. Set each one in **Pantry**: **Always have it** hides it from the list, **Remind me** hides small amounts and shows big ones under **You may need more**, **Always confirm** always shows it.",
        "Hidden items sit under **Assumed in pantry**. **Add Back** puts one on the list for now.",
        "Swipe an item right and tap **Add to Pantry** to stop buying it."
      ]),
      Section(heading: "Store areas", bullets: [
        "Items are grouped by store area. Change one with **Edit Item › Aisle**. The app remembers your change for that ingredient from then on."
      ])
    ]
  )
}

public extension RecipeChatContext {
  var helpPage: AppHelpPage? {
    switch self {
    case .menu: .menus
    case .mealPlan, .recipe, .workbench: nil
    }
  }
}

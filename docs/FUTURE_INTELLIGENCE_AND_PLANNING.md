# Future Intelligence and Planning

## 1. Purpose

This document captures the long-term product vision for meal planning, event planning, cooking logistics, and AI-assisted consultation.

These features are not part of MVP 1.

They are documented now because the MVP data model should not accidentally foreclose them. The app should begin as a reliable recipe library, but its long-term value is as a personal cooking-planning system that understands the user’s recipes, adaptations, preferences, pantry, equipment, shopping patterns, and event context.

The app should eventually help answer practical questions such as:

- What should I cook this week?
- What can I make ahead?
- What can I freeze?
- What should I buy locally?
- What needs to thaw?
- What equipment will be overbooked?
- What can be prepped two days ahead?
- What is too repetitive across this menu?
- What dishes fit this group of guests?
- What substitutions make sense given my preferences?
- What did I change last time?
- What is the realistic day-by-day plan?

The goal is not generic AI recipe generation. The goal is personal cooking consultation grounded in the user’s own data.

## 2. Product Thesis

Paprika-style recipe management is the foundation. The differentiated product is a planning and consultation layer.

The app should eventually function like a private culinary chief of staff:

- It knows the user’s recipe library.
- It knows what the user has cooked before.
- It knows what worked and what failed.
- It knows personal preferences.
- It knows household constraints.
- It knows equipment.
- It knows whether recipes are freezer-friendly, travel-friendly, grill-friendly, beach-house-friendly, or dinner-party-worthy.
- It can help convert a vague plan into a realistic cooking schedule.

This is the reason to build the app rather than simply keep using Paprika.

## 3. Planning Philosophy

Meal planning should not be treated as merely assigning recipes to dates.

Serious cooking plans include:

- Menu design
- Guest count
- Appetite/portion assumptions
- Dietary constraints
- Personal dislikes
- Shopping locations
- Ingredient availability
- Make-ahead strategy
- Freezing/thawing strategy
- Transport constraints
- Equipment conflicts
- Day-before prep
- Day-of cooking
- Serving timing
- Leftovers
- Risk management

The app should support lightweight weekly planning and more serious event planning.

## 4. Planning Modes

### 4.1 Weekly Meal Planning

A simple calendar-based planning mode.

Use cases:

- Plan dinners for the week.
- Generate a shopping list.
- Avoid repeating proteins or cuisines.
- Use recipes already in the library.
- Add non-recipe meals.
- Add leftover nights.
- Add restaurant nights.
- Adjust servings.

Example:

```text
Monday: Cumin tofu with vegetables
Tuesday: Chicken sausage stew
Wednesday: Leftovers
Thursday: Pork tinga tostadas
Friday: Grilled fish with slaw
```

### 4.2 Event Planning

A structured plan for a single meal or gathering.

Use cases:

- Dinner party
- Holiday meal
- Birthday dinner
- Cocktail party
- Family gathering

Event planning should include:

- Date
- Meal time
- Guest count
- Guest notes
- Menu
- Shopping list
- Prep schedule
- Day-of timeline
- Equipment schedule
- Serving notes
- Wine/cocktail notes
- Retrospective notes

Example:

```text
Saturday Dinner Party
Guests: 8
Menu:
- Cocktail
- Appetizer
- Main
- Side 1
- Side 2
- Dessert
```

### 4.3 Multi-Day Cooking Plan

A structured plan for a trip, vacation, or multi-day hosting situation.

Use cases:

- Beach week
- Family visit
- Mountain house weekend
- Holiday week
- Cooking for guests arriving midweek

Multi-day plans should support:

- Arrival day meals
- Guest arrival/departure changes
- Shopping before travel
- Shopping locally
- Cooler/freezer constraints
- Frozen components
- Make-ahead sauces
- Thawing schedule
- Transport notes
- Leftover management

Example:

```text
Beach Week
Sunday: Arrival dinner
Monday: Fish night
Tuesday: Korean bavette
Wednesday: Guests arrive, pork tinga tostadas
Thursday: Creole chicken tray bake
Friday: NY strip or local seafood
Saturday: Cleanup / leftovers
```

### 4.4 Component Planning

A mode for preparing components rather than complete meals.

Examples:

- Make aioli
- Make slaw dressing
- Freeze marinade
- Chop holy trinity
- Toast spices
- Make cocktail syrup
- Make pie crust
- Cook beans
- Make stock

This matters because serious cooking often depends on components prepared days ahead.

## 5. CookingPlan Entity Vision

A `CookingPlan` should represent a real cooking project.

Possible fields:

```text
id
title
planType
startDate
endDate
primaryMealDate
location
guestCount
guestNotes
recipes
mealPlanEntries
shoppingLists
tasks
equipmentSchedule
servingTimeline
notes
retrospective
dateCreated
dateModified
```

Possible plan types:

```text
weekly
event
trip
holiday
project
other
```

## 6. Cooking Plan Tasks

The app should eventually generate and manage tasks.

Task types:

```text
shop
prep
cook
cool
freeze
thaw
marinate
pack
transport
reheat
serve
clean
other
```

Examples:

```text
Move bavette from freezer to fridge 24 hours ahead.
Make aioli two days ahead.
Chop holy trinity and freeze flat.
Buy fish locally the morning of cooking.
Salt cabbage 2 hours before serving.
Make margarita base no more than 24 hours ahead.
Pack vacuum-sealed marinade in cooler.
Toast sesame seeds day-of.
Pull steak from fridge 45 minutes before grilling.
```

Tasks should support:

- Due date
- Due time
- Duration
- Recipe association
- Ingredient association
- Equipment association
- Location
- Completion state
- Notes
- Confidence

## 7. AI Consultation Layer

AI should act as a consultation layer over the user’s own data.

The AI should not be the data store. It should not silently rewrite the user’s recipes. It should propose, explain, and preserve.

### 7.1 Core Principle

AI suggestions must be grounded in:

- The user’s saved recipes
- The user’s notes
- The user’s cooking history
- The user’s explicit preferences
- The user’s pantry data, if available
- The user’s planned meals
- The user’s equipment
- The user’s imported source text

AI should be able to say:

```text
I do not know.
This is uncertain.
This requires user confirmation.
This is inferred from prior notes.
```

### 7.2 Good AI Uses

Good AI features include:

- Clean up imported recipes.
- Parse ingredient lines.
- Identify ingredient sections.
- Split long instruction paragraphs into steps.
- Extract timers.
- Extract oven temperatures.
- Extract make-ahead opportunities.
- Generate a reviewable make-ahead strategy for a saved recipe and persist the accepted
  version with that recipe, likely as its own make-ahead section rather than a generic
  note.
- For supported source sites, recover selected high-signal recipe comments and either
  let the user mark keepers in real time or synthesize useful adjustments into a
  reviewable proposal.
- Extract freezing/thawing implications.
- Suggest grocery categories.
- Merge shopping-list items.
- Generate prep timeline.
- Generate day-of cooking timeline.
- Identify equipment conflicts.
- Suggest substitutions.
- Compare candidate menus.
- Flag repetition across a meal plan.
- Suggest dishes from the existing library.
- Convert a group of recipes into a shopping plan.
- Convert a group of recipes into a prep plan.
- Summarize lessons from prior cooking notes.

### 7.3 Bad AI Uses

Avoid these as primary features:

- Generic recipe generation.
- Fake precision about nutrition.
- Silent rewriting of recipes.
- Unreviewed destructive cleanup.
- Confident substitutions without context.
- Invented pantry inventory.
- Invented personal preferences.
- Over-optimizing recipes into blandness.
- Turning the app into a chatbot with a recipe database bolted on.

### 7.4 Where AI runs (the no-server constraint)

The app has no server and no auth (see `docs/decisions/ADR-0002`). That rules out a
backend to hold model API keys or proxy requests, which forces an explicit split:

- **On-device models (preferred) for structure work.** Use Apple's on-device
  Foundation Models (available on the iOS 26 deployment target) for the §7.2 extraction
  tasks — cleanup, ingredient parsing, section detection, step splitting, timer/temp
  extraction. These are private, free, key-less, and need no network. This is the
  concrete form of §17's "prefer local processing."
- **Cloud model (Claude) for judgment.** Heavier consultation — menu design,
  substitutions, multi-day planning — can call a frontier model directly from the
  client (no server in between). With no backend, the key is a personal credential on
  the device; acceptable for a private family app, but it is a real decision, not a
  default. Default to the latest Claude model when this lands.

A useful test for each feature: can an on-device model do it? If yes, keep it local.

### 7.5 Deterministic core vs. AI judgment

Several capabilities filed under "AI" are not AI — they are deterministic algorithms
that belong in the pure functional core (testable, reliable), with AI only *narrating*
the result in language:

- Equipment / oven-conflict detection (§8.5) — a scheduling computation.
- Shopping-list combining and pantry suppression (§13) — list math.
- Menu repetition / balance flags (§12) — counting and rules over the menu.
- Scaling — arithmetic.

Compute these with pure functions; let AI phrase the explanation. Reserve genuine AI
for things that need world knowledge or judgment (substitutions, freeform menu design,
summarizing lessons from notes). This keeps the trustworthy parts deterministic and
shrinks the surface you have to trust a model with.

## 8. AI Consultation Examples

### 8.1 Menu Planning

User asks:

```text
Build a Saturday dinner menu for 8 using recipes I already have. Avoid seafood-heavy dishes. I want one make-ahead main or side.
```

AI response should consider:

- Saved recipes
- Tags
- Prior ratings
- Make-ahead notes
- Guest dislikes
- Equipment requirements
- Season
- Menu balance

Possible output:

```text
Recommended menu:
- Cocktail: Mai Tai
- Appetizer: spiced nuts or whipped feta
- Main: Korean bavette
- Side: lime-cumin slaw
- Side: roasted cabbage
- Dessert: raspberry mousse

Rationale:
- Main can be marinated ahead.
- Slaw dressing can be made ahead but cabbage should be dressed day-of.
- Dessert can be made the day before.
- Menu avoids seafood and does not overload the oven.
```

### 8.2 Beach Week Planning

User asks:

```text
Turn these six recipes into a beach-week cooking plan. Guests arrive Wednesday. I want to prep as much as possible at home without quality loss.
```

AI should produce:

- Home prep tasks
- Freezer tasks
- Cooler packing notes
- Local shopping notes
- Day-by-day thawing schedule
- Day-by-day cooking schedule
- Ingredient consolidation
- Risk flags

Example output:

```text
At home:
- Make and freeze marinade separately.
- Make aioli and freeze only if quality tradeoff is acceptable.
- Chop holy trinity and freeze flat.
- Make slaw dressing and transport in jars.
- Do not dress cabbage before travel.

At beach:
- Buy fish locally.
- Move bavette to fridge 24 hours before grilling.
- Start thawing tinga the morning of serving day.
```

### 8.3 Shopping Consultation

User asks:

```text
Generate the shopping list for this dinner party, but assume I already have soy sauce, fish sauce, rice vinegar, cumin, coriander, and kosher salt.
```

AI should:

- Generate shopping list from selected recipes.
- Suppress pantry staples based on user-controlled assumptions, not inferred stock
  quantities.
- Show skipped pantry staples for review.
- Group by store section.
- Flag uncertain quantities.
- Preserve recipe sources for each item.
- Allow user review.

### 8.4 Substitution Consultation

User asks:

```text
I do not have bavette. What else in my recipe library or notes suggests a good substitute?
```

AI should consider:

- Recipe notes
- Similar recipes
- Cooking method
- Marinade
- Thickness
- Grill behavior
- Availability
- Prior comments

Possible answer:

```text
Skirt steak or flank steak are the closest practical substitutes. Skirt will be more intensely beefy and thinner, so reduce grill time. Flank is easier to source and slices well but is less rich. Do not substitute tenderloin; the marinade and grilling style are wrong for it.
```

### 8.5 Equipment Conflict Consultation

User asks:

```text
Can I actually cook this whole menu in one oven?
```

AI should inspect:

- Oven temperatures
- Cooking times
- Resting times
- Make-ahead potential
- Reheating tolerance
- Serving order

Possible answer:

```text
This is tight. Two dishes require the oven in the final 45 minutes at different temperatures. Move the gratin earlier and reheat covered, or replace one oven side with a room-temperature salad.
```

## 9. AI Review and Confirmation Model

AI should propose changes; the user should approve them.

Examples:

- “Apply parsed ingredients”
- “Accept shopping-list merge”
- “Add these prep tasks”
- “Save as recipe note”
- “Create cooking plan”
- “Update recipe version”
- “Ignore suggestion”

The app should avoid hidden state changes.

## 10. Personal Preference Model

The app should eventually store explicit user preferences.

Examples:

```text
prefersMakeAheadQualityThreshold: high
likesFineDiningStyleMenus: true
dislikesGenericMealPrep: true
spouseDislikes:
  - octopus
  - cuttlefish
  - anchovy-forward dishes
preferredCookingStyles:
  - sous vide
  - grill
  - wok
  - braise
commonContexts:
  - beach week
  - dinner party
  - family visit
  - travel rental kitchen
```

Preferences should be:

- User-visible
- Editable
- Deletable
- Source-aware when inferred
- Never silently assumed as permanent without confirmation

## 11. Recipe Intelligence Metadata

Recipes should eventually support intelligence metadata. Model it the house way —
enums and small value types, not a pile of booleans (make impossible states
unrepresentable; see jon-platform swift-style §3). A dozen overlapping `Bool`s is the
"flag soup" the style guide warns against.

Suited-for flags (genuinely independent yes/no facts) can be a small set, ideally an
`OptionSet`:

```text
suitability: OptionSet { freezerFriendly, travelFriendly, beachHouseFriendly,
                         weeknightFriendly, companyWorthy, reheatsWell }
```

Mutually-exclusive states must be enums, not parallel booleans:

```text
servingTemperature: enum { hot, roomTemperature, cold }   // NOT three Bools
```

Graded qualities are scores/levels (a small enum or a 0–N value), not booleans:

```text
makeAheadScore:    Level { none, partial, mostly, fully }
equipmentIntensity: Level { light, moderate, heavy }
activeWorkload:     Level { low, medium, high }
riskLevel:          Level { low, medium, high }
requiresLastMinuteCooking: derive from makeAheadScore == none, don't store separately
```

These should not be required in MVP.

They can be:

- Manually entered
- Inferred from notes
- Suggested by AI
- Confirmed by user

## 12. Menu Balance

AI should eventually help evaluate a proposed menu.

Dimensions:

- Protein repetition
- Cuisine coherence
- Acid/fat balance
- Heavy/light balance
- Hot/cold balance
- Crunch/softness contrast
- Color variety
- Oven/stovetop/grill load
- Make-ahead feasibility
- Last-minute workload
- Guest preferences
- Seasonality
- Shopping complexity

Example flags:

```text
This menu has three rich dishes and no acidic/crisp counterpoint.
This plan relies too heavily on last-minute grilling.
This menu repeats cabbage in two forms.
This menu has too many dishes needing oven time at service.
This menu is seafood-heavy for a guest group that may not tolerate it.
```

## 13. Shopping Intelligence

Shopping should eventually go beyond aggregating ingredients.

Capabilities:

- Combine ingredients conservatively.
- Group by store section or user-defined shopping location. Grocy's assortment
  model is a useful reference for optimizing store order, but Yes Chef should stay
  recipe/planning-first rather than inventory/ERP-first.
- Group by store.
- Flag specialty items.
- Distinguish buy-ahead vs buy-day-of.
- Distinguish transport-from-home vs buy-local.
- Suppress pantry staples via pantry assumptions.
- Show skipped pantry staples for review and one-tap add-back.
- Support vacation-house shopping.
- Track what was hard to find.
- Remember preferred sources.

Examples:

```text
Buy locally:
- fish
- herbs
- bread

Bring from home:
- spices
- specialty vinegars
- gochujang
- cocktail syrups

Buy early:
- onions
- cabbage
- canned goods

Buy day-of:
- seafood
- baguette
- delicate herbs
```

## 14. Pantry Intelligence

Pantry features should eventually support:

- Pantry assumptions: "I usually have this"
- Shopping policies: shop by default, pantry staple, check first, never shop
- Reviewable skipped pantry staples
- Vacation-house shopping assumptions
- Specialty condiments
- Staple suppression
- User-specific defaults for common items

But pantry should not become a full inventory-management burden. The app should
support light, useful pantry awareness without making the user maintain a grocery
warehouse database. Do not assume the user will track exact amounts of soy sauce,
spices, flour, oil, or similar staples.

Settled boundary: pantry quantity is not a feature goal. Pantry should be modeled
as memory, assumptions, and shopping policy, not a stock ledger the user has to
maintain.

One bounded future idea is an "Inventory Confirm" shopping-list section. A pantry
item could optionally carry a threshold amount such as "1/2 cup brown sugar"; when
a recipe calls for an equal or greater amount, grocery generation could route that
line to "Inventory Confirm" instead of silently skipping it. This should not become
general quantity tracking. It would require a real measurement normalization layer
for unit families and conversions; the current parser stores quantity/unit text but
is not a complete measurement library.

Explicitly optional future layers:

- Freezer inventory
- Expiration dates
- Minimum stock rules
- Partial quantity tracking
- “Use this up” suggestions
- Recipe suggestions from inventory

## 15. Cooking History

Cooking history should primarily come from the meal calendar: if a recipe is on the
calendar and the date has passed, the app can treat that as the last time it was
cooked and update/derive `Recipe.lastCookedAt` from it.

Optional future retrospectives should be designed as meal-planning intelligence, not
as a manual "mark cooked" requirement in the recipe detail surface.

Questions:

- Would you make this again?
- What changed?
- Was the quantity right?
- Did it freeze well?
- Did it reheat well?
- Was it too much last-minute work?
- What would you change next time?
- Was this suitable for guests?
- Was this suitable for travel?
- What should future-you know?

These notes should feed future planning.

Example retrospective:

```text
Made for beach week. Worked well. Bavette thawed in about 24 hours. Marinade separately frozen was fine. Slaw should be cut at home but dressed day-of. Buy fish locally next time.
```

## 16. Recipe Versioning and AI

AI suggestions should integrate with recipe versioning. The foundation already ships
in MVP: the frozen `Recipe.originalSnapshot` (DATA_MODEL.md §2.4) is the immutable
"Original" this section builds on — full versioning later promotes it to version 0
(type original) with no rework. "Preserve original" below is that snapshot.

Possible actions:

- Save as note
- Save as alternate version
- Save as event-specific version
- Update canonical version
- Preserve original

Example:

```text
Original: Milk Street version
Adapted: Jon’s beach-week version
Event version: Serves 12, freezer-friendly prep
```

## 17. App Intents and Shortcuts

App Intents do not need a large plan before the core app stabilizes. The best early
targets are low-risk actions over existing local data:

- Open today's meal calendar.
- Open a specific recipe.
- Start cooking mode for a recipe.
- Add a recipe to a date, defaulting to dinner.
- Add selected recipe ingredients to the primary grocery list.
- Add a pantry assumption by name.

These should use the same model/repository paths as the app UI. Avoid intents that
silently rewrite recipes, infer pantry inventory, or run AI without a review step.

## 18. Privacy and Data Control

The app should be private by default.

Core principles:

- User owns recipe data.
- Export should be supported.
- AI features should not require surrendering the entire library unnecessarily.
- User should know what data is being sent to an AI model.
- Local processing should be preferred where practical.
- Destructive AI edits require confirmation.

## 19. MVP Implications

Although these features are not MVP, MVP should prepare for them by:

1. Preserving original recipe text (and a frozen `originalSnapshot` of the structured
   recipe — DATA_MODEL.md §2.4).
2. Supporting notes as first-class objects.
3. Supporting tags and categories.
4. Supporting equipment metadata.
5. Supporting ingredient sections and instruction sections.
6. Supporting parsed and unparsed ingredient fields.
7. Supporting dateCreated/dateModified.
8. Supporting future cooking sessions.
9. Avoiding rigid taxonomies.
10. Avoiding destructive import cleanup.

## 20. Explicit Non-MVP Status

The following are not MVP 1:

- AI menu planning
- AI prep timelines
- AI shopping consultation
- CookingPlan UI
- Pantry intelligence
- Equipment conflict engine
- Recipe versioning UI
- Cooking-history analytics
- Personal preference engine
- Multi-day trip planning
- AI chat interface
- App Intents

They are documented to shape the data model and product direction, not to expand the first build.

## 21. Long-Term Product Bet

The app becomes worth building when it can do something Paprika does not do well:

Turn a personal recipe library into practical cooking decisions.

The long-term product is not:

```text
A prettier recipe box.
```

The long-term product is:

```text
A private culinary planning system that knows what the user cooks, how the user adapts recipes, what worked before, what constraints matter, and how to turn a menu into a realistic plan.
```

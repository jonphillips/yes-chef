Data Model

1. Purpose

This document defines the initial data model for the recipe management and cooking-planning app.

The model should support:

* Recipe storage
* Recipe import
* Recipe editing
* Ingredient parsing
* Instruction organization
* Notes
* Tags and categories
* Search
* Scaling
* Cooking mode
* Grocery lists
* Meal planning
* Future cooking plans
* Future make-ahead intelligence
* Future AI-assisted cleanup and planning

The model should be tolerant of messy recipe data. It should preserve original user/imported text even when parsed or structured fields are available.

2. Core Design Principles

2.1 Preserve Original Data

The app must never silently discard imported or user-entered recipe text.

For any parsed structure, keep the original string.

Example:

Original ingredient line:

2 tablespoons finely chopped fresh rosemary

Parsed fields:

quantity: 2
unit: tablespoon
item: fresh rosemary
preparation: finely chopped

The original line must remain available.

2.2 Structure Where Useful, Text Where Necessary

Recipe data is messy. Many ingredient lines are not cleanly parseable.

Examples:

Kosher salt, to taste
A generous handful of basil
Juice of 1 lemon, plus more as needed
Enough olive oil to loosen the sauce
1 28-ounce can whole peeled tomatoes
2 pounds bone-in, skin-on chicken thighs, trimmed

The model should allow partial parsing. It is better to store uncertain data as text than to invent incorrect structure.

2.3 Avoid Premature Over-Normalization

The model should not require a global ingredient database in the first version.

For example, do not initially force:

Parmigiano-Reggiano
parmesan
Parmesan cheese
grated parmesan
aged Parm

into one canonical ingredient entity.

That can come later through optional ingredient intelligence.

2.4 Support Recipe Adaptation

The app should eventually distinguish:

* Original imported recipe
* Cleaned recipe
* User-adapted recipe
* Event-specific version
* Scaled version
* Notes from specific cooking sessions

The initial model should leave room for versioning without forcing full version history in MVP 1.

Frozen original snapshot (ships in MVP). The one piece of versioning that lands early:
on first save/import, capture an immutable, write-once snapshot of the recipe's
structured content into Recipe.originalSnapshot (a Data blob). It is never updated
after creation, so the user can always view the pristine original beside their edited
version. The snapshot reuses the recipe-transfer bundle serialization (§2.6) — same
format, captured locally instead of sent. This is the lightweight slice of the full
RecipeVersion vision (§22): later, originalSnapshot simply becomes "version 0" (type
original) with no rework. A read-only viewer is the only UI it needs; a what-changed
diff is a separate, deferred feature.

Note on the blob: an immutable archive is the one case where a Data blob is correct
even under the house "avoid opaque blobs for core editable data" rule — the snapshot is
never edited or queried into, only deserialized for display.

2.5 Local-First and Migration-Friendly

The data model should work well with Apple-native local persistence.

The model should:

* Use stable IDs.
* Avoid destructive renames.
* Be explicit about relationships.
* Allow future migration.
* Avoid unnecessary required fields.
* Prefer optional fields for metadata that may not exist in imported recipes.

2.6 Private Libraries + Recipe Transfer

Yes Chef is NOT a co-edited shared library. Each person — you, your wife, each kid as
they start cooking — keeps their OWN private recipe library. Recipes move between
people by *transfer*: you send (later, publish) a recipe and the recipient gets their
own independent copy; from then on edits never cross between copies. Settled in
ADR-0003.

Why this shape: a family member editing a recipe must never change anyone else's
recipe — and the only model that guarantees that is separate copies. It also matches
real use: most of your recipes won't interest your wife and vice versa, so the default
is "my library is mine," with an easy way to hand a recipe over when it's worth it.

Consequences for the data model (mostly simplifications vs. a co-edited library):

* Everything is private. The whole library lives in the user's own CloudKit PRIVATE
database — it syncs across that user's devices and is invisible to everyone else.
There is no shared zone for the library, no Household root, no co-editing, no
share-accept flow for normal use.
* Personal fields are just fields. favorite, rating, tags, notes are plain
columns/tables on your own recipes. No per-cook "opinion" rows, no attribution columns
inside a library — there is only one person in it (you).
* Relationships are ordinary. With nothing shared, there is no single-FK sharing
constraint: join tables (RecipeTag, RecipeCategory, RecipeEquipment) hold real foreign
keys to both sides. Model relationships the normal relational way.
* UUID primary keys everywhere, still. CloudKit private-DB sync requires them, and
they make transfer clean — an imported copy is re-keyed with fresh UUIDs so it can
never collide with the original.
* Dedup-on-read still applies, narrowly. Two of your OWN devices, both offline, can
each insert a name-unique row (e.g. a Tag "grill"). Keep UUID PKs + a code-level
upsert + dedup-on-read (lowest UUID wins) for name-unique entities (Tag, Category).
Lower stakes than a multi-person share, but the race still exists; seed duplicates in
tests.

Recipe transfer — two phases (see ROADMAP):

Phase 1 — Send a copy (no shared infrastructure). "Send recipe" serializes the recipe
and its children — sections, lines, instructions, notes, photos, plus its tag/category
NAMES — into a self-contained bundle (a .yeschef file or a universal link) handed to
the system share sheet (Messages, AirDrop, …). The recipient opens it and IMPORTS: the
bundle is rebuilt as new rows with fresh UUIDs in their private library. Tags and
categories are matched by name to the recipient's own (find-or-create) or dropped —
the recipient's organization wins. The sender's name can ride along as a plain string
("from Dad") for provenance; it is not a synced entity.

Phase 2 — Family Cookbook (browsable, later milestone). An always-on shared space the
family participates in (one shared CloudKit zone, accepted once) where members PUBLISH
recipes for others to browse and COPY into their own library. Same copy-on-adopt rule:
copying clones the published recipe into your private library with fresh UUIDs; editing
your copy never touches the published one or anyone else's. This is the ONLY part of
the app that uses CloudKit *sharing*, and because published recipes are read-then-copy
(never co-edited), it sidesteps the conflict/sharing-tree complexity a co-edited library
would force. Design it once the private library and Phase-1 send are solid.

No new shared entities. There is no Household, Cook, RecipeOpinion, or
RecipeSuggestedTag — those existed only to make a co-edited shared library survive
CloudKit. favorite and rating are plain columns on Recipe; tags and categories are
your own ordinary entities; provenance ("from Dad") is a plain string captured on
import.

Join entities (ordinary many-to-many, real FKs to both sides — nothing is shared):

  RecipeTag        { id, recipeID, tagID, sortOrder }
  RecipeCategory   { id, recipeID, categoryID }
  RecipeEquipment  { id, recipeID, equipmentID, notes: String? }

The transfer payload (shared by both transfer phases). A recipe bundle is a
self-contained snapshot: the Recipe plus its IngredientSections/Lines,
InstructionSections/Steps, RecipeNotes, RecipePhotos (or photo references), and its
tag/category NAMES (strings, not IDs — IDs are local to a library). On import,
everything is re-keyed with fresh UUIDs and names are reconciled against the
recipient's own tags/categories (find-or-create). source and originalImportText are
preserved — transfer is just another import path (see §29).

Adjustments to entities defined elsewhere in this document:

* Recipe has NO householdID and NO addedByCookID. favorite: Bool and rating: Int?
remain plain columns on Recipe (your own copy — there is only one you). archived,
timesCooked, lastCookedAt are plain fields too.
* IngredientLine and InstructionStep keep their sectionID and may also keep recipeID —
both are ordinary foreign keys now (no sharing-tree constraint).
* RecipeNote, CookingSession, etc. carry no Cook attribution columns; everything in a
library belongs to its single owner.
* Tag, Category, Equipment are ordinary local entities; their recipe links are the
join entities above, with real FKs to both sides. No householdID, no privateTables
exception — the whole library is private already.

MVP note: build the private library first — a single-user app whose data syncs across
the owner's devices via the CloudKit private database. No Household, no Cook, no
share-accept flow. "Send a recipe" (Phase 1) is a self-contained import/export feature
needing no shared infrastructure; the browsable Family Cookbook (Phase 2) is a later
milestone and the only piece that uses CloudKit sharing. Verify SQLiteData's current
CloudKit private-DB sync API at the start of the sync milestone.

3. Entity Overview

Initial core entities:

Recipe
RecipeSource
IngredientSection
IngredientLine
InstructionSection
InstructionStep
RecipeNote
RecipePhoto
Tag
Category
Equipment
RecipeTag
RecipeCategory
RecipeEquipment
CookingSession
MealPlanEntry
ShoppingList
ShoppingListItem
PantryItem
CookingPlan
CookingPlanTask
RecipeVersion
ImportJob
ImportIssue

MVP 1 entities (a single owner's private library — see §2.6):

Recipe
RecipeSource
IngredientSection
IngredientLine
InstructionSection
InstructionStep
RecipeNote
RecipePhoto
Tag
Category
Equipment
RecipeTag
RecipeCategory
RecipeEquipment

MVP 2+ entities:

ImportJob
ImportIssue
ShoppingList
ShoppingListItem
MealPlanEntry
CookingSession

Future entities:

PantryItem
CookingPlan
CookingPlanTask
RecipeVersion

4. Recipe

4.1 Purpose

A Recipe is the central entity. It represents a cookable or mixable item.

A recipe can be:

* A dish
* A drink
* A sauce
* A component
* A prep item
* A technique note
* A meal template

Examples:

Korean Bavette
Creole Chicken Tray Bake
Mai Tai
Lime-Cumin Slaw
Monkfish with Aioli
Roasted Cabbage
Pork Tinga

4.2 Fields

id: UUID
title: String
subtitle: String?
summary: String?
source: RecipeSource?
servings: Double?
servingsText: String?
yieldText: String?
prepTimeMinutes: Int?
cookTimeMinutes: Int?
totalTimeMinutes: Int?
activeTimeMinutes: Int?
restTimeMinutes: Int?
ingredientSections: [IngredientSection]
instructionSections: [InstructionSection]
notes: [RecipeNote]
photos: [RecipePhoto]
tags: [Tag]
categories: [Category]
equipment: [Equipment]
cuisine: String?
course: String?
difficulty: RecipeDifficulty?
rating: Int?
favorite: Bool
archived: Bool
libraryPlacement: RecipeLibraryPlacement
dateCreated: Date
dateModified: Date
lastCookedAt: Date?
timesCooked: Int
originalImportText: String?
originalSnapshot: Data?
importMetadata: ImportMetadata? (future, not persisted in MVP 1)

Note: favorite and rating are plain columns — this is your own private copy of the
recipe, so there is exactly one rating and one favorite flag (yours). See §2.6.

Taxonomy note: categories and tags are not the universal metadata bucket. Source,
author, cuisine, course, library placement, and future recipe-family role should be
typed fields/entities when the app understands them. See ADR-0006.

4.3 Field Notes

title

Required. Human-readable name.

Examples:

Korean Bavette
Best Fresh Margaritas
Chicken Tray Bake with Creole Trinity

subtitle

Optional secondary title.

Example:

LA galbi-style marinade, grilled and sliced after cooking

summary

Short description of the recipe.

Example:

A make-ahead-friendly grilled bavette using a Korean-style marinade.

source

Optional RecipeSource.

A recipe may have no source if it is original, personal, or manually created.

servings

Numeric serving count, if parseable.

Example:

4
8
10

servingsText

Original serving text.

Examples:

Serves 4
Makes 8 tostadas
Feeds 10 as part of a larger meal

This should be preserved because serving text is often more expressive than a number.

yieldText

Useful for non-serving yields.

Examples:

Makes 2 cups
Makes one 9-inch tart
Makes 1 quart

Time Fields

All time fields are optional integers in minutes.

Examples:

prepTimeMinutes: 30
cookTimeMinutes: 90
totalTimeMinutes: 150
activeTimeMinutes: 45
restTimeMinutes: 20

Imported recipes may have only vague time data. Do not force all fields.

cuisine

Optional user-facing cuisine.

Examples:

Korean
Mexican
French
Sicilian
Creole
Japanese

This should initially be plain text or a lightweight enum-like string, not a hard-coded taxonomy.

course

Optional course/type.

Examples:

Main
Side
Sauce
Cocktail
Dessert
Appetizer
Breakfast
Snack
Component

difficulty

Possible enum:

easy
medium
hard
project

This is user-defined, not an objective cooking score.

rating and favorite

Plain columns on your own copy of the recipe. rating is a personal 1–5 (not an
imported web rating); favorite is a quick-access flag. There is exactly one of each —
yours — because the library is private (see §2.6).

archived

Boolean flag for hiding recipes without deleting them. Archived recipes are hidden
because the user no longer wants them active. Do not use `archived` for recipes that
are still valuable as source/reference material; use future `libraryPlacement`
instead.

libraryPlacement

Future field, not persisted in MVP 1. Controls whether a recipe appears in the default
main library or is kept as source/reference material. Default should be `main`.

Possible enum:

main
reference

Reference recipes remain searchable and linkable, and may appear as related versions
from a canonical/preferred recipe. They should not clutter the default browse list.

originalImportText

Raw text from imported source when available.

This is important for debugging import, re-parsing later, or recovering lost structure.

originalSnapshot

Immutable, write-once snapshot of the recipe's structured content as it was first
saved/imported — serialized with the recipe-transfer bundle format (§2.6). Captured
once at creation, never updated, so "view original" always shows the pristine version.
Manual recipes get this snapshot too; "original" means first saved state, not only
imported source material.
Forward-compatible with full versioning: becomes version 0 (type original) under
RecipeVersion (§22). See §2.4.

5. RecipeSource

5.1 Purpose

Represents where a recipe came from.

Sources may include:

* Website
* Cookbook
* Magazine
* Friend
* Personal creation
* Adapted from another recipe
* Restaurant inspiration
* Imported Paprika record

5.2 Fields

id: UUID
recipeID: UUID
name: String?
url: URL?
author: String?
publicationName: String?
bookTitle: String?
pageNumber: String?
importedFrom: String?
dateImported: Date?
sourceNotes: String?

5.3 Persistence Shape

`RecipeSource` is its own table in the persisted schema, linked to `Recipe` by
`recipeID`. It is logically one optional source record per recipe for MVP 1, not a
set of flattened columns on `Recipe`. If a later recipe needs multiple sources, add a
new relationship deliberately rather than overloading this first shape.

Source identity and author identity are first-class metadata, not categories. Filtering
by source (America's Test Kitchen, Milk Street, The French Laundry Cookbook) or author
(Steve Dunn, Christopher Kimball, Thomas Keller) should use `RecipeSource` fields
rather than category/tag strings. Importers may use category strings as evidence, but
known source/author data should be mapped into typed fields when confidence is high.

5.4 Examples

Website:

name: "Serious Eats"
url: "https://..."
author: "J. Kenji López-Alt"
publicationName: "Serious Eats"

Cookbook:

name: "The Food Lab"
bookTitle: "The Food Lab"
author: "J. Kenji López-Alt"
pageNumber: "482"

Personal:

name: "Jon"
sourceNotes: "Adapted from several galbi recipes."

Paprika import:

importedFrom: "Paprika 3"
dateImported: 2026-06-15

6. IngredientSection

6.1 Purpose

Groups related ingredients inside a recipe.

Examples:

Main
Marinade
Sauce
Dressing
For serving
Garnish
Aioli
Slaw
Chicken
Rice

6.2 Fields

id: UUID
recipeID: UUID
name: String?
sortOrder: Int
ingredientLines: [IngredientLine]

6.3 Rules

* A recipe should have at least one ingredient section.
* If no section name exists, name may be nil or "Ingredients".
* Preserve imported section names where possible.
* Ingredient order matters.

7. IngredientLine

7.1 Purpose

Represents one line of ingredients.

This is one of the most important entities in the app.

7.2 Fields

id: UUID
recipeID: UUID
sectionID: UUID
originalText: String
quantity: Double?
quantityText: String?
unit: String?
item: String?
preparation: String?
comment: String?
isOptional: Bool
shoppingCategory: String?
doNotShop: Bool
isHeader: Bool
sortOrder: Int
confidence: ParseConfidence?

7.3 Field Notes

originalText

Required. The original ingredient line.

Examples:

2 tablespoons soy sauce
1 1/2 pounds bavette steak
Kosher salt, to taste
For serving: lime wedges, cilantro, warm tortillas

quantity

Numeric parsed quantity, if available.

Examples:

2
1.5
0.25

quantityText

Original quantity text.

Examples:

1 1/2
a handful
one 28-ounce can
about 2

This should be preserved because numeric parsing will often be incomplete.

unit

Parsed unit, if available.

Examples:

teaspoon
tablespoon
cup
ounce
pound
gram
clove
bunch
can
piece

Use a string initially rather than a strict enum. Unit normalization can come later.

item

Parsed item.

Examples:

soy sauce
bavette steak
kosher salt
cilantro
lime wedges

preparation

Prep state or modifier.

Examples:

finely chopped
thinly sliced
toasted
grated
peeled and minced
room temperature
drained

comment

Extra note.

Examples:

plus more to taste
divided
optional
for serving
preferably Diamond Crystal

isOptional

Boolean for optional ingredients. (Named isOptional, not optional, to avoid
shadowing Swift's Optional.)

Can be inferred from text but should be user-editable.

shoppingCategory

User-facing grocery grouping.

Examples:

Produce
Meat
Seafood
Dairy
Dry Goods
Condiments
Spices
Frozen
Bakery
Alcohol

doNotShop

True if the line should not be added to a shopping list.

Examples:

Water
Salt
Freshly ground black pepper

The user should be able to override this.

isHeader

True if the line is a header rather than an ingredient.

Example:

For the marinade:

This may be better represented as a section, but imports may produce header lines.

confidence

Possible enum:

unparsed
low
medium
high
manual

Manual means user-confirmed.

7.4 Examples

Clean parse:

originalText: "2 tablespoons soy sauce"
quantity: 2
quantityText: "2"
unit: "tablespoon"
item: "soy sauce"
preparation: nil
comment: nil
confidence: high

Partial parse:

originalText: "1 28-ounce can whole peeled tomatoes"
quantity: 1
quantityText: "1"
unit: "can"
item: "whole peeled tomatoes"
comment: "28-ounce"
confidence: medium

Unparsed:

originalText: "Kosher salt, to taste"
quantity: nil
quantityText: nil
unit: nil
item: "Kosher salt"
comment: "to taste"
confidence: low

Vague:

originalText: "A generous handful of basil"
quantity: nil
quantityText: "A generous handful"
unit: nil
item: "basil"
confidence: low

8. InstructionSection

8.1 Purpose

Groups instruction steps.

Examples:

Main
Marinade
Sauce
Assembly
Make ahead
Day of cooking
For the chicken
For the slaw

8.2 Fields

id: UUID
recipeID: UUID
name: String?
sortOrder: Int
steps: [InstructionStep]

8.3 Rules

* A recipe should have at least one instruction section.
* Step order matters.
* Preserve imported section names where possible.

9. InstructionStep

9.1 Purpose

Represents one instruction step.

9.2 Fields

MVP persisted fields:

id: UUID
recipeID: UUID
sectionID: UUID
text: String
sortOrder: Int
isOptional: Bool

Future helper fields, not persisted in MVP 1 until their value types and storage shape
are defined:

timerHints: [TimerHint]
temperatureHints: [TemperatureHint]
equipmentHints: [EquipmentHint]
ingredientReferences: [UUID]

9.3 Field Notes

text

Required instruction text.

Example:

Combine soy sauce, brown sugar, garlic, ginger, sesame oil, and scallions in a bowl. Add steak and marinate for at least 4 hours or overnight.

timerHints

Future feature.

Examples:

15 minutes
4 hours
overnight
until browned, 8 to 10 minutes

temperatureHints

Future feature.

Examples:

350°F
medium-high heat
internal temperature 130°F

equipmentHints

Future feature.

Examples:

grill
oven
wok
sheet pan
food processor
vacuum sealer

ingredientReferences

Optional links to specific ingredient lines.

Not required in MVP 1. This can power step-based ingredient highlighting later.

10. RecipeNote

10.1 Purpose

Stores user notes about a recipe.

Notes are a major product differentiator and should not be an afterthought.

10.2 Fields

id: UUID
recipeID: UUID
text: String
noteType: RecipeNoteType
dateCreated: Date
dateModified: Date
cookingSessionID: UUID?
pinned: Bool

10.3 Note Types

Possible enum:

general
adaptation
makeAhead
freezing
thawing
shopping
serving
equipment
scaling
wine
retrospective
warning

10.4 Examples

General:

Good beach-house recipe. Buy fish locally rather than transporting frozen.

Make-ahead:

Sauce can be made two days ahead. Do not dress slaw until day of serving.

Freezing:

Marinade freezes well separately. Combine with meat during thawing.

Retrospective:

Made June 2026. Needed more acid. Increase lime juice by 50% next time.

Warning:

Do not use boneless skinless breasts here; dish gets dry.

11. RecipePhoto

11.1 Purpose

Stores references to recipe photos.

11.2 Fields

id: UUID
recipeID: UUID
imageDataReference: String        // app-owned reference/identity, not an external path
displayData: Data?
thumbnailData: Data?
mediaType: String?
pixelWidth: Int?
pixelHeight: Int?
originalSourcePath: String?
sourceURL: String?
checksum: String?
kind: RecipePhotoKind
caption: String?
source: PhotoSource
sortOrder: Int
dateCreated: Date

11.3 Photo Source

Possible enum:

user
imported
web
generated

For MVP, avoid generated images.

Image storage/processing decision: see ADR-0005. `imageDataReference` is an app-owned
reference string. Imported external paths belong in provenance fields such as
`originalSourcePath`; do not depend on a private Paprika export path as photo identity.
Production import/user-photo features should preserve readability for
recipe-reference photos.

12. Tag

12.1 Purpose

Flexible user-defined metadata.

Tags are for cross-cutting concepts.

Examples:

beach
make-ahead
freezer-friendly
grill
sous-vide
wok
dinner-party
weeknight
company
low-carb
summer

12.2 Fields

id: UUID
name: String
color: String?
sortOrder: Int
dateCreated: Date

12.3 Rules

* Tags are your own — the whole library is private (§2.6), so a tag vocabulary belongs
to its single owner. When you send a recipe, its tag NAMES travel in the payload and
the recipient reconciles them against their own tags (find-or-create) on import.
* The recipe↔tag link is the RecipeTag join entity (real FKs to both sides).
* Tags are many-to-many with recipes.
* Tags should be user-editable.
* Tags should not be forced into a rigid taxonomy.

13. Category

13.1 Purpose

Broad recipe organization.

Categories are more stable and less numerous than tags.

Examples:

Appetizers
Beef
Chicken
Pork
Seafood
Vegetables
Salads
Soups
Pasta
Desserts
Cocktails
Sauces
Sides
Breakfast

13.2 Fields

id: UUID
name: String
parentCategoryID: Category.ID?
sortOrder: Int
dateCreated: Date

Possible future field:

description: String?

This should not be required initially. Category titles, child categories, and assigned
recipes are usually enough semantic context for LLM-assisted workflows. Add an
optional description or LLM hint only if ambiguous parent categories need more user
supplied meaning.

13.3 Rules

* Recipes may have multiple categories.
* Categories should support Paprika import if Paprika categories exist.
* Do not require exactly one category per recipe.
* Categories are the right place for stable hierarchy. The current editor accepts
path-style category entries such as `Meal Type > Appetizers`, `Protein > Chicken`,
or `Occasion > Beach`; a future category manager should add rename, merge, delete,
and re-parent workflows.
* Categories should not be the primary model for known facets that deserve typed
fields, including source, author, cuisine, course, and library placement. See
ADR-0006.
* Tags remain flat and cross-cutting; do not recreate Paprika-style parent/child
tags in the Tag model.
* Paprika `.paprikarecipes` exports observed so far preserve flat category names per
recipe but not the global parent/child category tree, so category hierarchy may need
manual reconstruction or a separate source of truth.

13.4 Category Management

Categories are user/library data, not built-in constants. Import can create categories
from source labels, and future UI should allow creating, renaming, merging, deleting,
and re-parenting categories. The app may ship suggestions or templates later, but the
owner's library taxonomy wins.

14. Equipment

14.1 Purpose

Represents cooking equipment associated with a recipe.

14.2 Fields

id: UUID
name: String
equipmentType: String?
notes: String?

14.3 Examples

oven
grill
gas grill
charcoal grill
wok burner
sous vide
Dutch oven
sheet pan
food processor
blender
stand mixer
rice cooker
vacuum sealer

14.4 Future Use

Equipment can later support:

* Filtering recipes
* Cooking-plan conflict detection
* Prep planning
* “Can I cook this at the beach house?” evaluation

15. CookingSession

15.1 Purpose

Records a specific time the user cooked a recipe.

This is not required for MVP 1, but it is central to the long-term product.

15.2 Fields

id: UUID
recipeID: UUID
dateCooked: Date
servingsMade: Double?
context: String?
rating: Int?
notes: [RecipeNote]
wouldMakeAgain: Bool?
changesMade: String?

15.3 Examples

context: "Beach week 2026"
changesMade: "Used 2 lb bavette, grilled over gas, sliced after cooking."
rating: 5
wouldMakeAgain: true

16. MealPlanEntry

16.1 Purpose

Represents a planned recipe or meal on a date.

16.2 Fields

id: UUID
date: Date
mealType: MealType
recipeID: UUID?
titleOverride: String?
servings: Double?
notes: String?
cookingPlanID: UUID?
sortOrder: Int

16.3 MealType

Possible enum:

breakfast
lunch
dinner
snack
cocktail
prep
event
other

16.4 Rules

A meal plan entry may refer to a recipe or may be free text.

Examples:

Recipe-linked:

Dinner: Korean Bavette

Free-text:

Lunch: leftovers / sandwiches

Prep item:

Prep: thaw pork tinga

17. ShoppingList

17.1 Purpose

Represents a grocery list.

17.2 Fields

id: UUID
name: String
dateCreated: Date
dateModified: Date
items: [ShoppingListItem]
sourceMealPlanStartDate: Date?
sourceMealPlanEndDate: Date?
cookingPlanID: UUID?

17.3 Examples

Beach Week Shopping
Dinner Party Shopping
Whole Foods
Costco
Fish Market

18. ShoppingListItem

18.1 Purpose

Represents one grocery item.

18.2 Fields

id: UUID
shoppingListID: UUID
originalText: String
quantity: Double?
quantityText: String?
unit: String?
item: String
category: String?
sourceRecipeIDs: [UUID]
sourceIngredientLineIDs: [UUID]
checked: Bool
manuallyAdded: Bool
sortOrder: Int
notes: String?

18.3 Rules

* Shopping items may be generated from ingredient lines.
* User edits should be preserved.
* Combining ingredients should be conservative.
* Original source lines should be traceable.
* Pantry-staple suppression should be traceable and reversible. If an item is
  skipped because the user usually has it, the user should be able to review the
  skipped item and add it back.
* Shopping categories are user-facing ordering/grouping hints, not a universal
  taxonomy. Grocy's "assortment" idea is useful inspiration for store-order
  grouping; Yes Chef should not require store-specific setup before grocery
  generation is useful.

18.4 Combining Example

Source lines:

1 onion
2 onions

Combined item:

3 onions

Ambiguous lines:

1 bunch cilantro
cilantro, for garnish

Should not be overconfidently combined unless user confirms.

19. PantryAssumption

19.1 Purpose

Represents an item the user generally assumes is on hand, or wants treated
according to a shopping policy.

This is future functionality.

This is not a quantity-based inventory ledger. The core use case is "I usually
have soy sauce; don't add it automatically, but let me see what was skipped."

19.2 Fields

id: UUID
displayName: String
canonicalItemKey: String
shoppingPolicy: PantryShoppingPolicy
category: String?
shoppingLocation: String?
notes: String?
dateCreated: Date
dateModified: Date

19.2.1 PantryShoppingPolicy

Possible values:

* shopByDefault
* pantryStaple
* checkFirst
* neverShop

19.3 Examples

soy sauce
fish sauce
basmati rice
frozen chicken thighs
dried hibiscus flowers

19.4 Future Use

Pantry can support:

* Suppressing owned items from shopping lists
* Showing skipped pantry staples for review
* "Check pantry" prompts for uncertain staples
* Vacation-house shopping assumptions
* User-specific defaults such as preferred soy sauce, rice, oil, or canned tomatoes

Explicitly deferred/opt-in only:

* Quantity tracking
* Minimum stock rules
* Expiration reminders
* Freezer inventory
* “Use this up” suggestions

20. CookingPlan

20.1 Purpose

Represents a larger cooking event or multi-day plan.

This is a major differentiator.

20.2 Fields

id: UUID
title: String
startDate: Date
endDate: Date?
guestCount: Int?
location: String?
recipes: [Recipe]
mealPlanEntries: [MealPlanEntry]
tasks: [CookingPlanTask]
shoppingLists: [ShoppingList]
notes: String?
dateCreated: Date
dateModified: Date

20.3 Examples

Beach Week June 2026
Saturday Dinner Party
Thanksgiving
Virginia Weekend
Christmas Dinner

21. CookingPlanTask

21.1 Purpose

Represents a task within a cooking plan.

21.2 Fields

id: UUID
cookingPlanID: UUID
recipeID: UUID?
title: String
notes: String?
taskType: CookingPlanTaskType
dueDate: Date?
durationMinutes: Int?
equipmentID: UUID?
completed: Bool
sortOrder: Int

21.3 Task Types

Possible enum:

shop
prep
cook
thaw
freeze
marinate
pack
transport
serve
clean
other

21.4 Examples

Move bavette from freezer to fridge
Make aioli
Chop holy trinity
Buy fish locally
Pack vacuum-sealed marinade
Toast spices
Salt cabbage
Make margarita base

22A. RecipeFamily

> **Contested (2026-06-30).** This entity bundles two relationships that a design
> discussion argues are distinct primitives — *suppression* (rivals, one real winner,
> losers hidden) and *variation clustering* (siblings, all visible, a synthetic header,
> manual membership + LLM-derived label). See open-questions.md → "Recipe relationships —
> suppression vs. variation vs. collection" before building from the shape below.

22A.1 Purpose

Future entity for grouping recipes that are variants or source material for the same
dish.

Examples:

Chocolate Chip Cookies
Kung Pao Chicken
Caesar Salad
French Onion Soup

A family lets the app keep several recipes without making the main library noisy. One
recipe can be the preferred/canonical recipe, while related recipes remain available
for comparison, inspiration, or source evidence.

22A.2 Fields

id: UUID
name: String
preferredRecipeID: Recipe.ID?
dateCreated: Date
dateModified: Date

22A.3 Join Entity

RecipeFamilyMember

id: UUID
familyID: RecipeFamily.ID
recipeID: Recipe.ID
role: RecipeFamilyRole
sortOrder: Int
notes: String?

Possible roles:

preferred
variant
sourceMaterial
adaptation
inspiration

22A.4 Rules

* A recipe family is not the same as a RecipeVersion. Families group separate recipe
rows that the user wants to compare or relate.
* A family may have zero or one preferred recipe.
* The preferred recipe usually belongs in the main library. Related source material
may use `libraryPlacement = reference`.
* Do not model "canonical" as a tag the user must constantly filter by.
* Related versions should be discoverable from the recipe detail view and from future
family browsing/search.

22. RecipeVersion

22.1 Purpose

Represents a version of a recipe.

This is future functionality but should influence early design. The one part that
ships in MVP is the frozen original snapshot stored in Recipe.originalSnapshot (§2.4):
when full versioning lands, that snapshot becomes the first RecipeVersion row
(versionType original) with no migration.

22.2 Fields

id: UUID
recipeID: UUID
versionName: String
versionType: RecipeVersionType
dateCreated: Date
sourceVersionID: UUID?
snapshotData: Data
notes: String?

22.3 Version Types

Possible enum:

original
cleaned
userAdapted
scaled
eventSpecific
archived

22.4 Examples

Original imported version
Jon's adapted version
Beach week version
Serves 12 version
Low-carb version

23. ImportJob

23.1 Purpose

Represents an import operation.

23.2 Fields

id: UUID
sourceName: String
sourceFileName: String?
dateStarted: Date
dateCompleted: Date?
status: ImportStatus
recipesImported: Int
recipesSkipped: Int
issues: [ImportIssue]

23.3 ImportStatus

Possible enum:

pending
running
completed
completedWithWarnings
failed
cancelled

24. ImportIssue

24.1 Purpose

Represents a warning or error during import.

24.2 Fields

id: UUID
importJobID: UUID
recipeTitle: String?
severity: ImportIssueSeverity
message: String
rawDataExcerpt: String?

24.3 Severity

Possible enum:

info
warning
error

24.4 Examples

Could not parse serving count.
Missing source URL.
Photo import failed.
Ingredient section preserved as raw text.

25. Supporting Types

25.1 RecipeDifficulty

easy
medium
hard
project

25.2 ParseConfidence

unparsed
low
medium
high
manual

25.3 MealType

breakfast
lunch
dinner
snack
cocktail
prep
event
other

25.4 RecipeNoteType

general
adaptation
makeAhead
freezing
thawing
shopping
serving
equipment
scaling
wine
retrospective
warning

25.5 CookingPlanTaskType

shop
prep
cook
thaw
freeze
marinate
pack
transport
serve
clean
other

25.6 PhotoSource

user
imported
web
generated

25.7 ImportStatus

pending
running
completed
completedWithWarnings
failed
cancelled

25.8 ImportIssueSeverity

info
warning
error

25.9 Deferred Helper Types

`TimerHint`, `TemperatureHint`, `EquipmentHint`, and `ImportMetadata` are placeholders
for future extraction/import work. Do not add them to the MVP 1 persisted schema until
their value types, confidence model, and migration path are defined. In the first
vertical slice, preserve the underlying instruction text and import/source text.

26. Search Requirements

Search should eventually cover:

* Recipe title
* Subtitle
* Summary
* Source name
* Source URL
* Author
* Ingredient original text
* Parsed ingredient item
* Instruction text
* Notes
* Tags
* Categories
* Cuisine
* Course
* Equipment

MVP search can be simple full-text filtering across recipe title, ingredients, instructions, notes, tags, and categories.

27. Scaling Requirements

Scaling should operate on parsed ingredient quantities where possible.

27.1 Scaling Inputs

User may scale by:

* Serving count
* Scale factor
* Yield target

MVP should support serving count and scale factor.

27.2 Scaling Rules

* Do not overwrite canonical recipe unless explicitly saved.
* Preserve original ingredient text.
* Display scaled quantity where possible.
* Leave unparsed quantities unchanged.
* Mark uncertain scaled lines clearly.
* Avoid absurd conversions in MVP.

27.3 Examples

Original:

2 tablespoons soy sauce

2x scaled:

4 tablespoons soy sauce

Original:

Kosher salt, to taste

2x scaled:

Kosher salt, to taste

Original:

1 28-ounce can whole peeled tomatoes

2x scaled:

2 28-ounce cans whole peeled tomatoes

28. Grocery List Requirements

Ingredient lines should be convertible into shopping list items.

Important rules:

* Preserve source recipe links.
* Preserve original ingredient text.
* Combine only when reasonably confident.
* Let the user edit everything.
* Do not treat shopping list as a perfect normalized ingredient database.
* Treat pantry as memory and suppression rules, not as automatic inventory
  accounting.
* Use pantry assumptions to keep generated lists clean, but expose skipped items
  for review.
* Product/barcode enrichment can come later. Open Food Facts and Grocy-style
  barcode workflows are useful for packaged products, not a prerequisite for
  recipe ingredient parsing.

29. Import Requirements

Import must be forgiving.

29.1 Import Rules

* Preserve original raw import data.
* Preserve source URL.
* Preserve recipe title.
* Preserve ingredients.
* Preserve instructions.
* Preserve notes.
* Preserve categories/tags.
* Preserve photos where possible.
* Generate warnings when data is incomplete.
* Never fail the entire import because one recipe is malformed.

29.2 Paprika Import

Do not assume the Paprika export format until a real sample is inspected. Observed
Paprika HTML export behavior is recorded in IMPORT_EXPORT.md.

Observed Paprika `.paprikarecipes` backups are ZIP archives of gzip-compressed JSON
records. Yes Chef currently uses them as a supplement source for `Recipe.dateCreated`,
not as a replacement for the HTML importer. Matching must be conservative: normalized
title match, with source URL required when the title is ambiguous. Supplementing
created dates must not change `dateModified` or rewrite recipe content.

Once a sample exists:

* Document the format.
* Create fixtures.
* Write parser tests.
* Map fields to internal model.
* Preserve unmapped fields.

30. Deletion and Archiving

Recipe deletion should be cautious.

MVP should support:

* Archive recipe
* Delete recipe only with confirmation

Future:

* Recently deleted
* Restore
* Export before destructive delete

31. Sync Considerations

The model should be compatible with future sync.

Design implications:

* Use stable IDs.
* Avoid relying only on array order without explicit sortOrder.
* Track dateCreated and dateModified.
* Avoid massive opaque blobs for core editable data.
* Keep photos as separate entities/references.
* Consider conflict resolution later.

32. Migration Considerations

Before changing persistent fields, evaluate:

* Is this field required?
* Can it be optional?
* Can old records be migrated?
* Is this a rename or a new field?
* Is data being split into multiple entities?
* Is original imported data preserved?
* Could this break existing user recipes?

33. Open Questions

33.1 Persistence Framework

Settled by house style (`~/code/jon-platform/docs/ios/persistence-and-sync.md`):
SQLiteData (Point-Free). Local SQLite is the source of truth; records are plain
structs queried with @FetchAll/@FetchOne. Not SwiftData, not Core Data, not a
hand-rolled SQLite layer. Verify the current SQLiteData API at the start of any
persistence milestone — the library moves fast.

33.2 Sync

Settled (ADR-0002, ADR-0003): each person's library syncs across their OWN devices via
the CloudKit PRIVATE database (SQLiteData's built-in CloudKit synchronization). No
custom backend, no hand-rolled sync engine, no auth. Sync can be deferred in MVP 1, but
the schema obeys the CloudKit basics from day one (UUID primary keys; no reliance on
unique indexes beyond the PK; dedup-on-read for offline multi-device inserts). Sharing
between people is NOT co-editing — it is recipe transfer (send a copy now; a browsable
Family Cookbook via a shared CloudKit zone later). See §2.6.

33.3 Ingredient Parsing

Need to decide:

* Simple custom parser
* Third-party parser
* AI-assisted parser
* Manual-first with optional parsing

Likely starting point: simple parser plus original text preservation.

33.4 Recipe Versions

Settled starting point: capture `Recipe.originalSnapshot` on first save/import and
defer full `RecipeVersion` rows/UI. The snapshot preserves the original structured
content now and can become version 0 later without reworking the user-facing model.

33.5 Grocery Categories

Need to decide whether grocery categories are:

* User-defined
* Fixed defaults
* Store-specific
* Learned over time

Likely starting point: default categories with user override. Keep the model
compatible with Grocy-style store-order grouping/assortments, but do not require
store setup in MVP grocery generation.

33.6 Pantry Scope

Settled starting point: pantry means assumptions and shopping policies, not precise
stock accounting. The app may remember that soy sauce is normally on hand and skip
it by default, but it should not require the user to log every use of soy sauce.
Quantity tracking, minimum stock, expiration, freezer inventory, and "use this up"
workflows are optional future layers, not the base pantry model.

34. MVP 1 Data Model

For the first implementation, use only:

Recipe
RecipeSource
IngredientSection
IngredientLine
InstructionSection
InstructionStep
RecipeNote
RecipePhoto
Tag
Category
Equipment
RecipeTag
RecipeCategory
RecipeEquipment

(A single owner's private library — no Household, Cook, or sharing entities. Recipe
transfer between people is a separate feature, not part of the core schema. See §2.6.)

The first vertical slice keeps `Recipe.lastCookedAt`/`timesCooked` in the schema but
does not expose a manual "mark cooked" action or retrospective-note flow. The meal
planner milestone owns cooking history: past dated `MealPlanEntry` records will
update or derive the last-cooked value. Full `CookingSession` history remains
deferred.

Defer:

CookingSession
MealPlanEntry
ShoppingList
ShoppingListItem
PantryItem
CookingPlan
CookingPlanTask
RecipeVersion
ImportJob
ImportIssue

35. Suggested Initial Swift Type Sketch

This is not final implementation code, but it illustrates the intended shape.

Persistence-shape note: under SQLiteData, persistence records are flat value-type
structs, one per table, related by UUID foreign keys. The nested arrays shown below
(`ingredientSections`, `tags`, `categories`, `equipment`, …) are the *logical*
composition of a recipe, not stored object graphs. They are materialized at read
time via @FetchAll queries over the child tables (using the `recipeID`/`sectionID`
FKs already defined on those entities) and join tables for the many-to-many links
(recipe↔tag, recipe↔category, recipe↔equipment). Do not model these as stored
nested collections on a `@Model` class — that is the SwiftData/Core Data shape this
stack deliberately avoids.

struct Recipe: Identifiable {
    var id: UUID
    var title: String
    var subtitle: String?
    var summary: String?
    var source: RecipeSource?
    var servings: Double?
    var servingsText: String?
    var yieldText: String?
    var prepTimeMinutes: Int?
    var cookTimeMinutes: Int?
    var totalTimeMinutes: Int?
    var activeTimeMinutes: Int?
    var restTimeMinutes: Int?
    var ingredientSections: [IngredientSection]
    var instructionSections: [InstructionSection]
    var notes: [RecipeNote]
    var tags: [Tag]
    var categories: [Category]
    var equipment: [Equipment]
    var cuisine: String?
    var course: String?
    var difficulty: RecipeDifficulty?
    var rating: Int?
    var favorite: Bool
    var archived: Bool
    var dateCreated: Date
    var dateModified: Date
    var lastCookedAt: Date?
    var timesCooked: Int
    var originalImportText: String?
    var originalSnapshot: Data?
}
struct IngredientLine: Identifiable {
    var id: UUID
    var originalText: String
    var quantity: Double?
    var quantityText: String?
    var unit: String?
    var item: String?
    var preparation: String?
    var comment: String?
    var isOptional: Bool
    var shoppingCategory: String?
    var doNotShop: Bool
    var isHeader: Bool
    var sortOrder: Int
    var confidence: ParseConfidence?
}
struct InstructionStep: Identifiable {
    var id: UUID
    var text: String
    var sortOrder: Int
    var isOptional: Bool
}

36. Final Data Model Guidance

The model should be boring, explicit, and hard to corrupt.

The first version does not need to be clever. It needs to be trustworthy.

The long-term power of the app will come from combining:

* Preserved original recipe data
* User adaptations
* Structured ingredients
* Notes from actual cooking
* Meal plans
* Shopping lists
* Prep tasks
* Event context

Do not sacrifice that foundation for premature UI flourish or AI magic.

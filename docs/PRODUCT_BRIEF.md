# Product Brief: Personal Recipe & Cooking Planner

## Working Name

Yes Chef

## Product Thesis

This iOS app is a modern recipe library and cooking-planning tool for serious home cooks who collect recipes from many sources, adapt them heavily, cook for real events, and need more than static recipe storage.

The app is inspired by the best parts of Paprika-style recipe management: reliable recipe capture, personal organization, grocery lists, meal planning, cooking mode, and cross-device access. It is not intended to be a clone. The goal is to build a personal cooking operating system: a tool that preserves recipes, understands adaptations, supports grocery and meal planning, and eventually helps generate realistic prep, shopping, make-ahead, thawing, and cooking plans.

## Primary User

The initial user is an experienced home cook who:

- Has an existing recipe library in Paprika.
- Frequently modifies recipes.
- Cooks from a mix of websites, cookbooks, personal notes, and adapted restaurant-style ideas.
- Hosts dinner parties and family trips.
- Wants practical planning help, not generic recipe inspiration.
- Uses equipment such as sous vide, grill, wok burner, oven, food processor, mixer, and vacuum sealer.
- Cares about food quality, timing, logistics, and repeatability.
- Wants personal cooking knowledge preserved over time.

## Product Positioning

This is not a social recipe network, meal-kit app, diet tracker, or generic AI recipe generator.

It should feel like a private, well-designed, serious cook’s notebook with enough structure to power shopping lists, scaling, planning, and future intelligence.

## Core Promise

The app should let the user answer:

- What recipes do I have?
- What did I change last time?
- What do I need to buy?
- What can I make ahead?
- What needs to thaw?
- What equipment will be in use?
- What am I cooking this week?
- What am I cooking for this event?
- What is the canonical version of this dish?

## Competitive Baseline

Paprika is the functional baseline. The app should eventually support:

- Recipe library
- Web recipe import
- Manual recipe entry
- Categories and tags
- Recipe photos
- Notes
- Grocery lists
- Meal planning
- Pantry awareness
- Recipe scaling
- Cooking mode
- Cross-device sync
- Import/export
- Search
- Timers

The first version should not attempt full parity. It should build the core data foundation first.

## Differentiation

The app should eventually be better than Paprika in the following ways:

### 1. Recipe Adaptation

Preserve the difference between the original recipe and the user’s adapted version.

Examples:

- Original source recipe
- Personal version
- Notes from each time cooked
- Version history
- Substitutions
- Equipment-specific variations
- Scaling notes
- Make-ahead notes

### 2. Serious Meal Planning

Planning should support real meals and events, not just assigning recipes to dates.

Examples:

- Dinner party plan
- Beach-week plan
- Multi-day family cooking plan
- Prep-ahead schedule
- Thawing schedule
- Shopping by location
- Dishes assigned to meals
- Equipment conflicts
- Day-before and day-of task lists

### 3. Ingredient Intelligence

Ingredient data should remain human-readable but become structured enough to power useful workflows.

Examples:

- Ingredient parsing
- Unit normalization
- Shopping-list grouping
- “Already have this” pantry suppression
- Substitution notes
- Prep state recognition: chopped, diced, toasted, grated, cooked, frozen
- Ingredient sections: marinade, dressing, sauce, garnish

### 4. Cooking Memory

The app should remember how the user actually cooks.

Examples:

- “Used 1.5x sauce”
- “Too salty”
- “Worked well frozen”
- “Do not use Publix chicken for this”
- “Buy fish locally”
- “Serve with roasted cabbage”
- “Wife dislikes octopus/cuttlefish/anchovy-forward dishes”
- “Good for beach house cooking”
- “Not worth making ahead”

### 5. Planning Intelligence

Future AI features should be practical and grounded in the user’s actual library.

Good AI use cases:

- Clean imported recipe text.
- Parse ingredient lines.
- Identify make-ahead steps.
- Suggest prep timeline.
- Generate shopping list from a meal plan.
- Identify missing ingredients.
- Suggest substitutions based on prior preferences.
- Flag oven/grill/stovetop conflicts.
- Convert a dinner menu into a realistic day-by-day plan.

Bad AI use cases:

- Generic recipe generation as the main feature.
- Unverifiable nutrition guessing.
- Rewriting recipes in a way that loses source fidelity.
- Overconfident substitutions without user review.

## Initial Platform

Apple-first.

Initial targets:

- iPhone
- iPad
- Mac, if the initial SwiftUI multiplatform setup makes it cheap

Later targets:

- Share extension
- Widgets
- App Intents / Shortcuts
- Possibly web, only if there is a compelling reason

Preferred starting stack (per the `~/code/jon-platform` house style — defer to it):

- SwiftUI multiplatform (`@Observable` feature models, swift-navigation `Destination` enums)
- SQLiteData (Point-Free) for persistence — local SQLite is the source of truth. **Not SwiftData, not Core Data.**
- CloudKit sync via SQLiteData's built-in CloudKit synchronization — no server, no auth (the iCloud account is the identity)
- swift-dependencies for clock/date/UUID/database
- Local-first data model with UUID primary keys

## Product Principles

1. Preserve user data above all else.
2. Never discard original imported recipe text.
3. Prefer explicit user-controlled data over magical transformation.
4. Keep the first version boring and reliable.
5. Build the data model before building clever AI.
6. Make common cooking workflows fast.
7. Avoid social features.
8. Avoid subscription-server dependence for personal recipe storage.
9. Design for adaptation, not just collection.
10. Treat import/export as first-class features.

## Non-Goals for MVP

The MVP should not include:

- Social sharing network
- Public recipe discovery feed
- Nutrition analysis
- Calorie tracking
- Automatic pantry deduction
- Multi-user collaboration
- Payments
- Accounts
- Server backend
- Android
- Web app
- AI recipe generation
- OCR from cookbooks
- Voice assistant
- Complex permission system
- Restaurant-style inventory management

## Success Criteria for Early Version

The first successful version should allow the user to:

1. Browse and search sample recipes stored in the real local schema.
2. Open a recipe in a pleasant, modern detail view.
3. Edit recipe metadata, ingredients, instructions, and notes.
4. Preserve original source text, URL, and a read-only first-saved snapshot.
5. Scale ingredient quantities without overwriting the canonical recipe.
6. Use a cooking-friendly display mode.
7. Preserve last-cooked fields for the future meal calendar without asking the user
   to manually mark recipes cooked in the first slice.
8. Validate the model against a small Paprika export fixture without shipping full import UI.
9. Trust that data will not be silently corrupted.

## Product Bet

Paprika already solves recipe storage well enough for casual users. This app is only worth building if it eventually becomes much better at serious cooking logistics: planning, adapting, shopping, prepping, freezing, thawing, hosting, and remembering what actually worked.

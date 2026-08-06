# Effort — Tandoor idea harvest (declarative correction rules + the import/ingredient model)

**Status:** Harvest — reference notes, no dispatch. Feeds future ADR work; nothing here is ratified.
**Summary:** Concepts mined from Tandoor Recipes (self-hosted OSS recipe manager) — chiefly its
**declarative, row-grain "automation" layer** that corrects import/parse deterministically without an
LLM in the loop. Idea-harvest only: Tandoor is AGPL-3.0, we reimplement concepts in Swift clean-room,
we do not read/port its source. Several ideas turn out to be **convergent** with decisions we already
made independently.
**Related:** [ADR-0051](../decisions/ADR-0051-text-to-recipe-extraction-strategy.md) (one parser, no new
bespoke parser — the guardrail these rules must respect) ·
[ADR-0052](../decisions/ADR-0052-grocery-learned-area-table.md) (persistent learned `canonicalName→area`
table — **already one instance** of the correction-rules pattern below) ·
[ADR-0007](../decisions/ADR-0007-web-recipe-capture-engine.md) (capture engine — where site-scoped
fixups would live) · [ADR-0022](../decisions/ADR-0022-grocery-merge-stays-deterministic.md) (deterministic
data-merge boundary) · [ADR-0040](../decisions/ADR-0040-editable-at-the-grain-it-is-stored.md)
(editable at the grain stored) · [ADR-0004](../decisions/ADR-0004-structured-recipe-editor.md)
(structured recipe model). Concept links: [[llm-vs-determinism-surface-boundary]],
[[editable-at-the-grain-stored]], [[grocery-area-no-learned-cache]], [[galavant-capture-engine-reuse]].

## Why Tandoor is worth mining at all

The marketing surface (scaling, cookbooks, Dropbox sync, themes) is nothing. The one architecturally
interesting thing is that **Tandoor fixes up its import/parse pipeline with user-editable typed rules,
not by re-running a model.** That is exactly the deterministic-correction layer our own architecture
keeps reaching for and hasn't named. It sits precisely on our LLM-vs-determinism boundary, it is
editable at the grain it is stored, and it feeds one parser rather than forking a new one — so it clears
all three of our standing guardrails at once. Everything below is filtered through "does this survive
*our* rules," not "what does Tandoor ship."

## The one big idea: a typed, ordered, row-grain **correction-rules** table

Tandoor's `Automation` is a table of typed rules, each a small row: a `type`, 2–3 string params, and an
`_order` integer (ascending, default 1000) that sequences them. The rules run deterministically over
imported/parsed data. Reproduced concept, in our vocabulary:

| Tandoor rule (concept) | What it does | Our reimplementation angle |
|---|---|---|
| `FOOD_ALIAS` / `UNIT_ALIAS` / `KEYWORD_ALIAS` | match name → canonical name (singularize, unify spellings) | canonicalization rows; overlaps our `canonicalName` machinery and ADR-0052 |
| `NEVER_UNIT` | protect a food-word from being parsed as a unit (`egg` in "egg yolk"); optional param inserts a real unit | **pre-parse nudge** for the deterministic ingredient tokenizer (ADR-0051 floor) |
| `TRANSPOSE_WORDS` | reorder two tokens ("garlic cloves" → "cloves garlic") so amount/unit/food land right | same — a cheap deterministic fix that avoids sending the messy line to the model |
| `DESCRIPTION_REPLACE` / `INSTRUCTION_REPLACE` / `TITLE_REPLACE` / `FOOD_REPLACE` / `UNIT_REPLACE` | **site-scoped** regex `re.sub`: param1 = site pattern (`.*chefkoch\.de.*`), param2 = find, param3 = replace | per-site import fixups living behind ADR-0007's capture engine |

**The insight to keep, in our words:** a bad deterministic parse should become *one addressable row you
add once* and it applies to every future import — never a blob you can only regenerate (that's
[[editable-at-the-grain-stored]]), and never "throw the messy line at the LLM again" (that's the wrong
side of [[llm-vs-determinism-surface-boundary]]). `NEVER_UNIT` and `TRANSPOSE_WORDS` are the clever
members: they make a *dumb* tokenizer get the amount/unit/food split right with a hint, instead of
buying an ML tagger.

**We already have the seed of this pattern:** ADR-0052's learned `canonicalName → area` table *is* a
correction-rules table for exactly one target (store-area placement) — a placement becomes a durable row
that wins over the classifier and loses to the seed and to you. The Tandoor harvest is the
*generalization*: the same "durable, human-authorable, deterministic override row that feeds a
deterministic floor" shape, applied to **ingredient parsing** (amount/unit/food) and **import
normalization**, not just aisle. If we ever build ingredient-parse corrections, it should be the same
table shape and the same win/lose ordering as ADR-0052, not a second bespoke mechanism.

**The trap to leave behind:** Tandoor exposes raw regex + an `_order` priority integer to end users. For
a ~10-user local-first app that is over-built and a foot-gun. Harvest *typed, ordered, row-grain
correction rules*; leave the regex-console UX and the user-facing priority knob. Most of our rule types
want to be structured (match-string → replacement), with regex reserved for the site-scoped import
fixups where it earns its keep.

## Convergent — already decided, logged here so we don't "re-discover" it

- **Supermarket categories with per-store aisle ordering, and drag-to-categorize that _persists_.**
  Tandoor lets you drag an uncategorized item into an aisle and remembers it. This is
  [ADR-0052](../decisions/ADR-0052-grocery-learned-area-table.md) — we arrived at the same "corrections
  stick" answer independently, and in fact ADR-0052 already reverses the earlier no-learned-cache half
  of [[grocery-area-no-learned-cache]]. **Nothing to harvest; noting the convergence as validation.**
- **Import from thousands of sites via JSON-LD / microdata, with a per-site fallback.** This is
  [ADR-0007](../decisions/ADR-0007-web-recipe-capture-engine.md) + [[galavant-capture-engine-reuse]]
  (harvest-now/converge-later). Tandoor's site-scoped `*_REPLACE` rules are the interesting delta on top
  of it — see the table above.

## Second tier — worth a glance, not urgent

- **Ingredient string → `{amount, unit, food, note}` as the canonical parse target.** Matches how we
  already decompose ([[decompose-notes-into-typed-homes]]). If ADR-0051's deterministic floor ever needs
  a reference for fraction/range/unicode-fraction handling, Tandoor's tokenizer is a good *conceptual*
  reference (read the behavior, not the code). The `NEVER_UNIT`/`TRANSPOSE_WORDS` hints above are what
  make such a tokenizer viable without an ML tagger.
- **Step references another recipe (sub-recipes / components).** A step can embed another recipe. Clean
  model if we ever want component recipes (a sauce recipe used inside three mains). Not on any current
  roadmap; parked as a data-model note against [ADR-0004](../decisions/ADR-0004-structured-recipe-editor.md).

## Skip

Cookbooks-as-books, 32 themes, Dropbox/Nextcloud file sync, Google-Keep shopping export, "AI auto-sorts
your steps," image-recognition nutrition. Nothing there we want or don't already have a better-scoped
plan for.

## License note (why harvesting is clean)

Tandoor is **AGPL-3.0**; Recipya (the lighter Go alternative we also looked at) is **GPL-3.0** — both
strong copyleft, both unusable for *code* reuse in a closed iOS app. But copyright protects source
*expression*, not the functional concepts or data-model shapes. This doc is a docs-level, clean-room
reimplementation plan written in our own words; we do not read, translate, or port their Go/Python. The
permissively-licensed engine in this space, if we ever want liftable *code* for web import, is
`hhursev/recipe-scrapers` (MIT) — same category as [[galavant-capture-engine-reuse]].

## If this graduates

The correction-rules generalization is the only piece that could become an ADR, and only when an actual
ingredient-parse pain point justifies it — it should not be built on harvest momentum alone (that's the
[[withdraw-not-defer-orphaned-schema]] lesson: don't ship synced schema ahead of a live consumer). The
right trigger is dogfood evidence that deterministic ingredient parsing is missing the same lines
repeatedly. At that point the design is "ADR-0052's table shape, second target," not a new subsystem.

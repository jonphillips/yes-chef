# Next Up — NYT capture fidelity: ingredient groups, author name, opt-in tags

**Slices:** effort `nyt-capture-fidelity` (Fixes 1–3, one PR)
**Briefs:** [docs/efforts/nyt-capture-fidelity.md](efforts/nyt-capture-fidelity.md)
**Done when:** per the brief § Done when (`check-drift.sh` + generic device build + `YesChefTests`)
**Owed:** Jon's device pass (NYT carrot cake via the in-app browser; a second NYT recipe via the share sheet) → `docs/device-passes.md`
**Notes:** Schema-free. The NYT DOM extractor is per-site hardening inside `RecipePageParser` (Milk Street precedent), not a new front-end; the brief says why the ADR-0051 guard doesn't apply. Tags become opt-in for every site, and the original snapshot keeps the full harvested list.

# Next Up — Menu detail declutter

**Slices:** menu-detail-declutter · S1 + S2 + S3 (one PR)
**Briefs:** [Menu detail declutter](efforts/menu-detail-declutter.md)
**Done when:** Per the brief: the menu toolbar carries Cook these · Add Recipes · Edit · the house AI menu (Hand off submenu, Paste, Ask now) and the Playbook column has no AI controls or toggle; an Edit Menu sheet edits title, notes, days and placements and replaces Place and the Calendar section; dish rows have no trailing action buttons; day headers and empty states are quiet; the ChatGPT Project field and entity property are gone; three custom symbol sets ship; tests, required builds, closeout.

**Owed:** see [device-passes.md](device-passes.md)
**Notes:** Decisions are ADR-0064 D1–D8 (Jon, 2026-11-10). No schema, sync or migration change: `Menu.externalProjectName` stays in the schema, unused. Symbol templates are in `docs/design/symbols/`; use them as given. UI acceptance is a Jon device gate.

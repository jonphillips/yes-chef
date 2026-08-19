# Known issues — beta-sensitive

Bugs we're tolerating for now, especially ones that may be Xcode/SDK **beta**
regressions worth re-checking as the betas evolve. Re-verify each on every new
Xcode 27 beta; delete an entry when it's fixed upstream or we work around it.

## Cross-container drag-and-drop has a beta-sensitive destination path

*Observed on Xcode 27 beta 1; partially re-verified on iPad with beta 5
(`27A5237l`) on 2026-08-19.*

Galavant observed a `List` destination failing to complete cross-section drops
with `System gesture gate timed out`; Yes Chef observed a menu dish row showing
the not-allowed badge. Yes Chef's Browse Recipes panel → day drop now works on
beta 5, so drag-and-drop itself is not broadly broken. The remaining open
platform question is the sectioned iOS 27
`.reorderContainer(for:in:)` path, which this effort exercises for the first
time in either app.

Galavant's `LazyVStack` fallback is **disproven as a diagnosis** by Yes Chef's
beta-5 probe: our plain `VStack` day container accepts the Browse Recipes drop.
The Yes Chef dish-row symptom was instead caused by two stacked
`.dropDestination` modifiers, where the inner destination shadowed the outer.
See the corresponding `galavant/docs/KNOWN-ISSUES.md` entry in the Galavant
repository and [ADR-0055](decisions/ADR-0055-drag-and-drop-on-the-sanctioned-reorder-path.md)
for the cross-repo investigation.

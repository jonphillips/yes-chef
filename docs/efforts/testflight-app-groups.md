# Effort — Let `testflight` verify Yes Chef's second app group (PROD-CUTOVER Step 3a and 3c)

Status: Designed 2026-10-26. Schema-free. Two PRs: jon-platform first, then Yes Chef.
Summary: jon-platform's `scripts/testflight` fails any app with a second application group, and Yes Chef's app
carries two (`group.com.jonphillips.yeschef` and ADR-0058's `group.com.jonphillips.cockpit-yeschef`). Add an
optional `EXTRA_APP_GROUPS` config key, and have the verifier check each bundle's full group set against the
config. Then add Yes Chef's `testflight.conf`.
Related: [`PROD-CUTOVER.md`](../PROD-CUTOVER.md) Step 3 · jon-platform `docs/ios/testflight.md` ·
[ADR-0058](../decisions/) (the cockpit app group)

## Why

`verify_bundle` reads index 0 of `com.apple.security.application-groups` as the group and requires index 1 to be
empty. That was right for Galavant, but Yes Chef's app entitlements (`YesChefApp/YesChef.entitlements`) list two
groups, so every Yes Chef export would fail with `app group or CloudKit container mismatch`. The share extension
(`YesChefShareExtension.entitlements`) has one group and keeps the single-group rule.

## PR 1 — jon-platform `scripts/testflight`

- **Config.** Add `EXTRA_APP_GROUPS` to the allowed keys in `load_config`. It's optional, space-separated, and
  defaults to empty, the same way `EXTENSION_BUNDLE_IDS` does. Reject the config (exit 10) if an entry doesn't
  start with `group.`, repeats an entry, or equals `APP_GROUP`.
- **Verifier.** In `verify_bundle`, read the whole `application-groups` array, not indexes 0 and 1. A
  PlistBuddy loop over indexes until one fails is fine.
  - **The app** (`is_app=yes`): the set of groups must equal `APP_GROUP` plus every `EXTRA_APP_GROUPS` entry,
    in any order. A configured extra that's missing fails, and so does an unlisted group.
  - **An extension** (`is_app=no`): exactly one group, `APP_GROUP`. `EXTRA_APP_GROUPS` never applies to
    extensions.
  - Split the failure line in two: `app groups=<found> expected=<expected>` and `CloudKit container mismatch`.
    That way a failed export says which check failed.
- **Unchanged.** A conf without the key, like Galavant's, behaves exactly as before. Every other check stays as
  it is.
- **Tests** in `scripts/test-testflight`, next to the existing `verify_bundle` cases:
  - an app with `APP_GROUP` plus a configured extra passes;
  - the same app fails when `EXTRA_APP_GROUPS` is unset;
  - an app with an unlisted third group fails;
  - an app missing a configured extra fails;
  - an extension carrying the extra group fails even when it's configured;
  - `load_config` accepts a quoted multi-entry value and rejects each of the three bad values above;
  - one passing case uses Yes Chef's real pair (`group.com.jonphillips.yeschef` plus
    `group.com.jonphillips.cockpit-yeschef`) with its real `testflight.conf` values. The first signed run of
    the verifier is Step 7's upload, during the freeze. A failure there is safe (exit 14, nothing uploaded), but
    this test is what keeps it from happening.
- **Docs.** In `docs/ios/testflight.md` § `testflight.conf` reference, add an `EXTRA_APP_GROUPS` row (No;
  "Further app groups the app, never an extension, may carry"; example `"group.com.jonphillips.cockpit-yeschef"`).
  Reword `APP_GROUP` to "The primary application group; the only one an extension may carry."
- **Verification:** `scripts/test-testflight` passes.

## PR 2 — Yes Chef `testflight.conf`

Add `testflight.conf` at the repo root, exactly as written in PROD-CUTOVER Step 3c. It rides with the chat-access
search fix (the same ticket), and merges after PR 1, because today's script rejects the unknown key.

## Done when

- PR 1 has merged with `test-testflight` green, and Galavant's conf still loads unchanged.
- PR 2 adds `testflight.conf`. The completing Yes Chef PR ticks PROD-CUTOVER 3a and 3c.
- Jon's Step 3e dry run (after his 3b and 3d) then fails only on the schema gate. It checks the config and setup,
  not the verifier: a dry run stops before archiving, so Step 7 is the verifier's first signed run.

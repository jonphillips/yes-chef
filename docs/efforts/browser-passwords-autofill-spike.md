# Spike: In-app browser Passwords / autofill (defending ADR-0009's "never store credentials")

**Type:** Investigation spike — **not an ADR.** The decision is already recorded:
[ADR-0009](../decisions/ADR-0009-in-app-authenticated-browser-capture.md) — in-app authenticated browser
capture works from the *rendered logged-in DOM*, and the app must **never store credentials.** This spike
exists to make that stance *actually usable* by getting system autofill to work in the capture browser,
**not** to reverse it.
**Owner:** Claude (spike/architect) → Codex (implement fix if it's config) · Jon (device pass).
Sourced from Jon's dogfood pass 2026-07-08.

## Why a spike, not an ADR

Jon asked whether to store ATK/NYT credentials client-side or fix the Passwords integration, and chose
**"investigate autofill first."** That is deliberately *inside* ADR-0009's existing decision — a
client-side credential store would **contradict** ADR-0009 ("never store credentials") and would only be
considered if this spike proves autofill is impossible, at which point we'd write an ADR **amendment**,
not a fresh decision. So the near-term artifact is findings, not a new ADR.

## Symptom (Jon, 2026-07-08)

Logging into ATK / NYTimes inside the in-app capture browser is painful; **system Passwords autofill does
not offer saved credentials** the way it does in Safari. Jon wants either working autofill or (rejected
for now) a client-side store.

## What to find out (the spike)

The capture browser is a `WKWebView` (`BrowserViews.swift` — confirm on read). Autofill/QuickType
credential suggestions in a `WKWebView` depend on a specific set of conditions; work through them in
order and report which one is missing:

1. **Associated Domains / AutoFill entitlement.** Does the app declare
   `com.apple.developer.associated-domains` with `webcredentials:` entries for the sites we log into
   (`webcredentials:cooking.nytimes.com`, `webcredentials:www.americastestkitchen.com`, etc.)? Without
   the `webcredentials:` association, iOS won't surface saved passwords for a given domain in an
   in-app web view. (Note the tension: we don't *own* these domains, so a true associated-domains
   handshake — which requires the site to host an `apple-app-site-association` file naming our app —
   **cannot** be arranged for third-party sites. Establish whether QuickType-bar password suggestion in
   `WKWebView` actually requires the AASA handshake, or whether the generic **QuickType credential
   accessory** (the row above the keyboard) is available without it. This is the crux.)
2. **`WKWebView` text-input config.** Is anything suppressing the QuickType/AutoFill accessory —
   `textContentType`, `isSecureTextEntry` handling, a custom `inputAccessoryView`, or JS that swaps the
   native inputs? Confirm the login fields are ordinary `<input type=password>`/username fields the
   system can recognize.
3. **Keyboard settings / device state.** Confirm on the device pass that Passwords AutoFill is enabled
   in Settings and the credentials exist in the user's Passwords for those domains (rule out a
   test-environment red herring before chasing entitlements).
4. **What Safari-View-Controller would give us instead.** If `WKWebView` fundamentally can't surface
   third-party-domain autofill, note whether an `SFSafariViewController`-based capture path would (it
   inherits Safari's autofill) — and what that costs us for **DOM capture** (SFSafariViewController does
   **not** expose page DOM to the host app, which is the whole point of ADR-0009's `WKWebView` choice).
   This is the likely core tension to surface for Jon: **DOM-capturable (`WKWebView`, weak autofill)**
   vs. **autofill-rich (`SFSafariViewController`, no DOM access).**

## Deliverable

A short findings note back to Jon: which of (1)–(4) is the blocker, whether it's a **fixable config**
(entitlement / input config — hand to Codex) or a **platform constraint** (the WKWebView-vs-SFSafari
tension — a decision for Jon that may warrant an ADR-0009 amendment). **No credential storage is
implemented as part of this spike.**

## Out of scope

- Building any client-side credential store (contradicts ADR-0009 unless/until an amendment says
  otherwise).
- Any change to the capture/extraction pipeline itself.

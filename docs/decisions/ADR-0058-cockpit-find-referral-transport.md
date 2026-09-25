# ADR-0058 — Cockpit Find referrals travel through a **pair-scoped App Group mailbox**, opened by a **single-purpose `yeschef://find-referral` door**; the verdict returns silently

Status: **Accepted — 2026-09-24.** D1, the transport choice, was ratified by Jon in Cockpit's plan
([jonphillips/cockpit#81](https://github.com/jonphillips/cockpit/pull/81)), which also records it as a
narrow exception to Cockpit's `APP-FAMILY-INTERACTION.md` §9. D2–D6 were accepted on the merge of
[#324](https://github.com/jonphillips/yes-chef/pull/324), and all six were built in
[#325](https://github.com/jonphillips/yes-chef/pull/325). Worked design + slice detail:
[`../efforts/cockpit-find-handoff-receiver.md`](../efforts/cockpit-find-handoff-receiver.md). Amends
[ADR-0053 Amd2-D3](ADR-0053-create-recipe-destination.md#amd2-d3--reuse-the-shipped-operation-no-new-parser-no-url-scheme)
(no URL scheme) for this one door; Amd2-D1/D2/D4 are unchanged.

## Context

Cockpit's M6 Gate 5 makes Yes Chef the first receiver of a cross-app Find referral. Cockpit sends raw
text, provenance, and an opaque `referralID`. Yes Chef owns all recipe intelligence and returns a
set-valued verdict. [PR #322](https://github.com/jonphillips/yes-chef/pull/322) built the receiver's
compute: 0/1/N extraction, referral staging in Create Recipe, and an exactly-one-verdict coordinator. It
left the return behind the `FindReturnEmitter` seam as a logging stub, because **no public API lets one
app invoke another app's App Intent**. App Intents surface to system experiences (Shortcuts, Siri,
Spotlight, widgets), never to peer apps.

That finding breaks the original contract in **both** directions. Cockpit cannot call
`CaptureRecipeFromText` any more than Yes Chef can call a Cockpit intent. Today there is no path from
Cockpit into Yes Chef at all. Yes Chef has no URL scheme (ADR-0053 Amd2-D3), and its share extension
accepts only web pages and URLs.

## Decisions

### D1 — The channel is a pair-scoped App Group mailbox (ratified)

A **new** App Group, `group.com.jonphillips.cockpit-yeschef`, entitled on both apps (team `7MQEE539G9`),
holds two folders:

- `find-referrals/<referralID>.json` — written by Cockpit, consumed by Yes Chef.
- `find-verdicts/<referralID>.json` — written by Yes Chef, consumed by Cockpit.

Writers write atomically (temp file + rename). **The consumer deletes a message once it has taken what
it needs.** The mailbox holds messages in transit, never records, so custody stays per-app: the
referral is an admission request, not shared ownership. Yes Chef's existing
`group.com.jonphillips.yeschef` stays share-extension-only. Letting Cockpit join it would expose Yes
Chef's share-extension container. No third app joins the pair group; a second receiver reopens the
transport question from scratch.

### D2 — One single-purpose URL door: `yeschef://find-referral?id=<referralID>` (amends ADR-0053 Amd2-D3)

Amd2-D3 declined a URL scheme because "minting one to do what a coordinator already does" is the new
navigation stack ADR-0046 refuses. That reasoning holds for every in-app and Shortcuts door. It does not
hold across apps: no coordinator is reachable from Cockpit, and opening another app is exactly what a URL
scheme is for. So Yes Chef registers the `yeschef` scheme with **exactly one** recognized form:

- host `find-referral` plus the single query item `id`;
- the handler reads `find-referrals/<id>.json`, decodes a `FindReferral`, and calls
  `CreateRecipeCoordinator.stage(referral:)`, the same staging path #322 built;
- **anything else is ignored** (logged to `AppLog.handoff`, no navigation);
- no routing table, no general deep links, no section selection outside the coordinator.

ADR-0046's "no new navigation stack" holds. The door is a front-end to an existing coordinator, just as
Amd2-D3 required of the Shortcuts door. The body travels in the file, never in the URL. A missing or
undecodable file is logged and ignored; Cockpit detects the unconsumed or failed referral on its side.

### D3 — `CaptureRecipeFromText` returns to Amd2-D1's producer-agnostic shape

#322 put `provenance` (a JSON string) and `referralID` on the Shortcuts intent, because the intent was
then going to be Cockpit's door. It isn't. Those parameters now show up in the Shortcuts editor as
"Provenance JSON" and "Referral ID" fields that no person should ever fill in. Remove them. The intent
takes text only, as Amd2-D1 specifies. `stage(referral:)` is reached from the D2 door only.

### D4 — The wire format is frozen by golden fixtures, not a shared package

Both messages are UTF-8 JSON with `"version": 1` and **ISO-8601** dates. `JSONEncoder`'s default
`.deferredToDate` is banned: two hand-maintained copies would disagree silently. `FindReferral` /
`FindProvenance` / `FindVerdict` stay in `YesChefCore` and gain **hand-written** `Codable` against the
fixtures in the effort doc. Synthesized enum coding (`{"admitted":{"_0":…}}`) is banned. Cockpit keeps
its own copy against the same fixtures. There is no shared package.

### D5 — Exactly one verdict per referral survives process death; drop abandon-on-scene-background

#322 guarantees one verdict per referral *within a process*: on leaving Create Recipe, on a superseding
intake, and on **scene background**. The background trigger existed because the return transport might
be a foreground URL hop, which cannot fire later. Under D1 a verdict can be written at any time. The
background trigger has also become harmful:

- a glance back at Cockpit mid-review emits `.dismissed` and clears the referral;
- a save after returning then goes unreported, so Cockpit shows the Find as re-sendable although the
  recipe was saved.

Instead:

- **Persist the outstanding `referralID` device-locally** (`UserDefaults`, never synced) when staging,
  and clear it when its verdict is written. Only the id is persisted. The body stays in memory, so
  Amd2-D4's "no durable pending-import table" holds.
- **On launch**, an outstanding id with no live session means the process died mid-review, so emit
  `.dismissed` for it.
- **Remove the `scenePhase == .background` abandonment.** Keep leaving Create Recipe and a superseding
  intake as the in-process triggers.
- **Order the D2 handler as stage → persist the id → delete the referral file**, so a death at any
  point leaves a state one side can detect.

A referral left open while Yes Chef sits backgrounded is **visible** on Cockpit's side as "Sent to Yes
Chef" and resolves when Jon returns and leaves Create Recipe. That is pending, not stranded.

### D6 — The live `FindReturnEmitter` is the mailbox writer

`FindReturnEmitter.liveValue` becomes an atomic write of `find-verdicts/<referralID>.json`, replacing
#322's logging stub; the seam and its call sites are unchanged. A write failure (e.g. the container is
unavailable) is logged to `AppLog.handoff` and leaves the outstanding id in place, so the next launch
retries by emitting `.dismissed`.

## Consequences

- Yes Chef gains its first URL scheme, a second App Group on the app target, and a device-local
  outstanding-referral key. It gains no synced schema, no durable staging, and no new parser.
- The cook's flow is unchanged: Create Recipe review opens with the referral's context, they finish in
  the moment, and nothing asks them for an id.
- Cockpit reads a verdict silently on its next foreground. It treats `noRecipeFound` / `duplicate` as
  quality signal, and `dismissed` / `extractionFailed` as "not admitted, re-sendable." Under the v1
  one-of-N review UI, one admitted outcome is a complete verdict.

## Rejected alternatives

- **App Intents both ways** (the original contract): no public API for a peer app to invoke another
  app's intent.
- **URLs both ways (`yeschef://` out, `cockpit://` back, x-callback style):**
  - the whole body would ride in a URL, and the practical size limit is unverified;
  - a backgrounded app cannot open a URL, so verdicts emitted on abandonment or process death would
    strand the Find.

  A "back to Cockpit" hop remains a possible convenience on top of D1, never the delivery path.
- **Joining Yes Chef's existing App Group:** exposes the share-extension container to Cockpit.
- **Keeping the referral parameters on `CaptureRecipeFromText`:** a second door into
  `stage(referral:)`, and one a person could fill by hand.

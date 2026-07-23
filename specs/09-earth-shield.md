# Add Earth Shield as a one-time-unlock defense game

**Type:** Feature
**Priority:** P2 — normal planned product work; it adds a premium game but does
not block the existing Rockimals experience.
**Risk:** High

## Problem / Opportunity

Rockimals' current games teach real asteroid facts through quizzes, sorting,
memory, and short action challenges, but none offers an escalating arcade loop.
An Earth-defense game would add immediate, replayable play while using the same
NASA size and velocity data.

The original "destroy Earth" framing is too frightening for Rockimals and could
suggest that real near-Earth flybys are on collision paths. The opportunity is
to retain the satisfying tap-to-protect mechanic as a clearly fictional shield
training simulation, with gentle failure language and scientifically honest
data attribution.

This is also Rockimals' first paid feature. The unlock must preserve the app's
no-login, no-advertising, child-safety model and use the native App Store and
Google Play purchase flows behind the existing parent gate.

## Proposed Solution

Add **🛡️ Earth Shield** to the Play hub as an endless portrait game for the
standard Rockimals experience. Earth remains at the bottom behind a
1,000-energy shield. Runaway space rocks enter from the top; tapping a rock
deflects it before impact. Shield energy reaching zero ends the run with a
repair-and-retry summary rather than destruction or "game over" language.

Use the shared live/cached/fallback asteroid feed without another NASA request.
The bundled fallback asteroids are a complete, deterministic local play pool, so
launching, balancing, and testing never depend on a network response:

- Relative velocity maps from 3–30 km/s to a base crossing time of 6.2–2.8
  seconds.
- The existing animal size ladder determines durability: Mouse–Fox needs one
  tap, Tiger–Bear two, and Elephant–Whale three. Cracks and hit reactions make
  the remaining durability visible; the UI never asks for an unexplained
  "double-click."
- A missed rock removes shield energy using the existing Power formula, made
  explicit here for balancing and tests:
  `clamp(round(3 * (9 * log10(diaMax + 1) + 2 * min(6, 10 / (missLunar + 0.4)) + velKps / 9 + (hazardous ? 2.2 : 0))), 40, 180)`.
  This is the current `powerStars(asteroid)` result, clamped for playability.
- The copy identifies this as a playful simulation inspired by today's real
  visitors, not a representation of their actual paths.

Difficulty increases every 15 seconds. Spawn interval begins at 1.4 seconds,
drops by 0.1 seconds per band to a 0.45-second floor, and permits at most ten
simultaneous rocks. Falling duration uses
`max(0.55, 1 - 0.04 * completedBands)` as its difficulty multiplier. A
deterministic large visitor appears every 20–35 seconds when the feed contains a
suitable asteroid.

Direct saves build a combo; every five consecutive saves increases the score
multiplier by one, capped at ×5, and an impact resets it. Ten direct saves fill
a power meter, allowing one of:

- **Freeze:** pause rocks and spawning for three seconds.
- **Repair:** restore 150 shield energy, capped at 1,000.
- **Pulse:** deflect all visible rocks for half score without extending combo.

Award lifetime Rockimals points when a run ends:
`min(100, savedRocks * 2 + floor(survivalSeconds / 15) * 5)`. Persist best
score, best survival time, and most rocks saved.

Provide 60 cumulative seconds of active play once per app installation on one
device, stored locally as consumed milliseconds; it is neither account-synced
nor recoverable after reinstall. Paused, backgrounded, covered, and purchase
time does not consume the trial. When it is exhausted, freeze safely at the run
summary and offer **Ask a grown-up to unlock** or **Not now**. A parent-gated,
non-consumable product named `earth_shield_forever` permanently unlocks the
mobile game for the purchasing platform-store account at a base price of 2.99,
displaying the store's localized price. The verified store transaction is the
entitlement authority; a local cache only enables already-unlocked offline
play. Put both Purchase and Restore Purchases behind the parent gate. The web
build remains trial-only and shows mobile-app availability without an external
checkout link.

## Scope

### MVP

- Pure, deterministic game rules for spawning, damage, durability, difficulty,
  combo, powers, scoring, and run completion.
- One ticker-driven animated game screen integrated with the shared game timer,
  sound, reaction, points, badge, Calm Motion, and app-lifecycle systems.
- A Play hub card and derived game-count update; hide the card in Little Kids
  mode.
- Hive fields for per-install trial milliseconds, an offline entitlement cache,
  and the three personal bests; the cache is refreshed only from a verified
  store purchase or parent-gated restore.
- Flutter `in_app_purchase` integration initialized early enough to receive
  new, pending, and restored transactions; complete successful purchases.
- Parent-gated purchase and restore UI with loading, unavailable, pending,
  cancelled, failed, purchased, and restored states.
- Store-product setup notes and sandbox/manual verification steps for both
  platforms.

### Nice to have after MVP

- Additional powers, cosmetic shield styles, authored wave campaigns, and
  permanent upgrade/loadout systems.
- Server-side receipt verification and refund/revocation handling.
- A non-purchasing gentle variant for Little Kids mode.

## Acceptance Criteria

- [ ] Earth Shield appears as the eleventh Play game for the standard
      experience, is absent in Little Kids mode, and uses the shared
      live/cached/fallback asteroid feed without a new NASA request.
- [ ] Real velocity, size class, and `powerStars` deterministically control
      crossing time, visible one-to-three-tap durability, and shield damage;
      all rocks remain at least 48dp tappable and the fallback feed can sustain
      an endless run.
- [ ] A run begins with 1,000 shield energy, applies the specified difficulty,
      combo, Freeze/Repair/Pulse, score, and lifetime-point rules, and ends only
      at zero with a gentle summary that persists all three personal bests.
- [ ] Exactly 60 seconds of cumulative foreground, unpaused gameplay is free
      per installation on one device; remaining time survives restart, no
      inactive time is charged, reinstall resets the trial, and exhausted trial
      access cannot start another mobile run without entitlement.
- [ ] Purchase and restore are available only after the parent gate; a verified
      platform-store transaction is the entitlement authority, while its local
      cache enables offline use. Pending, cancellation, store-unavailable, and
      failure states neither unlock nor lose trial/accounting data.
- [ ] Sound carries no required information, Calm Motion removes rotation,
      shake, and heavy particles without changing collision timing, timers pause
      for lifecycle/overlay interruptions, and the game works without overflow
      at 320×568 and enlarged text.
- [ ] iOS and Android sandbox purchase/restore/pending flows, the web trial-only
      ending, `dart format`, `flutter analyze`, and the full Flutter test suite
      all pass.

## Out of Scope

- A separate Earth Shield application, landscape mode, multiplayer,
  leaderboards, accounts, advertising, analytics, premium currency, loot boxes,
  subscriptions, consumable purchases, or external web checkout.
- Claims that real asteroids are approaching Earth on impact paths, direct
  depiction of Earth being destroyed, or frightening failure copy.
- Procedurally invented asteroid facts, new NASA endpoints, or a physics-engine
  dependency.
- Upgrade economies, loadouts, campaigns, additional purchasable games, or
  bundling this entitlement with future premium content.
- Backend receipt validation, cross-platform entitlement sharing between Apple
  and Google accounts, and automatic refund revocation in this client-only
  release.

## Open Questions

- Who will create and approve the `earth_shield_forever` products, localized
  metadata, tax category, and 2.99 price tier in App Store Connect and Google
  Play Console?
- Which Rockimals release should contain the feature, and must its store
  submission update the app's Kids/Families monetization disclosures?
- Should a later security iteration add first-party receipt validation, or is
  the documented client-only entitlement risk acceptable beyond the MVP?

## Suggested Next Step

Use `$ralph` to turn this clarified work item into an implementation spec and
small verified slices: pure game rules, animated screen, persistence/trial,
Play hub integration, billing abstraction, native purchases, and store sandbox
verification.

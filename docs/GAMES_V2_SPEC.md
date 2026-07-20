# Rockimals — Games v2: More Fun, NASA-Powered Play

**Status:** planned · **Targets releases:** 1.1 → 1.3 (v1.0 ships first, unchanged)
**Owner:** Ibrahim · **Drafted:** 2026-07-20 (reviewed against live app testing of build 1.0.0+2)

Rockimals moves beyond four quiz-style games into different kinds of play:
exploration, dragging, timing, building, and memory. This spec merges the
improvement plan with findings from hands-on testing of the current build, and
folds the remaining 1.0 polish items into the foundation work.

---

## Design rules (every game must satisfy all of these)

1. **Real NASA data changes the gameplay or the correct answer.** If a game
   would play identically with made-up numbers, it doesn't belong here.
2. **One clear idea per game** — size, distance, speed, or arrival date.
3. **A round is understandable in under 10 seconds and lasts 30–90 seconds.**
4. **No one-mistake endings.** Mistakes teach; they never slam the door.
   (Guardrail: wrong answers are always encouraging — `CLAUDE.md`.)
5. **Deterministic.** Same feed + same date ⇒ same missions, same answers.
   Seed all generation from the date and asteroid designations, exactly as the
   radar seeds orbit phases. Criteria with possible ties ("fastest") must
   accept *any* animal satisfying the criterion.
6. **Offline-first.** Every game reads the existing `AsteroidFeed` (live or
   fallback) — no new network calls anywhere.
7. **Playable without sound or motion.** Sound is garnish (it is already
   broken on web and must never carry meaning). A Calm Motion setting slows
   animations without changing facts or difficulty.
8. **Shared shell.** Lives, the Next button, feedback explanations, and badge
   handling live in the common game shell (`GameShell`) once — individual
   games must not reimplement them.

---

## Item 1 — Game foundation & 1.0 polish (P1, no dependencies)

The prerequisite for everything else. Combines the tester-reported issues with
the bugs found in the 1.0 test pass.

**Fixes (bugs):**
- **Badges never block play.** Badge popups (a) pause any round timer, (b) are
  wrapped in `IgnorePointer` so they never swallow taps (observed: the
  "Lift Off" toast ate the first Power Duel tap), and (c) queue until the
  current answer's feedback has been shown (observed: "Mouse Scout" covered
  Animal Match feedback while its timer kept running).
- **First-load glyph boxes (web).** Preload icon/emoji fonts; no essential
  control may rely on an emoji glyph alone.

**Gameplay changes:**
- **Three lives** in Power Duel and Closer or Farther (replacing sudden
  death). Streak bonuses stay; losing a life shows which rule would have won.
- **Player-paced feedback.** A **Next** button after every answer (current
  ~0.95–1.4 s auto-advance is too fast for the age band). Auto-advance
  remains as a fallback after 6 s of inactivity.
- **Educational feedback.** Every answer explains *why*:
  "Ziggy wins — he's bigger **and** passed closer." Wrong answers state the
  rule gently, not just the outcome.
- **Softer endings.** Replace "GAME OVER 0" with warm copy:
  "What a flight! ⭐ 20 points · best streak 2 — go again?"
- **Teach the hidden systems.** A skippable, replayable (from Settings)
  30-second tutorial: "Power = bigger + closer + faster" and the Mouse → Whale
  size ladder. First-time players get one unscored practice round per game.
- **Daily Challenge scoring made legible.** Show both measures:
  "Order accuracy: 83% · Exact positions: 2/4" (pairwise correctness vs exact
  slots), so the points make sense. Allow **drag to reorder** with
  tap-to-rank retained as the accessible alternative.
- **Short-phone layout (320×568).** Compact the points header so all four
  games are visible, or add a "4 games" indicator + scroll cue.

**Copy/consistency polish (from the 1.0 test report):**
- Kid-friendly dates everywhere: "flew past yesterday", "today → in 2 days"
  (never raw `2026-07-18`).
- Rename the bottom tab **Watchlist → My Animals** to match its screen title
  and the spec's follow-language.
- "≈ 1.3× the Statue of Liberty" (capitalise); one rounding rule for speeds
  (15.9 km/s on the card must not become 16 km/s elsewhere).

**Acceptance criteria:**
- [ ] Badges never hide or delay timed feedback, and never intercept taps.
- [ ] No game ends on a single mistake.
- [ ] Every incorrect answer teaches the rule that decided it.
- [ ] First-time players get one unscored practice round; tutorial is
      skippable and replayable.
- [ ] All games fully playable with sound off and Calm Motion on.
- [ ] All four games discoverable at 320×568.
- [ ] No raw ISO dates or "GAME OVER" text anywhere kid-facing.

---

## Item 2 — Radar Safari (P1, depends on Item 1)

Missions on the existing live radar — a scavenger hunt that makes the radar
itself the toy and proves every animal is real, current NASA data.

- "Find the fastest animal." · "Find an animal visiting inside 10× the Moon."
- "Find today's smallest visitor." · "Find a close-flyby animal waving hello."
- Later missions combine properties: "Find a Fox faster than 15 km/s."

Correct animals celebrate; incorrect taps reveal a gentle hint (never end the
game). After two misses, the hint points at the target's region.

**NASA fields:** `diaMax`, `missLunar`, `velKps`, `date`, softened close-flyby flag.

**Acceptance criteria:**
- [ ] Every target derives from the current feed; missions are solvable with
      offline sample data.
- [ ] Mission set is deterministic for a given date + feed.
- [ ] Tie-safe: any animal satisfying the criterion is accepted as correct.
- [ ] Incorrect taps never end the game; a hint appears after two misses.
- [ ] Each completed mission restates the supporting NASA fact.

## Item 3 — Moon Lanes (P1, depends on Item 1)

Drag approaching animals into distance lanes: **inside the Moon · 1–5× ·
5–20× · farther**. Teaches the app's most important unit through touch.

Difficulty is adaptive: everyone starts with two lanes; sustained success
unlocks three, then four. (No separate "Little Kids mode" — adaptivity covers
it without settings UI.)

**NASA field:** `missLunar`.

**Acceptance criteria:**
- [ ] Real miss distance determines the correct lane; the actual value is
      revealed after every drop.
- [ ] Incorrect drops bounce back with encouragement (a life-free game).
- [ ] Lanes adapt 2 → 4 with success, and back off after struggles.
- [ ] A round lasts ≤ 60 seconds.

## Item 4 — Flyby Snap (P2, depends on Item 1)

An animal crosses a photography window; tap when it's in the frame. Real
velocity scales the animation speed (with clamped min/max so 3 km/s is never
boring and 30 km/s is never impossible). Copy presents it honestly: a playful
animation *inspired by* the real speed, not a simulation.
After each attempt: "Great shot! Bella was travelling 19 km/s."

**NASA field:** `velKps`.

**Acceptance criteria:**
- [ ] Real velocity measurably changes difficulty, within clamps.
- [ ] A missed photo always gets a second attempt.
- [ ] Calm Motion slows the animation without changing the stated fact.
- [ ] The real speed is revealed after every attempt.

## Item 5 — Size Stack (P2, depends on Item 1)

Build a space-animal tower: big animals are stable foundations, small ones go
on top. Correct placements grow a combo; wrong ones wobble but are recoverable.
Implementation note: simple spring/wobble animation, no physics engine — keep
per-frame allocations low (same budget rule as the radar loop).

**NASA field:** `diaMax` + the existing Mouse → Whale ladder.

**Acceptance criteria:**
- [ ] Real diameters control sprite size and correct ordering.
- [ ] The size ladder is introduced before scoring begins.
- [ ] Towers grow from four to seven animals with success.
- [ ] Wrong placements wobble and are recoverable — never an instant fail.
- [ ] The result compares the largest and smallest real diameters.

## Item 6 — Space Zoo Memory (P2, depends on Item 1)

Animals appear with one fact each; the facts hide; reconnect them.
"Which animal flew closest?" · "Who was fastest?" · "Which one was Bear-sized?"
Easy mode keeps avatars visible; harder modes hide facts and positions.

**NASA fields:** `diaMax`, `missLunar`, `velKps`, `date`.

**Acceptance criteria:**
- [ ] Every card uses a real NASA fact from today's feed.
- [ ] Difficulty spans two to five animals; no one-mistake game over.
- [ ] Rounds are built to exclude ambiguity (duplicate names or equal values
      for the asked question can never appear in one round).
- [ ] Results replay the facts in plain language.

## Item 7 — Daily Data Quest (P2, depends on Items 2–6, ≥3 games shipped)

A three-part daily mission from today's visitors: find an animal on the radar
→ complete a size/speed/distance challenge → finish with a short action game.
Completion earns a **daily mission patch**. Missing a day never removes
anything — no long-streak pressure (the existing 🔥 streak chip must not gate
or punish the quest).

**Acceptance criteria:**
- [ ] Generated deterministically from today's feed; works cached/offline.
- [ ] Rotates game types to avoid repetition.
- [ ] Missing a day never removes rewards.
- [ ] Completion takes ~3 minutes.

---

## Delivery order & release mapping

| Release | Contents |
|---|---|
| **1.0** | Ships now, unchanged — this spec does not block the current submission. |
| **1.1** | Item 1 (foundation + polish), then **Radar Safari** + **Moon Lanes**. Playtest before going further. |
| **1.2** | **Flyby Snap** + **Size Stack**. |
| **1.3** | **Space Zoo Memory** + **Daily Data Quest** + Play screen reorganised into **Daily · Explore · Quick Play · Build**. |

Radar Safari leads because it makes the existing radar interactive, feels
different from the current quizzes, and proves the live-data promise. Moon
Lanes follows because it teaches the app's core unit — distance from the Moon
— through a tactile activity.

## Engineering constraints (apply to every item)

- All games read the shared `AsteroidFeed`; zero new network calls.
- Deterministic generation seeded by date + designation (test like the
  AnimalSystem math — pure functions, unit-tested).
- Follow repo conventions: feature-first folders (`lib/features/games/…`),
  `dart format lib test` clean, `flutter analyze` clean, tests for scoring/
  generation logic, works on iOS + Android + web.
- Kids-safety guardrails unchanged: no new permissions, no data collection,
  gentle copy throughout, external links stay behind the parent gate.

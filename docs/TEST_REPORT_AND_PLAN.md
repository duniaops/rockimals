# Rockimals — Pre-submission test report & fix plan

Tested 2026-07-19/20 on the release web build (same Flutter code as the iOS
binary), phone-sized viewport, driven end-to-end. iOS build 1.0.0 (1) is already
uploaded and "Ready to Submit"; nothing found blocks review, but a few things
are worth fixing before the screenshots are taken.

## What was verified working ✅

- **Title screen** — Rusty, tagline, Play button; matches the prototype design.
- **Radar** — Earth-centred orrery animates smoothly; Moon-relative rings
  (1×–50×); planet backdrop; pause/zoom controls work; tap-to-select works;
  header stats ("8 visiting today", "closest 23× Moon") are correct.
- **Live NASA data** — the app is on the real NeoWs feed (current window
  2026-07-18 → 2026-07-20, "today" provenance, 8 objects). Fallback path
  reviewed in code: never throws, always yields a playable sky.
- **Meet card** — friendly stats (HOW WIDE / FAST / CLOSE / POWER), size
  comparison vs Statue of Liberty, distance slider, Follow toggle persists.
- **Parent gate (guideline 1.3 critical)** — wrong answer rejected with gentle
  copy; correct answer opens the right JPL page for that exact asteroid. Real
  designation appears only in "grown-up facts". ✅ Review-safe.
- **Power Duel** — win (+10 ⭐, streak, glow) and lose (encouraging "So close!
  Try the next one 💪") flows; points persist to hub and Zoo.
- **Badges/Zoo** — "Lift Off" badge awarded; progress bar to next badge;
  stats tiles correct.
- **Watchlist** — followed animal appears with approach date; persists.
- **The Sky list** — full window list with Closest/Biggest/Fastest sorting.

## Bugs found 🐛 (ordered by priority)

1. **Distance-slider label collision (visible, fix before screenshots).**
   On the meet screen, for distant asteroids (e.g. 177× Moon) the "Earth" and
   "Moon" labels at the slider's left end render on top of each other,
   producing garbled text ("PaMbon"). Visible on most asteroids' meet pages —
   would appear in App Store screenshot #2.
   *Fix:* hide the Moon label (or merge into "Earth·Moon") when the Moon's
   position is within ~24 px of the left end.

2. **Web-only: sound engine floods console with handled TimeoutExceptions.**
   Every cue on web times out after 2 s (autoplay/platform quirk in
   `sound_engine.dart`). Handled — nothing crashes — but it violates the
   "no console errors" definition of done on web. iOS device is likely fine.
   *Action:* verify sounds are audible in the TestFlight build; optionally
   short-circuit `ToneSoundEngine` behind `kIsWeb` later. Not an iOS blocker.

3. **Possible tap-swallowing by badge toast.** First tap on a Power Duel card
   did nothing while the "New badge! Lift Off" toast was fading. Couldn't
   reproduce deterministically. *Action:* check the toast is wrapped in
   `IgnorePointer` during its exit animation. Low priority.

## Improvements 💡 (non-blocking, could ship in 1.0.1)

4. **Soften "GAME OVER".** Sudden-death after one miss plus a stark "GAME
   OVER 0" reads harsh for ages 6–8, against the "calm & playful" guardrail.
   Consider "What a flight! ⭐ 10 points" + maybe 3 misses per run. (Check
   prototype first — the golden rule is port, don't reinvent.)
5. **Kid-friendly dates.** Raw ISO dates leak into kid-facing UI:
   "approach 2026-07-18" (Watchlist) and "Showing 2026-07-18 → 2026-07-20"
   (Sky). Friendlier: "flew past yesterday", "today → in 2 days".
6. **Naming consistency.** Bottom tab says "Watchlist"; the screen is titled
   "My Animals" (the spec's follow-language). Rename the tab to "My Animals".
7. Animals drifting behind the floating zoom buttons can't be tapped there.
8. Capitalise "≈ 1.3× the Statue of Liberty".
9. Speed rounds differently on card (15.9 km/s) vs Watchlist (16 km/s).

## Recommended path to submission

1. Fix **#1** now (one widget change), run `flutter analyze` + `flutter test`,
   commit.
2. Bump build to 1.0.0+2, rebuild the IPA, upload via Transporter (10 min).
   — or accept the glitch in build 1 and fix in 1.0.1; but since screenshots
   would immortalise it, fixing first is better.
3. Take the five screenshots from the fixed build (web capture at 1284×2778).
4. Attach build + screenshots in App Store Connect → Add for Review.
5. Queue #4–#9 for a 1.0.1 polish release while 1.0 is in review.

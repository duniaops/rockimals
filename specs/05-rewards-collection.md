# 05 — Rewards, Reactions, Collection & Profile

**Goal:** The feel-good loop — points, animal badges with celebration popups, happy/
sad reactions with sound, plus the My Animals list and the My Space Zoo profile.

**Depends on:** 04 (games award through this), 03 (Follow), 02 (streak/stat strip).

**Reference:**
- Prototype `index.html`: `addPoints()/checkBadges()/drainBadges()`, the `ZBADGES`
  table, `react()`, the `hop`/`wob` keyframes, the WebAudio `playHappy/playSad/
  playCheer`, the badge popup, `renderProfile()` (My Space Zoo), `renderWatch()`
  (My Animals).
- Spec §8, §5.1 (My Animals, My Space Zoo).

## Build

### Points
- A single points total, persisted on-device, accumulating across all games
  (default +10 per correct; Challenge by accuracy). Points never decrease.

### Reactions ("juice")
- **Correct:** the animal avatar does a **hop + 360° spin** (~0.85s) with a short
  rising jingle. **Wrong:** a gentle **wobble** (~0.65s) with a soft two-note "aww"
  and an encouraging line. Use `AnimationController` per avatar for the motion.
- **Sound:** synthesized tones (or a few tiny bundled clips). Honour a **global
  sound on/off** toggle (persisted). No audio asset dependencies required.

### Animal badges (the collection meta-game)
- Port the badge set (Appendix B / prototype `ZBADGES`): **Lift Off** (first game),
  point tiers **Mouse Scout / Fox Explorer / Bear Ranger / Elephant Expert / Whale
  Master** (50/150/300/600/1000), **On Fire** (5 in a row), **Zoo Keeper** (follow
  3), **Perfect Match** (8/8 Animal Match).
- When a badge is newly earned, show a **celebration popup** (bouncing badge +
  fanfare, tap to continue). Queue multiple unlocks. Persist earned badges.

### My Animals (Watchlist tab)
- The followed animals, each with avatar, name, size, and a next-approach note.
  Friendly empty state prompting the first follow.

### My Space Zoo (Profile tab)
- Big **points** counter + a progress bar to the **next animal badge**; quick stats
  (badges earned, best streak, animals followed); and the **badge shelf** (earned
  lit, locked dimmed with their goal).

## Acceptance criteria
- [ ] Correct answers play the hop+spin+jingle; wrong ones the wobble+aww +
      encouraging message; the sound toggle mutes all audio.
- [ ] Points accumulate across games and persist; the profile bar shows progress to
      the next badge.
- [ ] Earning a badge shows the celebration popup (queued if several); earned
      badges persist across launches.
- [ ] Following animals fills My Animals and can unlock Zoo Keeper.
- [ ] My Space Zoo shows correct points, badges, streak, and follow count.

## Verify
- Play until several badges unlock; restart and confirm points/badges persisted.
- Toggle sound off and confirm silence; confirm reactions still animate.

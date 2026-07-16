# 04 — Games: Framework + the Four Games

**Goal:** A Play hub and four playable games, all using the shared animal data and
the reaction system (reactions/sound/points wiring lands in task 05 — build the
hooks here).

**Depends on:** 01 (data/animals). Points & reactions integrate with 05.

**Reference:**
- Prototype `index.html`: `openGames()`, `startChallenge()/renderChallenge()/
  revealChallenge()`, `startDuel()/duelRound()`, `startCloser()/closerRound()`,
  `startSize()/sizeRound()` (Animal Match), plus the game CSS.
- Spec §7.

## Build

### Play hub
- Shows the points total, a **sound on/off** toggle, and four game cards (Today's
  Challenge featured), each with a personal best. Cards launch the games.

### Game framework
- A common game surface (route/overlay) with a back button and a score bar.
- A single place to **award points** and trigger a **reaction** (happy/sad) on the
  relevant animal avatar — wired to the systems in task 05.

### The four games (match the prototype exactly)
1. **Today's Challenge (rank).** Show 4 of today's animals; child taps them in
   order strongest-Power-first; on Reveal, show each true rank + Power, animate
   correct/incorrect placements, award points by accuracy (correct placements ×15,
   +40 for a perfect order). One round; "Play again" reshuffles.
2. **Power Duel (endless streak).** Two animals with stats; tap the higher Power.
   Correct → +10, streak+1, next pair. Wrong → game over. Track best streak.
3. **Closer or Farther (higher/lower chain).** Show a reference animal + its
   distance; a new animal (distance hidden) → "closer or farther?". Reveal; correct
   → it becomes the new reference, +10, continue. Wrong → game over. Track best.
4. **Animal Match (8-round quiz).** Show a mystery "?" rock with only its width in
   metres; offer 3 animal choices; on tap, reveal the real animal + size band.
   +10 per correct. After 8 rounds show the score; 8/8 flags a perfect run.

## Acceptance criteria
- [ ] The Play hub lists all four games with bests and a working sound toggle.
- [ ] Each game plays start-to-finish exactly like the prototype (rules, copy,
      scoring, round counts).
- [ ] Wrong answers are encouraging, never harsh; correct answers award points.
- [ ] Best scores per game persist across launches.
- [ ] All games work with the offline sample data.
- [ ] Games use animal names/avatars everywhere (never the raw designation).

## Verify
- Play each game to a win and a loss; compare scoring and messages to the
  prototype. Confirm bests persist after a restart.

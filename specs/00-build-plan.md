# 00 — Build Plan & How to Use These Specs

This folder breaks the Rockimals build into ordered, self-contained tasks. Each
file is written as a prompt you can hand to Claude Code one at a time.

## Order

1. `01-foundation.md` — Flutter scaffold + NASA data + the AnimalSystem (the spine)
2. `02-live-radar.md` — the animated radar home screen
3. `03-meet-animal.md` — the "meet an animal" detail screen
4. `07-sky-tab.md` — the browse-all Sky tab
5. `04-games.md` — game framework + the four games
6. `05-rewards-collection.md` — points, animal badges, reactions/sound, My Animals, My Space Zoo
7. `08-settings-about.md` — Settings screen, Calm motion, NASA attribution
8. `06-title-polish-safety.md` — Rusty title/splash, accessibility, kids-safety, release checklist

Build them **in this order** — each depends on the ones before it. The order is
**not** the filename numbering: `07` and `08` were written after `01`–`06` to close
gaps those files left open, so they slot in where their dependencies are met rather
than at the end. `07` reuses the animal card and detail sheet from `03`, so it comes
before `04` (`07-sky-tab.md:13`); `08` needs the Profile tab and the persistence
store from `05`, and `06` hardens what it places, so it comes between the two
(`08-settings-about.md:10`).

## How each task file is structured

- **Goal** — the one-sentence outcome.
- **Depends on** — what must exist first.
- **Reference** — the exact prototype sections / spec pages to match.
- **Build** — what to implement.
- **Acceptance criteria** — a checklist; all must pass to call it done.
- **Verify** — how to prove it works.

## Working agreement

- One vertical slice at a time. Finish + verify a task before starting the next.
- The prototype (`index.html`) is the behavioural source of truth — match its
  copy, colours, math, and animations. Use `docs/Space_Zoo_Dev_Spec.docx` for the
  rationale and structure.
- Keep the guardrails in `CLAUDE.md` true at every step (safety, tone, units).
- Commit per task with a clear message (e.g. `feat(radar): animated orrery home`).

## Milestone checklist

- [ ] 01 Foundation — data + animals, with offline fallback and unit tests
- [ ] 02 Radar — animated, interactive home
- [ ] 03 Detail — meet an animal, with grown-up facts
- [ ] 07 Sky — browse every animal in the window, with sort and filter
- [ ] 04 Games — all four playable
- [ ] 05 Rewards — points, badges, reactions, collection, profile
- [ ] 08 Settings — toggles, Calm motion, NASA attribution in-app
- [ ] 06 Polish — title/splash, accessibility, safety, release-ready

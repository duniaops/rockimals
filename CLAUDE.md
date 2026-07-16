# CLAUDE.md — Rockimals

Project context for Claude Code. Read this first; it applies to **every** task.

## What we're building

**Rockimals** — a kid-friendly mobile game that turns NASA's live near-Earth
asteroid data into a "space zoo." Every real asteroid becomes a friendly space
animal whose species is set by its **real size** (Mouse 🐭 → Whale 🐋). Kids watch
the animals orbit Earth on a live radar, meet them, follow favourites, and play
quick games that teach size / distance / speed. The real science (distances,
speeds, official NASA name) lives in a "grown-up facts" section.

## Sources of truth (read these before coding)

1. **`index.html`** — the working prototype. It is the **authoritative spec for
   behaviour, copy, visuals, colours, animations, and all the math** (size→animal
   ladder, power formula, Moon-distance labels, game rules, radar rendering).
   When in doubt, match the prototype.
2. **`docs/Space_Zoo_Dev_Spec.docx`** — the *why* and structure (product goals,
   screens, data mapping, roadmap, safety).
3. **`title.html`** — the title/splash screen with the fox mascot ("Rusty").

> Golden rule: **port the prototype, don't reinvent it.** Use the docx for
> rationale, the prototype for exact behaviour.

## Target stack (single decision point — change here if needed)

- **Flutter (Dart)**, one codebase for iOS + Android.
- Rendering: `CustomPainter` + `Ticker`/`AnimationController` for the radar and
  avatar reactions (direct port of the prototype's Canvas 2D loop).
- Networking: `dio` (or `http`) with a caching + retry/backoff interceptor.
- Local storage: `hive` or `shared_preferences` (points, badges, follows, bests,
  settings). **No backend in v1.**
- State: `riverpod` (preferred) or `bloc` — pick one and stay consistent.

> Alternative: if we decide to ship the existing web app as a PWA instead of a
> Flutter rewrite, only this section and the "Build" steps change — the behaviour
> and acceptance criteria in every `specs/` file still apply.

## Guardrails (non-negotiable, apply to every task)

- **Kids-first & safe:** no login, no ads, no analytics that identify a child, no
  personal-data collection. External links (NASA/JPL) only inside "grown-up
  facts" and behind a simple parent-gate.
- **Gentle tone:** "hazardous" → **"close flyby"**, "threat" → **"power ⭐"**,
  "track" → **"follow"**. Nothing scary. Wrong answers are always encouraging.
- **Units:** every distance is shown **relative to the Moon** ("7% to Moon",
  "12× Moon"). No astronomical/lunar-distance jargon, no giant raw numbers in the
  main flow.
- **Real designation** (e.g. `2004 BL86`) appears **only** in "grown-up facts".
- **Deterministic animal system:** the same asteroid always yields the same
  species and name, with no storage.
- **Works offline** via bundled sample data (port `FALLBACK` from the prototype).
- **Calm & playful:** slow radar motion; delightful reactions on every answer.

## Architecture conventions

- Feature-first folders: `lib/features/<feature>/…`, shared code in `lib/core/…`.
- One **AnimalSystem** module is the single home for the size→species ladder,
  naming, `power()`, `flybyTag()`, and Moon-distance formatters.
- One radar render loop; **pause it when the radar isn't the visible tab.**
- Keep per-frame allocations low in the render loop; target ~60fps on mid devices.

## How to work

1. Do the `specs/` files **in order** (`01` → `06`). Each is a self-contained task.
2. Build **one vertical slice at a time**; meet its **Acceptance criteria**;
   verify; then move on. **Do not one-shot the whole app.**
3. Prefer small PRs/commits per task so each slice can be reviewed.
4. Add tests where a task asks for them (especially the AnimalSystem math).

## Global definition of done

A task is done when: it builds and runs on iOS **and** Android; behaviour matches
the prototype; the task's Acceptance criteria all pass; offline mode still works;
and there are no crashes or console errors.

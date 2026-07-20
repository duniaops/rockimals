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

## House style: the repo uses `dart format`

**Decided 2026-07-19.** `lib/` and `test/` are `dart format`-clean, and
`dart format --output=none --set-exit-if-changed lib test` must exit **zero**
before you commit. Run `dart format lib test` as part of finishing a task.

Why this needed deciding at all: `flutter analyze` does not check formatting, so
nothing ever failed, and the tree drifted to 85-of-149 files unformatted. The
status quo — each agent formatting only the files it happened to edit — was the
worst of the three options, because it smears unrelated reflow across every
future diff instead of paying for it once. It was paid once, in a
formatting-only commit.

Two things worth knowing before you run it:

- `dart format` can **create** analyzer findings. Deeper indentation pushes a
  one-line `if` over the column limit; the formatter wraps the body but does not
  add braces, and `curly_braces_in_flow_control_structures` — which tolerates
  the single-line form — then fires. Re-run `flutter analyze` after formatting,
  not just before.
- Several tests read `lib/**.dart` as a fixture and assert over the source text
  (`parent_gate_test.dart`, `featured_gradient_test.dart`,
  `kids_safety_checklist_test.dart`, `about_block_test.dart`). A reflow that
  splits a string they match with `.contains(...)` breaks them. The 2026-07-19
  sweep hit none of these, but a future one can, and the failure reads as a
  behaviour regression when it is only a line break.

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


## Secrets — never commit one

**Never commit a secret to this repo, in any form.** The repo is public; a
secret that lands in a commit stays published forever, because a follow-up
commit removes it from the tree but not from history. This has already
happened once: the registered NASA API key was baked into a web build
(`--dart-define` writes it into `main.dart.js` ~120 times) and pushed in
`c51d9fe`, and the key had to be regenerated.

Concretely:

- `--dart-define=NASA_API_KEY=<key>` is for **iOS/Android release builds
  only** — never for `flutter build web`. The web demo ships on `DEMO_KEY`
  (the `AppConfig` fallback when the define is absent), which is rate-limited
  per visitor IP and fine for a demo.
- Before committing anything under `docs/app/` (the deployed web build),
  verify the bundle is clean: `grep -c DEMO_KEY docs/app/main.dart.js` must be
  ≥ 1, and a search for any 40-character key-looking string
  (`grep -oE '[A-Za-z0-9]{40}' docs/app/main.dart.js`) must turn up nothing
  that is a credential.
- Keys, tokens, passwords, `.env` files, and service credentials never go in
  source, fixtures, tests, comments, or docs. A build that needs one takes it
  as a flag or environment value at build time; it stays out of the tree.
- If a secret does land in a commit anyway: treat it as public from that
  moment, regenerate/rotate it immediately, and only then clean the tree.

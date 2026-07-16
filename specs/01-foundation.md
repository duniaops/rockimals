# 01 — Foundation: Project, NASA Data & the Animal System

**Goal:** Scaffold the Flutter app and build the data spine — fetch NASA asteroids,
turn them into space animals, and work offline. No UI yet beyond a debug screen.

**Depends on:** nothing (first task).

**Reference:**
- Prototype `index.html`: the `normalize()` parser, the `FALLBACK` sample array,
  `loadData()`, `animalFor()` / `critter()` / `hashStr()`, `power`/`danger()`,
  `flybyTag()`, `distLabel()` / `moonCompare()`, and the `ANIMALS` / `NAME_POOL`
  tables.
- Spec §3, §6, §10, §11, Appendix A & C.

## Build

### 1. Project scaffold
- Create a Flutter app; set up feature-first folders: `lib/core/`,
  `lib/features/`, `lib/data/`.
- Add deps: state management (riverpod **or** bloc), `dio` (or `http`), `hive`
  (or `shared_preferences`).
- Add a config for the NASA API key (`DEMO_KEY` default; overridable).

### 2. Data layer — NeoWs client
- Fetch the **feed**: `GET /neo/rest/v1/feed?start_date=&end_date=&api_key=` for a
  small window ending today (match the prototype's ~3-day window).
- Parse each near-earth object into an `Asteroid` model with: `id`, `name`
  (real designation), `diameterMin/Max` (metres), `isHazardous`, `missMoon`
  (lunar distance), `missKm`, `velKps`, `magnitude`, `jplUrl`, `date`.
- Cache each day's response by date key; **past days are immutable → cache
  indefinitely**; today's with a short TTL. Add retry + exponential backoff and
  respect rate limits.

### 3. Offline fallback
- Bundle a sample dataset (port the prototype's `FALLBACK` array). If the network
  fails or returns too few objects, use it so the app is always playable.

### 4. The AnimalSystem (single shared module) — the heart of the app
- `animalFor(asteroid) -> {emoji, species}` using this exact ladder (max diameter):
  Mouse `<8m`, Rabbit `8–20`, Fox `20–50`, Tiger `50–120`, Bear `120–300`,
  Elephant `300–800`, Dino `800–2000`, Whale `>2000`. Emojis:
  🐭🐰🦊🐯🐻🐘🦕🐋.
- `critterName(asteroid) -> {emoji, species, first, name}` — `first` chosen from a
  fixed name pool by a **stable hash of the real designation** (port `hashStr` +
  `NAME_POOL`). `name = "{first} the {species}"`. Must be deterministic, no storage.
- `power(asteroid)` — the size+closeness+speed blend (+ hazard bump) from the
  prototype's `danger()`; expose an integer "Power ⭐" = `round(power * 3)`.
- `flybyTag(asteroid)` — "close flyby" if hazardous **or** `missMoon < 1`, else
  "just passing".
- Distance formatters: `distLabel` (compact: "7% to Moon" / "12× Moon") and
  `moonCompare` (long form). **Never** show raw LD/AU.

### 5. Debug screen (temporary)
- A throwaway list screen printing each animal's name, species, power, distance,
  and flyby tag — to prove the pipeline before real UI.

## Acceptance criteria
- [ ] `flutter run` shows the debug list of today's animals on iOS and Android.
- [ ] Species, names, power, and distances match what the prototype shows for the
      same data (spot-check against `index.html`).
- [ ] Turning off the network still yields a full, playable animal list (fallback).
- [ ] The animal mapping is deterministic: the same designation always gives the
      same species **and** first name.
- [ ] Unit tests cover `animalFor`, `critterName` (stability), `power`, `flybyTag`,
      and both distance formatters, including boundary sizes (8, 20, 50, 120, 300,
      800, 2000 m) and `missMoon` around 1.

## Verify
- Run the tests. Compare 5–6 sample asteroids side-by-side with the prototype.
- Toggle airplane mode and confirm the fallback path.

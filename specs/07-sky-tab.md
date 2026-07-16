# 07 — The Sky (Browse-All Tab)

**Goal:** The fourth bottom-nav tab — a scrollable list of *every* animal in the
current data window, with simple sort and filter controls. The radar shows
"what's around Earth right now"; the Sky tab is how you browse the whole set.

**Depends on:** 01 (AnimalSystem + data), 03 (the animal card taps through to the
detail screen).

> **Why this spec exists:** the prototype ships this tab (`renderSky`,
> `index.html:473`) and the bottom nav has four tabs, but tasks `01`–`06` never
> describe it. This file closes that gap. Build it after `03` (it reuses the
> animal card and opens the detail sheet) and before `04`.

**Reference:**
- Prototype `index.html`: `renderSky()` (line 473), `acardEl()` (the shared animal
  card), the `skySort` / `skyFilterHaz` state, and the `.bar` / `.toggle` CSS.

## Build

### The list
- Title **"The Sky"**, subtitle **"Every asteroid NASA is tracking in this window."**
- One shared **animal card** per asteroid (the same widget the Watchlist uses):
  avatar emoji, `"{Name} the {Species}"`, flyby badge, size / distance / speed.
- Source is the **full `asteroids` list** (not `todayList`). Tapping a card opens
  the Meet-an-Animal screen (task 03).

### Sort & filter bar
- Three mutually-exclusive sort toggles — **Closest** (`missLunar` asc, default),
  **Biggest** (`diaMax` desc), **Fastest** (`velKps` desc).
- One independent filter toggle for close flybys only. **Soften the prototype's
  copy:** it reads "⚠ Hazardous only", which breaks the tone guardrail in
  `CLAUDE.md`. Use **"👋 Close flybys only"** and filter on `flybyTag` (hazardous
  **or** `missMoon < 1`), not on the raw `hazardous` flag alone.
- Selected toggles get the "on" treatment; changing one re-renders the list.

### Footer note
- `"📅 Showing {feedRange}"`, or **"sample set"** when running on the bundled
  fallback data. Drop the prototype's "Time Machine ready" string — it advertises
  a feature that does not exist.

### Empty state
- When the close-flyby filter matches nothing:
  **"No close flybys in this window — good news! 🌍"**
  (The prototype's "No hazardous asteroids…" wording is softened per the
  guardrails.)

## Acceptance criteria
- [ ] The Sky tab lists every animal in the current window, each on an animal card.
- [ ] Each of the three sorts orders the list correctly; the default is Closest.
- [ ] The close-flyby filter uses `flybyTag` logic and shows the friendly empty
      state when nothing matches.
- [ ] Tapping any card opens that animal's detail screen.
- [ ] The footer shows the real date range, or "sample set" when offline.
- [ ] No jargon: no "hazardous", no raw km/LD/AU — distances are Moon-relative and
      the real designation never appears here.
- [ ] The list scrolls smoothly on a busy day (60+ animals).

## Verify
- Compare side-by-side with the prototype's Sky tab. Toggle each sort and the
  filter. Run offline and confirm the "sample set" footer and a full list.

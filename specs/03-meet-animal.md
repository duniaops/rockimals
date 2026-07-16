# 03 — Meet an Animal (Detail Screen)

**Goal:** A kid-first detail screen for one animal, with the real science tucked
into a "grown-up facts" section.

**Depends on:** 01 (AnimalSystem), 02 (opened from the radar's selected-animal card).

**Reference:**
- Prototype `index.html`: `openDetail()` — the avatar, species line, flyby badge,
  stat tiles, size-comparison and distance-comparison modules, Follow / Show-on-
  radar buttons, and the "grown-up facts" panel.
- Spec §5.1 (Meet an Animal).

## Build
- **Header:** big animal avatar, `"{Name} the {Species}"`, and
  `"a {Species}-sized space rock"`.
- **Badge:** "👋 close flyby" or "just passing" (from `flybyTag`).
- **Kid stat tiles:** How wide (m), How fast (km/s), How close (Moon-distance),
  **Power ⭐**.
- **Size comparison:** the animal vs a familiar object scaled to real diameter
  (bus, stadium, tower, etc.) with an "≈ N× the {object}" line.
- **Distance comparison:** a track showing Earth → animal vs Earth → Moon.
- **Actions:** **Follow / Unfollow** (adds to My Animals) and **Show on radar**
  (returns to the radar with this animal selected).
- **Grown-up facts panel:** the **real NASA designation** and a **NASA/JPL link**.
  The link opens externally and should sit behind a simple **parent-gate** (see 06)
  — the only place the real designation and external links appear.

## Acceptance criteria
- [ ] Opening an animal shows the correct avatar, name, species, and stats.
- [ ] Size and distance comparisons render correctly and match the prototype.
- [ ] Follow toggles membership in My Animals; Show-on-radar reselects it.
- [ ] The real designation appears **only** here, in "grown-up facts"; the NASA
      link is parent-gated and opens in the system browser.
- [ ] No jargon; distances shown relative to the Moon.

## Verify
- Meet several animals of different sizes; confirm species/comparison correctness
  vs the prototype. Confirm the NASA link is gated and opens externally.

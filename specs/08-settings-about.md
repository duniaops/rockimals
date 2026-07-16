# 08 — Settings & About

**Goal:** Give the app one home for its grown-up-facing toggles and its NASA
attribution — the surface that `06-title-polish-safety.md` assumes exists but
never builds.

**Depends on:** 02 (the app shell exists), 05 (the Profile tab and the
persistence store exist).

**Slots in:** after 05, before 06. Task 06 hardens what this task places.

**Reference:**
- `specs/06-title-polish-safety.md:25` — the reduced-motion setting.
- `specs/06-title-polish-safety.md:60` — NASA attribution + "unofficial" note.
- `specs/05-rewards-collection.md` — the Profile tab that hosts the entry point.
- No prototype precedent. `index.html` has **no** settings screen, no
  reduced-motion concept, and no attribution string (all three greps return
  zero). This screen is new work, not a port — but it must match the
  prototype's visual language (navy surfaces, rounded chips, emoji-led rows).

## Why this exists

Three requirements in spec 06 have nowhere to live:

1. The **reduced-motion** toggle needs a surface *and* a persisted key. The
   store in task 01/05 enumerates its fields exhaustively and omits it.
2. **NASA attribution** and the "unofficial / not affiliated with NASA"
   disclaimer must *render in the app*, not merely be ticked on a release
   checklist. Attribution is a condition of using NASA's data and branding.
3. The **Little Kids mode** stub (spec 06) needs an extension point that is
   reachable, or it is untestable.

The sound toggle currently sits in the Play hub (task 04). Leave it there — it
belongs next to the games — but mirror it here so all toggles are discoverable
in one place. Both read and write the same `soundOn` key.

## Build

### Entry point
- A **⚙️ Settings** row at the bottom of the **👤 Profile** tab. Do **not** add a
  fifth bottom-nav tab — the nav is fixed at four (Radar / Sky / Watchlist /
  Profile).
- Pushes a full screen with a back button, titled "Settings".

### Toggles (all persisted)
- **🔊 Sound** — mirrors the Play hub's toggle; same `soundOn` key.
- **🐢 Calm motion** — the reduced-motion setting. Kid-facing label; never the
  phrase "reduced motion" in the UI. Defaults to the OS accessibility flag
  (`MediaQuery.disableAnimations`) on first run, then follows the user's choice.
  Persisted as `reducedMotion`.
- **🧸 Little Kids mode** — the spec-06 stub. Ships as a visible, persisted
  toggle wired to a `LittleKidsMode` interface; the v1 body may be a no-op
  documented as the v1.1 extension point.

### About section
- **NASA attribution:** "Asteroid data from NASA's NeoWs (Near Earth Object Web
  Service)." — plain text, no link outside the parent gate.
- **Disclaimer:** "Rockimals is an unofficial app. It is not affiliated with,
  endorsed by, or sponsored by NASA." — must be legible, not fine print.
- **Privacy line:** "Rockimals collects nothing about you. No accounts, no ads,
  no tracking." — the in-app statement of the `CLAUDE.md` guardrail.
- App version + build number.
- **No external links on this screen.** The NASA/JPL link stays parent-gated in
  grown-up facts (task 03/06). If a privacy-policy link is added later it takes
  the same gate.

### Tone
- Kid-safe copy throughout — this screen is reachable by a child even though its
  content is aimed at grown-ups. No jargon, no scare words, no dead ends.

## Acceptance criteria
- [ ] Settings opens from the Profile tab and backs out cleanly.
- [ ] All three toggles persist across a restart.
- [ ] **Calm motion** on → the radar drifts slowly or holds still and reactions
      shorten; off → full motion returns. No restart required.
- [ ] Calm motion defaults to **on** when the OS accessibility flag is set, and
      a later manual choice overrides the OS default.
- [ ] The sound toggle here and the one in the Play hub always agree.
- [ ] NASA attribution and the "unofficial / not affiliated" disclaimer are both
      visible on screen.
- [ ] The screen contains zero outbound links.
- [ ] Every tap target is ≥48dp.

## Verify
- Toggle each switch, force-quit, relaunch, confirm all three held.
- Turn on Calm motion and watch the radar settle without leaving the screen.
- Enable the OS "reduce motion" setting on a fresh install and confirm the
  default follows it.
- Greyscale screenshot: every toggle's on/off state still readable.
- Grep the screen's widget tree for `url_launcher` — expect no hits.

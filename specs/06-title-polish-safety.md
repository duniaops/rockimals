# 06 — Title/Splash, Polish, Accessibility & Kids-Safety Release

**Goal:** Wrap the app with the Rockimals title screen and mascot, make it
accessible and calm, and meet the kids-safety bar for store release.

**Depends on:** 02–05 (the app exists).

**Reference:**
- `title.html` — the Rockimals title screen with **Rusty the fox** (SVG mascot,
  wordmark with the asteroid "O", warm glow, Play button).
- Spec §14 (safety/privacy), §15 (accessibility), §16 (performance).

## Build

### Title / splash
- Recreate the `title.html` screen as the app's entry: Rusty bobbing, wordmark,
  tagline, warm background; **tap / Play → the radar home**. Reuse Rusty as the
  brand mascot on the loading screen and empty states.

### Accessibility & "little kids" friendliness
- Large, well-spaced tap targets everywhere; keep the radar's inner "safe zone" +
  zoom so small fingers can hit crowded animals.
- **Never rely on colour alone** — pair the close-flyby colour with icon + text;
  keep a colour-blind-safe palette.
- A **reduced-motion** setting that calms the radar and shortens reactions.
- Stub a **Little Kids mode** (read-aloud names/prompts via TTS, bigger controls,
  simplest two games) — implement or leave a clean extension point for v1.1.

### Kids-safety & privacy (required before release)
- No account/login; no personal-data collection; no ads to children; no chat/UGC.
- External links (NASA/JPL) only inside "grown-up facts", behind a **parent-gate**
  (e.g. a simple "ask a grown-up" math/hold gesture) and opened in the system
  browser.
- Design toward COPPA / GDPR-K / Age-Appropriate Design and the App Store **Kids**
  category / Google Play **Families** policies (incl. their SDK & ad rules).

### Performance & offline
- Cache feeds by date (past days forever); prefetch tomorrow; bundle the sample
  set; pause the radar loop off-tab; cap on-screen animals on unusually busy days.

## Acceptance criteria
- [ ] The app opens on the Rockimals title with Rusty; tap/Play → radar.
- [ ] Reduced-motion setting works; tap targets are comfortably large.
- [ ] Close-flyby state is conveyed by icon+text, not colour alone.
- [ ] No login, no ads, no personal-data collection anywhere in the app.
- [ ] The only external link is the parent-gated NASA/JPL link in grown-up facts.
- [ ] Fully usable offline; radar loop pauses off-tab.

## Verify
- Cold-launch to the title and into the radar. Toggle reduced-motion. Attempt the
  NASA link and confirm the parent-gate. Run a release checklist against the
  chosen store's Kids/Families policy before submitting.

---

### Release checklist (final gate)
- [ ] Store "Kids/Families" category questionnaire completed honestly.
- [ ] Privacy policy published (states: no personal data collected).
- [ ] A qualified reviewer has signed off on child-privacy compliance.
- [ ] NASA attribution present; "unofficial / not affiliated with NASA" noted.
- [ ] Registered NASA API key in place (not DEMO_KEY) for production.

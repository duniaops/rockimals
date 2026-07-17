# 02 — Live Radar (Home Screen)

**Goal:** The signature screen — an animated, interactive, Earth-centred orrery of
every space animal, with a decorative solar-system backdrop. This is the home tab.

**Depends on:** 01 (AnimalSystem + data).

**Reference:**
- Prototype `index.html`: `radarDraw()`, `radarLoop()`, `radiusFor()` (inner-floor
  log scale), the asteroid/animal chip drawing, `drawPlanets()`, the pointer
  handlers (`bindRadar`), `radarSelect()`, `homeShow()`/`updateHomeOverlay()`, and
  the home overlay markup.
- Spec §5.1 (Live Radar), §9.

## Build

### Rendering (CustomPainter + Ticker/AnimationController)
- **Earth** glowing at centre; the **Moon** orbiting on the 1-Moon ring.
- **Distance rings** labelled `Moon, 2×, 5×, 10×, 20×, 50× Moon`. Use the
  prototype's **log scale with an inner "safe zone" floor** so close animals never
  pile on Earth (port `radiusFor`).
- **Each animal** = a navy chip + ring + its species emoji, sized by species.
  Ring is **orange for close flybys**, **white for the selected** one, subtle blue
  otherwise. Show a name label for close/selected animals. (This chip backdrop is
  important — without it animals look "disabled" on the dark background.)
- **Backdrop:** the Sun bleeding in from the edge + Mercury, Venus, Mars, Jupiter
  (bands + red spot), Saturn (rings), Neptune, drifting slowly and **scaling from
  centre with zoom** for depth. Purely decorative.
- Motion is **calm** (slow orbital drift). Pause the loop when the radar tab isn't
  visible.

### Interactions
- **Drag** to spin the whole field; **pinch / +− buttons** to zoom
  (clamp to a framed range so content never flies off-screen); **tap** an animal
  to select it (with an easy tap radius). *(Mouse-wheel/scroll zoom is **out of
  scope** on the iOS + Android touch target: those devices have no wheel, and
  pinch plus the ＋− buttons already cover the same need. Revisit if the project
  ever ships to a device with a pointing device — an Android tablet with a mouse,
  a Chromebook — or takes the PWA path named in `CLAUDE.md`.)*
- **Play/pause** control; toggle chips: **Planets, Labels, Rings, Moon**, and an
  advanced **Hazards** filter.

### Home overlay (on top of the radar)
- Top: app title, streak flame, and a slim stat strip — animals visiting today,
  closest approach ("% / × Moon"), and number of close flybys.
- Selected-animal card that slides up on tap, with **Meet** and **Follow** buttons.
- A big **🎮 Play** button that opens the games hub (built in task 04).

## Acceptance criteria
- [ ] The radar animates smoothly (~60fps) with animals, Moon, rings, and planets.
- [ ] Drag spins, pinch/buttons zoom within a sensible range, tap selects.
      (Wheel/scroll zoom is out of scope on the touch target — see Interactions.)
- [ ] Every animal is clearly visible on its chip (none look faded); close flybys
      have an orange ring, the selected one a white ring.
- [ ] Rings read in Moon-distances; no jargon anywhere.
- [ ] The stat strip and streak match the current data; Play opens the hub stub.
- [ ] The animation loop pauses when another tab is shown and resumes on return.
- [ ] Close-to-Earth animals are spread into a tappable ring (inner floor works).

## Verify
- Compare side-by-side with the prototype radar. Profile a few seconds to confirm
  frame rate and that the loop stops when off-tab.

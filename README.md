# 🦊 Rockimals

**Real asteroids flying past Earth — as friendly space animals.**

Rockimals is a kid-friendly mobile game concept that turns NASA's live near-Earth
asteroid data into a playful "space zoo." Every real asteroid becomes a cuddly
space animal whose species is decided by the asteroid's **real size** — a tiny
rock is a Mouse 🐭, a giant is a Whale 🐋. Kids watch the animals drift around
Earth on a live radar, meet them, follow their favourites, and play quick games
that quietly teach real ideas about size, distance and speed. The true science
(real distances, speeds and the asteroid's official NASA name) lives in a
"grown-up facts" section for parents and curious older kids.

> Status: **interactive prototype** (single-file HTML/Canvas/JS). The in-app
> branding still reads "Asteroid Watch" and is being updated to Rockimals.

---

## ▶️ Try it

Open **`index.html`** in any modern browser (best viewed on a phone or a narrow
window). No build step, no dependencies. It pulls live data from NASA's NeoWs API
and falls back to a bundled sample set when offline, so it always works.

The **`title.html`** file is the Rockimals title screen concept with the fox
mascot ("Rusty").

---

## ✨ What's inside the app

- **Live Radar** — an animated, Earth-centred orrery of every asteroid-animal,
  with drag-to-spin, pinch/scroll zoom, tap-to-select, and a decorative
  solar-system backdrop (Sun + planets). Distances are shown relative to the Moon.
- **Meet an animal** — avatar, size & distance comparisons, kid-friendly stats,
  and a "grown-up facts" panel with the real NASA designation + JPL link.
- **Four games** — Today's Challenge (rank by power), Power Duel, Closer or
  Farther, and Animal Match.
- **Rewards** — collect points across games, unlock animal badges (Mouse →
  Whale), with happy jump/spin animations + jingles on correct answers and
  gentle encouragement on wrong ones.
- **My Animals** (follow list) and **My Space Zoo** (points & badge shelf).

---

## 🗂️ Project structure

```
.
├── index.html              # Main interactive app (the prototype) — behavioural source of truth
├── title.html              # Rockimals title screen (fox mascot)
├── CLAUDE.md               # Project context + guardrails, loaded by Claude Code
├── specs/                  # Ordered build tasks; 00-build-plan.md owns the order
├── docs/
│   └── Space_Zoo_Dev_Spec.docx   # Development specification — the "why" and structure
└── README.md
```

---

## 🛰️ Data

Powered by **NASA Open APIs — NeoWs (Near Earth Object Web Service)**.
The prototype uses `DEMO_KEY`; for unlimited use, get a free key at
<https://api.nasa.gov> and swap it in (`API_KEY` in `index.html`).

Asteroid attributes map to animals like this:

| NeoWs field | Becomes |
|---|---|
| `estimated_diameter` | the animal species (size ladder) |
| `miss_distance` (lunar) | "how close" — shown as % of / × the Moon's distance |
| `relative_velocity` | "how fast" |
| `is_potentially_hazardous_asteroid` | the (softened) "close flyby" badge |
| `name` / `nasa_jpl_url` | the real designation in "grown-up facts" |

---

## 🧭 Roadmap

**`docs/Space_Zoo_Dev_Spec.docx` is the spec we're building from** — the full
build-ready document (animal system, game specs, rewards, radar rendering, tech
stack, kids' safety & privacy, and a build roadmap). Recommended stack: **Flutter**
(cross-platform), no backend for v1, optional Supabase later for
accounts/leaderboards.

### 🤖 Building with Claude Code

This repo is set up for agent-driven development:

- **`CLAUDE.md`** (repo root) — project context, stack, and guardrails that Claude
  Code loads automatically.
- **`specs/`** — the build broken into ordered, self-contained task prompts.
  **`specs/00-build-plan.md` owns the build order** — read it first. The order is
  deliberately not the filename numbering. Do them in order, one vertical slice at
  a time.

The key idea: **`index.html` is the behavioural source of truth** — the tasks
port the proven prototype to Flutter, using the `.docx` for rationale.

---

*Asteroid data courtesy of NASA. This is an independent, unofficial project and is
not affiliated with or endorsed by NASA.*

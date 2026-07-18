import 'package:rockimals/data/models/asteroid.dart';

/// How many animals the radar will draw at once
/// (`specs/06-title-polish-safety.md:39`, "cap on-screen animals on unusually
/// busy days").
///
/// **Sixty, and the number is the project's own definition of a busy day** —
/// `specs/07-sky-tab.md:57` calls 60+ animals the case the Sky list has to stay
/// smooth for, and the radar painter's label comment already reasons about
/// "sixty labels at once" (`radar_painter.dart:352`). Taking the same number
/// here means one idea of "busy" rather than two.
///
/// **What it is protecting.** Every animal on the field costs a fresh
/// `ui.Gradient.radial` plus two or three `drawCircle`s *per frame*
/// (`radar_painter.dart:296-313`) — the one per-animal allocation the painter
/// could not hoist out of the loop, because the shader is positioned at the
/// animal. That is linear in the count and it is spent sixty times a second, so
/// a NeoWs window that happens to list two hundred rocks would spend most of a
/// frame on shader construction alone (`CLAUDE.md:79-80`).
///
/// A three-day window is normally well under this, so on almost every day the
/// cap does nothing at all and the radar is exactly the prototype's.
const int kMaxRadarAnimals = 60;

/// The animals the radar draws: [asteroids] unchanged on an ordinary day, its
/// first [kMaxRadarAnimals] on a busy one.
///
/// **A prefix, not a selection, and that is the deliberate half.** The obvious
/// alternative — keep the sixty closest, since the radar is a *distance* view —
/// was rejected twice over. It would reorder the list, and an animal's index in
/// that list is what seeds its orbit phase (`RadarOrbits.seed`, plan decision
/// 9), so every animal on the field would sit somewhere different the moment the
/// cap engaged. And "which animals are most interesting" is a question the app
/// already answers somewhere else, with sort chips the child controls, on the
/// Sky tab. This is a frame-budget guard, so it does the least interesting thing
/// that fits in the budget.
///
/// **Only the radar is capped.** The Sky tab, the watchlist and all four games
/// keep reading the whole window through `asteroidsProvider` — none of them
/// redraws sixty times a second, and a child who cannot find an animal on the
/// radar can still meet it in a list. Capping the shared provider instead would
/// have quietly deleted rocks from the games' pool to buy a frame on a screen
/// they are not on.
///
/// Returns the argument itself when it fits, so the ordinary day costs no copy.
List<Asteroid> capRadarAnimals(List<Asteroid> asteroids) =>
    asteroids.length <= kMaxRadarAnimals
    ? asteroids
    : asteroids.take(kMaxRadarAnimals).toList(growable: false);

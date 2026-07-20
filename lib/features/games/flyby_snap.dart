/// The deterministic timing rules for Flyby Snap.
///
/// Real relative velocity changes how quickly an animal crosses the photo
/// window, but the playable range stays kind for both slow and fast flybys.
library;

import 'dart:math';

import 'package:rockimals/core/animals/animal_system.dart';
import 'package:rockimals/data/models/asteroid.dart';

/// The real-speed range mapped directly into the game's playable timing range.
/// Values outside it still use the nearest playable difficulty rather than
/// making a slow visitor boring or a fast visitor impossible to photograph.
const double kFlybySnapMinVelocityKps = 3;
const double kFlybySnapMaxVelocityKps = 30;

/// A 3 km/s flyby takes this long to cross the scene.
const Duration kFlybySnapSlowCrossingDuration = Duration(seconds: 6);

/// A 30 km/s flyby takes this long to cross the scene.
const Duration kFlybySnapFastCrossingDuration = Duration(seconds: 2);

/// Calm Motion makes the crossing take longer without changing its NASA fact.
const double kFlybySnapCalmDurationScale = 2;

/// The portion of the flight occupied by the photography window.
const double kFlybySnapWindowStart = 0.43;
const double kFlybySnapWindowEnd = 0.57;

/// Clamp a real velocity to the range Flyby Snap can present playably.
double flybySnapDifficultyVelocity(double velocityKps) {
  if (!velocityKps.isFinite || velocityKps < 0) {
    throw ArgumentError.value(
      velocityKps,
      'velocityKps',
      'Flyby Snap needs a finite, non-negative real velocity.',
    );
  }
  return velocityKps.clamp(kFlybySnapMinVelocityKps, kFlybySnapMaxVelocityKps);
}

/// The crossing duration inspired by a real velocity.
///
/// The interpolation is deliberately linear and explicit: two nearby real
/// speeds yield nearby difficulty, while the published endpoints remain easy
/// to test and explain.
Duration flybySnapCrossingDuration({
  required double velocityKps,
  bool calmMotion = false,
}) {
  final double difficultyVelocity = flybySnapDifficultyVelocity(velocityKps);
  final double fraction =
      (difficultyVelocity - kFlybySnapMinVelocityKps) /
      (kFlybySnapMaxVelocityKps - kFlybySnapMinVelocityKps);
  final int normalMilliseconds =
      kFlybySnapSlowCrossingDuration.inMilliseconds -
      ((kFlybySnapSlowCrossingDuration.inMilliseconds -
                  kFlybySnapFastCrossingDuration.inMilliseconds) *
              fraction)
          .round();
  return Duration(
    milliseconds: calmMotion
        ? (normalMilliseconds * kFlybySnapCalmDurationScale).round()
        : normalMilliseconds,
  );
}

/// Whether a photo taken at [flightProgress] lands in the camera window.
bool isFlybySnapPhotoInWindow(double flightProgress) =>
    flightProgress >= kFlybySnapWindowStart &&
    flightProgress <= kFlybySnapWindowEnd;

/// Deal the shared feed in a repeatable order for this day's photo session.
///
/// Sorting first means a network response's order cannot change a child's
/// round. The injected [dayKey] keeps this pure and free of wall-clock reads.
List<Asteroid> generateFlybySnapDeal({
  required List<Asteroid> asteroids,
  required String dayKey,
}) {
  if (asteroids.isEmpty) {
    throw ArgumentError.value(
      asteroids,
      'asteroids',
      'Flyby Snap needs at least one asteroid.',
    );
  }
  final List<Asteroid> deal = List<Asteroid>.of(asteroids)
    ..sort((Asteroid a, Asteroid b) => a.name.compareTo(b.name));
  final String designations = deal
      .map((Asteroid asteroid) => asteroid.name)
      .join('|');
  deal.shuffle(Random(hashStr('$dayKey|$designations')));
  return List<Asteroid>.unmodifiable(deal);
}

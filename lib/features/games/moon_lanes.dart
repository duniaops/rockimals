/// The pure rules behind Moon Lanes: which distance lane an animal belongs in,
/// how the number of visible lanes adapts during one play session, and the
/// repeatable order in which animals are dealt.
///
/// Keeping these rules outside the eventual drag screen makes the NASA-backed
/// answer independent of presentation and keeps difficulty in memory. Nothing
/// here reads the clock, storage, or a provider.
library;

import 'dart:math';

import 'package:rockimals/core/animals/animal_system.dart';
import 'package:rockimals/data/models/asteroid.dart';

/// The four real miss-distance bands taught by Moon Lanes.
///
/// Bounds are lower-inclusive: exactly 1 Moon belongs in [oneToFiveMoons],
/// exactly 5 in [fiveToTwentyMoons], and exactly 20 in [farther]. That keeps the
/// four lanes exhaustive and non-overlapping.
enum MoonLane {
  insideMoon('inside the Moon'),
  oneToFiveMoons('1–5× the Moon'),
  fiveToTwentyMoons('5–20× the Moon'),
  farther('farther');

  const MoonLane(this.label);

  /// Kid-facing lane copy from the Games v2 specification.
  final String label;
}

/// A lane the screen can show at a particular adaptive difficulty.
///
/// Two and three lane rounds deliberately merge distant bands instead of
/// hiding them. That means every real asteroid still has exactly one valid
/// drop target before a child has unlocked the full four-lane lesson.
enum MoonLaneChoice {
  insideFiveMoons('inside 5× the Moon'),
  fiveOrMoreMoons('5× the Moon or farther'),
  insideMoon('inside the Moon'),
  oneToFiveMoons('1–5× the Moon'),
  fiveToTwentyMoons('5–20× the Moon'),
  farther('farther');

  const MoonLaneChoice(this.label);

  /// Kid-facing copy for this visible drop target.
  final String label;
}

/// Return the one lane determined by a real miss distance in Moon distances.
MoonLane moonLaneFor(double missLunar) {
  if (!missLunar.isFinite || missLunar < 0) {
    throw ArgumentError.value(
      missLunar,
      'missLunar',
      'Moon Lanes needs a finite, non-negative miss distance.',
    );
  }
  if (missLunar < 1) return MoonLane.insideMoon;
  if (missLunar < 5) return MoonLane.oneToFiveMoons;
  if (missLunar < 20) return MoonLane.fiveToTwentyMoons;
  return MoonLane.farther;
}

/// The drop targets for a round at [laneCount] difficulty.
///
/// At two lanes, the game teaches near versus far. At three, it introduces the
/// Moon itself. Four lanes expose the complete NASA-distance ladder from the
/// specification. Returning explicit choices prevents a screen from showing
/// only the first two canonical lanes and leaving a farther animal ungradeable.
List<MoonLaneChoice> moonLaneChoicesFor(int laneCount) => switch (laneCount) {
  2 => const <MoonLaneChoice>[
    MoonLaneChoice.insideFiveMoons,
    MoonLaneChoice.fiveOrMoreMoons,
  ],
  3 => const <MoonLaneChoice>[
    MoonLaneChoice.insideMoon,
    MoonLaneChoice.oneToFiveMoons,
    MoonLaneChoice.fiveOrMoreMoons,
  ],
  4 => const <MoonLaneChoice>[
    MoonLaneChoice.insideMoon,
    MoonLaneChoice.oneToFiveMoons,
    MoonLaneChoice.fiveToTwentyMoons,
    MoonLaneChoice.farther,
  ],
  _ => throw ArgumentError.value(
    laneCount,
    'laneCount',
    'Moon Lanes supports between 2 and 4 lanes.',
  ),
};

/// Grade a real miss distance against the visible targets at [laneCount].
///
/// This is the screen-facing answer: it first uses [moonLaneFor] for the
/// precise NASA band, then merges only the bands that the current adaptive
/// lesson intentionally presents together.
MoonLaneChoice moonLaneChoiceFor({
  required double missLunar,
  required int laneCount,
}) {
  final MoonLane lane = moonLaneFor(missLunar);
  return switch (laneCount) {
    2 => switch (lane) {
      MoonLane.insideMoon ||
      MoonLane.oneToFiveMoons => MoonLaneChoice.insideFiveMoons,
      MoonLane.fiveToTwentyMoons ||
      MoonLane.farther => MoonLaneChoice.fiveOrMoreMoons,
    },
    3 => switch (lane) {
      MoonLane.insideMoon => MoonLaneChoice.insideMoon,
      MoonLane.oneToFiveMoons => MoonLaneChoice.oneToFiveMoons,
      MoonLane.fiveToTwentyMoons ||
      MoonLane.farther => MoonLaneChoice.fiveOrMoreMoons,
    },
    4 => switch (lane) {
      MoonLane.insideMoon => MoonLaneChoice.insideMoon,
      MoonLane.oneToFiveMoons => MoonLaneChoice.oneToFiveMoons,
      MoonLane.fiveToTwentyMoons => MoonLaneChoice.fiveToTwentyMoons,
      MoonLane.farther => MoonLaneChoice.farther,
    },
    _ => throw ArgumentError.value(
      laneCount,
      'laneCount',
      'Moon Lanes supports between 2 and 4 lanes.',
    ),
  };
}

/// How many consecutive correct drops unlock the next lane.
///
/// Three demonstrates sustained understanding rather than promoting on one
/// lucky drop, while still allowing a child to reach all four lanes quickly in
/// a 30–60 second round.
const int kMoonLanesSuccessesToAdvance = 3;

/// How many consecutive wrong drops back difficulty off by one lane.
///
/// A single exploratory drag is harmless; two in a row is enough evidence that
/// one less choice would be kinder. Moon Lanes remains life-free either way.
const int kMoonLanesStrugglesToBackOff = 2;

/// In-session adaptive difficulty for Moon Lanes.
///
/// A fresh session starts at two lanes. Three consecutive correct drops add
/// one lane (up to four); two consecutive wrong drops remove one (down to two).
/// Any opposite result resets the current run. The class has no serialization
/// or storage dependency, deliberately making a new play session a fresh start.
class MoonLanesDifficulty {
  MoonLanesDifficulty() : _laneCount = 2, _successes = 0, _struggles = 0;

  /// The current number of choices the screen should present.
  int get laneCount => _laneCount;

  int _laneCount;
  int _successes;
  int _struggles;

  /// Record one drop and update [laneCount] when a run reaches its threshold.
  void recordDrop({required bool correct}) {
    if (correct) {
      _struggles = 0;
      _successes++;
      if (_successes >= kMoonLanesSuccessesToAdvance) {
        _laneCount = min(MoonLane.values.length, _laneCount + 1);
        _successes = 0;
      }
      return;
    }

    _successes = 0;
    _struggles++;
    if (_struggles >= kMoonLanesStrugglesToBackOff) {
      _laneCount = max(2, _laneCount - 1);
      _struggles = 0;
    }
  }
}

/// Deal every asteroid in a deterministic order for this day and feed.
///
/// Designations are sorted before shuffling, so the order supplied by a feed or
/// radar cannot alter the deal. [dayKey] is injected from the shared app clock;
/// this function never reads the current time. As elsewhere in Games v2, the
/// seed is the day plus sorted real designations via [hashStr].
List<Asteroid> generateMoonLanesDeal({
  required List<Asteroid> asteroids,
  required String dayKey,
}) {
  if (asteroids.isEmpty) {
    throw ArgumentError.value(
      asteroids,
      'asteroids',
      'Moon Lanes needs at least one asteroid.',
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

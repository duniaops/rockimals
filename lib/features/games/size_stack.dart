/// Deterministic size rules for Size Stack.
///
/// A tower is stable only when its real NASA diameters descend from its base to
/// its top.  The rules live apart from the drag screen so the answer stays
/// testable, replayable offline, and independent of animation.
library;

import 'dart:math';

import 'package:rockimals/core/animals/animal_system.dart';
import 'package:rockimals/data/models/asteroid.dart';

/// A first Size Stack tower contains four animals; a successful tower adds one
/// animal until the seven-animal cap.
const int kSizeStackMinTowerSize = 4;
const int kSizeStackMaxTowerSize = 7;

/// The minimum and maximum visual sizes used for animal sprites.
const double kSizeStackMinSpriteSize = 42;
const double kSizeStackMaxSpriteSize = 82;

/// Return a child-friendly sprite size derived from a real maximum diameter.
///
/// Log scaling preserves a visible difference between small rocks without
/// letting a kilometre-wide visitor crowd the rest of the tower. Values beyond
/// the taught Mouse-to-Whale range remain at a friendly maximum size.
double sizeStackSpriteSize(double diameterMetres) {
  if (!diameterMetres.isFinite || diameterMetres <= 0) {
    throw ArgumentError.value(
      diameterMetres,
      'diameterMetres',
      'Size Stack needs a finite, positive real diameter.',
    );
  }
  final double clamped = diameterMetres.clamp(1, 2000);
  final double fraction = log(clamped) / log(2000);
  return kSizeStackMinSpriteSize +
      (kSizeStackMaxSpriteSize - kSizeStackMinSpriteSize) * fraction;
}

/// A deterministic, unambiguous tower. [stackingOrder] is base to top.
class SizeStackRound {
  const SizeStackRound({required this.stackingOrder, required this.offerOrder});

  /// The one stable order, largest real diameter first.
  final List<Asteroid> stackingOrder;

  /// The same animals in the order the child initially sees them.
  final List<Asteroid> offerOrder;
}

/// Build a day's tower from unique real diameters.
///
/// Duplicate diameters are deliberately excluded: a child cannot learn a
/// strict big-to-small ordering from two equally wide visitors. Sorting names
/// before the seeded shuffle keeps the result stable when NASA changes feed
/// ordering.
SizeStackRound generateSizeStackRound({
  required List<Asteroid> asteroids,
  required String dayKey,
  int towerSize = kSizeStackMinTowerSize,
}) {
  if (towerSize < kSizeStackMinTowerSize ||
      towerSize > kSizeStackMaxTowerSize) {
    throw ArgumentError.value(
      towerSize,
      'towerSize',
      'Size Stack supports towers from 4 to 7 animals.',
    );
  }

  final List<Asteroid> candidates = List<Asteroid>.of(asteroids)
    ..sort((Asteroid a, Asteroid b) => a.name.compareTo(b.name));
  final Set<double> seenDiameters = <double>{};
  final List<Asteroid> distinct = candidates
      .where((Asteroid asteroid) => seenDiameters.add(asteroid.diaMax))
      .toList(growable: false);
  if (distinct.length < towerSize) {
    throw ArgumentError.value(
      asteroids,
      'asteroids',
      'Size Stack needs $towerSize unique real diameters.',
    );
  }

  final String designations = candidates
      .map((Asteroid asteroid) => asteroid.name)
      .join('|');
  distinct.shuffle(Random(hashStr('$dayKey|$designations|$towerSize')));
  final List<Asteroid> stackingOrder = distinct.take(towerSize).toList()
    ..sort((Asteroid a, Asteroid b) {
      final int diameterOrder = b.diaMax.compareTo(a.diaMax);
      return diameterOrder != 0 ? diameterOrder : a.name.compareTo(b.name);
    });
  final List<Asteroid> offerOrder = List<Asteroid>.of(stackingOrder)
    ..shuffle(Random(hashStr('$dayKey|$designations|$towerSize|offers')));
  return SizeStackRound(
    stackingOrder: List<Asteroid>.unmodifiable(stackingOrder),
    offerOrder: List<Asteroid>.unmodifiable(offerOrder),
  );
}

/// Tracks only the in-session tower growth; Size Stack needs no storage key.
class SizeStackDifficulty {
  int _towerSize = kSizeStackMinTowerSize;

  int get towerSize => _towerSize;

  /// A completed stable tower earns a slightly taller next tower, up to seven.
  void recordCompletedTower() {
    _towerSize = min(kSizeStackMaxTowerSize, _towerSize + 1);
  }
}

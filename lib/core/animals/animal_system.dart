/// The AnimalSystem: the single home for the size→species ladder, naming,
/// `power()`, `flybyTag()`, and the Moon-distance formatters (`CLAUDE.md:78`).
///
/// This file currently holds the size ladder. The remaining pieces land here
/// too — one module, so that "the same asteroid always yields the same animal"
/// is a property of one table rather than an agreement between several.
library;

import 'package:rockimals/data/models/asteroid.dart';

/// One rung of the ladder: an asteroid's species and how it is described to a
/// child.
///
/// [max] is an **exclusive** ceiling — a rung claims an asteroid when its
/// `diaMax` is *strictly* below it, which is what puts exactly 8 m in the
/// Rabbit band rather than the Mouse one.
class Animal {
  const Animal({
    required this.max,
    required this.emoji,
    required this.species,
    required this.sizeLabel,
  });

  /// The exclusive upper bound in metres. The Whale rung is unbounded.
  final double max;

  final String emoji;

  /// The species name, as shown to a child: "Milo the Fox".
  final String species;

  /// The kid vocabulary for this size band ("car-sized" → "mountain-sized").
  ///
  /// This lives on the rung rather than in a second lookup because the
  /// prototype's `sizeLabel()` (`index.html:416-419`) is a byte-for-byte
  /// parallel of the `ANIMALS` ladder (`index.html:431-440`): same seven
  /// boundaries, same order, and every call site passes the same `diaMax` that
  /// picked the species. Two tables would only be two places for those
  /// boundaries to drift apart. The public [sizeLabel] function keeps the
  /// prototype's diameter-in, string-out signature.
  final String sizeLabel;

  @override
  String toString() => '$emoji $species (<${max}m, $sizeLabel)';
}

/// The ladder, in ascending order — a direct port of `index.html:431-440`,
/// with the labels from `index.html:416-419` folded onto their rungs.
///
/// Order is load-bearing: [animalFor] returns the first rung an asteroid fits
/// under, so sorting or reordering this list silently reassigns species.
const List<Animal> kAnimals = <Animal>[
  Animal(max: 8, emoji: '🐭', species: 'Mouse', sizeLabel: 'car-sized'),
  Animal(max: 20, emoji: '🐰', species: 'Rabbit', sizeLabel: 'bus-sized'),
  Animal(max: 50, emoji: '🦊', species: 'Fox', sizeLabel: 'house-sized'),
  Animal(max: 120, emoji: '🐯', species: 'Tiger', sizeLabel: 'plane-sized'),
  Animal(
    max: 300,
    emoji: '🐻',
    species: 'Bear',
    sizeLabel: 'football-pitch-sized',
  ),
  Animal(max: 800, emoji: '🐘', species: 'Elephant', sizeLabel: 'stadium-sized'),
  Animal(max: 2000, emoji: '🦕', species: 'Dino', sizeLabel: 'skyscraper-sized'),
  Animal(
    max: double.infinity,
    emoji: '🐋',
    species: 'Whale',
    sizeLabel: 'mountain-sized',
  ),
];

/// The species an asteroid is, decided by its real maximum diameter.
///
/// Deterministic and storage-free: the same rock is always the same animal
/// because [Asteroid.diaMax] is the only input.
Animal animalFor(Asteroid a) => _rungFor(a.diaMax);

/// How a child hears the size of a [m]-metre rock: "car-sized" →
/// "mountain-sized" (`index.html:416-419`).
String sizeLabel(double m) => _rungFor(m).sizeLabel;

/// First-fit down the ladder, exactly as `index.html:441` scans `ANIMALS`.
///
/// The trailing return is the Whale rung again — unreachable for any real
/// diameter, since Whale's ceiling is infinite, but it is the answer for a
/// `NaN` [m], where every `<` comparison is false. The prototype has the same
/// line for the same reason.
Animal _rungFor(double m) {
  for (final Animal rung in kAnimals) {
    if (m < rung.max) return rung;
  }
  return kAnimals.last;
}

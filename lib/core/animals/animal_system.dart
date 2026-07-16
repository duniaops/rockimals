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

/// The 24 first names a critter can be given — a verbatim port of
/// `index.html:430`.
///
/// Order is load-bearing: [critter] indexes this list by `hash % length`, so
/// reordering it, or adding a 25th name, renames every animal in the sky.
const List<String> kNamePool = <String>[
  'Milo',
  'Bella',
  'Coco',
  'Rocky',
  'Daisy',
  'Simba',
  'Luna',
  'Buddy',
  'Ruby',
  'Zola',
  'Pip',
  'Nova',
  'Ziggy',
  'Mango',
  'Pepper',
  'Biscuit',
  'Waffle',
  'Olive',
  'Peanut',
  'Bruno',
  'Poppy',
  'Teddy',
  'Suki',
  'Gizmo',
];

/// An asteroid presented as a friendly space animal: a species from the size
/// ladder plus a first name from [kNamePool].
class Critter {
  const Critter({required this.animal, required this.first});

  /// The rung the asteroid's diameter put it on — its emoji, species, and
  /// size label all read through here rather than being copied, so the ladder
  /// stays the one table.
  final Animal animal;

  /// The first name, chosen by hashing the real designation.
  final String first;

  /// How a child is introduced to this rock: "Milo the Fox"
  /// (`index.html:444`).
  String get name => '$first the ${animal.species}';

  @override
  String toString() => '${animal.emoji} $name';
}

/// The djb2 variant the prototype seeds its names with (`index.html:442`):
/// `h = 5381; h = ((h * 33) ^ codeUnit) >>> 0`.
///
/// The `& 0xFFFFFFFF` is JavaScript's `>>> 0` written out. Dart's ints are
/// 64-bit and do not wrap to unsigned 32-bit on their own, so without the mask
/// `h` grows past 2^32 and every name after the first character diverges from
/// the prototype. Masking is enough to be bit-exact rather than merely close:
/// `h < 2^32` means `h * 33 < 2^37`, well inside both Dart's 64-bit int and the
/// 2^53 JS doubles compute it exactly in, and the XOR only touches the low 16
/// bits — so truncating to the low 32 at the end lands on the same value JS
/// reaches by truncating at each step.
///
/// Always non-negative, which is what makes `%` in [critter] safe: Dart's `%`
/// returns a non-negative remainder anyway, but a negative hash would still
/// pick a different name than JS does.
int hashStr(String s) {
  int h = 5381;
  for (final int codeUnit in s.codeUnits) {
    h = ((h * 33) ^ codeUnit) & 0xFFFFFFFF;
  }
  return h;
}

/// The animal an asteroid *is*, name and all — a port of `index.html:443-444`.
///
/// Deterministic and storage-free (`CLAUDE.md:70`): the species comes from
/// [Asteroid.diaMax] and the first name from hashing [Asteroid.name], so the
/// same rock is the same animal on every device, every launch, with nothing
/// written down. Both inputs are facts about the asteroid, which is the whole
/// trick — there is no counter, no seed, and nothing to keep in sync.
///
/// Seeded on the **real designation** deliberately: it is this app's identity
/// for a rock everywhere else too (dedupe, radar seeds, follows), so an animal
/// cannot drift away from the asteroid it belongs to.
Critter critter(Asteroid a) => Critter(
  animal: animalFor(a),
  first: kNamePool[hashStr(a.name) % kNamePool.length],
);

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

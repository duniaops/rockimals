/// Deterministic, ambiguity-free facts for Space Zoo Memory.
library;

import 'dart:math';

import 'package:rockimals/core/animals/animal_system.dart';
import 'package:rockimals/core/format/friendly_date.dart';
import 'package:rockimals/data/models/asteroid.dart';

/// A first memory round has two pairs; a successful round can reach five.
const int kZooMemoryMinAnimals = 2;
const int kZooMemoryMaxAnimals = 5;

/// The one real NASA fact each memory round asks a child to reconnect.
enum ZooMemoryFact { size, distance, speed, arrival }

extension ZooMemoryFactCopy on ZooMemoryFact {
  String get question => switch (this) {
    ZooMemoryFact.size => 'Who was this size?',
    ZooMemoryFact.distance => 'Who flew this far from Earth?',
    ZooMemoryFact.speed => 'Who zoomed this fast?',
    ZooMemoryFact.arrival => 'Who visited on this day?',
  };

  String valueFor(Asteroid asteroid, DateTime today) => switch (this) {
    ZooMemoryFact.size => critter(asteroid).animal.sizeLabel,
    ZooMemoryFact.distance => distLabel(asteroid.missLunar),
    ZooMemoryFact.speed => speedLabel(asteroid.velKps),
    ZooMemoryFact.arrival => friendlyDate(asteroid.date, today),
  };

  /// A plain-language recap for the result board, never a raw designation.
  String recapFor(Asteroid asteroid, DateTime today) {
    final String name = critter(asteroid).first;
    return switch (this) {
      ZooMemoryFact.size =>
        '$name is ${critter(asteroid).animal.sizeLabel}, at ${asteroid.diaMax.round()} m wide.',
      ZooMemoryFact.distance =>
        '$name flew ${distLabel(asteroid.missLunar)} from Earth.',
      ZooMemoryFact.speed => '$name zoomed ${speedLabel(asteroid.velKps)}.',
      ZooMemoryFact.arrival =>
        '$name is visiting ${friendlyDate(asteroid.date, today)}.',
    };
  }
}

/// One round's chosen fact and its two independently shuffled matching rows.
class ZooMemoryRound {
  const ZooMemoryRound({
    required this.fact,
    required this.animals,
    required this.animalOfferOrder,
    required this.factOfferOrder,
  });

  final ZooMemoryFact fact;
  final List<Asteroid> animals;
  final List<Asteroid> animalOfferOrder;
  final List<Asteroid> factOfferOrder;
}

/// Builds a round whose answer is always unique.
///
/// Animal names can collide in the intentionally compact naming system, and
/// NASA values can tie. Both are excluded before dealing so a child never has
/// to guess between two visually identical or numerically equal answers.
ZooMemoryRound generateZooMemoryRound({
  required List<Asteroid> asteroids,
  required String dayKey,
  int animalCount = kZooMemoryMinAnimals,
  ZooMemoryFact? fact,
}) {
  if (animalCount < kZooMemoryMinAnimals ||
      animalCount > kZooMemoryMaxAnimals) {
    throw ArgumentError.value(
      animalCount,
      'animalCount',
      'Space Zoo Memory supports 2 to 5 animals.',
    );
  }
  final List<Asteroid> sorted = List<Asteroid>.of(asteroids)
    ..sort((Asteroid a, Asteroid b) => a.name.compareTo(b.name));
  final String designations = sorted.map((Asteroid a) => a.name).join('|');
  final List<ZooMemoryFact> possible = ZooMemoryFact.values
      .where(
        (ZooMemoryFact option) =>
            _selectUnique(
              sorted,
              option,
              dayKey,
              designations,
              animalCount,
            ).length ==
            animalCount,
      )
      .toList(growable: false);
  if (possible.isEmpty || (fact != null && !possible.contains(fact))) {
    throw ArgumentError.value(
      asteroids,
      'asteroids',
      'Space Zoo Memory needs $animalCount unique names and fact values.',
    );
  }
  final ZooMemoryFact chosen =
      fact ?? possible[hashStr('$dayKey|$designations') % possible.length];
  final List<Asteroid> animals = _selectUnique(
    sorted,
    chosen,
    dayKey,
    designations,
    animalCount,
  );
  final List<Asteroid> animalOfferOrder = List<Asteroid>.of(animals)
    ..shuffle(Random(hashStr('$dayKey|$designations|${chosen.name}|animals')));
  final List<Asteroid> factOfferOrder = List<Asteroid>.of(animals)
    ..shuffle(Random(hashStr('$dayKey|$designations|${chosen.name}|facts')));
  return ZooMemoryRound(
    fact: chosen,
    animals: List<Asteroid>.unmodifiable(animals),
    animalOfferOrder: List<Asteroid>.unmodifiable(animalOfferOrder),
    factOfferOrder: List<Asteroid>.unmodifiable(factOfferOrder),
  );
}

List<Asteroid> _selectUnique(
  List<Asteroid> sorted,
  ZooMemoryFact fact,
  String dayKey,
  String designations,
  int animalCount,
) {
  final List<Asteroid> shuffled = List<Asteroid>.of(sorted)
    ..shuffle(Random(hashStr('$dayKey|$designations|${fact.name}|select')));
  final Set<String> names = <String>{};
  final Set<Object> values = <Object>{};
  final List<Asteroid> selected = <Asteroid>[];
  for (final Asteroid asteroid in shuffled) {
    if (!names.add(critter(asteroid).name) ||
        !values.add(_valueOf(asteroid, fact))) {
      continue;
    }
    selected.add(asteroid);
    if (selected.length == animalCount) break;
  }
  return selected;
}

Object _valueOf(Asteroid asteroid, ZooMemoryFact fact) => switch (fact) {
  // Match the words a child sees, rather than a more precise hidden value.
  // Two distinct diameters can still both be Bear-sized; treating them as
  // different here would make the visible memory cards impossible to tell apart.
  ZooMemoryFact.size => critter(asteroid).animal.sizeLabel,
  ZooMemoryFact.distance => distLabel(asteroid.missLunar),
  ZooMemoryFact.speed => speedLabel(asteroid.velKps),
  ZooMemoryFact.arrival => asteroid.date,
};

/// In-session progression only; Memory does not need a storage key.
class ZooMemoryDifficulty {
  int _animalCount = kZooMemoryMinAnimals;

  int get animalCount => _animalCount;

  void recordCompletedRound() {
    _animalCount = min(kZooMemoryMaxAnimals, _animalCount + 1);
  }

  void reset() => _animalCount = kZooMemoryMinAnimals;
}

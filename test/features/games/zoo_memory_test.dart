import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/core/animals/animal_system.dart';
import 'package:rockimals/data/fallback_asteroids.dart';
import 'package:rockimals/data/models/asteroid.dart';
import 'package:rockimals/features/games/zoo_memory.dart';

void main() {
  group('generateZooMemoryRound', () {
    test('is deterministic and never deals ambiguous names or facts', () {
      final ZooMemoryRound first = generateZooMemoryRound(
        asteroids: kFallbackAsteroids,
        dayKey: '2026-07-20',
        animalCount: 3,
      );
      final ZooMemoryRound reordered = generateZooMemoryRound(
        asteroids: kFallbackAsteroids.reversed.toList(),
        dayKey: '2026-07-20',
        animalCount: 3,
      );

      expect(_names(first.animals), _names(reordered.animals));
      expect(
        _names(first.animalOfferOrder),
        _names(reordered.animalOfferOrder),
      );
      expect(_names(first.factOfferOrder), _names(reordered.factOfferOrder));
      expect(
        first.animals.map((Asteroid a) => critter(a).name).toSet(),
        hasLength(first.animals.length),
      );
      expect(
        first.animals
            .map((Asteroid a) => first.fact.valueFor(a, DateTime(2026, 7, 20)))
            .toSet(),
        hasLength(first.animals.length),
      );
    });

    test('supports every difficulty from two to five animals', () {
      for (
        int count = kZooMemoryMinAnimals;
        count <= kZooMemoryMaxAnimals;
        count++
      ) {
        final ZooMemoryRound round = generateZooMemoryRound(
          asteroids: kFallbackAsteroids,
          dayKey: '2026-07-20',
          animalCount: count,
        );
        expect(round.animals, hasLength(count));
      }
    });

    test(
      'rejects a requested fact when its values would make guessing necessary',
      () {
        final List<Asteroid> tiedDistances = kFallbackAsteroids
            .take(3)
            .map((Asteroid a) => _withDistance(a, 2))
            .toList(growable: false);

        expect(
          () => generateZooMemoryRound(
            asteroids: tiedDistances,
            dayKey: '2026-07-20',
            fact: ZooMemoryFact.distance,
          ),
          throwsArgumentError,
        );
      },
    );

    test('does not deal two animals with the same displayed size label', () {
      final List<Asteroid> sameSized = <Asteroid>[
        _withDiameter(kFallbackAsteroids[0], 302),
        _withDiameter(kFallbackAsteroids[1], 640),
        _withDiameter(kFallbackAsteroids[2], 100),
      ];

      final ZooMemoryRound round = generateZooMemoryRound(
        asteroids: sameSized,
        dayKey: '2026-07-20',
        fact: ZooMemoryFact.size,
      );
      expect(
        round.animals.map((Asteroid a) => critter(a).animal.sizeLabel).toSet(),
        hasLength(round.animals.length),
      );
    });
  });

  test('difficulty grows to five and resets without persistence', () {
    final ZooMemoryDifficulty difficulty = ZooMemoryDifficulty();
    expect(difficulty.animalCount, 2);
    for (int i = 0; i < 5; i++) {
      difficulty.recordCompletedRound();
    }
    expect(difficulty.animalCount, 5);
    difficulty.reset();
    expect(difficulty.animalCount, 2);
  });
}

List<String> _names(List<Asteroid> asteroids) =>
    asteroids.map((Asteroid a) => a.name).toList(growable: false);

Asteroid _withDistance(Asteroid asteroid, double distance) => Asteroid(
  name: asteroid.name,
  diaMax: asteroid.diaMax,
  diaMin: asteroid.diaMin,
  hazardous: asteroid.hazardous,
  missLunar: distance,
  missKm: asteroid.missKm,
  velKps: asteroid.velKps,
  mag: asteroid.mag,
  jpl: asteroid.jpl,
  date: asteroid.date,
);

Asteroid _withDiameter(Asteroid asteroid, double diameter) => Asteroid(
  name: asteroid.name,
  diaMax: diameter,
  diaMin: asteroid.diaMin,
  hazardous: asteroid.hazardous,
  missLunar: asteroid.missLunar,
  missKm: asteroid.missKm,
  velKps: asteroid.velKps,
  mag: asteroid.mag,
  jpl: asteroid.jpl,
  date: asteroid.date,
);

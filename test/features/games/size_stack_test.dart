import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/data/fallback_asteroids.dart';
import 'package:rockimals/data/models/asteroid.dart';
import 'package:rockimals/features/games/size_stack.dart';

void main() {
  group('sizeStackSpriteSize', () {
    test(
      'makes bigger real diameters visibly bigger without crowding a tower',
      () {
        expect(sizeStackSpriteSize(1), kSizeStackMinSpriteSize);
        expect(sizeStackSpriteSize(2000), kSizeStackMaxSpriteSize);
        expect(sizeStackSpriteSize(640), greaterThan(sizeStackSpriteSize(60)));
        expect(sizeStackSpriteSize(16800), kSizeStackMaxSpriteSize);
      },
    );

    test('rejects non-real diameters', () {
      expect(() => sizeStackSpriteSize(0), throwsArgumentError);
      expect(() => sizeStackSpriteSize(double.nan), throwsArgumentError);
    });
  });

  group('generateSizeStackRound', () {
    test('deals a deterministic largest-to-smallest stable tower', () {
      final SizeStackRound first = generateSizeStackRound(
        asteroids: kFallbackAsteroids,
        dayKey: '2026-07-20',
      );
      final SizeStackRound reordered = generateSizeStackRound(
        asteroids: kFallbackAsteroids.reversed.toList(),
        dayKey: '2026-07-20',
      );

      expect(_names(reordered.stackingOrder), _names(first.stackingOrder));
      expect(_names(reordered.offerOrder), _names(first.offerOrder));
      expect(first.stackingOrder, hasLength(kSizeStackMinTowerSize));
      for (int i = 1; i < first.stackingOrder.length; i++) {
        expect(
          first.stackingOrder[i - 1].diaMax,
          greaterThan(first.stackingOrder[i].diaMax),
        );
      }
      expect(
        _names(first.offerOrder).toSet(),
        _names(first.stackingOrder).toSet(),
      );
    });

    test('requires enough distinct diameters for an unambiguous tower', () {
      expect(
        () => generateSizeStackRound(
          asteroids: kFallbackAsteroids.take(3).toList(),
          dayKey: '2026-07-20',
        ),
        throwsArgumentError,
      );
    });
  });

  test('completed towers grow from four to seven animals and then stop', () {
    final SizeStackDifficulty difficulty = SizeStackDifficulty();

    expect(difficulty.towerSize, 4);
    difficulty
      ..recordCompletedTower()
      ..recordCompletedTower()
      ..recordCompletedTower()
      ..recordCompletedTower();
    expect(difficulty.towerSize, 7);
  });
}

List<String> _names(List<Asteroid> asteroids) =>
    asteroids.map((Asteroid asteroid) => asteroid.name).toList();

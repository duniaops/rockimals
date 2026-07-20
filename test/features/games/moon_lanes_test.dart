import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/data/fallback_asteroids.dart';
import 'package:rockimals/data/models/asteroid.dart';
import 'package:rockimals/features/games/moon_lanes.dart';

/// Moon Lanes' NASA-backed answers, adaptive session state, and deal order with
/// no drag widget or persistence involved.
void main() {
  group('moonLaneFor', () {
    test('maps real fallback distances into all four lanes', () {
      expect(moonLaneFor(_fallback('2020 SW').missLunar), MoonLane.insideMoon);
      expect(
        moonLaneFor(_fallback('2004 BL86').missLunar),
        MoonLane.oneToFiveMoons,
      );
      expect(
        moonLaneFor(_fallback('2011 EW').missLunar),
        MoonLane.fiveToTwentyMoons,
      );
      expect(moonLaneFor(_fallback('433 Eros').missLunar), MoonLane.farther);
    });

    test(
      'puts exact boundaries in the farther of their neighbouring lanes',
      () {
        expect(moonLaneFor(0), MoonLane.insideMoon);
        expect(moonLaneFor(0.999), MoonLane.insideMoon);
        expect(moonLaneFor(1), MoonLane.oneToFiveMoons);
        expect(moonLaneFor(4.999), MoonLane.oneToFiveMoons);
        expect(moonLaneFor(5), MoonLane.fiveToTwentyMoons);
        expect(moonLaneFor(19.999), MoonLane.fiveToTwentyMoons);
        expect(moonLaneFor(20), MoonLane.farther);
      },
    );

    test('rejects distances that cannot be real lane answers', () {
      expect(() => moonLaneFor(-0.1), throwsArgumentError);
      expect(() => moonLaneFor(double.nan), throwsArgumentError);
      expect(() => moonLaneFor(double.infinity), throwsArgumentError);
    });

    test(
      'keeps every real distance gradeable at two, three, and four lanes',
      () {
        expect(moonLaneChoicesFor(2), const <MoonLaneChoice>[
          MoonLaneChoice.insideFiveMoons,
          MoonLaneChoice.fiveOrMoreMoons,
        ]);
        expect(moonLaneChoicesFor(3), const <MoonLaneChoice>[
          MoonLaneChoice.insideMoon,
          MoonLaneChoice.oneToFiveMoons,
          MoonLaneChoice.fiveOrMoreMoons,
        ]);
        expect(
          moonLaneChoiceFor(missLunar: 0.07, laneCount: 2),
          MoonLaneChoice.insideFiveMoons,
        );
        expect(
          moonLaneChoiceFor(missLunar: 3.1, laneCount: 2),
          MoonLaneChoice.insideFiveMoons,
        );
        expect(
          moonLaneChoiceFor(missLunar: 12.4, laneCount: 2),
          MoonLaneChoice.fiveOrMoreMoons,
        );
        expect(
          moonLaneChoiceFor(missLunar: 52, laneCount: 3),
          MoonLaneChoice.fiveOrMoreMoons,
        );
        expect(
          moonLaneChoiceFor(missLunar: 12.4, laneCount: 4),
          MoonLaneChoice.fiveToTwentyMoons,
        );
        expect(
          moonLaneChoiceFor(missLunar: 52, laneCount: 4),
          MoonLaneChoice.farther,
        );
      },
    );

    test('rejects unsupported adaptive lane counts', () {
      expect(() => moonLaneChoicesFor(1), throwsArgumentError);
      expect(
        () => moonLaneChoiceFor(missLunar: 3, laneCount: 5),
        throwsArgumentError,
      );
    });
  });

  group('MoonLanesDifficulty', () {
    test('starts at two lanes and ramps 2 to 3 to 4 on sustained success', () {
      final MoonLanesDifficulty difficulty = MoonLanesDifficulty();

      expect(difficulty.laneCount, 2);
      _record(difficulty, correct: true, times: 2);
      expect(difficulty.laneCount, 2, reason: 'one short run is not sustained');
      difficulty.recordDrop(correct: true);
      expect(difficulty.laneCount, 3);

      _record(difficulty, correct: true, times: 3);
      expect(difficulty.laneCount, 4);
      _record(difficulty, correct: true, times: 6);
      expect(difficulty.laneCount, 4, reason: 'four is the lane-count ceiling');
    });

    test('backs off after repeated struggles but never below two lanes', () {
      final MoonLanesDifficulty difficulty = MoonLanesDifficulty();
      _record(
        difficulty,
        correct: true,
        times: kMoonLanesSuccessesToAdvance * 2,
      );
      expect(difficulty.laneCount, 4);

      difficulty.recordDrop(correct: false);
      expect(difficulty.laneCount, 4, reason: 'one exploratory miss is gentle');
      difficulty.recordDrop(correct: false);
      expect(difficulty.laneCount, 3);
      _record(difficulty, correct: false, times: kMoonLanesStrugglesToBackOff);
      expect(difficulty.laneCount, 2);
      _record(difficulty, correct: false, times: 6);
      expect(difficulty.laneCount, 2, reason: 'two is the lane-count floor');
    });

    test('an opposite result breaks a success or struggle run', () {
      final MoonLanesDifficulty difficulty = MoonLanesDifficulty();
      _record(difficulty, correct: true, times: 2);
      difficulty.recordDrop(correct: false);
      difficulty.recordDrop(correct: true);
      expect(difficulty.laneCount, 2);

      _record(difficulty, correct: true, times: 2);
      expect(difficulty.laneCount, 3);
      difficulty.recordDrop(correct: false);
      difficulty.recordDrop(correct: true);
      difficulty.recordDrop(correct: false);
      expect(difficulty.laneCount, 3);
    });
  });

  group('generateMoonLanesDeal', () {
    test('is deterministic from day and designations, not feed order', () {
      final List<Asteroid> first = generateMoonLanesDeal(
        asteroids: kFallbackAsteroids,
        dayKey: '2026-07-20',
      );
      final List<Asteroid> repeated = generateMoonLanesDeal(
        asteroids: kFallbackAsteroids,
        dayKey: '2026-07-20',
      );
      final List<Asteroid> reordered = generateMoonLanesDeal(
        asteroids: kFallbackAsteroids.reversed.toList(),
        dayKey: '2026-07-20',
      );

      expect(_names(repeated), _names(first));
      expect(_names(reordered), _names(first));
      expect(first, isNot(same(kFallbackAsteroids)));
    });

    test('a different date produces a different repeatable deal', () {
      final List<String> firstDay = _names(
        generateMoonLanesDeal(
          asteroids: kFallbackAsteroids,
          dayKey: '2026-07-20',
        ),
      );
      final List<String> nextDay = _names(
        generateMoonLanesDeal(
          asteroids: kFallbackAsteroids,
          dayKey: '2026-07-21',
        ),
      );

      expect(nextDay, isNot(firstDay));
      expect(nextDay.toSet(), firstDay.toSet());
    });

    test('rejects an empty sky instead of producing an unplayable deal', () {
      expect(
        () => generateMoonLanesDeal(
          asteroids: const <Asteroid>[],
          dayKey: '2026-07-20',
        ),
        throwsArgumentError,
      );
    });
  });
}

Asteroid _fallback(String designation) => kFallbackAsteroids.singleWhere(
  (Asteroid asteroid) => asteroid.name == designation,
);

void _record(
  MoonLanesDifficulty difficulty, {
  required bool correct,
  required int times,
}) {
  for (int i = 0; i < times; i++) {
    difficulty.recordDrop(correct: correct);
  }
}

List<String> _names(List<Asteroid> asteroids) =>
    asteroids.map((Asteroid asteroid) => asteroid.name).toList(growable: false);

import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/data/fallback_asteroids.dart';
import 'package:rockimals/data/models/asteroid.dart';
import 'package:rockimals/features/games/flyby_snap.dart';

void main() {
  group('flybySnapCrossingDuration', () {
    test('maps real velocity into a clamped, measurably faster crossing', () {
      expect(
        flybySnapCrossingDuration(velocityKps: 3),
        kFlybySnapSlowCrossingDuration,
      );
      expect(
        flybySnapCrossingDuration(velocityKps: 30),
        kFlybySnapFastCrossingDuration,
      );
      expect(
        flybySnapCrossingDuration(velocityKps: 15),
        lessThan(kFlybySnapSlowCrossingDuration),
      );
      expect(
        flybySnapCrossingDuration(velocityKps: 15),
        greaterThan(kFlybySnapFastCrossingDuration),
      );
      expect(
        flybySnapCrossingDuration(velocityKps: 0),
        kFlybySnapSlowCrossingDuration,
      );
      expect(
        flybySnapCrossingDuration(velocityKps: 80),
        kFlybySnapFastCrossingDuration,
      );
    });

    test('Calm Motion slows the picture but not the real difficulty fact', () {
      const double realVelocity = 19.4;
      final Duration normal = flybySnapCrossingDuration(
        velocityKps: realVelocity,
      );
      expect(
        flybySnapCrossingDuration(velocityKps: realVelocity, calmMotion: true),
        Duration(
          milliseconds: (normal.inMilliseconds * kFlybySnapCalmDurationScale)
              .round(),
        ),
      );
    });

    test('rejects impossible real velocities', () {
      expect(
        () => flybySnapDifficultyVelocity(double.nan),
        throwsArgumentError,
      );
      expect(
        () => flybySnapDifficultyVelocity(double.infinity),
        throwsArgumentError,
      );
      expect(() => flybySnapDifficultyVelocity(-0.1), throwsArgumentError);
    });
  });

  test('the photo window includes its edges and excludes nearby flight', () {
    expect(isFlybySnapPhotoInWindow(kFlybySnapWindowStart), isTrue);
    expect(isFlybySnapPhotoInWindow(kFlybySnapWindowEnd), isTrue);
    expect(isFlybySnapPhotoInWindow(kFlybySnapWindowStart - 0.001), isFalse);
    expect(isFlybySnapPhotoInWindow(kFlybySnapWindowEnd + 0.001), isFalse);
  });

  group('generateFlybySnapDeal', () {
    test('is deterministic from day and designations, not feed order', () {
      final List<Asteroid> first = generateFlybySnapDeal(
        asteroids: kFallbackAsteroids,
        dayKey: '2026-07-20',
      );
      final List<Asteroid> reordered = generateFlybySnapDeal(
        asteroids: kFallbackAsteroids.reversed.toList(),
        dayKey: '2026-07-20',
      );
      final List<Asteroid> anotherDay = generateFlybySnapDeal(
        asteroids: kFallbackAsteroids,
        dayKey: '2026-07-21',
      );

      expect(_names(reordered), _names(first));
      expect(_names(anotherDay), isNot(_names(first)));
      expect(_names(anotherDay).toSet(), _names(first).toSet());
    });

    test('rejects an empty sky instead of creating an unplayable round', () {
      expect(
        () => generateFlybySnapDeal(
          asteroids: const <Asteroid>[],
          dayKey: '2026-07-20',
        ),
        throwsArgumentError,
      );
    });
  });
}

List<String> _names(List<Asteroid> asteroids) =>
    asteroids.map((Asteroid asteroid) => asteroid.name).toList(growable: false);

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/core/audio/sound_engine.dart';
import 'package:rockimals/core/streak/day_streak.dart';
import 'package:rockimals/data/fallback_asteroids.dart';
import 'package:rockimals/data/models/asteroid.dart';
import 'package:rockimals/data/models/asteroid_feed.dart';
import 'package:rockimals/features/data/providers.dart';
import 'package:rockimals/features/games/safari_game.dart';
import 'package:rockimals/features/games/safari_missions.dart';
import 'package:rockimals/features/radar/radar_geometry.dart';
import 'package:rockimals/features/radar/radar_orbits.dart';
import 'package:rockimals/features/settings/calm_motion.dart';
import 'package:rockimals/features/settings/sound.dart';

import '../../support/recording_sound_engine.dart';
import '../../support/stub_settings.dart';

/// Radar Safari is a radar interaction, so these tests tap positions produced
/// by [RadarOrbits] itself. That makes the test exercise the game screen's
/// public hit-test path instead of guessing a location from a painted emoji.
void main() {
  final DateTime today = DateTime(2026, 7, 20);
  final List<SafariMission> missions = generateSafariMissions(
    asteroids: kFallbackAsteroids,
    dayKey: DayStreak.keyOf(today),
  );
  final SafariMission first = missions.first;
  final Asteroid target = kFallbackAsteroids.firstWhere(first.accepts);
  final Asteroid wrong = kFallbackAsteroids.firstWhere(
    (Asteroid asteroid) => !first.accepts(asteroid),
  );

  testWidgets('completes a mission and restates its supporting NASA fact', (
    WidgetTester tester,
  ) async {
    await _mount(tester, today: today);

    expect(find.text(first.prompt), findsOneWidget);
    await _tapAsteroid(tester, target);

    expect(find.text(first.supportingFact(target)), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);
  });

  testWidgets('wrong radar taps stay in the mission and reveal a region hint', (
    WidgetTester tester,
  ) async {
    await _mount(tester, today: today);

    await _tapAsteroid(tester, wrong);
    expect(
      find.text('Not this animal yet — read the clue and try another one.'),
      findsOneWidget,
    );
    expect(find.text('Next'), findsNothing);
    expect(find.text(first.prompt), findsOneWidget);

    await _tapAsteroid(tester, wrong);
    expect(find.textContaining('Look near the '), findsOneWidget);
    expect(find.text('Next'), findsNothing);
    expect(find.text(first.prompt), findsOneWidget);
  });
}

Future<void> _mount(WidgetTester tester, {required DateTime today}) async {
  tester.view
    ..physicalSize = const Size(390, 780)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        asteroidFeedProvider.overrideWith(
          (Ref ref) => AsteroidFeed(
            asteroids: kFallbackAsteroids,
            todayList: kFallbackAsteroids,
            feedRange: 'sample data',
            provenance: FeedProvenance.sample,
          ),
        ),
        dayClockProvider.overrideWithValue(() => today),
        soundEngineProvider.overrideWithValue(RecordingSoundEngine()),
        soundOnProvider.overrideWith(() => StubSoundOn(true)),
        reducedMotionProvider.overrideWith(StubCalmMotion.new),
      ],
      child: const MaterialApp(home: SafariGame()),
    ),
  );
  await tester.pump();
}

Future<void> _tapAsteroid(WidgetTester tester, Asteroid asteroid) async {
  final Finder radar = find.byKey(const ValueKey<String>('safari-radar'));
  await tester.ensureVisible(radar);
  final Size size = tester.getSize(radar);
  final RadarOrbits orbits = RadarOrbits.seed(kFallbackAsteroids);
  final RadarOrbit orbit = orbits.orbits.singleWhere(
    (RadarOrbit candidate) => candidate.asteroid.name == asteroid.name,
  );
  final Offset local = orbits.positionOf(
    orbit,
    geometry: RadarGeometry(
      size: size,
      maxLd: RadarGeometry.maxLdFor(kFallbackAsteroids),
    ),
    zoom: 1,
    viewRot: 0,
  );
  await tester.tapAt(tester.getTopLeft(radar) + local);
  await tester.pump();
}

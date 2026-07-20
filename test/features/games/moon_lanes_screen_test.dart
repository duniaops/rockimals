import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/core/a11y/tap_target.dart';
import 'package:rockimals/core/animals/animal_system.dart';
import 'package:rockimals/core/audio/sound_engine.dart';
import 'package:rockimals/core/streak/day_streak.dart';
import 'package:rockimals/data/fallback_asteroids.dart';
import 'package:rockimals/data/models/asteroid.dart';
import 'package:rockimals/data/models/asteroid_feed.dart';
import 'package:rockimals/features/data/providers.dart';
import 'package:rockimals/features/games/moon_lanes.dart';
import 'package:rockimals/features/games/moon_lanes_screen.dart';
import 'package:rockimals/features/settings/calm_motion.dart';
import 'package:rockimals/features/settings/sound.dart';

import '../../support/memory_store.dart';
import '../../support/recording_sound_engine.dart';
import '../../support/stub_settings.dart';

void main() {
  final DateTime today = DateTime(2026, 7, 20);
  final Asteroid first = generateMoonLanesDeal(
    asteroids: kFallbackAsteroids,
    dayKey: DayStreak.keyOf(today),
  ).first;

  testWidgets('a correct drop reveals the real Moon distance', (tester) async {
    await _mount(tester);

    await _dragTo(tester, _correctLane(first));

    expect(find.text('✓ Great Moon sorting!'), findsOneWidget);
    expect(find.textContaining(distLabel(first.missLunar)), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);
  });

  testWidgets('a wrong drop bounces back with encouragement and no game over', (
    tester,
  ) async {
    await _mount(tester);

    await _dragTo(tester, _wrongLane(first));

    expect(find.text('Nice try — your animal bounced back!'), findsOneWidget);
    expect(find.textContaining(distLabel(first.missLunar)), findsOneWidget);
    expect(find.textContaining('There are no lives to lose.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('moon-lanes-animal')),
      findsOneWidget,
    );
    expect(find.textContaining('game over', findRichText: true), findsNothing);
  });

  testWidgets('Calm Motion uses the shorter bounce without changing the fact', (
    tester,
  ) async {
    await _mount(tester);
    await _dragTo(tester, _wrongLane(first));
    await tester.pump(kMoonLanesCalmBounceDuration);
    final double normalOffset = _bounceOffset(tester);

    await _mount(tester, calmMotion: true);
    await _dragTo(tester, _wrongLane(first));
    await tester.pump(kMoonLanesCalmBounceDuration);

    expect(normalOffset.abs(), greaterThan(0));
    expect(_bounceOffset(tester), 0);
    expect(find.textContaining(distLabel(first.missLunar)), findsOneWidget);
  });

  testWidgets('Moon lane drop zones meet the 48dp target floor', (
    tester,
  ) async {
    await _mount(tester);

    for (final MoonLaneChoice choice in moonLaneChoicesFor(2)) {
      final Size size = tester.getSize(
        find.byKey(ValueKey<String>('moon-lane-${choice.name}')),
      );
      expect(size.height, greaterThanOrEqualTo(kMinTapTarget));
    }
  });
}

Future<void> _mount(WidgetTester tester, {bool calmMotion = false}) async {
  tester.view
    ..physicalSize = const Size(390, 780)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        storeProvider.overrideWithValue(MemoryStore()),
        asteroidFeedProvider.overrideWith(
          (Ref ref) => AsteroidFeed(
            asteroids: kFallbackAsteroids,
            todayList: kFallbackAsteroids,
            feedRange: 'sample data',
            provenance: FeedProvenance.sample,
          ),
        ),
        dayClockProvider.overrideWithValue(() => DateTime(2026, 7, 20)),
        soundEngineProvider.overrideWithValue(RecordingSoundEngine()),
        soundOnProvider.overrideWith(() => StubSoundOn(true)),
        reducedMotionProvider.overrideWith(() => StubCalmMotion(calmMotion)),
      ],
      child: const MaterialApp(home: MoonLanesScreen()),
    ),
  );
  await tester.pump();
}

MoonLaneChoice _correctLane(Asteroid asteroid) =>
    moonLaneChoiceFor(missLunar: asteroid.missLunar, laneCount: 2);

MoonLaneChoice _wrongLane(Asteroid asteroid) => moonLaneChoicesFor(
  2,
).firstWhere((MoonLaneChoice choice) => choice != _correctLane(asteroid));

Future<void> _dragTo(WidgetTester tester, MoonLaneChoice choice) async {
  final Offset source = tester.getCenter(
    find.byKey(const ValueKey<String>('moon-lanes-animal')),
  );
  final Offset target = tester.getCenter(
    find.byKey(ValueKey<String>('moon-lane-${choice.name}')),
  );
  final TestGesture gesture = await tester.startGesture(source);
  await tester.pump();
  await gesture.moveTo(target, timeStamp: const Duration(milliseconds: 250));
  await tester.pump();
  await gesture.up();
  await tester.pump();
}

double _bounceOffset(WidgetTester tester) => tester
    .widget<Transform>(find.byKey(const ValueKey<String>('moon-lanes-bounce')))
    .transform
    .storage[12];

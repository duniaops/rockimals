import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/core/a11y/tap_target.dart';
import 'package:rockimals/core/audio/sound_engine.dart';
import 'package:rockimals/core/streak/day_streak.dart';
import 'package:rockimals/data/fallback_asteroids.dart';
import 'package:rockimals/data/models/asteroid.dart';
import 'package:rockimals/data/models/asteroid_feed.dart';
import 'package:rockimals/features/data/providers.dart';
import 'package:rockimals/features/games/zoo_memory.dart';
import 'package:rockimals/features/games/zoo_memory_screen.dart';
import 'package:rockimals/features/settings/calm_motion.dart';
import 'package:rockimals/features/settings/sound.dart';

import '../../support/memory_store.dart';
import '../../support/recording_sound_engine.dart';
import '../../support/stub_settings.dart';

void main() {
  final DateTime today = DateTime(2026, 7, 20);
  final ZooMemoryRound firstRound = generateZooMemoryRound(
    asteroids: kFallbackAsteroids,
    dayKey: '${DayStreak.keyOf(today)}|0',
  );

  testWidgets('shows real fact pairs before hiding them for an easy round', (
    tester,
  ) async {
    await _mount(tester);

    expect(find.text('Remember these pairs!'), findsOneWidget);
    expect(
      find.textContaining('Easy round: the animal pictures will stay visible.'),
      findsOneWidget,
    );
    for (final Asteroid asteroid in firstRound.animals) {
      expect(
        find.textContaining(firstRound.fact.valueFor(asteroid, today)),
        findsOneWidget,
      );
    }
  });

  testWidgets('a wrong match is recoverable and results replay real facts', (
    tester,
  ) async {
    await _mount(tester);
    await tester.tap(find.text('Hide facts and play'));
    await tester.pump();

    final Asteroid fact = firstRound.factOfferOrder.first;
    final Asteroid wrong = firstRound.animalOfferOrder.firstWhere(
      (Asteroid asteroid) => asteroid.name != fact.name,
    );
    await _match(tester, fact, wrong);

    expect(find.text('Nice try — keep remembering!'), findsOneWidget);
    expect(find.textContaining('There are no lives to lose'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pump();

    for (final Asteroid asteroid in firstRound.animals) {
      await _match(tester, asteroid, asteroid);
      await tester.tap(find.text('Next'));
      await tester.pump();
    }

    expect(find.text('You remembered the whole zoo!'), findsOneWidget);
    for (final Asteroid asteroid in firstRound.animals) {
      expect(
        find.textContaining(firstRound.fact.recapFor(asteroid, today)),
        findsOneWidget,
      );
    }
  });

  testWidgets('fact and animal cards meet the 48dp target floor', (
    tester,
  ) async {
    await _mount(tester);
    await tester.tap(find.text('Hide facts and play'));
    await tester.pump();

    expect(
      tester
          .getSize(
            find.byKey(
              ValueKey<String>(
                'zoo-memory-fact-${firstRound.factOfferOrder.first.name}',
              ),
            ),
          )
          .height,
      greaterThanOrEqualTo(kMinTapTarget),
    );
    expect(
      tester
          .getSize(
            find.byKey(
              ValueKey<String>(
                'zoo-memory-animal-${firstRound.animalOfferOrder.first.name}',
              ),
            ),
          )
          .height,
      greaterThanOrEqualTo(kMinTapTarget),
    );
  });
}

Future<void> _match(WidgetTester tester, Asteroid fact, Asteroid animal) async {
  await tester.tap(
    find.byKey(ValueKey<String>('zoo-memory-fact-${fact.name}')),
  );
  await tester.pump();
  await tester.tap(
    find.byKey(ValueKey<String>('zoo-memory-animal-${animal.name}')),
  );
  await tester.pump();
}

Future<void> _mount(WidgetTester tester) async {
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
        reducedMotionProvider.overrideWith(StubCalmMotion.new),
      ],
      child: const MaterialApp(home: ZooMemoryScreen()),
    ),
  );
  await tester.pump();
}

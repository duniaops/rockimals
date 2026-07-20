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
import 'package:rockimals/features/games/flyby_snap.dart';
import 'package:rockimals/features/games/flyby_snap_screen.dart';
import 'package:rockimals/features/games/game_round_timer.dart';
import 'package:rockimals/features/settings/calm_motion.dart';
import 'package:rockimals/features/settings/sound.dart';

import '../../support/memory_store.dart';
import '../../support/recording_sound_engine.dart';
import '../../support/stub_settings.dart';

void main() {
  final DateTime today = DateTime(2026, 7, 20);
  final Asteroid first = generateFlybySnapDeal(
    asteroids: kFallbackAsteroids,
    dayKey: DayStreak.keyOf(today),
  ).first;

  testWidgets('a missed photo reveals speed and always gets a second try', (
    tester,
  ) async {
    await _mount(tester);
    final ProviderContainer container = ProviderScope.containerOf(
      tester.element(find.byType(FlybySnapScreen)),
    );

    await tester.tap(find.byKey(const ValueKey<String>('flyby-photo-button')));
    await tester.pump();

    expect(find.text('Almost! Your photo gets one more try.'), findsOneWidget);
    expect(find.textContaining(speedLabel(first.velKps)), findsOneWidget);
    expect(
      container.read(gameRoundTimerPausedProvider),
      isTrue,
      reason: 'shared feedback pauses Flyby Snap while the fact is readable',
    );

    final Finder next = find.text('Next');
    await tester.scrollUntilVisible(next, 200);
    await tester.tap(next);
    await tester.pump();

    expect(find.text('2/2'), findsOneWidget);
    expect(container.read(gameRoundTimerPausedProvider), isFalse);
  });

  testWidgets(
    'Calm Motion slows the animation without changing revealed speed',
    (tester) async {
      await _mount(tester, calmMotion: true);

      expect(
        find.text('🐢 Calm Motion makes the crossing slower.'),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('flyby-photo-button')),
      );
      await tester.pump();

      expect(find.textContaining(speedLabel(first.velKps)), findsOneWidget);
    },
  );

  testWidgets('a badge pause holds the photo timer until celebration clears', (
    tester,
  ) async {
    await _mount(tester);
    final ProviderContainer container = ProviderScope.containerOf(
      tester.element(find.byType(FlybySnapScreen)),
    );
    final GameRoundTimerPauseNotifier pause = container.read(
      gameRoundTimerPauseReasonsProvider.notifier,
    );

    pause.setPaused(GameRoundTimerPauseReason.badge, true);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('flyby-photo-button')));
    await tester.pump();

    expect(find.text('Almost! Your photo gets one more try.'), findsNothing);

    pause.setPaused(GameRoundTimerPauseReason.badge, false);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('flyby-photo-button')));
    await tester.pump();

    expect(find.text('Almost! Your photo gets one more try.'), findsOneWidget);
  });

  testWidgets('the photo control keeps the 48dp target floor', (tester) async {
    await _mount(tester);

    expect(
      tester
          .getSize(find.byKey(const ValueKey<String>('flyby-photo-button')))
          .height,
      greaterThanOrEqualTo(kMinTapTarget),
    );
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
        // A production first play opens the Lift Off popup, which pauses every
        // game timer until a child dismisses it. This direct screen harness
        // intentionally has no popup host, so seed that already-earned badge
        // and keep the Flyby timer test focused on this game's own behaviour.
        storeProvider.overrideWithValue(
          MemoryStore(badges: const <String>['play']),
        ),
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
      child: const MaterialApp(home: FlybySnapScreen()),
    ),
  );
  await tester.pump();
}

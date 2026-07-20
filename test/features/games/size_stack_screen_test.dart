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
import 'package:rockimals/features/games/size_stack.dart';
import 'package:rockimals/features/games/size_stack_screen.dart';
import 'package:rockimals/features/settings/calm_motion.dart';
import 'package:rockimals/features/settings/sound.dart';

import '../../support/memory_store.dart';
import '../../support/recording_sound_engine.dart';
import '../../support/stub_settings.dart';

void main() {
  final String dayKey = DayStreak.keyOf(DateTime(2026, 7, 20));
  final SizeStackRound firstRound = generateSizeStackRound(
    asteroids: kFallbackAsteroids,
    dayKey: '$dayKey|0',
  );

  testWidgets('introduces the size ladder before a tower starts', (
    tester,
  ) async {
    await _mount(tester);

    expect(find.text('Build from big to small'), findsOneWidget);
    expect(find.text('Start stacking'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('size-stack-tower')),
      findsNothing,
    );

    await tester.tap(find.text('Start stacking'));
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('size-stack-tower')),
      findsOneWidget,
    );
  });

  testWidgets('a wrong placement wobbles and recovers for another try', (
    tester,
  ) async {
    await _start(tester);
    final Asteroid wrong = firstRound.offerOrder.firstWhere(
      (Asteroid asteroid) =>
          asteroid.name != firstRound.stackingOrder.first.name,
    );

    await _drag(tester, wrong);
    expect(find.text('Whoops — wobble, wobble!'), findsOneWidget);
    expect(find.textContaining('The tower recovered'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
    expect(_wobbleAngle(tester).abs(), greaterThan(0));

    final Finder next = find.text('Next');
    await tester.ensureVisible(next);
    await tester.pump();
    await tester.tap(next);
    await tester.pump();
    expect(
      find.byKey(ValueKey<String>('size-stack-${wrong.name}')),
      findsOneWidget,
    );
  });

  testWidgets(
    'a completed tower compares the largest and smallest real sizes',
    (tester) async {
      await _start(tester);

      for (final Asteroid asteroid in firstRound.stackingOrder) {
        await _drag(tester, asteroid);
        final Finder next = find.text('Next');
        await tester.ensureVisible(next);
        await tester.pump();
        await tester.tap(next);
        await tester.pump();
      }

      final Asteroid largest = firstRound.stackingOrder.first;
      final Asteroid smallest = firstRound.stackingOrder.last;
      expect(find.text('What a steady tower!'), findsOneWidget);
      expect(
        find.textContaining('${largest.diaMax.round()} m'),
        findsOneWidget,
      );
      expect(
        find.textContaining('${smallest.diaMax.round()} m'),
        findsOneWidget,
      );
    },
  );

  testWidgets('tower and animal controls meet the 48dp target floor', (
    tester,
  ) async {
    await _start(tester);
    expect(
      tester
          .getSize(find.byKey(const ValueKey<String>('size-stack-tower')))
          .height,
      greaterThanOrEqualTo(kMinTapTarget),
    );
    expect(
      tester
          .getSize(
            find.byKey(
              ValueKey<String>(
                'size-stack-${firstRound.offerOrder.first.name}',
              ),
            ),
          )
          .height,
      greaterThanOrEqualTo(kMinTapTarget),
    );
  });
}

Future<void> _start(WidgetTester tester) async {
  await _mount(tester);
  await tester.tap(find.text('Start stacking'));
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
      child: const MaterialApp(home: SizeStackScreen()),
    ),
  );
  await tester.pump();
}

Future<void> _drag(WidgetTester tester, Asteroid asteroid) async {
  final Offset source = tester.getCenter(
    find.byKey(ValueKey<String>('size-stack-${asteroid.name}')),
  );
  final Offset target = tester.getCenter(
    find.byKey(const ValueKey<String>('size-stack-tower')),
  );
  final TestGesture gesture = await tester.startGesture(source);
  await tester.pump();
  await gesture.moveTo(target, timeStamp: const Duration(milliseconds: 250));
  await tester.pump();
  await gesture.up();
  await tester.pump();
}

double _wobbleAngle(WidgetTester tester) => tester
    .widget<Transform>(find.byKey(const ValueKey<String>('size-stack-wobble')))
    .transform
    .storage[1];

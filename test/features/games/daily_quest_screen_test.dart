import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/core/audio/sound_engine.dart';
import 'package:rockimals/core/streak/day_streak.dart';
import 'package:rockimals/data/fallback_asteroids.dart';
import 'package:rockimals/data/models/asteroid_feed.dart';
import 'package:rockimals/features/data/providers.dart';
import 'package:rockimals/features/games/daily_quest.dart';
import 'package:rockimals/features/games/daily_quest_screen.dart';
import 'package:rockimals/features/settings/calm_motion.dart';
import 'package:rockimals/features/settings/sound.dart';

import '../../support/memory_store.dart';
import '../../support/recording_sound_engine.dart';
import '../../support/stub_settings.dart';

void main() {
  final DateTime today = DateTime(2026, 7, 20);
  final DailyQuest quest = generateDailyQuest(
    asteroids: kFallbackAsteroids,
    dayKey: DayStreak.keyOf(today),
  );

  testWidgets('completes all three parts and keeps the daily patch', (
    tester,
  ) async {
    final MemoryStore store = MemoryStore(
      dailyQuestPatches: <String>['2026-07-18'],
    );
    await _mount(tester, store);

    await tester.tap(
      find.byKey(ValueKey<String>('daily-quest-radar-${quest.target.name}')),
    );
    await tester.pump();
    await tester.ensureVisible(find.text('Next'));
    await tester.tap(find.text('Next'));
    await tester.pump();

    await tester.tap(
      find.byKey(ValueKey<String>('daily-quest-data-${quest.target.name}')),
    );
    await tester.pump();
    await tester.ensureVisible(find.text('Next'));
    await tester.tap(find.text('Next'));
    await tester.pump();

    for (int tap = 0; tap < quest.actionTapGoal; tap++) {
      await tester.tap(find.byKey(const ValueKey<String>('daily-quest-dash')));
      await tester.pump();
    }

    expect(find.text('Daily mission patch earned! 🏅'), findsOneWidget);
    expect(store.dailyQuestPatches, <String>['2026-07-18', '2026-07-20']);
  });
}

Future<void> _mount(WidgetTester tester, MemoryStore store) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        storeProvider.overrideWithValue(store),
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
      child: const MaterialApp(home: DailyQuestScreen()),
    ),
  );
  await tester.pump();
}

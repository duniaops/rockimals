import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// `Override` is not exported from the package root — Riverpod 3 parks it under
// `misc.dart`. See the same note in `lib/main.dart`.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/data/models/asteroid_feed.dart';
import 'package:rockimals/features/data/providers.dart';
import 'package:rockimals/main.dart';

import '../../support/memory_store.dart';

/// The third trigger for the consecutive-days-played streak: a child who never
/// closed the app and never started a game, coming back on a new day.
///
/// **The habit this is here for.** A phone is locked, not quit. A child leaves
/// the radar running, the screen goes dark, and the next morning they unlock it
/// — same process, same widget tree, no cold launch. `bootstrap()`'s
/// launch-time write already ran yesterday and `GameActions.markPlayed` needs a
/// game they have not started, so before this the flame read yesterday's count
/// until they force-quit the app. `day_streak_test.dart` owns the rule itself;
/// this owns the wiring, which is where the staleness lived.
void main() {
  group('the rule', () {
    /// A container over a seeded in-memory store, with "today" pinned.
    ///
    /// The clock is overridden rather than faked at the `DateTime.now` level so
    /// this drives the app's *real* `recordEngagementProvider` — callbacks,
    /// invalidation and all — on any day it likes.
    (ProviderContainer, MemoryStore) containerOn(
      DateTime today, {
      String? lastPlayed,
      int streak = 0,
    }) {
      final MemoryStore store = MemoryStore(dayStreak: streak)
        ..lastPlayedDate = lastPlayed;
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          storeProvider.overrideWithValue(store),
          dayClockProvider.overrideWithValue(() => today),
        ],
      );
      addTearDown(container.dispose);
      return (container, store);
    }

    test('a new day advances the flame and tells it', () async {
      final (ProviderContainer container, MemoryStore store) = containerOn(
        DateTime(2026, 7, 19),
        lastPlayed: '2026-07-18',
        streak: 1,
      );
      expect(container.read(dayStreakProvider), 1);

      final List<int> seen = <int>[];
      container.listen<int>(
        dayStreakProvider,
        (int? _, int next) => seen.add(next),
      );

      await container.read(recordEngagementProvider)();

      expect(container.read(dayStreakProvider), 2);
      expect(store.lastPlayedDate, '2026-07-19');
      expect(seen, <int>[
        2,
      ], reason: 'the flame must be told, not just re-read');
    });

    test('and the same day writes nothing and repaints nothing', () async {
      // The overwhelmingly common case: every unlock after the first on a given
      // day. It must be free — no box write, no rebuild of anything watching
      // the flame.
      final (ProviderContainer container, MemoryStore store) = containerOn(
        DateTime(2026, 7, 19, 20),
        lastPlayed: '2026-07-19',
        streak: 4,
      );
      expect(container.read(dayStreakProvider), 4);

      final List<int> seen = <int>[];
      container.listen<int>(
        dayStreakProvider,
        (int? _, int next) => seen.add(next),
      );

      await container.read(recordEngagementProvider)();

      expect(container.read(dayStreakProvider), 4);
      expect(store.dayStreak, 4);
      expect(seen, isEmpty, reason: 'a same-day return must not repaint');
    });

    test('a return after a gap starts a fresh run', () async {
      final (ProviderContainer container, _) = containerOn(
        DateTime(2026, 7, 19),
        lastPlayed: '2026-07-12',
        streak: 6,
      );

      await container.read(recordEngagementProvider)();

      expect(container.read(dayStreakProvider), 1);
    });
  });

  group('the wiring', () {
    testWidgets('a resume on a new day moves the flame with no relaunch', (
      tester,
    ) async {
      // The item's Done-when, end to end and through the app itself: no
      // `bootstrap()`, no game, no new process — just a phone coming back.
      //
      // The store is seeded as a child who used the app yesterday, and the
      // clock says today, which is the state a phone left open overnight is
      // actually in.
      final MemoryStore store = MemoryStore(dayStreak: 3)
        ..lastPlayedDate = '2026-07-18';
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            storeProvider.overrideWithValue(store),
            dayClockProvider.overrideWithValue(() => DateTime(2026, 7, 19)),
            // Held back rather than resolved: this asks nothing about the sky,
            // and a real repository here would build a Dio and leave its
            // ten-second ceiling pending at teardown.
            asteroidFeedProvider.overrideWith(
              (Ref ref) => Completer<AsteroidFeed>().future,
            ),
          ],
          child: const RockimalsApp(),
        ),
      );

      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(RockimalsApp)),
      );
      expect(container.read(dayStreakProvider), 3);

      await _backgroundAndReturn(tester);

      expect(container.read(dayStreakProvider), 4);
      expect(store.dayStreak, 4);
      expect(store.lastPlayedDate, '2026-07-19');
    });

    testWidgets('and a resume on the same day leaves the box alone', (
      tester,
    ) async {
      final MemoryStore store = MemoryStore(dayStreak: 3)
        ..lastPlayedDate = '2026-07-19';
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            storeProvider.overrideWithValue(store),
            dayClockProvider.overrideWithValue(() => DateTime(2026, 7, 19, 9)),
            asteroidFeedProvider.overrideWith(
              (Ref ref) => Completer<AsteroidFeed>().future,
            ),
          ],
          child: const RockimalsApp(),
        ),
      );

      await _backgroundAndReturn(tester);

      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(RockimalsApp)),
      );
      expect(container.read(dayStreakProvider), 3);
      expect(store.dayStreak, 3);
    });
  });
}

/// A full trip to the background and back, stepped through the neighbouring
/// states in the order a device delivers them — see
/// `test/core/lifecycle/app_resume_host_test.dart`, which owns why.
///
/// The trailing pump is what lets the write land: the lifecycle callback is
/// synchronous and fires the store write unawaited, so the streak moves on the
/// microtask after the event rather than during it.
Future<void> _backgroundAndReturn(WidgetTester tester) async {
  for (final AppLifecycleState state in <AppLifecycleState>[
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
    await tester.pump();
  }
  await tester.pump();
}

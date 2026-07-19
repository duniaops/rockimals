import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// `Override` is not exported from the package root — Riverpod 3 parks it under
// `misc.dart`. See the same note in `lib/main.dart`.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/data/models/asteroid.dart';
import 'package:rockimals/data/models/asteroid_feed.dart';
import 'package:rockimals/features/data/providers.dart';
import 'package:rockimals/features/shell/app_shell.dart';
import 'package:rockimals/main.dart';

import '../../support/memory_store.dart';

/// The sky's half of the once-per-process problem the day streak's resume hook
/// solved for the flame.
///
/// **The habit this is here for is the same one.** A phone is locked, not quit.
/// `loadData()` runs exactly once per process (plan decision 13), so a child who
/// leaves the radar open overnight and unlocks it in the morning is looking at
/// yesterday's animals — under a Sky tab whose footer prints today's date. There
/// is no launch to recompute it and no game they need to have started.
///
/// **Why this is more than `ref.invalidate(asteroidFeedProvider)` on resume.**
/// That one line would re-hit the network on every single unlock, and every
/// screen behind the loading gate reads the feed with `.requireValue`. So the
/// two things these tests actually pin are the guard — a same-day return must
/// cost nothing — and the continuity: the child must not be bounced back to
/// "Contacting NASA…", or offline, out to a sample sky they were not looking at
/// a moment ago.
void main() {
  group('the rule', () {
    test('a return on the same day re-requests nothing', () async {
      // The overwhelmingly common case, and the one that has to be free: every
      // unlock after the first on a given day. NASA's feed is keyed by calendar
      // day, so re-asking could not return anything different — it would only
      // spend a request against a key a household shares.
      final _CountingSky sky = _CountingSky();
      final ProviderContainer container = _containerOn(
        () => DateTime(2026, 7, 19, 9),
        sky,
      );

      await _launch(container);
      expect(sky.loads, 1);

      container.read(refreshSkyForNewDayProvider)();

      // Awaited for the same reason the new-day test awaits: an invalidation is
      // scheduled rather than applied on the spot, so a bare read here would
      // pass even against a refresh that fires unconditionally.
      await container.read(asteroidFeedProvider.future);
      expect(sky.loads, 1);
    });

    test('and a return on a new day asks for that day\'s sky', () async {
      final _CountingSky sky = _CountingSky();
      final _MutableClock now = _MutableClock(DateTime(2026, 7, 19, 23, 50));
      final ProviderContainer container = _containerOn(now.read, sky);

      await _launch(container);
      expect(sky.loads, 1);

      // Midnight, with the phone in a pocket the whole time.
      now.value = DateTime(2026, 7, 20, 7);
      container.read(refreshSkyForNewDayProvider)();

      // Awaited because an invalidation is scheduled, not applied on the spot —
      // and the assertion still means what it says: had the guard swallowed the
      // refresh, this would hand back the sky already in hand and leave the
      // count at one.
      await container.read(asteroidFeedProvider.future);
      expect(sky.loads, 2);
    });

    test('and the sky that lands re-stamps the day, so it asks once', () async {
      // The guard is only as good as the stamp behind it. If the refreshed sky
      // did not move `skyDayProvider` forward, every later unlock that morning
      // would still compare against yesterday and re-request — turning the
      // once-a-day refresh into the unconditional one this exists to avoid.
      final _CountingSky sky = _CountingSky();
      final _MutableClock now = _MutableClock(DateTime(2026, 7, 19, 23, 50));
      final ProviderContainer container = _containerOn(now.read, sky);

      await _launch(container);

      now.value = DateTime(2026, 7, 20, 7);
      container.read(refreshSkyForNewDayProvider)();
      await container.read(asteroidFeedProvider.future);
      expect(sky.loads, 2);

      // Two more unlocks over breakfast.
      now.value = DateTime(2026, 7, 20, 8);
      container.read(refreshSkyForNewDayProvider)();
      now.value = DateTime(2026, 7, 20, 9);
      container.read(refreshSkyForNewDayProvider)();

      expect(sky.loads, 2, reason: 'the new sky is today\'s; leave it alone');
    });

    test('a day is the child\'s local one, not the feed\'s UTC window', () async {
      // `skyDayProvider` reads `DayStreak.keyOf`, whose local-day rule the flame
      // already depends on. The failure this guards is a stamp taken in UTC:
      // on a UTC+13 phone the sky would then roll over mid-afternoon, refreshing
      // while the child watched, and stay stale through their actual midnight.
      final _CountingSky sky = _CountingSky();
      final _MutableClock now = _MutableClock(DateTime(2026, 7, 19, 23, 30));
      final ProviderContainer container = _containerOn(now.read, sky);

      expect(container.read(skyDayProvider), '2026-07-19');

      now.value = DateTime(2026, 7, 20, 0, 30);
      container.invalidate(asteroidFeedProvider);
      await container.read(asteroidFeedProvider.future);

      expect(container.read(skyDayProvider), '2026-07-20');
    });

    test('a stamp nobody took fails towards not refreshing', () async {
      // `skyDayProvider` is created at launch by `TitleScreen`, and it is
      // nothing else's dependency — so an entry point that skipped it would make
      // the resume its first reader. It then stamps *now*, matches today, and
      // this does nothing. That is the safe direction: a sky that goes
      // unrefreshed, rather than one refetched on every unlock forever.
      final _CountingSky sky = _CountingSky();
      final ProviderContainer container = _containerOn(
        () => DateTime(2026, 7, 19),
        sky,
      );

      // Deliberately no `_launch` — nothing has created the stamp.
      container.read(refreshSkyForNewDayProvider)();

      // One load, and it is not a refresh: creating [SkyDay] subscribes it to
      // the feed, which is what starts that first fetch. What matters is that
      // nothing was *re*-requested — a second load here would mean the stamp
      // had defaulted to something older than today.
      expect(sky.loads, 1);
    });
  });

  group('the wiring', () {
    testWidgets('a new day\'s sky arrives without the loading screen', (
      tester,
    ) async {
      // The item's Done-when, through the real app: title → gate → shell, then
      // a night in a pocket. The refresh must not put the child back behind
      // "Contacting NASA…" — the gate is what they passed to get here, and
      // returning them to it on an unlock reads as the app having crashed and
      // restarted.
      final _CountingSky sky = _CountingSky(holdSecondLoad: true);
      final _MutableClock now = _MutableClock(DateTime(2026, 7, 19, 23, 50));
      await tester.pumpWidget(_app(now.read, sky));
      await _tapPlay(tester);

      expect(find.byType(AppShell), findsOneWidget);
      expect(find.text('Contacting NASA…'), findsNothing);

      now.value = DateTime(2026, 7, 20, 7);
      await _backgroundAndReturn(tester);

      // The second load is deliberately still in flight here — that is the
      // window in which a torn-down feed would show.
      expect(sky.loads, 2);
      expect(find.text('Contacting NASA…'), findsNothing);
    });

    testWidgets('and the child keeps their animals while it is in flight', (
      tester,
    ) async {
      // The other half, and the one that matters offline: a refresh that
      // dropped the feed's value would leave every `.requireValue` behind the
      // gate with nothing to answer. Riverpod carries the previous sky through
      // an invalidation — this is what says so out loud, so a future change to
      // how the refresh is triggered cannot quietly lose it.
      final _CountingSky sky = _CountingSky(holdSecondLoad: true);
      final _MutableClock now = _MutableClock(DateTime(2026, 7, 19, 23, 50));
      await tester.pumpWidget(_app(now.read, sky));
      await _tapPlay(tester);

      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(RockimalsApp)),
      );
      expect(container.read(asteroidsProvider).requireValue, hasLength(1));

      now.value = DateTime(2026, 7, 20, 7);
      await _backgroundAndReturn(tester);

      final AsyncValue<List<Asteroid>> mid = container.read(asteroidsProvider);
      expect(mid.isLoading, isTrue, reason: 'the refresh is still running');
      expect(
        mid.requireValue.single.name,
        _rock.name,
        reason: 'and the child is still looking at the animal they had',
      );
    });

    testWidgets('a same-day unlock never reaches the network', (tester) async {
      final _CountingSky sky = _CountingSky();
      final _MutableClock now = _MutableClock(DateTime(2026, 7, 19, 9));
      await tester.pumpWidget(_app(now.read, sky));
      await _tapPlay(tester);

      now.value = DateTime(2026, 7, 19, 18);
      await _backgroundAndReturn(tester);

      expect(sky.loads, 1);
    });
  });
}

/// A feed that counts how many times it was actually asked, which is the only
/// thing every test here is really measuring.
///
/// [holdSecondLoad] leaves the refresh pending so a test can look at the app
/// *during* it — the window where a torn-down feed or a re-entered loading gate
/// would be visible, and which a completed load would close before any
/// assertion ran.
class _CountingSky {
  _CountingSky({this.holdSecondLoad = false});

  final bool holdSecondLoad;
  int loads = 0;

  Future<AsteroidFeed> load() {
    loads++;
    if (loads >= 2 && holdSecondLoad) return Completer<AsteroidFeed>().future;
    return Future<AsteroidFeed>.value(_sky);
  }
}

/// A clock a test can wind forward mid-test, which the plain
/// `dayClockProvider.overrideWithValue(() => fixed)` cannot do — and winding it
/// over midnight *is* the event under test.
class _MutableClock {
  _MutableClock(this.value);

  DateTime value;

  DateTime read() => value;
}

ProviderContainer _containerOn(DateTime Function() now, _CountingSky sky) {
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      storeProvider.overrideWithValue(MemoryStore()),
      dayClockProvider.overrideWithValue(now),
      asteroidFeedProvider.overrideWith((Ref ref) => sky.load()),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// What a cold launch does before any resume can happen: start the sky and
/// stamp the day it is for. `TitleScreen.initState` is the production copy of
/// these two lines — see its comment.
Future<void> _launch(ProviderContainer container) async {
  container.listen(asteroidFeedProvider, (_, _) {});
  container.read(skyDayProvider);
  await container.read(asteroidFeedProvider.future);
}

Widget _app(DateTime Function() now, _CountingSky sky) {
  return ProviderScope(
    overrides: <Override>[
      storeProvider.overrideWithValue(MemoryStore()),
      dayClockProvider.overrideWithValue(now),
      asteroidFeedProvider.overrideWith((Ref ref) => sky.load()),
      // The radar tab's home overlay reads the flame; a value in front of it
      // keeps this suite off the streak's own behaviour, which
      // `record_engagement_test.dart` owns.
      dayStreakProvider.overrideWithValue(0),
    ],
    child: const RockimalsApp(),
  );
}

/// Title → "tap anywhere" → the gate → the shell, which is the only route a
/// child has to the radar. Pumped rather than settled: the radar runs a ticker
/// that never finishes, so `pumpAndSettle` here would time out rather than
/// arrive.
Future<void> _tapPlay(WidgetTester tester) async {
  await tester.tap(find.text('▶ Play'));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pump();
}

/// A full trip to the background and back, stepped through the neighbouring
/// states in the order a device delivers them — see
/// `test/core/lifecycle/app_resume_host_test.dart`, which owns why.
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

final AsteroidFeed _sky = AsteroidFeed(
  asteroids: <Asteroid>[_rock],
  todayList: <Asteroid>[_rock],
  feedRange: '2026-07-17 → 2026-07-19',
  provenance: FeedProvenance.today,
);

const Asteroid _rock = Asteroid(
  name: '2026 AB',
  diaMax: 100,
  diaMin: 50,
  hazardous: false,
  missLunar: 3,
  missKm: 1153200,
  velKps: 12,
  mag: 22,
  jpl: 'https://ssd.jpl.nasa.gov/tools/sbdb_lookup.html',
  date: '2026-07-19',
);

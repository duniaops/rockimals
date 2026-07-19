import 'package:flutter_riverpod/flutter_riverpod.dart';
// `Override` is not exported from the package root — Riverpod 3 parks it under
// `misc.dart`. See the same note in `lib/main.dart`.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/data/models/asteroid.dart';
import 'package:rockimals/data/models/feed_window.dart';
import 'package:rockimals/data/neows_client.dart';
import 'package:rockimals/features/data/providers.dart';

import '../../support/memory_store.dart';

/// The half of the resume refresh that `refresh_sky_test.dart` structurally
/// could not reach: **which window the refresh actually asks NASA for.**
///
/// That suite overrides `asteroidFeedProvider` wholesale, because what it pins
/// is the trigger — the guard, the continuity, the stamp. But replacing the feed
/// replaces the repository, and the repository is what turns a clock into a pair
/// of date strings. So the app had two clocks answering "what day is the sky
/// for": `skyDayProvider` decided *whether* to re-ask from `dayClockProvider`,
/// and `AsteroidRepository` decided *what to ask for* from a `DateTime.now` of
/// its own. They agreed in production and no test could make them disagree,
/// which is exactly the shape a drift bug hides in.
///
/// These stand in one layer lower — at `asteroidFeedSourceProvider` — so the
/// real repository runs and its arithmetic is observable.
void main() {
  group('the window the sky is asked for', () {
    test('is built from the same clock that decides whether to re-ask', () async {
      // **Two days, not one, and that is the whole design of this test.**
      //
      // The obvious version — boot on a fixed day, assert that day's window —
      // is a test that does not bite. A repository still reading the wall clock
      // passes it on whatever day the fixed date happens to match, and this
      // item was written on 2026-07-19, so the obvious version would have gone
      // green against the very bug it exists to catch. (Confirmed by mutation,
      // not reasoned about: dropping the `now:` wiring left it passing.)
      //
      // Loading twice under two different clocks removes the host's date from
      // the question entirely. If the repository ignores `dayClockProvider`,
      // both windows collapse to the same wall-clock day and the inequality
      // below fails — every day of the year.
      expect(
        await _windowAskedFor(DateTime.utc(2026, 7, 19, 9)),
        '2026-07-17 → 2026-07-19',
      );
      expect(
        await _windowAskedFor(DateTime.utc(2026, 3, 5, 9)),
        '2026-03-03 → 2026-03-05',
      );
    });

    test('and tomorrow is prefetched against that clock too', () async {
      // Every load fires `prefetchTomorrow`, which builds *tomorrow's* window
      // from the same `_now` — so the second entry here is not noise to filter
      // out, it is the other half of the wiring. The cache counts only an exact
      // window match as a hit, so a prefetch dated off the wall clock while the
      // load was dated off the day clock would warm a window tomorrow's launch
      // never asks for. Silent: nothing fails, the disk just fills with entries
      // that never hit.
      //
      // Two clocks again, for the reason the test above spells out.
      expect(await _windowsAskedFor(DateTime.utc(2026, 7, 19, 9)), <String>[
        '2026-07-17 → 2026-07-19',
        '2026-07-18 → 2026-07-20',
      ]);
      expect(await _windowsAskedFor(DateTime.utc(2026, 3, 5, 9)), <String>[
        '2026-03-03 → 2026-03-05',
        '2026-03-04 → 2026-03-06',
      ]);
    });

    test(
      'and a refresh after midnight asks for the new day, not the old one',
      () async {
        // The bug this exists to catch, and the reason the item was worth doing.
        // `skyDayProvider` crossing midnight is what fires the refresh; if the
        // repository kept its own clock, a fixed one in a test would fire that
        // refresh and then re-request *yesterday's window* — the child would take
        // the network hit and get the identical sky back. Two clocks, one
        // overridden, and the symptom is invisible from the trigger's side.
        final _RecordingSource source = _RecordingSource();
        final _MutableClock now = _MutableClock(
          DateTime.utc(2026, 7, 19, 23, 50),
        );
        final ProviderContainer container = _containerOn(now.read, source);

        // A cold launch: start the sky and stamp the day it is for, as
        // `TitleScreen.initState` does.
        container.listen(asteroidFeedProvider, (_, _) {});
        container.read(skyDayProvider);
        await container.read(asteroidFeedProvider.future);

        // Midnight, with the phone in a pocket the whole time.
        now.value = DateTime.utc(2026, 7, 20, 7);
        container.read(refreshSkyForNewDayProvider)();
        await container.read(asteroidFeedProvider.future);

        // Four requests, and the **third is the one this item is about**: the
        // refresh asks for 20 July's window, not a second copy of 19 July's.
        //
        // That the third equals the second is the prefetch design paying off end
        // to end, and is visible here for the first time: last night's launch
        // warmed exactly the window this morning's refresh needs, so a child who
        // wakes up on a train with no signal still gets the new day's real rocks
        // off the disk. Both halves of that only line up because one clock now
        // dates both.
        expect(source.windows, <String>[
          '2026-07-17 → 2026-07-19',
          '2026-07-18 → 2026-07-20',
          '2026-07-18 → 2026-07-20',
          '2026-07-19 → 2026-07-21',
        ]);
      },
    );
  });

  group('the split that made the above testable', () {
    test('the source is assembled once, below the repository', () {
      // `asteroidFeedSourceProvider` was extracted so a test could stand in
      // front of the network *without* replacing the arithmetic under test.
      // Reading it must still perform no I/O — construction is wiring, and
      // neither the request nor the disk read happens until the feed is asked
      // for.
      final ProviderContainer container = ProviderContainer.test(
        overrides: <Override>[storeProvider.overrideWithValue(MemoryStore())],
      );

      expect(
        container.read(asteroidFeedSourceProvider),
        isA<AsteroidFeedSource>(),
      );
    });

    test('and the repository is built on whatever source is wired', () {
      // The seam is real rather than incidental: an override of the source has
      // to be what the repository ends up loading through, or every test above
      // is asserting against a stack the app does not run.
      final _RecordingSource source = _RecordingSource();
      final ProviderContainer container = _containerOn(
        () => DateTime.utc(2026, 7, 19),
        source,
      );

      expect(container.read(asteroidRepositoryProvider), isNotNull);
      expect(source.windows, isEmpty, reason: 'building asks for nothing');
    });
  });
}

/// One full load on [day], and every window it caused — the live request first,
/// then the prefetch of tomorrow that follows it.
Future<List<String>> _windowsAskedFor(DateTime day) async {
  final _RecordingSource source = _RecordingSource();
  final ProviderContainer container = _containerOn(() => day, source);
  await container.read(asteroidFeedProvider.future);
  return source.windows;
}

/// Just the live request's window — the prefetch has its own test.
Future<String> _windowAskedFor(DateTime day) async =>
    (await _windowsAskedFor(day)).first;

/// A feed source that records the windows it was asked for, which is the one
/// thing every test here is measuring.
///
/// It answers enough rocks to clear the repository's six-record minimum, so the
/// load resolves down the live path rather than short-circuiting to the sample
/// sky — a fallback would return before the window ever mattered.
class _RecordingSource implements AsteroidFeedSource {
  final List<String> windows = <String>[];

  @override
  Future<FeedWindow> fetchFeed({
    required String startDate,
    required String endDate,
  }) async {
    windows.add('$startDate → $endDate');
    return FeedWindow(
      asteroids: <Asteroid>[
        for (int i = 0; i < 6; i++) _rock('$endDate rock $i', endDate),
      ],
      startDate: startDate,
      endDate: endDate,
    );
  }
}

/// A clock a test can wind forward mid-test, which the plain
/// `dayClockProvider.overrideWithValue(() => fixed)` cannot do — and winding it
/// over midnight *is* the event under test. Mirrors `refresh_sky_test.dart`'s.
class _MutableClock {
  _MutableClock(this.value);

  DateTime value;

  DateTime read() => value;
}

/// **Overrides the source, never the feed or the repository** — that is the
/// whole point of this file. Everything from `AsteroidRepository` upward is the
/// real code under test.
ProviderContainer _containerOn(
  DateTime Function() now,
  _RecordingSource source,
) {
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      storeProvider.overrideWithValue(MemoryStore()),
      dayClockProvider.overrideWithValue(now),
      asteroidFeedSourceProvider.overrideWithValue(source),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Asteroid _rock(String name, String date) => Asteroid(
  name: name,
  diaMax: 100,
  diaMin: 50,
  hazardous: false,
  missLunar: 3,
  missKm: 1153200,
  velKps: 12,
  mag: 22,
  jpl: 'https://ssd.jpl.nasa.gov/tools/sbdb_lookup.html',
  date: date,
);

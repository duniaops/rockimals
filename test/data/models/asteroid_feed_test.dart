import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/data/fallback_asteroids.dart';
import 'package:rockimals/data/models/asteroid.dart';
import 'package:rockimals/data/models/asteroid_feed.dart';

/// One load of the sky is shared by every consumer in the app, so the only
/// thing this type really has to guarantee is that none of them can change it
/// under the others.
///
/// The failure this prevents is silent, which is why it is pinned rather than
/// left to code review: an in-place `sort()` on `asteroids` throws nothing and
/// breaks nothing visible at the call site — it reorders the radar's source
/// list, and the radar seeds each animal's orbit phase from that list's index
/// (plan decision 9). The bug surfaces a screen away as "why did the animals
/// jump?".
void main() {
  group('AsteroidFeed hands out unmodifiable lists', () {
    test(
      'sorting `asteroids` in place throws rather than reordering the sky',
      () {
        final AsteroidFeed feed = _feed();
        final List<Asteroid> before = feed.asteroids.toList();

        expect(
          () => feed.asteroids.sort(
            (Asteroid a, Asteroid b) => a.diaMax.compareTo(b.diaMax),
          ),
          throwsUnsupportedError,
        );
        // The throw is only half the guarantee: a sort that threw *partway*
        // would have already written, and left the radar reordered anyway.
        expect(feed.asteroids, orderedEquals(before));
      },
    );

    test('sorting `todayList` in place throws too', () {
      final AsteroidFeed feed = _feed();

      expect(
        () => feed.todayList.sort(
          (Asteroid a, Asteroid b) => a.diaMax.compareTo(b.diaMax),
        ),
        throwsUnsupportedError,
      );
    });

    test('every other way of writing to the lists throws as well', () {
      // `sort` is the plausible accident; these are the ones that would sneak
      // past a fixed-length list, which blocks only `add`/`remove`. `[]=` is
      // what `sort` itself writes through, so it is the primitive under test.
      final AsteroidFeed feed = _feed();

      for (final List<Asteroid> list in <List<Asteroid>>[
        feed.asteroids,
        feed.todayList,
      ]) {
        expect(() => list[0] = list[1], throwsUnsupportedError);
        expect(() => list.add(list[0]), throwsUnsupportedError);
        expect(list.clear, throwsUnsupportedError);
        expect(list.shuffle, throwsUnsupportedError);
      }
    });

    test('the sample sky is unmodifiable on the same terms', () {
      // The offline path builds its lists differently (plan decision 10), so
      // it gets its own assertion rather than being assumed to inherit one.
      final AsteroidFeed feed = AsteroidFeed.fallback();

      expect(feed.asteroids, orderedEquals(kFallbackAsteroids));
      expect(
        () => feed.asteroids.sort((Asteroid a, Asteroid b) => 0),
        throwsUnsupportedError,
      );
      expect(
        () => feed.todayList.sort((Asteroid a, Asteroid b) => 0),
        throwsUnsupportedError,
      );
    });

    test('a list mutated after construction does not change the feed', () {
      // The reason the constructor copies instead of wrapping the caller's
      // list in a view. A view would leave the guarantee conditional on nobody
      // retaining the backing list — and the disk feed cache is about to retain
      // its entry and hand it out (plan decision 13).
      final List<Asteroid> source = <Asteroid>[
        _rock('2011 EW'),
        _rock('433 Eros'),
      ];
      final AsteroidFeed feed = AsteroidFeed(
        asteroids: source,
        todayList: source,
        feedRange: '2026-07-14 → 2026-07-16',
        provenance: FeedProvenance.today,
      );

      source
        ..clear()
        ..add(_rock('99942 Apophis'));

      expect(feed.asteroids.map((Asteroid a) => a.name), <String>[
        '2011 EW',
        '433 Eros',
      ]);
      expect(feed.todayList.map((Asteroid a) => a.name), <String>[
        '2011 EW',
        '433 Eros',
      ]);
    });
  });

  group('the sample sky', () {
    test('is the whole bundled set, with the first seven visiting today', () {
      // Plan decision 10, and the one rule that is **only** true offline: a
      // live window derives `todayList` by date, while the sample set takes a
      // fixed prefix (`index.html:381`). The two lists therefore differ here
      // and nowhere else, which is exactly what makes the mistake invisible —
      // a screen wired to `todayList` instead of `asteroids` shows seven
      // plausible animals rather than fourteen, and no live test can catch it.
      //
      // Pinned here in 2026-07-18 as the debug list screen was deleted: its
      // suite was the only thing asserting this, and the count had to survive
      // the screen that happened to be displaying it.
      final AsteroidFeed feed = AsteroidFeed.fallback();

      expect(feed.asteroids, hasLength(14));
      expect(feed.todayList, hasLength(7));
      // Identity, not just length: a `take(7)` on a *sorted* copy would satisfy
      // both counts above while handing the home strip the wrong seven rocks.
      expect(feed.todayList, orderedEquals(kFallbackAsteroids.take(7)));
      expect(feed.provenance, FeedProvenance.sample);
    });
  });
}

AsteroidFeed _feed() => AsteroidFeed(
  asteroids: <Asteroid>[
    _rock('2011 EW', diaMax: 302),
    _rock('433 Eros', diaMax: 23300),
  ],
  todayList: <Asteroid>[
    _rock('2011 EW', diaMax: 302),
    _rock('433 Eros', diaMax: 23300),
  ],
  feedRange: '2026-07-14 → 2026-07-16',
  provenance: FeedProvenance.today,
);

Asteroid _rock(String name, {double diaMax = 100}) => Asteroid(
  name: name,
  diaMax: diaMax,
  diaMin: diaMax / 2,
  hazardous: false,
  missLunar: 12.4,
  missKm: 4800000,
  velKps: 7.1,
  mag: 21.2,
  jpl: 'https://ssd.jpl.nasa.gov/tools/sbdb_lookup.html',
  date: '2026-07-16',
);

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:rockimals/core/storage/store.dart';
import 'package:rockimals/data/asteroid_repository.dart';
import 'package:rockimals/data/feed_cache.dart';
import 'package:rockimals/data/models/asteroid.dart';
import 'package:rockimals/data/models/asteroid_feed.dart';
import 'package:rockimals/data/models/feed_window.dart';
import 'package:rockimals/data/neows_client.dart';

/// The cache exists for one moment: a child opens the app somewhere with no
/// signal, and gets real rocks instead of the fourteen invented ones. So almost
/// every test here **closes the box and opens a new one** before asserting the
/// hit — reading back through a live instance would only prove Hive's in-memory
/// map works, and this class holds no memory of its own by design (plan decision
/// 13 killed the in-memory half: nothing asks twice within a process).
void main() {
  late Directory tempDir;
  late Store store;
  late _FakeSource source;
  late DateTime clock;

  /// Noon UTC, mid-window. Fixed, because a cache is a thing about time and a
  /// test that reads the wall clock is a test about nothing.
  const Duration ttl = Duration(hours: 6);

  setUp(() async {
    // A directory per test: Hive is a process-wide singleton, so a shared one
    // lets a test read the previous test's box and pass for it.
    tempDir = await Directory.systemTemp.createTemp('rockimals_feed_cache');
    Hive.init(tempDir.path);
    store = await Store.open();
    source = _FakeSource(<Asteroid>[_asteroid('2011 EW'), _asteroid('2020 SW')]);
    clock = DateTime.utc(2026, 7, 17, 12);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await Hive.close();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  CachingFeedSource cache() =>
      CachingFeedSource(source, store, now: () => clock, ttl: ttl);

  /// Force-quit and relaunch, as far as this layer can tell the difference.
  Future<void> restart() async {
    await store.close();
    store = await Store.open();
  }

  Future<FeedWindow> fetch({
    String start = '2026-07-15',
    String end = '2026-07-17',
  }) => cache().fetchFeed(startDate: start, endDate: end);

  /// Just the rocks, for the many tests that are not about which window they
  /// came from.
  Future<List<Asteroid>> fetchRocks({
    String start = '2026-07-15',
    String end = '2026-07-17',
  }) async => (await fetch(start: start, end: end)).asteroids;

  group('a hit', () {
    test('skips the network entirely', () async {
      await fetchRocks();
      await restart();

      final List<Asteroid> second = await fetchRocks();

      expect(source.fetchCount, 1);
      expect(second.map((Asteroid a) => a.name), <String>['2011 EW', '2020 SW']);
    });

    test('survives the app being force-quit — the whole point of the disk',
        () async {
      await fetchRocks();
      await restart();

      // A brand new source, as if the process had restarted around a dead
      // network. The sky still comes back, and it is NASA's, not the sample set.
      source = _FakeSource.dead();

      expect((await fetchRocks()).map((Asteroid a) => a.name), <String>[
        '2011 EW',
        '2020 SW',
      ]);
      expect(
        source.fetchCount,
        0,
        reason: 'a fresh entry is not worth a request, dead network or not',
      );
    });

    test('round-trips every field a child can see', () async {
      // The cache is the only place an `Asteroid` is written down and read back,
      // so a field silently dropped here would surface as an animal changing
      // species between launches — `hashStr` seeds on `name` and the ladder on
      // `diaMax`.
      final Asteroid original = _asteroid('433 Eros', hazardous: true);
      source = _FakeSource(<Asteroid>[original]);
      await fetchRocks();
      await restart();
      source = _FakeSource.dead();

      final Asteroid restored = (await fetchRocks()).single;

      expect(restored.name, original.name);
      expect(restored.diaMax, original.diaMax);
      expect(restored.diaMin, original.diaMin);
      expect(restored.hazardous, original.hazardous);
      expect(restored.missLunar, original.missLunar);
      expect(restored.missKm, original.missKm);
      expect(restored.velKps, original.velKps);
      expect(restored.mag, original.mag);
      expect(restored.jpl, original.jpl);
      expect(restored.date, original.date);
    });

    test('hands out a sky no consumer can reorder', () async {
      // The entry is re-read from one string and handed straight out, so a
      // caller sorting it would reorder what the next reader sees — and the
      // radar seeds each animal's orbit phase from list index (plan decision 9).
      await fetchRocks();
      await restart();

      final List<Asteroid> cached = await fetchRocks();

      expect(
        () => cached.sort((Asteroid a, Asteroid b) => a.name.compareTo(b.name)),
        throwsUnsupportedError,
      );
    });
  });

  group('a stale entry', () {
    test('refetches once the TTL is spent', () async {
      await fetchRocks();
      await restart();
      clock = clock.add(ttl + const Duration(minutes: 1));

      await fetchRocks();

      expect(source.fetchCount, 2);
    });

    test('is still fresh one minute inside the TTL', () async {
      // Pins which side of the boundary is which, so that a `<` flipped to `>`
      // cannot pass by being off by a hair.
      await fetchRocks();
      await restart();
      clock = clock.add(ttl - const Duration(minutes: 1));

      await fetchRocks();

      expect(source.fetchCount, 1);
    });

    test('is served when the network is dead — real rocks beat sample rocks',
        () async {
      // The load-bearing test of the file, and the reason the cache is on the
      // disk at all. Note what it does *not* do: it does not answer the sample
      // set, because that is the repository's decision and this layer only says
      // "I still have what NASA said".
      await fetchRocks();
      await restart();
      clock = clock.add(ttl * 10);
      source = _FakeSource.dead();

      final List<Asteroid> served = await fetchRocks();

      expect(served.map((Asteroid a) => a.name), <String>['2011 EW', '2020 SW']);
      expect(source.fetchCount, 1, reason: 'it tried the network first');
    });

    test('is replaced, not appended to, by a successful refetch', () async {
      await fetchRocks();
      clock = clock.add(ttl + const Duration(minutes: 1));
      source = _FakeSource(<Asteroid>[_asteroid('99942 Apophis')]);

      await fetchRocks();
      await restart();
      source = _FakeSource.dead();

      expect((await fetchRocks()).map((Asteroid a) => a.name), <String>[
        '99942 Apophis',
      ]);
    });
  });

  group('a miss', () {
    test('fetches, and a dead network with nothing cached rethrows', () async {
      // Rethrows rather than deciding: the sample set is the repository's answer
      // to a source that could not help, and this layer must not pre-empt it —
      // if it invented an empty list here, `usingFallback` would come out false
      // and the app would present nothing as today's real sky.
      source = _FakeSource.dead();

      await expectLater(fetch(), throwsA(isA<_DeadNetwork>()));
    });

    test('a new UTC day misses by key without ever consulting the TTL',
        () async {
      // The window key self-invalidates daily, which is why decision 13 rejected
      // day-keying. The entry here is *perfectly fresh* — the clock has not
      // moved — and it is still a miss, because it answers a different question.
      // That ordering is what this pins: key first, TTL second.
      await fetch(start: '2026-07-13', end: '2026-07-15');
      await restart();

      await fetch(start: '2026-07-14', end: '2026-07-16');

      expect(source.fetchCount, 2);
    });

    test(
      'a dead network with only another window cached serves it, saying which '
      'window it is',
      () async {
        // **This replaces the test that pinned the opposite**, which read: "a
        // dead network with only another window cached falls through to the
        // repository". That was the deliberate cost of a source that could only
        // answer `List<Asteroid>` — a different window's rocks could not be
        // served without the repository captioning them as today's, so the
        // honest move was to refuse, and a child offline across UTC midnight got
        // fourteen invented rocks while real ones sat on the disk.
        //
        // Saying *which* window came back unties it: the rocks are served and
        // nothing has to pretend they are today's. The refusal has not been
        // dropped, it has moved and grown a reason — `AsteroidRepository` still
        // refuses this window once it is genuinely old (see its ceiling tests),
        // which is a rule about staleness rather than a limit of the type.
        await fetch(start: '2026-07-13', end: '2026-07-15');
        await restart();
        source = _FakeSource.dead();

        final FeedWindow served = await fetch(
          start: '2026-07-14',
          end: '2026-07-16',
        );

        expect(served.asteroids.map((Asteroid a) => a.name), <String>[
          '2011 EW',
          '2020 SW',
        ]);
        // The window it answered, not the window it was asked for. Everything
        // this item is worth rests on this line.
        expect(served.startDate, '2026-07-13');
        expect(served.endDate, '2026-07-15');
        expect(source.fetchCount, 1, reason: 'it tried the network first');
      },
    );

    test('a fresh entry for another window is still a miss — hits stay exact',
        () async {
      // The generosity above is strictly a failure-path rule. Asking "may I skip
      // the network?" of an entry for a different window must still be answered
      // no, however fresh it is, or a new UTC day would never re-ask and the sky
      // would stop moving (plan decision 13). The clock has not moved here; only
      // the window has.
      await fetch(start: '2026-07-13', end: '2026-07-15');
      await restart();

      final FeedWindow served = await fetch(
        start: '2026-07-14',
        end: '2026-07-16',
      );

      expect(source.fetchCount, 2);
      expect(served.endDate, '2026-07-16', reason: 'the fresh one it fetched');
    });
  });

  group('an empty window', () {
    test('is a successful answer that holds its slot, not a miss', () async {
      // NASA does list quiet windows. Treating empty as "nothing cached" would
      // re-ask on every single launch — the one case where the cache is both
      // useless and expensive against a 30-per-hour household budget. The
      // repository turns an empty window into the sample set through its
      // too-few rule; that is a decision about what to *show*, not a claim that
      // no fetch happened.
      source = _FakeSource(<Asteroid>[]);

      expect(await fetchRocks(), isEmpty);
      await restart();

      expect(await fetchRocks(), isEmpty);
      expect(source.fetchCount, 1);
    });
  });

  group('a clock that moved', () {
    test('does not make an entry fresh forever', () async {
      // Device clocks move backwards — a manual change, a setup screen, an NTP
      // correction — and a negative age passes any `age < ttl` test for as long
      // as the clock stays behind. Without this guard the app would serve one
      // frozen sky indefinitely, which is a worse failure than one extra
      // request.
      await fetchRocks();
      await restart();
      clock = clock.subtract(const Duration(days: 365));

      await fetchRocks();

      expect(source.fetchCount, 2);
    });
  });

  group('a box that cannot be trusted', () {
    test('garbage in the entry is a miss, not a crash', () async {
      await store.setCachedFeed('this is not json{{{');
      await restart();

      expect((await fetchRocks()).length, 2);
      expect(source.fetchCount, 1);
    });

    test('a half-written entry is a miss', () async {
      await store.setCachedFeed(
        jsonEncode(<String, Object?>{'startDate': '2026-07-15'}),
      );
      await restart();

      expect((await fetchRocks()).length, 2);
    });

    test('one corrupt asteroid throws the whole entry away', () async {
      // Not "skip the bad record": a cache entry is meant to be exactly what
      // this app wrote, so a record that will not parse means the entry cannot
      // be trusted — and unlike a live feed, there is a pristine copy one
      // request away. `Asteroid.fromJson` is strict for this reason.
      await store.setCachedFeed(
        _entry(
          asteroids: <Object?>[
            _asteroid('2011 EW').toJson(),
            <String, Object?>{'name': '2020 SW'}, // every other field missing
          ],
        ),
      );
      await restart();

      expect((await fetchRocks()).length, 2);
      expect(source.fetchCount, 1);
    });

    test('a savedAt that is not a date is a miss', () async {
      await store.setCachedFeed(_entry(savedAt: 'yesterday-ish'));
      await restart();

      expect(source.fetchCount, 0);
      expect((await fetchRocks()).length, 2);
    });

    test('a window that is not a pair of dates is a miss', () async {
      // The entry is otherwise perfect — fresh, and its asteroids parse. But a
      // `FeedWindow` promises to say which days its rocks are about, and
      // `banana` does not, so there is no whole entry here to hand out.
      //
      // **The network is dead on purpose, and that is the whole test.** Written
      // against a live source it asserted nothing: a rejected entry and an
      // unreadable one both end in "ask NASA, get two rocks", so it passed
      // whether or not the check existed — and the mutation that deleted the
      // check sailed through it. Only a dead network separates the two, because
      // only then does a bad entry actually get served to somebody.
      source = _FakeSource.dead();
      await store.setCachedFeed(_entry(startDate: 'banana'));
      await restart();

      await expectLater(fetch(), throwsA(isA<_DeadNetwork>()));
    });

    test('a box that will not answer never costs a good fetch', () async {
      // Both halves at once: a store that throws on read must not throw out of
      // `fetchFeed` — the repository cannot see what failed and would answer a
      // perfectly good connection with the sample set — and a store that throws
      // on write must not lose a sky that is already in hand.
      await store.close();

      final List<Asteroid> served = await fetchRocks();

      expect(served.length, 2);
      expect(source.fetchCount, 1);

      store = await Store.open();
    });
  });

  group('through the real repository', () {
    // Every test above is about this class alone. These two are the item's
    // actual promise, which is only true of the assembled stack: what a child
    // sees on a plane. They also pin the composition itself — the cache inside
    // the repository, and both handed the *same* clock, which is the rule that
    // keeps the window this keys on identical to the window the repository asks
    // for.

    /// Six is the repository's floor for a live sky (`index.html:376`); below it
    /// the sample set wins regardless of any cache.
    List<Asteroid> sixRocks() => List<Asteroid>.generate(
      6,
      (int i) => _asteroid('2026 X$i'),
      growable: false,
    );

    AsteroidRepository repository() => AsteroidRepository(
      CachingFeedSource(source, store, now: () => clock, ttl: ttl),
      now: () => clock,
    );

    test('a dead network with a cached window shows NASA rocks, not sample ones',
        () async {
      source = _FakeSource(sixRocks());
      expect((await repository().loadData()).usingFallback, isFalse);

      await restart();
      // Stale, but still the same UTC day — so still the same window. Six hours
      // and a minute after breakfast, on a train with no signal.
      clock = clock.add(ttl + const Duration(minutes: 1));
      source = _FakeSource.dead();

      final AsteroidFeed feed = await repository().loadData();

      expect(feed.usingFallback, isFalse);
      expect(feed.asteroids.length, 6);
      expect(feed.asteroids.first.name, '2026 X0');
      // The caption is honest because the entry answers the window that was
      // asked for. It is the reason a hit is refused across a day boundary.
      expect(feed.feedRange, '2026-07-15 → 2026-07-17');
    });

    test('without the cache the same launch gets the fourteen sample rocks',
        () async {
      // The contrast that proves the test above is about the cache and not about
      // some other kindness in the stack. This is the app as it shipped before
      // this item: dead network, sample sky.
      source = _FakeSource.dead();

      final AsteroidFeed feed = await AsteroidRepository(
        source,
        now: () => clock,
      ).loadData();

      expect(feed.usingFallback, isTrue);
      expect(feed.asteroids.length, 14);
    });
  });
}

/// A hand-written entry in the on-disk shape, defaulting to a **valid** one for
/// the suite's window and clock.
///
/// Each corruption test overrides exactly one field, so that what it breaks is
/// the only thing that can make it a miss. That matters more than it looks: when
/// the stored shape changed from a single `window` string to a `startDate` /
/// `endDate` pair, every one of these tests kept passing — as a miss for a
/// missing field, not for the corruption each was written to pin. They asserted
/// nothing and said so in green. Building from one shared default is what stops
/// that happening the next time the shape moves.
String _entry({
  String startDate = '2026-07-15',
  String endDate = '2026-07-17',
  String? savedAt,
  List<Object?>? asteroids,
}) => jsonEncode(<String, Object?>{
  'startDate': startDate,
  'endDate': endDate,
  'savedAt': savedAt ?? DateTime.utc(2026, 7, 17, 12).toIso8601String(),
  'asteroids': asteroids ?? <Object?>[_asteroid('2011 EW').toJson()],
});

Asteroid _asteroid(String name, {bool hazardous = false}) => Asteroid(
  name: name,
  diaMax: 302.3,
  diaMin: 135.2,
  hazardous: hazardous,
  missLunar: 12.4,
  missKm: 4768123.5,
  velKps: 7.13,
  mag: 21.2,
  jpl: 'https://ssd.jpl.nasa.gov/tools/sbdb_lookup.html',
  date: '2026-07-16',
);

/// Stands in for the client, not for the socket: what is under test here is the
/// cache's policy, and `neows_client_test.dart` already owns the wire.
class _FakeSource implements AsteroidFeedSource {
  _FakeSource(this._asteroids);

  /// A source that cannot reach NASA — which is the only kind of failure this
  /// class distinguishes, because [AsteroidFeedSource] deliberately collapses
  /// every reason into one.
  _FakeSource.dead() : _asteroids = null;

  final List<Asteroid>? _asteroids;
  int fetchCount = 0;

  /// Stands in for `NeoWsClient`, so it answers the window it was asked for.
  @override
  Future<FeedWindow> fetchFeed({
    required String startDate,
    required String endDate,
  }) async {
    fetchCount++;
    final List<Asteroid>? asteroids = _asteroids;
    if (asteroids == null) throw _DeadNetwork();
    return FeedWindow(
      asteroids: asteroids,
      startDate: startDate,
      endDate: endDate,
    );
  }
}

class _DeadNetwork implements Exception {
  @override
  String toString() => 'the network is dead';
}

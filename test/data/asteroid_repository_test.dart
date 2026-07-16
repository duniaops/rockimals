import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/data/asteroid_repository.dart';
import 'package:rockimals/data/fallback_asteroids.dart';
import 'package:rockimals/data/models/asteroid.dart';
import 'package:rockimals/data/models/asteroid_feed.dart';
import 'package:rockimals/data/neows_client.dart';

import '../support/stub_http_adapter.dart';

/// The repository is where "the app is always playable" (spec 01 §3) is either
/// true or not, so most of what follows is about the ways a load goes wrong.
///
/// The feed source is faked rather than stubbed at the network, because what is
/// under test here is policy — how thin is too thin, which asteroid wins a
/// duplicate designation, who counts as visiting today — and none of that has
/// anything to do with HTTP. `neows_client_test.dart` covers the wire.
void main() {
  group('AsteroidRepository.loadData — the live path', () {
    test('asks for a three-day window ending today, and captions it', () async {
      final _FakeSource source = _FakeSource.returning(_pool(12, date: '2026-07-16'));
      final AsteroidRepository repository = _repository(source, at: DateTime.utc(2026, 7, 16));

      final AsteroidFeed feed = await repository.loadData();

      expect(source.lastStart, '2026-07-14');
      expect(source.lastEnd, '2026-07-16');
      expect(feed.feedRange, '2026-07-14 → 2026-07-16');
      expect(feed.usingFallback, isFalse);
    });

    test('zero-pads the date keys NASA expects', () async {
      // `2026-1-3` is not a date NeoWs understands; it answers 400, and the app
      // would quietly spend every January on the sample set.
      final _FakeSource source = _FakeSource.returning(_pool(12, date: '2026-07-16'));
      final AsteroidRepository repository = _repository(source, at: DateTime.utc(2026, 1, 3));

      await repository.loadData();

      expect(source.lastStart, '2026-01-01');
      expect(source.lastEnd, '2026-01-03');
    });

    test('keeps the feed as the sky when it is usable', () async {
      final AsteroidFeed feed = await _load(_pool(12, date: '2026-07-16'));

      expect(feed.usingFallback, isFalse);
      expect(feed.asteroids.length, 12);
    });

    test('collapses a repeated designation to its first appearance', () async {
      // A three-day window routinely lists one asteroid on more than one day.
      // First-seen-wins (`index.html:396`), and which one wins is not cosmetic:
      // the survivor's date decides whether it is "visiting today", and its
      // index seeds its orbit phase on the radar.
      final AsteroidFeed feed = await _load(<Asteroid>[
        _asteroid(name: '2011 EW', date: '2026-07-16'),
        _asteroid(name: '2020 SW', date: '2026-07-16'),
        _asteroid(name: '2011 EW', date: '2026-07-15'),
        _asteroid(name: '2004 BL86', date: '2026-07-15'),
        _asteroid(name: '2020 SW', date: '2026-07-14'),
        _asteroid(name: '433 Eros', date: '2026-07-14'),
      ]);

      expect(
        feed.asteroids.map((Asteroid a) => a.name),
        <String>['2011 EW', '2020 SW', '2004 BL86', '433 Eros'],
      );
      expect(feed.asteroids.first.date, '2026-07-16');
    });
  });

  group('AsteroidRepository.loadData — falling back', () {
    test('uses the sample set when the request fails', () async {
      // The airplane-mode case, and the one the guardrails care about most.
      final AsteroidFeed feed = await _load(null);

      expect(feed.usingFallback, isTrue);
      expect(feed.asteroids, kFallbackAsteroids);
      expect(feed.feedRange, 'sample data');
    });

    test('uses the sample set when a record is corrupt', () async {
      // The model throws a FormatException on a number that will not parse, and
      // the repository's catch has to be wide enough to hold it. If it is not,
      // one bad record from NASA crashes the app on launch.
      final AsteroidFeed feed = await _load(null, error: const FormatException('bad number'));

      expect(feed.usingFallback, isTrue);
    });

    test('uses the sample set when the feed is too thin to be a sky', () async {
      final AsteroidFeed feed = await _load(_pool(5, date: '2026-07-16'));

      expect(feed.usingFallback, isTrue);
      expect(feed.asteroids.length, 14);
    });

    test('keeps a feed of exactly six — the threshold is not off by one', () async {
      final AsteroidFeed feed = await _load(_pool(6, date: '2026-07-16'));

      expect(feed.usingFallback, isFalse);
      expect(feed.asteroids.length, 6);
    });

    test('counts the raw pool, not the deduplicated one', () async {
      // Faithful to `index.html:376-377`, which checks before dedupe. Six
      // records that collapse to two therefore pass, and the app shows two
      // animals rather than the sample set. Pinned because it looks like a bug
      // and the "fix" is a silent behaviour change: checking after dedupe would
      // send more days to the sample data than the prototype does.
      final AsteroidFeed feed = await _load(<Asteroid>[
        _asteroid(name: '2011 EW', date: '2026-07-14'),
        _asteroid(name: '2011 EW', date: '2026-07-14'),
        _asteroid(name: '2011 EW', date: '2026-07-14'),
        _asteroid(name: '2020 SW', date: '2026-07-14'),
        _asteroid(name: '2020 SW', date: '2026-07-14'),
        _asteroid(name: '2020 SW', date: '2026-07-14'),
      ]);

      expect(feed.usingFallback, isFalse);
      expect(feed.asteroids.length, 2);
    });

    test('offline, today is the first seven records — not a date filter', () async {
      // Decision 10, and the assertion that catches the plausible wrong port.
      // Every sample record's date is the non-date `sample`, so an agent that
      // derives todayList by date offline gets the four-record padding instead
      // of seven — changing the home strip and the Challenge pool on exactly
      // the path every offline test exercises.
      final AsteroidFeed feed = await _load(null);

      expect(feed.todayList.length, 7);
      expect(
        feed.todayList.map((Asteroid a) => a.name),
        <String>[
          '2011 EW',
          '2006 QV89',
          '2020 SW',
          '433 Eros',
          '2004 BL86',
          '2012 DA14',
          '99942 Apophis',
        ],
      );
    });
  });

  group('AsteroidRepository.loadData — who is visiting today', () {
    test('keeps today\'s own animals when there are enough of them', () async {
      final AsteroidFeed feed = await _load(<Asteroid>[
        ..._pool(4, date: '2026-07-16'),
        ..._pool(4, date: '2026-07-15', from: 4),
      ]);

      expect(feed.todayList.length, 4);
      expect(feed.todayList.every((Asteroid a) => a.date == '2026-07-16'), isTrue);
    });

    test('pads from the window when today is quiet', () async {
      // `index.html:378`. Note it *replaces* rather than tops up: today's one
      // rock is not guaranteed a seat. That is the prototype's behaviour, and
      // the strip is captioned by feedRange either way.
      final AsteroidFeed feed = await _load(<Asteroid>[
        ..._pool(5, date: '2026-07-14'),
        _asteroid(name: 'today-1', date: '2026-07-16'),
      ]);

      expect(feed.todayList.length, 4);
      expect(feed.todayList.every((Asteroid a) => a.date == '2026-07-14'), isTrue);
    });

    test('pads to what is there when dedupe leaves fewer than four', () async {
      // The pool passed the six-record check but collapsed to two, so there is
      // no fourth animal to pad with. Asking for a fixed window of four would
      // throw — on the load path that is never allowed to fail.
      final AsteroidFeed feed = await _load(<Asteroid>[
        _asteroid(name: '2011 EW', date: '2026-07-14'),
        _asteroid(name: '2011 EW', date: '2026-07-14'),
        _asteroid(name: '2011 EW', date: '2026-07-14'),
        _asteroid(name: '2020 SW', date: '2026-07-14'),
        _asteroid(name: '2020 SW', date: '2026-07-14'),
        _asteroid(name: '2020 SW', date: '2026-07-14'),
      ]);

      expect(feed.todayList.length, 2);
    });

    test('draws today from the deduplicated sky, never a separate fetch', () async {
      final _FakeSource source = _FakeSource.returning(_pool(12, date: '2026-07-16'));
      final AsteroidRepository repository = _repository(source, at: DateTime.utc(2026, 7, 16));

      final AsteroidFeed feed = await repository.loadData();

      expect(source.calls, 1);
      expect(feed.todayList.length, 12);
      expect(feed.asteroids, containsAll(feed.todayList));
    });
  });

  group('AsteroidRepository.loadData — parity with the prototype', () {
    // The real client, the real repository, and the real capture — everything
    // but the socket. This is spec 01's "compare 5-6 sample asteroids
    // side-by-side with the prototype" done mechanically instead of by eye.
    //
    // The expected values below are not hand-derived. They were produced by
    // eval-ing the prototype's own `normalize()` and `dedupe()` straight out of
    // `index.html` and running `loadData()`'s body over this same fixture with
    // the clock pinned to 2026-07-16 — the same technique the FALLBACK port
    // used, and for the same reason: a port that is off by one record or one
    // ordering rule throws nothing, it just quietly gives a child a different
    // sky. Re-run that comparison rather than re-reading this list if it ever
    // needs to change.
    test('reproduces the prototype loadData, record for record', () async {
      final AsteroidFeed feed = await _liveRepository().loadData();

      expect(feed.usingFallback, isFalse);
      expect(feed.feedRange, '2026-07-14 → 2026-07-16');
      expect(feed.asteroids.map((Asteroid a) => a.name), <String>[
        // The five of 2026-07-16 lead, because that is the key order NASA sent,
        // not because it is the latest day.
        '2009 DB1', '2009 HA21', '2017 FX101', '2018 XQ2', '2019 NX4',
        '2011 UT', '2016 NB1', '2018 BV1', '2018 SD2',
        '2004 KG1', '2010 WB3', '2011 LA19', '2015 AF45',
      ]);
      expect(feed.todayList.map((Asteroid a) => a.name), <String>[
        '2009 DB1', '2009 HA21', '2017 FX101', '2018 XQ2', '2019 NX4',
      ]);
    });

    test('reproduces the prototype normalize, field for field', () async {
      final AsteroidFeed feed = await _liveRepository().loadData();

      final Asteroid first = feed.asteroids.first;
      expect(first.name, '2009 DB1');
      expect(first.diaMax, 145.8948556919);
      expect(first.diaMin, 65.2461629789);
      expect(first.hazardous, isFalse);
      expect(first.missLunar, 179.7297197531);
      expect(first.missKm, 69118723.00966758);
      expect(first.velKps, 26.5513517944);
      expect(first.mag, 23.05);
      expect(first.date, '2026-07-16');
    });

    test('falls back when NASA rate-limits the demo key', () async {
      // End to end, through the client's status check: a 429 has to come out
      // the other side as a playable sky, not an exception.
      final AsteroidRepository repository = AsteroidRepository(
        NeoWsClient(
          dio: Dio()
            ..httpClientAdapter = StubHttpAdapter.json(
              '{"error":{"code":"OVER_RATE_LIMIT"}}',
              status: 429,
            ),
        ),
        now: () => DateTime.utc(2026, 7, 16),
      );

      final AsteroidFeed feed = await repository.loadData();

      expect(feed.usingFallback, isTrue);
      expect(feed.asteroids.length, 14);
      expect(feed.todayList.length, 7);
    });
  });
}

/// The real client over the real capture, with the clock pinned to the day the
/// fixture was captured so that `2026-07-16` is genuinely "today".
AsteroidRepository _liveRepository() {
  final String feedJson = File('test/fixtures/neows_feed.json').readAsStringSync();
  return AsteroidRepository(
    NeoWsClient(dio: Dio()..httpClientAdapter = StubHttpAdapter.json(feedJson)),
    now: () => DateTime.utc(2026, 7, 16),
  );
}

Future<AsteroidFeed> _load(List<Asteroid>? pool, {Object? error}) {
  final _FakeSource source = pool == null
      ? _FakeSource.failing(error ?? const SocketExceptionStandIn())
      : _FakeSource.returning(pool);
  return _repository(source, at: DateTime.utc(2026, 7, 16)).loadData();
}

AsteroidRepository _repository(_FakeSource source, {required DateTime at}) =>
    AsteroidRepository(source, now: () => at);

/// [count] distinct asteroids — distinct because the designation is the dedupe
/// key, so a pool of identical ones would silently be a pool of one.
List<Asteroid> _pool(int count, {required String date, int from = 0}) {
  return List<Asteroid>.generate(
    count,
    (int i) => _asteroid(name: 'rock-${from + i}', date: date),
    growable: false,
  );
}

/// Every field but the designation and the date is arbitrary here: nothing on
/// this path reads a diameter or a distance. Both of those are required rather
/// than defaulted because both are load-bearing — one is the dedupe key, the
/// other decides who is visiting today.
Asteroid _asteroid({required String name, required String date}) {
  return Asteroid(
    name: name,
    diaMax: 42,
    diaMin: 19,
    hazardous: false,
    missLunar: 3.2,
    missKm: 1229000,
    velKps: 9.4,
    mag: 24.1,
    jpl: 'https://ssd.jpl.nasa.gov/tools/sbdb_lookup.html',
    date: date,
  );
}

/// Stands in for a dead network without dragging `dart:io` in: what the
/// repository must do with it is the same whatever type it is, which is the
/// whole point of the bare catch.
class SocketExceptionStandIn implements Exception {
  const SocketExceptionStandIn();
}

class _FakeSource implements AsteroidFeedSource {
  _FakeSource.returning(List<Asteroid> pool) : _pool = pool, _error = null;
  _FakeSource.failing(Object error) : _pool = null, _error = error;

  final List<Asteroid>? _pool;
  final Object? _error;

  int calls = 0;
  String? lastStart;
  String? lastEnd;

  @override
  Future<List<Asteroid>> fetchFeed({
    required String startDate,
    required String endDate,
  }) async {
    calls++;
    lastStart = startDate;
    lastEnd = endDate;
    final Object? error = _error;
    if (error != null) throw error;
    return _pool!;
  }
}

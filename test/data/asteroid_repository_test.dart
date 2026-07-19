import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/data/asteroid_repository.dart';
import 'package:rockimals/data/fallback_asteroids.dart';
import 'package:rockimals/data/models/asteroid.dart';
import 'package:rockimals/data/models/asteroid_feed.dart';
import 'package:rockimals/data/models/feed_window.dart';
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
      final _FakeSource source = _FakeSource.returning(
        _pool(12, date: '2026-07-16'),
      );
      final AsteroidRepository repository = _repository(
        source,
        at: DateTime.utc(2026, 7, 16),
      );

      final AsteroidFeed feed = await repository.loadData();

      expect(source.lastStart, '2026-07-14');
      expect(source.lastEnd, '2026-07-16');
      expect(feed.feedRange, '2026-07-14 → 2026-07-16');
      expect(feed.usingFallback, isFalse);
    });

    test('zero-pads the date keys NASA expects', () async {
      // `2026-1-3` is not a date NeoWs understands; it answers 400, and the app
      // would quietly spend every January on the sample set.
      final _FakeSource source = _FakeSource.returning(
        _pool(12, date: '2026-07-16'),
      );
      final AsteroidRepository repository = _repository(
        source,
        at: DateTime.utc(2026, 1, 3),
      );

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

      expect(feed.asteroids.map((Asteroid a) => a.name), <String>[
        '2011 EW',
        '2020 SW',
        '2004 BL86',
        '433 Eros',
      ]);
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
      final AsteroidFeed feed = await _load(
        null,
        error: const FormatException('bad number'),
      );

      expect(feed.usingFallback, isTrue);
    });

    test('uses the sample set when the answer never comes', () async {
      // The captive-portal case — a hotel or café splash page that accepts the
      // connection and then answers nothing. It is the one failure the bare
      // catch below cannot save the app from, because nothing is ever thrown:
      // without a ceiling this future simply never completes, and the loading
      // screen is the app forever. Airplane mode, by contrast, fails fast.
      //
      // The ceiling is injected here so the assertion costs 50ms rather than
      // the real ten seconds; what it proves is that there is one at all.
      final AsteroidRepository repository = AsteroidRepository(
        _FakeSource.hanging(),
        now: () => DateTime.utc(2026, 7, 16),
        loadCeiling: const Duration(milliseconds: 50),
      );

      final AsteroidFeed feed = await repository.loadData();

      expect(feed.usingFallback, isTrue);
      expect(feed.asteroids.length, 14);
    });

    test('uses the sample set when the feed is too thin to be a sky', () async {
      final AsteroidFeed feed = await _load(_pool(5, date: '2026-07-16'));

      expect(feed.usingFallback, isTrue);
      expect(feed.asteroids.length, 14);
    });

    test(
      'keeps a feed of exactly six — the threshold is not off by one',
      () async {
        final AsteroidFeed feed = await _load(_pool(6, date: '2026-07-16'));

        expect(feed.usingFallback, isFalse);
        expect(feed.asteroids.length, 6);
      },
    );

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

    test(
      'offline, today is the first seven records — not a date filter',
      () async {
        // Decision 10, and the assertion that catches the plausible wrong port.
        // Every sample record's date is the non-date `sample`, so an agent that
        // derives todayList by date offline gets the four-record padding instead
        // of seven — changing the home strip and the Challenge pool on exactly
        // the path every offline test exercises.
        final AsteroidFeed feed = await _load(null);

        expect(feed.todayList.length, 7);
        expect(feed.todayList.map((Asteroid a) => a.name), <String>[
          '2011 EW',
          '2006 QV89',
          '2020 SW',
          '433 Eros',
          '2004 BL86',
          '2012 DA14',
          '99942 Apophis',
        ]);
      },
    );
  });

  group('AsteroidRepository.loadData — who is visiting today', () {
    test('keeps today\'s own animals when there are enough of them', () async {
      final AsteroidFeed feed = await _load(<Asteroid>[
        ..._pool(4, date: '2026-07-16'),
        ..._pool(4, date: '2026-07-15', from: 4),
      ]);

      expect(feed.todayList.length, 4);
      expect(
        feed.todayList.every((Asteroid a) => a.date == '2026-07-16'),
        isTrue,
      );
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
      expect(
        feed.todayList.every((Asteroid a) => a.date == '2026-07-14'),
        isTrue,
      );
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

    test(
      'draws today from the deduplicated sky, never a separate fetch',
      () async {
        final _FakeSource source = _FakeSource.returning(
          _pool(12, date: '2026-07-16'),
        );
        final AsteroidRepository repository = _repository(
          source,
          at: DateTime.utc(2026, 7, 16),
        );

        final AsteroidFeed feed = await repository.loadData();

        expect(source.calls, 1);
        expect(feed.todayList.length, 12);
        expect(feed.asteroids, containsAll(feed.todayList));
      },
    );
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
        '2009 DB1',
        '2009 HA21',
        '2017 FX101',
        '2018 XQ2',
        '2019 NX4',
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

  group('AsteroidRepository.loadData — a window from an earlier day', () {
    // Only the feed cache can answer a window other than the one it was asked
    // for: it holds the last thing NASA said and offers it when the network is
    // gone. These are the rules for what the repository then does with it, and
    // they are the reason a device offline since yesterday shows real rocks
    // instead of the fourteen invented ones.

    /// A source stuck on the window ending [endDate], as an offline cache is.
    Future<AsteroidFeed> loadCached({
      required String endDate,
      String startDate = '2026-07-12',
      List<Asteroid>? pool,
    }) => _repository(
      _FakeSource.answering(
        pool ?? _pool(12, date: endDate),
        startDate: startDate,
        endDate: endDate,
      ),
      at: DateTime.utc(2026, 7, 16),
    ).loadData();

    test('is shown, captioned with the window it really came from', () async {
      // The item's whole promise. The app asked for `2026-07-14 → 2026-07-16`
      // and got a two-day-old window; the child sees real animals and a footer
      // that says exactly which days they are from. Nothing pretends.
      final AsteroidFeed feed = await loadCached(endDate: '2026-07-14');

      expect(feed.usingFallback, isFalse);
      expect(feed.asteroids.length, 12);
      expect(feed.feedRange, '2026-07-12 → 2026-07-14');
    });

    test('is marked `earlier`, so nothing may call it today', () async {
      // `usingFallback` cannot express this: these rocks are neither invented
      // nor current. The prototype's home strip renders
      // `${todayList.length} visiting ${usingFallback?'(sample)':'today'}`
      // (`index.html:454`), and on this feed both branches are false — which is
      // what `FeedProvenance` exists to stop a future port from discovering the
      // hard way.
      final AsteroidFeed feed = await loadCached(endDate: '2026-07-14');

      expect(feed.provenance, FeedProvenance.earlier);
      expect(feed.usingFallback, isFalse);
    });

    test('a window ending today is `today`, cache or not', () async {
      // The mirror, and the reason the value is not called `live`: a fresh cache
      // hit for today's window never touches the network, and is still `today`.
      // Nothing above the cache can tell, and nothing needs to — the rocks and
      // the days are identical either way.
      final AsteroidFeed feed = await loadCached(
        startDate: '2026-07-14',
        endDate: '2026-07-16',
      );

      expect(feed.provenance, FeedProvenance.today);
    });

    test('deals its Challenge from the window\'s own last day', () async {
      // The bug that filtering on the *real* today would have caused, pinned so
      // it cannot come back. No record in an earlier window carries today's
      // date, so that filter matches nothing, `todayList` becomes the window's
      // first four rocks, and — since the Challenge deals from
      // `todayList.length >= 4 ? todayList : asteroids` (`index.html:881`) —
      // every offline child gets the same four animals on every launch, forever.
      // Filtering on the answered day reproduces the live shape instead.
      final AsteroidFeed feed = await loadCached(
        endDate: '2026-07-14',
        // `from:` so the two days do not share designations — first-seen-wins
        // dedupe would otherwise eat the later day whole.
        pool: <Asteroid>[
          ..._pool(6, date: '2026-07-13'),
          ..._pool(5, date: '2026-07-14', from: 6),
        ],
      );

      expect(feed.todayList.length, 5);
      expect(
        feed.todayList.every((Asteroid a) => a.date == '2026-07-14'),
        isTrue,
      );
    });

    test(
      'is refused once it is older than the ceiling — sample set instead',
      () async {
        // Three days back is the last servable window; four is a museum piece. A
        // fixed real sky that old is worth no more to a child than the sample one
        // and carries a stranger caption, so the sample set wins.
        final AsteroidFeed feed = await loadCached(endDate: '2026-07-12');

        expect(feed.usingFallback, isTrue);
        expect(feed.asteroids.length, 14);
      },
    );

    test(
      'is kept at exactly the ceiling — the boundary is not off by one',
      () async {
        final AsteroidFeed feed = await loadCached(endDate: '2026-07-13');

        expect(feed.usingFallback, isFalse);
        expect(feed.feedRange, '2026-07-12 → 2026-07-13');
      },
    );

    test('a window dated in the future is refused, not served', () async {
      // A device clock knocked backwards — a manual change, a setup screen, an
      // NTP correction — leaves a perfectly real entry apparently ahead of
      // today. There is no separate branch for this: the ceiling asks whether
      // the window is one of the last few days, and tomorrow is not one of them.
      final AsteroidFeed feed = await loadCached(endDate: '2026-07-17');

      expect(feed.usingFallback, isTrue);
    });

    test('judges the ceiling in UTC, not in the device timezone', () async {
      // The bug this design exists to avoid, and it would never have shown up in
      // a test run in UTC. `DateTime.parse('2026-07-13')` yields **local**
      // midnight, so differencing it against a UTC clock is out by the device's
      // offset — up to ±14 hours, which is more than enough to move a window
      // across the ceiling. It would have misfired only for children east of
      // UTC: every one of them, and none of us.
      //
      // The window ends 3 days and 1 hour before the clock here. In UTC that is
      // the day `2026-07-13`, which is exactly at the ceiling and must be kept.
      // Parsing dates instead would make the answer depend on where the phone is.
      final AsteroidFeed feed = await _repository(
        _FakeSource.answering(
          _pool(12, date: '2026-07-13'),
          startDate: '2026-07-11',
          endDate: '2026-07-13',
        ),
        at: DateTime.utc(2026, 7, 16, 1),
      ).loadData();

      expect(feed.usingFallback, isFalse);
      expect(feed.feedRange, '2026-07-11 → 2026-07-13');
    });

    test('still applies every live rule to it — thin is thin', () async {
      // An old window is a sky, not an exemption: the too-few rule, dedupe and
      // the rest run on it exactly as they do on a live one.
      final AsteroidFeed feed = await loadCached(
        endDate: '2026-07-14',
        pool: _pool(5, date: '2026-07-14'),
      );

      expect(feed.usingFallback, isTrue);
      expect(feed.asteroids.length, 14);
    });
  });

  /// The prefetch shows nobody anything — it exists so that *tomorrow's* launch
  /// has a real sky on the disk when there is no signal
  /// (`specs/06-title-polish-safety.md:38`). So these tests are about which
  /// window it asks for and about it never costing the child anything.
  group('AsteroidRepository.prefetchTomorrow', () {
    test('asks for exactly the window tomorrow will ask for', () async {
      // The whole value of the prefetch turns on this being byte-identical to
      // what `loadData` will build once the date rolls over: the cache counts an
      // entry as a hit only on an exact window match, so a window that is one
      // day wide, or shifted, would be stored and then never asked for again.
      final _FakeSource source = _FakeSource.returning(
        _pool(12, date: '2026-07-17'),
      );

      await _repository(
        source,
        at: DateTime.utc(2026, 7, 16),
      ).prefetchTomorrow();

      expect(source.lastStart, '2026-07-15');
      expect(source.lastEnd, '2026-07-17');
    });

    test('is the window the next day builds for itself', () async {
      // Says the sentence above as a test rather than as a comment: tomorrow's
      // real load, run against tomorrow's clock, must land on the same pair.
      final _FakeSource prefetch = _FakeSource.returning(
        _pool(12, date: '2026-07-17'),
      );
      final _FakeSource tomorrow = _FakeSource.returning(
        _pool(12, date: '2026-07-17'),
      );

      await _repository(
        prefetch,
        at: DateTime.utc(2026, 7, 16),
      ).prefetchTomorrow();
      await _repository(tomorrow, at: DateTime.utc(2026, 7, 17)).loadData();

      expect(prefetch.lastStart, tomorrow.lastStart);
      expect(prefetch.lastEnd, tomorrow.lastEnd);
    });

    test('zero-pads across a month boundary', () async {
      // The same trap `loadData` has its own test for, and one the prefetch
      // reaches a day earlier: on the 31st, tomorrow is next month.
      final _FakeSource source = _FakeSource.returning(
        _pool(12, date: '2026-07-31'),
      );

      await _repository(
        source,
        at: DateTime.utc(2026, 7, 31),
      ).prefetchTomorrow();

      expect(source.lastStart, '2026-07-30');
      expect(source.lastEnd, '2026-08-01');
    });

    test(
      'swallows a dead network — the child is already looking at a sky',
      () async {
        // It runs behind a resolved feed, so there is nothing left for a failure
        // here to spoil. Throwing would turn a loaded app into an unhandled
        // asynchronous error, because the caller deliberately does not await it.
        await expectLater(
          _repository(
            _FakeSource.failing(const SocketException('offline')),
            at: DateTime.utc(2026, 7, 16),
          ).prefetchTomorrow(),
          completes,
        );
      },
    );

    test(
      'gives up on a source that never answers, rather than hanging forever',
      () async {
        // The captive portal, again. Without the ceiling this future stays pending
        // for the life of the process — harmless to look at, but it holds the
        // request and everything under it alive on a screen a child left minutes
        // ago.
        final AsteroidRepository repository = AsteroidRepository(
          _FakeSource.hanging(),
          now: () => DateTime.utc(2026, 7, 16),
          loadCeiling: const Duration(milliseconds: 10),
        );

        await expectLater(repository.prefetchTomorrow(), completes);
      },
    );
  });

  group('AsteroidRepository takes its clock and never reaches for one', () {
    // `now` was optional until 2026-07-19, defaulting to `DateTime.now`. Every
    // caller passed a clock even then, so the default was never *reached* — it
    // was loaded, waiting for the next caller who forgot, at which point a
    // second clock would decide a date in the feed path and nothing would fail.
    // That is the exact split `dayClockProvider` was created to close.
    //
    // Requiring the parameter makes a forgetful caller a compile error, so the
    // call sites need no test. What needs one is the *default itself*: putting
    // `?? DateTime.now` back compiles, breaks nothing, and silently re-arms the
    // trap. Only reading the source can see that, so this reads the source.
    //
    // Scoped to this one file on purpose. `CachingFeedSource` has the same
    // optional-`now` shape and must **not** be swept up — its clock is a TTL
    // stopwatch (`age < _ttl`), not a calendar, and freezing it to a chosen day
    // would make every cached entry eternally fresh.
    final String source = File(
      'lib/data/asteroid_repository.dart',
    ).readAsStringSync();

    test('declares `now` required rather than defaulted', () {
      expect(
        source,
        contains('required DateTime Function() now'),
        reason:
            'an optional clock lets a new caller put a second one in the feed '
            'path without failing anything',
      );
    });

    test('names no wall clock of its own', () {
      expect(
        source,
        isNot(contains('DateTime.now')),
        reason:
            'every date this class acts on must arrive through `now`, so that '
            'one clock decides what day the sky is for',
      );
    });
  });
}

/// The real client over the real capture, with the clock pinned to the day the
/// fixture was captured so that `2026-07-16` is genuinely "today".
AsteroidRepository _liveRepository() {
  final String feedJson = File(
    'test/fixtures/neows_feed.json',
  ).readAsStringSync();
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
  _FakeSource.returning(List<Asteroid> pool)
    : _pool = pool,
      _answers = null,
      _error = null,
      _hangs = false;

  /// A source that answers a **different window** than the one it was asked for
  /// — which is exactly what `CachingFeedSource` does when the network is gone
  /// and the only entry on the disk is yesterday's. Faked at this seam rather
  /// than through a real cache: what is under test is the repository's rule for
  /// an old window, and `feed_cache_test.dart` already owns the assembled stack.
  _FakeSource.answering(
    List<Asteroid> pool, {
    required String startDate,
    required String endDate,
  }) : _pool = pool,
       _answers = <String>[startDate, endDate],
       _error = null,
       _hangs = false;

  _FakeSource.failing(Object error)
    : _pool = null,
      _answers = null,
      _error = error,
      _hangs = false;

  /// Answers nothing, ever — the captive portal. Note it does not throw: this
  /// is the failure the repository's catch cannot see.
  _FakeSource.hanging()
    : _pool = null,
      _answers = null,
      _error = null,
      _hangs = true;

  final List<Asteroid>? _pool;
  final List<String>? _answers;
  final Object? _error;
  final bool _hangs;

  int calls = 0;
  String? lastStart;
  String? lastEnd;

  @override
  Future<FeedWindow> fetchFeed({
    required String startDate,
    required String endDate,
  }) async {
    calls++;
    lastStart = startDate;
    lastEnd = endDate;
    if (_hangs) return Completer<FeedWindow>().future;
    final Object? error = _error;
    if (error != null) throw error;
    final List<String>? answers = _answers;
    return FeedWindow(
      asteroids: _pool!,
      startDate: answers?[0] ?? startDate,
      endDate: answers?[1] ?? endDate,
    );
  }
}

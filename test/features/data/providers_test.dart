import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
// `ProviderException` is not exported from the package root — the same gap as
// `Override`, and the second time this port has hit it. Riverpod 3 parks the
// types you only need in a test under `misc.dart`.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:rockimals/core/storage/store.dart';
import 'package:rockimals/data/asteroid_repository.dart';
import 'package:rockimals/data/fallback_asteroids.dart';
import 'package:rockimals/data/models/asteroid.dart';
import 'package:rockimals/data/models/asteroid_feed.dart';
import 'package:rockimals/data/neows_client.dart';
import 'package:rockimals/features/data/providers.dart';

/// The providers are a view of one load, so what is worth testing is not the
/// data — `asteroid_repository_test.dart` owns that — but the wiring: that the
/// load happens once, that every field comes from the *same* load, that the
/// loading state is honest rather than an empty sky, and that this layer adds
/// no retry policy of its own on top of the repository's.
void main() {
  group('asteroidFeedProvider', () {
    test('surfaces loading and then the feed', () async {
      final _FakeRepository repository = _FakeRepository(_liveFeed());
      final ProviderContainer container = _container(repository);

      expect(
        container.read(asteroidFeedProvider),
        isA<AsyncLoading<AsteroidFeed>>(),
      );

      final AsteroidFeed feed = await container.read(
        asteroidFeedProvider.future,
      );

      expect(feed.usingFallback, isFalse);
      expect(container.read(asteroidFeedProvider).requireValue, same(feed));
    });

    test(
      'surfaces loading and then the sample sky when the network is dead',
      () async {
        // The repository answers a dead network with the sample set rather than
        // an error (spec 01 §3), so from up here a fallback load is an ordinary
        // successful one. `usingFallback` is the only thing that gives it away —
        // which is exactly the contract the loading screen depends on.
        final _FakeRepository repository = _FakeRepository(
          AsteroidFeed.fallback(),
        );
        final ProviderContainer container = _container(repository);

        expect(
          container.read(asteroidFeedProvider),
          isA<AsyncLoading<AsteroidFeed>>(),
        );

        final AsteroidFeed feed = await container.read(
          asteroidFeedProvider.future,
        );

        expect(feed.usingFallback, isTrue);
        expect(feed.asteroids, kFallbackAsteroids);
        expect(container.read(asteroidFeedProvider).hasError, isFalse);
      },
    );

    test('loads once however many providers read it', () async {
      // The prototype calls `loadData()` exactly once per process
      // (`index.html:1143`). Five listeners must not be five requests against
      // a 30-per-hour key that a whole household shares.
      final _FakeRepository repository = _FakeRepository(_liveFeed());
      final ProviderContainer container = _container(repository);

      await container.read(asteroidFeedProvider.future);
      container
        ..read(asteroidsProvider)
        ..read(todayListProvider)
        ..read(feedRangeProvider)
        ..read(usingFallbackProvider)
        ..read(asteroidFeedProvider);

      expect(repository.loadCount, 1);
    });

    test(
      'reloads on invalidate, because that is the one gesture that should',
      () async {
        final _FakeRepository repository = _FakeRepository(_liveFeed());
        final ProviderContainer container = _container(repository);

        await container.read(asteroidFeedProvider.future);
        container.invalidate(asteroidFeedProvider);
        await container.read(asteroidFeedProvider.future);

        expect(repository.loadCount, 2);
      },
    );
  });

  group('the derived field providers', () {
    test('each expose their field of the loaded feed', () async {
      final AsteroidFeed feed = _liveFeed();
      final ProviderContainer container = _container(_FakeRepository(feed));

      await container.read(asteroidFeedProvider.future);

      expect(
        container.read(asteroidsProvider).requireValue,
        same(feed.asteroids),
      );
      expect(
        container.read(todayListProvider).requireValue,
        same(feed.todayList),
      );
      expect(
        container.read(feedRangeProvider).requireValue,
        '2026-07-14 → 2026-07-16',
      );
      expect(container.read(usingFallbackProvider).requireValue, isFalse);
    });

    test('hand out a sky no consumer can reorder', () async {
      // `same()` above is the whole reason this matters: every consumer gets
      // the one list instance, not a copy each, so a screen sorting it in place
      // would reorder the radar's own source list — and the radar seeds each
      // animal's orbit phase from that list's index (plan decision 9).
      // `asteroid_feed_test.dart` owns the guarantee; this pins that it
      // survives the trip through the providers.
      final ProviderContainer container = _container(
        _FakeRepository(_liveFeed()),
      );

      await container.read(asteroidFeedProvider.future);

      final List<Asteroid> asteroids = container
          .read(asteroidsProvider)
          .requireValue;
      expect(
        () => asteroids.sort(
          (Asteroid a, Asteroid b) => a.diaMax.compareTo(b.diaMax),
        ),
        throwsUnsupportedError,
      );
      expect(
        () =>
            container.read(todayListProvider).requireValue.add(asteroids.first),
        throwsUnsupportedError,
      );
    });

    test(
      'report loading rather than an empty sky before the feed lands',
      () async {
        // The load-bearing assertion of the file. A bare `List<Asteroid>` would
        // have to answer this moment with `[]`, and a radar cannot tell "space is
        // empty" from "we have not asked yet" — it would paint an empty sky and
        // then jump. Every field says "loading" instead.
        final ProviderContainer container = _container(
          _FakeRepository(_liveFeed()),
        );

        expect(
          container.read(asteroidsProvider),
          isA<AsyncLoading<List<Asteroid>>>(),
        );
        expect(
          container.read(todayListProvider),
          isA<AsyncLoading<List<Asteroid>>>(),
        );
        expect(container.read(feedRangeProvider), isA<AsyncLoading<String>>());
        expect(
          container.read(usingFallbackProvider),
          isA<AsyncLoading<bool>>(),
        );

        await container.read(asteroidFeedProvider.future);

        expect(container.read(asteroidsProvider).hasValue, isTrue);
      },
    );

    test('all describe the same load, never a mix of two', () async {
      // These are four views of one value, so they cannot disagree — a footer
      // captioned with today's real range while the strip shows sample rocks
      // would be the app lying about where its animals came from.
      final ProviderContainer container = _container(
        _FakeRepository(AsteroidFeed.fallback()),
      );

      await container.read(asteroidFeedProvider.future);

      expect(container.read(usingFallbackProvider).requireValue, isTrue);
      expect(container.read(feedRangeProvider).requireValue, sampleFeedRange);
      expect(container.read(todayListProvider).requireValue.length, 7);
      expect(container.read(asteroidsProvider).requireValue.length, 14);
    });

    test('do not rebuild when a reload leaves their own field alone', () async {
      // The reason these are four providers rather than one `feed.asteroids`
      // read at each call site: the Sky footer's caption is identical across a
      // refresh, so it must not repaint just because the asteroids behind it
      // changed.
      //
      // This pins a Riverpod guarantee the UI will lean on — a derived provider
      // notifies only when its own output differs by `==` — rather than
      // anything clever in `_fieldOf`. It is here deliberately: an earlier draft
      // reached for `.select` to buy this, and this test is what showed the
      // suppression was already happening without it.
      final _FakeRepository repository = _FakeRepository(_liveFeed());
      final ProviderContainer container = _container(repository);
      await container.read(asteroidFeedProvider.future);

      int feedRangeBuilds = 0;
      int asteroidsBuilds = 0;
      container.listen(feedRangeProvider, (_, _) => feedRangeBuilds++);
      container.listen(asteroidsProvider, (_, _) => asteroidsBuilds++);

      // A reload with the same caption but a different list of rocks.
      repository.next = _liveFeed(names: <String>['2020 SW', '433 Eros']);
      container.invalidate(asteroidFeedProvider);
      await container.read(asteroidFeedProvider.future);
      // Riverpod flushes listeners on its own scheduler, so awaiting the load
      // is not enough — without this the counters read 0 and the test would
      // "pass" its select assertion by simply never having looked.
      await container.pump();

      expect(asteroidsBuilds, greaterThan(0));
      expect(feedRangeBuilds, 0);
    });
  });

  group('retry policy', () {
    // Riverpod 3 retries a throwing provider by default, ten times over ~25
    // seconds. `loadData()` never throws, so this is unreachable through the
    // real repository — but the default is invisible, survives any later
    // refactor, and would silently outlast the repository's 10-second ceiling
    // and re-retry the 429 that was deliberately made non-retryable. These two
    // tests are what stop `retry: _neverRetry` being deleted as noise.
    test('does not retry a throwing repository', () async {
      final _FakeRepository repository = _FakeRepository.throwing();
      final ProviderContainer container = _container(repository);

      await expectLater(
        container.read(asteroidFeedProvider.future),
        throwsA(isA<_LoadFailure>()),
      );
      // Comfortably past the default's first 200ms backoff.
      await Future<void>.delayed(const Duration(milliseconds: 600));

      expect(repository.loadCount, 1);
      expect(container.read(asteroidFeedProvider).hasError, isTrue);
    });

    test(
      'the framework default really would retry — this is not a no-op guard',
      () async {
        // Proves the previous test bites, by watching the behaviour it suppresses
        // happen to an identical provider that only differs by opting in.
        final _FakeRepository repository = _FakeRepository.throwing();
        final FutureProvider<AsteroidFeed> retrying =
            FutureProvider<AsteroidFeed>(
              (Ref ref) => ref.watch(asteroidRepositoryProvider).loadData(),
            );
        final ProviderContainer container = _container(repository);

        container.listen(retrying, (_, _) {}, onError: (_, _) {});
        await Future<void>.delayed(const Duration(milliseconds: 600));

        expect(repository.loadCount, greaterThan(1));
      },
    );
  });

  group('asteroidRepositoryProvider', () {
    test('builds a NeoWs-backed repository by default', () {
      // The composition root is the one place the app names a concrete client.
      // Reading it must not perform any I/O — construction is wiring, and the
      // request only happens when something asks for the feed.
      final ProviderContainer container = ProviderContainer.test();

      expect(
        container.read(asteroidRepositoryProvider),
        isA<AsteroidRepository>(),
      );
    });
  });

  group('storeProvider', () {
    // The store is opened once, at boot, and handed down — so what these pin is
    // the seam itself: that an override reaches every reader, and that a
    // missing one is loud. `app_test.dart` owns the boot sequence that supplies
    // it; `store_test.dart` owns what the store remembers.
    late Directory tempDir;
    late Store store;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('rockimals_store_prov');
      Hive.init(tempDir.path);
      store = await Store.open();
    });

    tearDown(() async {
      await Hive.deleteFromDisk();
      await Hive.close();
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    });

    test('throws until something overrides it with an opened store', () {
      // Every consumer to come — points, badges, follows, the settings toggles
      // — reads this synchronously. If a wiring mistake ever left it
      // unoverridden, the failure must be a crash on the first read and not a
      // whole app quietly reporting a fresh install to a child who has played
      // for weeks.
      final ProviderContainer container = ProviderContainer.test();

      // Riverpod 3 wraps anything a provider throws in a `ProviderException`,
      // so the raw type never surfaces — the assertion has to reach through to
      // `.exception`, and the message has to survive the wrapping to be worth
      // writing. It does: `ProviderException.toString()` prints it.
      expect(
        () => container.read(storeProvider),
        throwsA(
          isA<ProviderException>().having(
            (ProviderException e) => e.exception,
            'exception',
            isA<UnimplementedError>(),
          ),
        ),
      );
    });

    test('an override hands the same live store to every reader', () async {
      // `same`, not `equals`: two stores over one box would each hold their own
      // Hive handle, and a write through one would be invisible to the other
      // until a reopen. One instance is what makes a point scored in a game
      // show up on the profile without a round trip through the disk.
      final ProviderContainer container = ProviderContainer.test(
        overrides: [storeProvider.overrideWithValue(store)],
      );

      expect(container.read(storeProvider), same(store));

      await container.read(storeProvider).setPoints(12);

      expect(container.read(storeProvider).points, 12);
      expect(store.points, 12);
    });
  });
}

ProviderContainer _container(AsteroidRepository repository) {
  // The override list is left to inference: Riverpod 3 does not export the
  // `Override` type, so there is no name to annotate it with.
  return ProviderContainer.test(
    overrides: [asteroidRepositoryProvider.overrideWithValue(repository)],
  );
}

AsteroidFeed _liveFeed({
  List<String> names = const <String>['2011 EW', '2020 SW'],
}) {
  final List<Asteroid> asteroids = names
      .map(
        (String name) => Asteroid(
          name: name,
          diaMax: 300,
          diaMin: 130,
          hazardous: false,
          missLunar: 12.4,
          missKm: 4800000,
          velKps: 7.1,
          mag: 21.2,
          jpl: 'https://ssd.jpl.nasa.gov/tools/sbdb_lookup.html',
          date: '2026-07-16',
        ),
      )
      .toList(growable: false);

  return AsteroidFeed(
    // `todayList` is deliberately a *different* list from `asteroids` — a
    // window's worth of rocks with only some of them visiting today, which is
    // the normal live shape. Reusing one list for both would leave the two
    // providers indistinguishable, and a mutation swapping them would pass.
    asteroids: asteroids,
    todayList: asteroids.take(1).toList(growable: false),
    feedRange: '2026-07-14 → 2026-07-16',
    usingFallback: false,
  );
}

/// Stands in for the whole repository rather than for the feed source: what is
/// under test is the wiring above `loadData()`, and going through a real
/// repository would drag its clock, its window, and its ceiling into tests
/// about Riverpod.
class _FakeRepository extends AsteroidRepository {
  _FakeRepository(AsteroidFeed feed) : next = feed, super(_UnusedSource());

  /// A repository that breaks its own "never throws" promise. Only the retry
  /// tests use it — it is the bug, staged, not a state the real app reaches.
  _FakeRepository.throwing() : next = null, super(_UnusedSource());

  AsteroidFeed? next;
  int loadCount = 0;

  @override
  Future<AsteroidFeed> loadData() async {
    loadCount++;
    final AsteroidFeed? feed = next;
    if (feed == null) throw _LoadFailure();
    return feed;
  }
}

/// The staged bug: `loadData()` breaking its never-throws promise.
///
/// An `Exception` rather than an `Error`, and the distinction is the whole
/// test. `ProviderContainer.defaultRetry` reads
/// `if (error is ProviderException || error is Error) return null` — so
/// Riverpod's retry **exempts `Error` and retries `Exception`**. A `StateError`
/// here would sail through untouched and the retry tests would both pass while
/// proving nothing. What would actually escape a catch that someone later
/// narrowed is a `DioException` or a `TimeoutException`, and both are
/// `Exception`s — squarely inside what the default retries.
class _LoadFailure implements Exception {
  @override
  String toString() => 'loadData broke its never-throws promise';
}

/// The fake overrides `loadData()` whole, so its source is never reached —
/// and this throws rather than returning an empty list so that a future edit
/// which accidentally calls through fails loudly instead of quietly resolving
/// to the sample set.
class _UnusedSource implements AsteroidFeedSource {
  @override
  Future<List<Asteroid>> fetchFeed({
    required String startDate,
    required String endDate,
  }) => throw StateError('the fake repository never reaches its source');
}

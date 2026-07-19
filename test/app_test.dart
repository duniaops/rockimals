import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:rockimals/core/storage/store.dart';
import 'package:rockimals/core/theme/palette.dart';
import 'package:rockimals/data/asteroid_repository.dart';
import 'package:rockimals/data/feed_cache.dart';
import 'package:rockimals/data/models/asteroid_feed.dart';
import 'package:rockimals/data/neows_client.dart';
import 'package:rockimals/features/data/providers.dart';
import 'package:rockimals/features/loading/loading_screen.dart';
import 'package:rockimals/features/radar/radar_view.dart';
import 'package:rockimals/features/shell/app_shell.dart';
import 'package:rockimals/features/title/title_screen.dart';
import 'package:rockimals/main.dart';

import 'support/memory_store.dart';

void main() {
  // What `RockimalsApp` opens onto. It was the scaffold's placeholder, then the
  // task-01 debug list, then the four-tab shell, then the loading gate; it is
  // now the title screen, which hands over to that gate on a tap.
  // `title_screen_test.dart` owns what the title does, `loading_screen_test.dart`
  // the gate, and `app_shell_test.dart` which tabs exist — all this pins is that
  // a cold launch lands on the title at all, i.e. that nothing routes around it
  // straight to the gate or the shell.
  testWidgets('opens onto the title screen', (tester) async {
    // Needs a scope: the title starts the feed loading at mount (it is what
    // keeps a splash in front of a network gate from being a delay). Overridden
    // with a never-completing future rather than left to the real repository,
    // which would build a Dio to answer a question about routing.
    //
    // **And a store, which it did not need until the badge system.** The
    // celebration popup mounts through `MaterialApp.builder`, above the
    // `Navigator` — it has to, since a badge is nearly always earned inside a
    // pushed game route — so it is built in the first frame of *every* launch
    // and reads the earned ledger there. An in-memory one, because nothing here
    // is asking whether anything persists.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storeProvider.overrideWithValue(MemoryStore()),
          asteroidFeedProvider.overrideWith(
            (Ref ref) => Completer<AsteroidFeed>().future,
          ),
        ],
        child: const RockimalsApp(),
      ),
    );

    expect(find.byType(TitleScreen), findsOneWidget);
    expect(find.byType(LoadingGate), findsNothing);
  });

  // The theme is what every Material widget in the app reads when nothing
  // nearer says otherwise, and until this group it was a `flutter create`
  // default — a seed blue (`#5B7CFA`) that appears nowhere in the prototype.
  group('the theme is a decision', () {
    Future<ThemeData> themeOf(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            // See the note above: the badge popup reads the store in the first
            // frame, so mounting the app at all now needs one.
            storeProvider.overrideWithValue(MemoryStore()),
            asteroidFeedProvider.overrideWith(
              (Ref ref) => Completer<AsteroidFeed>().future,
            ),
          ],
          child: const RockimalsApp(),
        ),
      );
      return tester.widget<MaterialApp>(find.byType(MaterialApp)).theme!;
    }

    testWidgets('the brand orange is the prototype\'s, exactly', (
      tester,
    ) async {
      final ThemeData theme = await themeOf(tester);
      expect(theme.colorScheme.primary, Palette.accent);
      expect(theme.colorScheme.onPrimary, Palette.onAccent);
      expect(theme.colorScheme.brightness, Brightness.dark);
    });

    testWidgets(
      'and it is pinned because the seed alone does not give it back',
      (tester) async {
        // **This is the test that earns the `copyWith` in `main.dart`.** Seeding
        // with `--accent` reads like it would make `primary` be `--accent`; it
        // does not. `fromSeed` runs the seed through a Material 3 tonal palette
        // and returns a harmonised neighbour, so without the override the app
        // would ship an orange that is *not* `#E8571F` while every comment
        // claimed otherwise. Asserting the inequality pins the reason, so a
        // future agent tidying away a `copyWith` that looks redundant finds out
        // here rather than on a device.
        final ColorScheme seeded = ColorScheme.fromSeed(
          seedColor: Palette.accent,
          brightness: Brightness.dark,
        );
        expect(seeded.primary, isNot(Palette.accent));

        final ThemeData theme = await themeOf(tester);
        expect(theme.colorScheme.primary, Palette.accent);
      },
    );

    testWidgets('the backdrop is the prototype\'s page background', (
      tester,
    ) async {
      // Three of the four tabs are bare bodies with no surface of their own, so
      // this colour is on screen today — it is not housekeeping for later.
      final ThemeData theme = await themeOf(tester);
      expect(theme.scaffoldBackgroundColor, Palette.pageBackground);
    });
  });

  group('bootstrap', () {
    late Directory tempDir;

    setUp(() async {
      // A fresh directory per test, for the reason the store's own suite gives:
      // Hive is a process-wide singleton, so a shared one lets a test read the
      // previous test's box and pass for it.
      tempDir = await Directory.systemTemp.createTemp('rockimals_bootstrap');
      PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    });

    tearDown(() async {
      await Hive.deleteFromDisk();
      await Hive.close();
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    });

    testWidgets('opens the store, and it is live in the first frame', (
      tester,
    ) async {
      // The whole point of the item this test covers. `runApp(await
      // bootstrap())` cannot paint before the box is open, so a store read from
      // the very first pumped frame must already answer from disk — no
      // AsyncValue, no null, no "not loaded yet" branch for a child's points to
      // appear from a frame late.
      final Widget root = await _bootstrap(tester);

      await tester.pumpWidget(root);

      final Store store = _storeOf(tester);
      expect(store.points, 0);
      expect(store.follows, isEmpty);
    });

    testWidgets('hands out a store that actually writes to the box', (
      tester,
    ) async {
      // A store on an *unopened* box would satisfy the test above — every read
      // would answer with the same defaults a fresh install gives. Writing and
      // reopening is what separates "the app has a Store object" from "the app
      // has the child's box", which is the thing being wired up here.
      await tester.pumpWidget(await _bootstrap(tester));
      final Store store = _storeOf(tester);

      final Store reopened = (await tester.runAsync(() async {
        await store.setPoints(40);
        await store.setFollows(<String>['2011 EW']);
        await store.close();
        return Store.open();
      }))!;

      expect(reopened.points, 40);
      expect(reopened.follows, <String>['2011 EW']);
    });

    testWidgets('opens the box under the app documents directory', (
      tester,
    ) async {
      // `initFlutter()` is what puts the box somewhere the OS backs up and the
      // app owns, rather than in a temp dir the system may reap. Skipping it
      // would leave `Hive.init` never called and the open would throw — but on
      // a device, not here, so the path is asserted rather than assumed.
      await tester.pumpWidget(await _bootstrap(tester));

      expect(
        File('${tempDir.path}/${Store.boxName}.hive').existsSync(),
        isTrue,
      );
    });

    testWidgets('records the day the clock says, not the day the host is having', (
      tester,
    ) async {
      // The launch used to call `DateTime.now()` inline, so it was the one
      // day-streak trigger no test could drive on a chosen day — the group below
      // asserted nothing about the flame as a result.
      //
      // **Why the seeded history, rather than booting a fresh install on a fixed
      // date and asserting a streak of 1.** That test would pass without the
      // clock being read at all: a fresh install returns 1 on *every* day, so
      // the wall clock produces the same answer. Seeding "played yesterday, on a
      // run of 4" makes the two answers differ and keeps differing — a launch on
      // 2020-01-02 continues the run to 5, while a launch on the host's actual
      // date is years past the gap and restarts at 1. That holds on any day of
      // the year, which is the property a clock test needs; one pinned to a
      // single date passes for the wrong reason 364 days out of 365.
      await _seedStore(tester, (Store store) async {
        await store.setDayStreak(4);
        await store.setLastPlayedDate('2020-01-01');
      });

      await tester.pumpWidget(
        await _bootstrap(
          tester,
          overrides: <Override>[
            dayClockProvider.overrideWithValue(() => DateTime(2020, 1, 2)),
          ],
        ),
      );

      final Store store = _storeOf(tester);
      expect(store.dayStreak, 5);
      expect(store.lastPlayedDate, '2020-01-02');
    });

    testWidgets('one clock override dates the launch and the app alike', (
      tester,
    ) async {
      // The seam this item chose, stated as a test. `bootstrap()` reads
      // [dayClockProvider] out of the overrides it is handed rather than taking
      // a clock parameter of its own, so the single override a test writes for
      // the running app also dates the streak written before the first frame.
      // A `now:` parameter would leave this passing only when a test remembered
      // to set both, which is the two-clock split the sky just closed.
      //
      // Asserted through the flame the child sees — `dayStreakProvider` at the
      // first pumped frame — because "right at first paint" is the reason the
      // record happens in `bootstrap()` at all.
      await _seedStore(tester, (Store store) async {
        await store.setDayStreak(6);
        await store.setLastPlayedDate('2021-03-14');
      });

      await tester.pumpWidget(
        await _bootstrap(
          tester,
          overrides: <Override>[
            dayClockProvider.overrideWithValue(() => DateTime(2021, 3, 15)),
          ],
        ),
      );

      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(RockimalsApp)),
      );
      expect(container.read(dayStreakProvider), 7);
    });
  });

  group('storeProvider', () {
    testWidgets('throws when nothing overrode it', (tester) async {
      // Reading an unwired store must be loud. The quiet alternative — a store
      // over an unopened box — answers zero points and an empty shelf, which is
      // exactly what a child sees when their progress is genuinely gone, with
      // nothing anywhere reporting a problem.
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: SizedBox())),
      );
      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(SizedBox)),
      );

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
  });

  /// `specs/06-title-polish-safety.md:47` — "fully usable offline". Every layer
  /// of that promise is already tested on its own (`asteroid_repository_test`
  /// owns the fallback, `feed_cache_test` the cached sky), so what is left, and
  /// what only a test at this level can ask, is whether they add up to a child
  /// getting from a cold launch to a playable radar with the aeroplane switch on.
  ///
  /// **The whole real stack runs here** — repository, cache, client, retry,
  /// parser — stubbed only at Dio's socket, which is the one thing an aeroplane
  /// actually takes away.
  group('airplane mode', () {
    testWidgets('a cold launch with no network reaches a radar full of animals', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            storeProvider.overrideWithValue(MemoryStore()),
            asteroidRepositoryProvider.overrideWith(_offlineRepository),
          ],
          child: const RockimalsApp(),
        ),
      );

      // Tap Play, as a child does, rather than routing past the title.
      //
      // Pumped by hand rather than settled: the radar's loop schedules a frame
      // forever by design, so `pumpAndSettle` on this screen waits for a quiet
      // frame that never comes. One pump starts the route, one spends its
      // transition, one lands the resolved feed.
      await tester.tap(find.byType(TitleScreen));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      // The gate itself stays — it is the widget that *renders* the shell, not
      // one the shell replaces. What must be gone is the spinner behind it.
      expect(
        find.byType(LoadingScreen),
        findsNothing,
        reason: 'the gate must not strand a child on "Contacting NASA…"',
      );
      expect(find.byType(AppShell), findsOneWidget);

      // A sky, and specifically the bundled one — the fourteen sample rocks the
      // repository substitutes when NASA cannot be reached.
      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(RockimalsApp)),
      );
      final AsteroidFeed feed = container
          .read(asteroidFeedProvider)
          .requireValue;
      expect(feed.usingFallback, isTrue);
      expect(feed.asteroids, hasLength(14));

      // And it is *playing*: the radar's loop is running, which is the
      // difference between a screen that opened offline and one that works
      // offline. Earth's glow is the thing on this screen that only moves if
      // frames are being drawn (`radar_view_test.dart` pins the radii).
      expect(find.byType(RadarView), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 471));
      expect(tester.takeException(), isNull);
    });

    testWidgets('and never leaves a prefetch pending behind it', (
      tester,
    ) async {
      // The prefetch fires only when the sky is a real one, so an offline launch
      // must not start one at all. If it ever did, this test would fail at
      // teardown with a pending timer rather than anywhere near the cause —
      // which is why it is asserted here rather than left to be discovered.
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            storeProvider.overrideWithValue(MemoryStore()),
            asteroidRepositoryProvider.overrideWith(_offlineRepository),
          ],
          child: const RockimalsApp(),
        ),
      );
      await tester.tap(find.byType(TitleScreen));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });
}

/// The app's real data stack over a socket that refuses every connection — the
/// composition `asteroidRepositoryProvider` builds, with one adapter swapped.
///
/// The retry interceptor's sleeps are stubbed out: they are real durations
/// (400ms, then 800ms) that `neows_client_test.dart` already owns, and leaving
/// them in would only make this test wait out a schedule it is not asking about.
AsteroidRepository _offlineRepository(Ref ref) {
  final Dio dio = Dio()..httpClientAdapter = _RefusedAdapter();
  return AsteroidRepository(
    CachingFeedSource(
      NeoWsClient(dio: dio, sleep: (Duration _) async {}),
      ref.watch(storeProvider),
    ),
  );
}

/// Airplane mode, as Dio sees it.
class _RefusedAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => throw DioException.connectionError(
    requestOptions: options,
    reason: 'airplane mode',
  );

  @override
  void close({bool force = false}) {}
}

/// Runs the real boot sequence with the sky held back, and **must** go through
/// [WidgetTester.runAsync].
///
/// The feed is overridden with a future that never completes, so these stay
/// tests of the boot sequence. `RockimalsApp` opens onto the title screen, which
/// starts the feed loading the moment it mounts — so without this, asking
/// whether the store is open would build a real Dio, fire a real request, and
/// leave the repository's ten-second ceiling pending when the tree is disposed.
/// A never-completing future also holds the app on the title, which is exactly
/// the state a cold launch is in at the moment these assertions look — and the
/// reason they pin the store rather than anything the shell shows: in front of
/// the gate, the shell does not exist yet.
///
/// A `testWidgets` body runs in a fake-async zone where timers and I/O
/// completions are the test's to pump, so a future that only completes on a real
/// disk read never completes at all: `await bootstrap()` here hangs until the
/// framework kills the test 100s later with "did not complete", which reads as a
/// deadlock in the app rather than as the test harness doing exactly what it
/// says on the tin. `runAsync` hands the body back the real event loop for the
/// duration. Anything else in this file that touches the box — a `setPoints`, a
/// reopen — needs the same treatment for the same reason.
Future<Widget> _bootstrap(
  WidgetTester tester, {
  List<Override> overrides = const <Override>[],
}) async => (await tester.runAsync(
  () => bootstrap(
    overrides: <Override>[
      asteroidFeedProvider.overrideWith(
        (Ref ref) => Completer<AsteroidFeed>().future,
      ),
      ...overrides,
    ],
  ),
))!;

/// Write into the box `bootstrap()` is about to open, so a launch can be asked
/// what it did with a history rather than only with a fresh install.
///
/// Opens and closes around the seed deliberately: [Store.open] hands back a
/// handle on the process-wide Hive box, and leaving it open would let
/// `bootstrap()`'s own open answer from an already-live handle — which passes
/// here and is not what a cold launch does. `initFlutter` is called first
/// because nothing else has yet; `bootstrap()` calls it again and it is
/// idempotent.
Future<void> _seedStore(
  WidgetTester tester,
  Future<void> Function(Store store) seed,
) async {
  await tester.runAsync(() async {
    await Hive.initFlutter();
    final Store store = await Store.open();
    await seed(store);
    await store.close();
  });
}

/// Anchored on [RockimalsApp] rather than on any screen, deliberately: it is the
/// one widget under the scope that is there in every load state, so this keeps
/// answering the store's question while the app in front of it changes. It used
/// to look for the shell, which the loading gate now holds back until the sky
/// lands — a store test failing on a routing change was the wrong coupling.
Store _storeOf(WidgetTester tester) {
  return ProviderScope.containerOf(
    tester.element(find.byType(RockimalsApp)),
  ).read(storeProvider);
}

/// The documented way to fake `path_provider` on the host VM: swap the platform
/// implementation, not the method channel. `Hive.initFlutter()` asks it for the
/// app-documents directory and nothing else here does.
class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.path);

  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

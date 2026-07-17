import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:rockimals/core/storage/store.dart';
import 'package:rockimals/core/theme/palette.dart';
import 'package:rockimals/data/models/asteroid_feed.dart';
import 'package:rockimals/features/data/providers.dart';
import 'package:rockimals/features/loading/loading_screen.dart';
import 'package:rockimals/main.dart';

void main() {
  // What `RockimalsApp` opens onto. It was the scaffold's placeholder, then the
  // task-01 debug list, then the four-tab shell; it is now the loading gate,
  // which shows "Contacting NASA…" and puts that shell up once there is a sky.
  // `loading_screen_test.dart` owns what the gate does and `app_shell_test.dart`
  // owns which tabs exist — all this pins is that the app opens onto the gate at
  // all, i.e. that nothing routes around it straight to the shell.
  testWidgets('opens onto the loading gate', (tester) async {
    // Needs a scope: the gate watches the feed. Overridden with a
    // never-completing future rather than left to the real repository, which
    // would build a Dio and a store to answer a question about routing.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          asteroidFeedProvider.overrideWith(
            (Ref ref) => Completer<AsteroidFeed>().future,
          ),
        ],
        child: const RockimalsApp(),
      ),
    );

    expect(find.byType(LoadingGate), findsOneWidget);
  });

  // The theme is what every Material widget in the app reads when nothing
  // nearer says otherwise, and until this group it was a `flutter create`
  // default — a seed blue (`#5B7CFA`) that appears nowhere in the prototype.
  group('the theme is a decision', () {
    Future<ThemeData> themeOf(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            asteroidFeedProvider.overrideWith(
              (Ref ref) => Completer<AsteroidFeed>().future,
            ),
          ],
          child: const RockimalsApp(),
        ),
      );
      return tester.widget<MaterialApp>(find.byType(MaterialApp)).theme!;
    }

    testWidgets('the brand orange is the prototype\'s, exactly', (tester) async {
      final ThemeData theme = await themeOf(tester);
      expect(theme.colorScheme.primary, Palette.accent);
      expect(theme.colorScheme.onPrimary, Palette.onAccent);
      expect(theme.colorScheme.brightness, Brightness.dark);
    });

    testWidgets('and it is pinned because the seed alone does not give it back', (
      tester,
    ) async {
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
    });

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

      expect(File('${tempDir.path}/${Store.boxName}.hive').existsSync(), isTrue);
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
}

/// Runs the real boot sequence with the sky held back, and **must** go through
/// [WidgetTester.runAsync].
///
/// The feed is overridden with a future that never completes, so these stay
/// tests of the boot sequence. `RockimalsApp` opens onto the loading gate, which
/// watches the feed — so without this, asking whether the store is open would
/// build a real Dio, fire a real request, and leave the repository's
/// ten-second ceiling pending when the tree is disposed. A never-completing
/// future also holds the app on "Contacting NASA…", which is exactly the state a
/// cold launch is in at the moment these assertions look — and the reason they
/// pin the store rather than anything the shell shows: behind the gate, the
/// shell does not exist yet.
///
/// A `testWidgets` body runs in a fake-async zone where timers and I/O
/// completions are the test's to pump, so a future that only completes on a real
/// disk read never completes at all: `await bootstrap()` here hangs until the
/// framework kills the test 100s later with "did not complete", which reads as a
/// deadlock in the app rather than as the test harness doing exactly what it
/// says on the tin. `runAsync` hands the body back the real event loop for the
/// duration. Anything else in this file that touches the box — a `setPoints`, a
/// reopen — needs the same treatment for the same reason.
Future<Widget> _bootstrap(WidgetTester tester) async => (await tester.runAsync(
  () => bootstrap(
    overrides: <Override>[
      asteroidFeedProvider.overrideWith(
        (Ref ref) => Completer<AsteroidFeed>().future,
      ),
    ],
  ),
))!;

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

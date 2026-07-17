import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:rockimals/core/storage/store.dart';
import 'package:rockimals/features/data/providers.dart';
import 'package:rockimals/features/games/games_hub.dart';
import 'package:rockimals/features/games/games_providers.dart';

/// The Play hub (`specs/04`, "Build the Play hub"): the four game cards with
/// their bests, and the sound toggle that must survive a restart.
///
/// **Split the way the codebase splits store-backed UI.** The *widget* tests
/// stand values in front of the two hub providers and never touch a box — the
/// same seam the radar suite uses, and the reason it exists is sharp here: real
/// Hive I/O awaited inside `testWidgets` deadlocks, because the binding's fake
/// async never advances the disk write's real timer. The *persistence* promise
/// is a store round trip, so it is a plain `test()` against a real box (the
/// store suite's own pattern), where `await` works.
void main() {
  group('the hub screen', () {
    Future<void> pumpHub(
      WidgetTester tester, {
      GamesHubStats stats = const GamesHubStats(
        points: 0,
        bestDuel: 0,
        bestCloser: 0,
        bestSize: 0,
      ),
      bool soundOn = true,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            gamesHubStatsProvider.overrideWithValue(stats),
            soundOnProvider.overrideWith(() => _FakeSoundOn(soundOn)),
          ],
          child: const MaterialApp(home: GamesHub()),
        ),
      );
      await tester.pump();
    }

    group('the four game cards', () {
      testWidgets('lists all four with the prototype titles', (tester) async {
        await pumpHub(tester);

        expect(find.text("Today's Challenge"), findsOneWidget);
        expect(find.text('Power Duel'), findsOneWidget);
        expect(find.text('Closer or Farther'), findsOneWidget);
        expect(find.text('Animal Match'), findsOneWidget);
      });

      testWidgets('shows the points total and each best from storage', (
        tester,
      ) async {
        await pumpHub(
          tester,
          stats: const GamesHubStats(
            points: 120,
            bestDuel: 7,
            bestCloser: 3,
            bestSize: 5,
          ),
        );

        expect(find.text('120'), findsOneWidget);
        // Today's Challenge carries the fixed "Daily" tag, not a best.
        expect(find.text('Daily'), findsOneWidget);
        expect(find.text('Best 7'), findsOneWidget);
        expect(find.text('Best 3'), findsOneWidget);
        // Animal Match is scored out of 8.
        expect(find.text('Best 5/8'), findsOneWidget);
      });

      testWidgets('a fresh install shows zeroed bests', (tester) async {
        await pumpHub(tester);

        expect(find.text('0'), findsOneWidget); // points
        expect(find.text('Best 0'), findsNWidgets(2)); // Duel + Closer
        expect(find.text('Best 0/8'), findsOneWidget); // Animal Match
      });
    });

    group('the sound toggle', () {
      testWidgets('flips the icon on tap', (tester) async {
        await pumpHub(tester);

        // Defaults to on (`Store.soundOn`).
        expect(find.text('🔊'), findsOneWidget);
        expect(find.text('🔇'), findsNothing);

        await tester.tap(find.text('🔊'));
        await tester.pump();

        expect(find.text('🔇'), findsOneWidget);
        expect(find.text('🔊'), findsNothing);
      });

      testWidgets('starts muted when the stored value is off', (tester) async {
        await pumpHub(tester, soundOn: false);

        expect(find.text('🔇'), findsOneWidget);
        expect(find.text('🔊'), findsNothing);
      });
    });

    group('launching a game', () {
      testWidgets('a card opens its game placeholder', (tester) async {
        await pumpHub(tester);

        await tester.tap(find.text('Power Duel'));
        await tester.pumpAndSettle();

        // The games themselves are still ahead in specs/04, so a tap lands on
        // the kid-toned placeholder that names the game — proof the route is
        // wired, which each game item swaps for the real game.
        expect(
          find.text('This game is on its way — coming soon!'),
          findsOneWidget,
        );
      });

      testWidgets('Back returns to the hub', (tester) async {
        await pumpHub(tester);

        await tester.tap(find.text('Animal Match'));
        await tester.pumpAndSettle();
        expect(
          find.text('This game is on its way — coming soon!'),
          findsOneWidget,
        );

        await tester.tap(find.bySemanticsLabel('Back'));
        await tester.pumpAndSettle();

        // Back on the hub: the placeholder is gone and the cards are up again.
        expect(
          find.text('This game is on its way — coming soon!'),
          findsNothing,
        );
        expect(find.text("Today's Challenge"), findsOneWidget);
      });
    });
  });

  // The promise the item names — "the sound toggle persists across a restart" —
  // is a store round trip, so it is exercised against a real box in a plain
  // async test where `await` on Hive works (unlike inside `testWidgets`).
  group('the sound toggle persists (real store)', () {
    late Directory tempDir;
    late Store store;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('rockimals_games_hub');
      Hive.init(tempDir.path);
      store = await Store.open();
    });

    tearDown(() async {
      await Hive.deleteFromDisk();
      await Hive.close();
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    });

    test('toggling off survives a close and reopen', () async {
      final ProviderContainer container = ProviderContainer(
        overrides: [storeProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);

      // Seeded on from the store's default.
      expect(container.read(soundOnProvider), isTrue);

      await container.read(soundOnProvider.notifier).toggle();
      expect(container.read(soundOnProvider), isFalse);

      // Force-quit and relaunch: closing flushes the write, a new Store reads
      // it back off disk.
      await store.close();
      final Store reopened = await Store.open();
      expect(reopened.soundOn, isFalse);
    });
  });
}

/// An in-memory [SoundOnNotifier] for the widget tests: it flips [state] the way
/// the real one does but writes to no box, keeping these tests off Hive (and so
/// off the fake-async deadlock a real write would cause).
class _FakeSoundOn extends SoundOnNotifier {
  _FakeSoundOn(this._initial);

  final bool _initial;

  @override
  bool build() => _initial;

  @override
  Future<void> toggle() async => state = !state;
}

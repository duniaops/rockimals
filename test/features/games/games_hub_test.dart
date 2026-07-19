import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:rockimals/core/audio/sound_engine.dart';
import 'package:rockimals/core/chrome/panel.dart';
import 'package:rockimals/core/storage/store.dart';
import 'package:rockimals/core/theme/featured_gradient.dart';
import 'package:rockimals/core/theme/palette.dart';
import 'package:rockimals/features/data/providers.dart';
import 'package:rockimals/features/games/games_hub.dart';
import 'package:rockimals/features/games/games_providers.dart';
import 'package:rockimals/features/settings/calm_motion.dart';
import 'package:rockimals/features/settings/little_kids_mode.dart';
import 'package:rockimals/features/settings/sound.dart';

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
import '../../support/recording_sound_engine.dart';
import '../../support/stub_settings.dart';

void main() {
  /// The snapshot is provider *state*, and Riverpod asks it whether it changed.
  /// `GameActions` only invalidates after a number moved, so nothing hits the
  /// equal case today — which is exactly why it is pinned here rather than left
  /// to the first item that widens the invalidation list.
  group('GamesHubStats compares by value, not identity', () {
    test('two snapshots of the same four numbers are equal', () {
      const GamesHubStats a = GamesHubStats(
        points: 120,
        bestDuel: 7,
        bestCloser: 3,
        bestSize: 5,
      );
      const GamesHubStats b = GamesHubStats(
        points: 120,
        bestDuel: 7,
        bestCloser: 3,
        bestSize: 5,
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('a move in any one of the four is a different snapshot', () {
      const GamesHubStats base = GamesHubStats(
        points: 120,
        bestDuel: 7,
        bestCloser: 3,
        bestSize: 5,
      );

      // One assertion per field, because an `==` that forgets a field is
      // exactly the bug that would strand that number on the hub.
      expect(
        base,
        isNot(
          const GamesHubStats(
            points: 130,
            bestDuel: 7,
            bestCloser: 3,
            bestSize: 5,
          ),
        ),
      );
      expect(
        base,
        isNot(
          const GamesHubStats(
            points: 120,
            bestDuel: 8,
            bestCloser: 3,
            bestSize: 5,
          ),
        ),
      );
      expect(
        base,
        isNot(
          const GamesHubStats(
            points: 120,
            bestDuel: 7,
            bestCloser: 4,
            bestSize: 5,
          ),
        ),
      );
      expect(
        base,
        isNot(
          const GamesHubStats(
            points: 120,
            bestDuel: 7,
            bestCloser: 3,
            bestSize: 6,
          ),
        ),
      );
    });
  });

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
      bool littleKidsMode = false,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            gamesHubStatsProvider.overrideWithValue(stats),
            soundOnProvider.overrideWith(() => _FakeSoundOn(soundOn)),
            reducedMotionProvider.overrideWith(StubCalmMotion.new),
            // Stubbed rather than left real: the hub resolves this setting to
            // pick its card list, and the real notifier reads a store this
            // suite deliberately does not open (see the file's header).
            littleKidsModeProvider.overrideWith(
              () => StubLittleKids(littleKidsMode),
            ),
            // Turning the toggle on answers with a jingle; keep it off the
            // plugin. `game_sound_test.dart` asserts the blip itself.
            soundEngineProvider.overrideWithValue(RecordingSoundEngine()),
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

    /// `.gcard`'s two branches (`index.html:204-210`).
    ///
    /// **Why the hub's suite pins a surface at all.** A plain game card is the
    /// prototype's `.panel` with a tap on it — the same fill, corners, border
    /// and padding the detail panels and the About block wear — and it used to
    /// say so by restating all four values locally. It now reads
    /// `core/chrome/panel.dart`, and these tests are what stops it drifting
    /// back: the plain card must equal that surface, and the featured branch
    /// must *not* have been folded in with it, which is the way a
    /// de-duplication of this shape goes wrong.
    ///
    /// Asserted against `kPanelSurface` rather than against re-typed literals on
    /// purpose. This suite's job is "the card wears the shared surface"; the job
    /// of pinning what that surface *is* belongs to `panel_test.dart`, which
    /// asserts the radius, padding, fill and border against the values in
    /// `index.html:105`. Restating them here would mean editing two suites to
    /// change one number, and would say nothing the pair does not already say.
    group('the card surface', () {
      /// The nearest [Ink] above a card's title — its surface. `.first` because
      /// the points card at the top of the hub is an [Ink] too, further up.
      BoxDecoration surfaceOf(WidgetTester tester, String title) {
        final Ink ink = tester.widget<Ink>(
          find.ancestor(of: find.text(title), matching: find.byType(Ink)).first,
        );
        return ink.decoration! as BoxDecoration;
      }

      testWidgets('every plain card wears the shared `.panel` surface', (
        tester,
      ) async {
        // All three, not one: the branch is per-card, so a card that stopped
        // taking the shared surface would be a single tile looking wrong on a
        // screen whose other tiles still looked right.
        await pumpHub(tester);

        expect(surfaceOf(tester, 'Power Duel'), kPanelSurface);
        expect(surfaceOf(tester, 'Closer or Farther'), kPanelSurface);
        expect(surfaceOf(tester, 'Animal Match'), kPanelSurface);
      });

      testWidgets('the featured card keeps its gradient and accent border', (
        tester,
      ) async {
        // `.gfeat` (`index.html:210`) is a *different* surface that happens to
        // share `.panel`'s geometry. The failure this guards is the tempting
        // one: routing both branches through the shared surface and losing the
        // one card the hub is built around standing out.
        await pumpHub(tester);

        final BoxDecoration featured = surfaceOf(tester, "Today's Challenge");

        expect(featured.gradient, kFeaturedGradient);
        expect(featured.color, isNull, reason: 'the gradient is the fill');
        expect(
          featured.border,
          const Border.fromBorderSide(BorderSide(color: Palette.accent)),
        );
      });

      testWidgets('both branches wear the panel radius and 14px padding', (
        tester,
      ) async {
        // The half `.gfeat` genuinely does share, and the half that made the
        // two branches worth reading from one place even where they differ.
        await pumpHub(tester);

        for (final String title in <String>[
          'Power Duel',
          "Today's Challenge",
        ]) {
          expect(
            surfaceOf(tester, title).borderRadius,
            kPanelRadius,
            reason: title,
          );

          final Padding pad = tester.widget<Padding>(
            find
                .ancestor(of: find.text(title), matching: find.byType(Padding))
                .first,
          );
          expect(pad.padding, kPanelPadding, reason: title);
        }
      });

      testWidgets('the splash is clipped to the same corners it paints', (
        tester,
      ) async {
        // The radius is stated twice — once on the decoration, once on the
        // [InkWell] — because Flutter has no way to state it once. A ripple
        // spilling past a card's corner is the symptom when they drift.
        await pumpHub(tester);

        final InkWell well = tester.widget<InkWell>(
          find
              .ancestor(
                of: find.text('Power Duel'),
                matching: find.byType(InkWell),
              )
              .first,
        );

        expect(well.borderRadius, kPanelRadius);
      });
    });

    /// 🧸 Little Kids mode narrows the hub to "the simplest two games"
    /// (`specs/06-title-polish-safety.md:26`).
    ///
    /// **Asserted here rather than only on the experience object**, because the
    /// promise a grown-up is making when they flip that switch is about what a
    /// child can reach, and the hub is the only door to any game — no other
    /// widget in the app constructs one. A card that is not drawn is a game that
    /// cannot be started, and that is the claim worth pinning.
    group('🧸 Little Kids mode', () {
      testWidgets('keeps only Power Duel and Closer or Farther', (
        tester,
      ) async {
        await pumpHub(tester, littleKidsMode: true);

        expect(find.text('Power Duel'), findsOneWidget);
        expect(find.text('Closer or Farther'), findsOneWidget);

        // The two dropped, and *why* they are the two: Today's Challenge asks a
        // child to order four animals against each other, and Animal Match poses
        // its question as a width in metres. See `_GameCard.simplest`.
        expect(find.text("Today's Challenge"), findsNothing);
        expect(find.text('Animal Match'), findsNothing);
      });

      testWidgets('drops the featured card without breaking the screen', (
        tester,
      ) async {
        // Today's Challenge is the only `featured: true` card, so turning the
        // mode on removes the one gradient tile from the list. The points card
        // above still carries the accent, and nothing overflows — worth a look
        // because the hub's layout was built around a featured card existing.
        await pumpHub(tester, littleKidsMode: true);

        expect(tester.takeException(), isNull);
        expect(find.text('Daily'), findsNothing);
        expect(find.text('Best 0'), findsNWidgets(2), reason: 'Duel + Closer');
        expect(
          find.text('Best 0/8'),
          findsNothing,
          reason: 'Animal Match went',
        );
      });

      testWidgets('narrows and widens without a restart', (tester) async {
        // `specs/08-settings-about.md:75`'s bar for the toggle beside this one,
        // and the reason the hub watches the experience rather than reading it
        // once: a grown-up flipping the switch in Settings expects the Play
        // screen to have changed by the time they walk back to it.
        await pumpHub(tester);
        expect(find.text('Animal Match'), findsOneWidget);

        final ProviderContainer container = ProviderScope.containerOf(
          tester.element(find.byType(GamesHub)),
        );
        await container.read(littleKidsModeProvider.notifier).choose(true);
        await tester.pump();

        expect(find.text('Animal Match'), findsNothing);
        expect(find.text('Power Duel'), findsOneWidget);

        await container.read(littleKidsModeProvider.notifier).choose(false);
        await tester.pump();

        expect(find.text('Animal Match'), findsOneWidget);
        expect(find.text("Today's Challenge"), findsOneWidget);
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

    // **The "launching a game" group is gone, on purpose.** Both of its tests
    // asserted the kid-toned "coming soon" placeholder, and Animal Match — the
    // last card still routed to it — has landed, so the placeholder and its
    // branch are deleted. Each game's own suite now proves its card reaches it
    // (`match_game_test.dart` also carries the Back-to-the-hub leg), which is
    // strictly more than a placeholder could show.
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

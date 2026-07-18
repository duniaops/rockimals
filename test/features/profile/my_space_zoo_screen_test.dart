/// The My Space Zoo tab (`specs/05`, "My Space Zoo (Profile tab)"): *"All values
/// match storage; the progress bar advances as points are earned."*
///
/// **Two halves, and the second is the one the item was really about.** The
/// first half is ordinary rendering — the right number in the right place, the
/// shelf lit and dimmed correctly. The second is the seam: this is the first
/// screen in the app that shows numbers moved by a *different* screen, so the
/// live tests drive the real `gameActionsProvider` — the same object a game
/// calls — and assert that each of the four figures moves without a relaunch.
/// Asserting that against a hand-built `GameActions` would test everything
/// except the wiring, and the wiring is where staleness lives
/// (`games_providers.dart` says so at length).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/core/audio/sound_engine.dart';
import 'package:rockimals/core/storage/store.dart';
import 'package:rockimals/features/data/providers.dart';
import 'package:rockimals/features/games/game_shell.dart';
import 'package:rockimals/features/profile/my_space_zoo_screen.dart';
import 'package:rockimals/features/profile/profile_providers.dart';
import 'package:rockimals/features/rewards/badge_controller.dart';
import 'package:rockimals/features/rewards/badges.dart';

import '../../support/memory_store.dart';
import '../../support/recording_sound_engine.dart';

void main() {
  group('ProfileStats', () {
    test('reads the points total and the best answer streak off the store', () {
      final ProviderContainer container = _container(
        MemoryStore(points: 142, bestStreak: 7),
      );

      final ProfileStats stats = container.read(profileStatsProvider);
      expect(stats.points, 142);
      expect(stats.bestStreak, 7);
    });

    test('does not read the day streak in place of the answer streak', () {
      // `bestStreak` (runs of correct answers) and `dayStreak` (consecutive days
      // opened) are one word apart and both plausible under a 🔥. The Profile
      // shows the first; the radar's home flame shows the second. A fixture
      // where they differ is the only way this stays true.
      final ProviderContainer container = _container(
        MemoryStore(bestStreak: 3, dayStreak: 11),
      );

      expect(container.read(profileStatsProvider).bestStreak, 3);
    });

    test('compares by value, so an idle invalidation repaints nothing', () {
      // A `Provider` notifies on `!=`, and this snapshot is dropped and rebuilt
      // by every points award — including the ones that land while the Profile
      // is the visible tab. Identity equality would repaint the whole nine-tile
      // shelf on each one.
      expect(
        const ProfileStats(points: 40, bestStreak: 2),
        const ProfileStats(points: 40, bestStreak: 2),
      );
      expect(
        const ProfileStats(points: 40, bestStreak: 2),
        isNot(const ProfileStats(points: 41, bestStreak: 2)),
      );
      expect(
        const ProfileStats(points: 40, bestStreak: 2).hashCode,
        const ProfileStats(points: 40, bestStreak: 2).hashCode,
      );
    });
  });

  group('the points hero', () {
    testWidgets('shows the total and its caption', (tester) async {
      await tester.pumpWidget(_app(MemoryStore(points: 142)));

      expect(find.text('142'), findsOneWidget);
      expect(find.text('points collected'), findsOneWidget);
    });

    testWidgets('names the next tier and what it costs', (tester) async {
      // `${goal.need-goal.have} more points to unlock ${goal.name}`
      // (`index.html:532`). 60 points is past Mouse Scout (50) and short of Fox
      // Explorer (150), so the line must name the tier *ahead* rather than the
      // one just passed — the off-by-one `nextBadgeGoal` exists to get right.
      await tester.pumpWidget(_app(MemoryStore(points: 60)));

      expect(
        find.text('90 more points to unlock 🦊 Fox Explorer'),
        findsOneWidget,
      );
    });

    testWidgets('fills the bar to the fraction of the next tier reached', (
      tester,
    ) async {
      await tester.pumpWidget(_app(MemoryStore(points: 75)));

      // 75/150 towards Fox Explorer. Read off the rendered box rather than off
      // `BadgeGoal.progress`, so a bar wired to the wrong number — or to
      // nothing — fails here rather than passing on the model's word.
      expect(_barFill(tester), closeTo(0.5, 1e-9));
    });

    testWidgets('starts the bar empty on a fresh install', (tester) async {
      await tester.pumpWidget(_app(MemoryStore()));

      expect(_barFill(tester), 0);
      expect(find.text('50 more points to unlock 🐭 Mouse Scout'), findsOneWidget);
    });

    testWidgets('swaps the bar for the master line once every tier is passed', (
      tester,
    ) async {
      // `index.html:533`. A bar pinned at 100% forever would read as unfinished
      // business; past 1000 there is none, and this is the one screen that gets
      // to say so.
      await tester.pumpWidget(_app(MemoryStore(points: 1000)));

      expect(
        find.text('🏆 All animal badges collected — you’re a Space Zoo Master!'),
        findsOneWidget,
      );
      expect(find.byType(FractionallySizedBox), findsNothing);
    });
  });

  group('the three stats', () {
    testWidgets('read from the three different places they live', (
      tester,
    ) async {
      // The whole point of this test is that these three numbers do *not* share
      // a source: the badge count comes from `badgesProvider` (seeded off
      // `Store.badges`), the streak from `ProfileStats`, and the follow count
      // from `followsProvider`. Three distinct values, so a tile wired to the
      // wrong one cannot pass by coincidence.
      await tester.pumpWidget(
        _app(
          MemoryStore(
            bestStreak: 7,
            badges: const <String>['play', 'mouse'],
            follows: const <String>['2026 AA', '2026 BB', '2026 CC'],
          ),
        ),
      );

      expect(find.text('🏅 2'), findsOneWidget);
      expect(find.text('🔥 7'), findsOneWidget);
      expect(find.text('🐾 3'), findsOneWidget);
      expect(find.text('BADGES'), findsOneWidget);
      expect(find.text('BEST STREAK'), findsOneWidget);
      expect(find.text('FOLLOWING'), findsOneWidget);
    });

    testWidgets('announce a whole sentence rather than an emoji and a number', (
      tester,
    ) async {
      // "paw prints 3" is not a fact, and "FOLLOWING" without its number is not
      // one either — the two fragments only mean something together, so the tile
      // carries one label and hides its own visual.
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(
          MemoryStore(
            bestStreak: 7,
            badges: const <String>['play'],
            follows: const <String>['2026 AA', '2026 BB'],
          ),
        ),
      );

      expect(find.bySemanticsLabel('1 badge earned'), findsOneWidget);
      expect(find.bySemanticsLabel('Best streak: 7'), findsOneWidget);
      expect(find.bySemanticsLabel('Following 2 animals'), findsOneWidget);
      // The hero is one figure too, not a star beside a loose number.
      expect(find.bySemanticsLabel('0 points collected'), findsOneWidget);

      handle.dispose();
    });

    testWidgets('say "badge" and "animal" when there is exactly one', (
      tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(MemoryStore(follows: const <String>['2026 AA'])),
      );

      expect(find.bySemanticsLabel('Following 1 animal'), findsOneWidget);
      expect(find.bySemanticsLabel('0 badges earned'), findsOneWidget);

      handle.dispose();
    });
  });

  group('the badge shelf', () {
    testWidgets('shows all nine badges with their goals, earned or not', (
      tester,
    ) async {
      // Every badge, including the ones still ahead — a locked tile is an
      // invitation that says what to do, and a shelf of only what you have is a
      // receipt (`specs/05`: "locked dimmed with their goal").
      await tester.pumpWidget(_app(MemoryStore(badges: const <String>['play'])));

      for (final AnimalBadge badge in kBadges) {
        expect(find.text(badge.title), findsOneWidget, reason: badge.id);
        expect(find.text(badge.description), findsOneWidget, reason: badge.id);
      }
      expect(kBadges, hasLength(9));
    });

    testWidgets('lights the earned ones and dims the rest', (tester) async {
      await tester.pumpWidget(
        _app(MemoryStore(badges: const <String>['play', 'mouse'])),
      );

      // `.zb.lock{opacity:.4}` (`index.html:277`).
      expect(_tileOpacity(tester, 'Lift Off'), 1);
      expect(_tileOpacity(tester, 'Mouse Scout'), 1);
      expect(_tileOpacity(tester, 'Fox Explorer'), 0.4);
      expect(_tileOpacity(tester, 'Perfect Match'), 0.4);
    });

    testWidgets('says out loud which state a tile is in', (tester) async {
      // Dimming is the *only* visual difference between the two states, and
      // opacity is invisible to a screen reader — so without a label an unearned
      // badge would be announced exactly like a won one.
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(_app(MemoryStore(badges: const <String>['play'])));

      expect(
        find.bySemanticsLabel('Lift Off, earned. Play your first game'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          'Mouse Scout, not earned yet. Earn 50 points',
        ),
        findsOneWidget,
      );

      handle.dispose();
    });

    testWidgets('keeps the ladder in kBadges order', (tester) async {
      // The shelf reads as a journey rather than nine unrelated trophies only
      // because the tiers ascend (`badges.dart` pins the list's order; this
      // pins that the *screen* honours it). Read off the rendered tree, so a
      // grid that laid out column-major would fail here.
      await tester.pumpWidget(_app(MemoryStore()));

      final List<String> onScreen = tester
          .widgetList<Text>(find.byType(Text))
          .map((Text t) => t.data)
          .whereType<String>()
          .where((String s) => kBadges.any((AnimalBadge b) => b.title == s))
          .toList();

      expect(onScreen, kBadges.map((AnimalBadge b) => b.title).toList());
    });
  });

  group('the layout holds', () {
    // A `RenderFlex overflowed` is a thrown exception in a widget test, so
    // these pass only if nothing overflowed. Both cases exist because the shelf
    // is two columns of wrapping text: "Score 8/8 in Animal Match" takes two
    // lines in a half-width tile where "Earn 50 points" takes one, and the
    // three stat captions are not the same length either. This is the risk the
    // rows-of-two layout was chosen over a `SliverGrid` to avoid (see the shelf
    // widget's doc), and an untested claim is not one.
    testWidgets('on a real phone', (tester) async {
      tester.view
        ..physicalSize = const Size(390, 844)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_app(MemoryStore(points: 320)));
      await tester.pumpAndSettle();
    });

    testWidgets('on a narrow phone at the largest text a child may have set', (
      tester,
    ) async {
      // A child handed a phone with the system font scaled up is not an edge
      // case, and 1.5× is inside what iOS and Android offer without their
      // accessibility sizes.
      tester.view
        ..physicalSize = const Size(320, 700)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _scoped(
          _container(MemoryStore(points: 320)),
          textScale: 1.5,
        ),
      );
      await tester.pumpAndSettle();

      // Still all there, not merely un-crashed. The hero is above the fold at
      // this size; the ninth badge is below it, so it is *scrolled to* rather
      // than asserted with `skipOffstage: false` — "built somewhere in the
      // tree" is not the question a child asks of the bottom of a shelf.
      expect(find.text('320'), findsOneWidget);
      await tester.ensureVisible(
        find.text('Perfect Match', skipOffstage: false),
      );
      await tester.pumpAndSettle();
      expect(find.text('Perfect Match'), findsOneWidget);
    });
  });

  group('the numbers stay live', () {
    testWidgets('a follow made anywhere else moves the 🐾 count in one pump', (
      tester,
    ) async {
      // The radar's HUD and the detail screen write `followsProvider`; neither
      // knows this tab exists. The seam is tested at the provider rather than by
      // driving a button another suite already owns.
      final ProviderContainer container = _container(MemoryStore());
      await tester.pumpWidget(_scoped(container));
      expect(find.text('🐾 0'), findsOneWidget);

      await container.read(followsProvider.notifier).toggle('2026 AA');
      await tester.pump();

      expect(find.text('🐾 1'), findsOneWidget);
    });

    testWidgets('points won in a game move the hero and advance the bar', (
      tester,
    ) async {
      // The item's Done-when, driven through the real `gameActionsProvider` —
      // the same object a game holds. This is the invalidation `_onStatsChanged`
      // performs, seen from the screen that would otherwise show a stale total
      // until the next launch.
      final ProviderContainer container = _container(MemoryStore());
      await tester.pumpWidget(_scoped(container));
      expect(find.text('0'), findsOneWidget);
      expect(_barFill(tester), 0);

      await container.read(gameActionsProvider).awardPoints(30);
      await tester.pump();

      expect(find.text('30'), findsOneWidget);
      expect(_barFill(tester), closeTo(0.6, 1e-9));
      expect(find.text('20 more points to unlock 🐭 Mouse Scout'), findsOneWidget);
    });

    testWidgets('a new best answer streak moves the 🔥 stat', (tester) async {
      // `noteStreak` used to fire only the badge check, so this number was the
      // one that would have been stale — the exact bug the plan called out when
      // it asked for the snapshot and the invalidation list to be widened
      // together.
      final ProviderContainer container = _container(MemoryStore());
      await tester.pumpWidget(_scoped(container));
      expect(find.text('🔥 0'), findsOneWidget);

      await container.read(gameActionsProvider).noteStreak(4);
      await tester.pump();

      expect(find.text('🔥 4'), findsOneWidget);
    });

    testWidgets('crossing a tier lights its tile and bumps the 🏅 count', (
      tester,
    ) async {
      // Points, badge count, and the shelf all move off one award — the three
      // living on three different mechanisms is exactly why they are asserted in
      // one breath.
      final ProviderContainer container = _container(MemoryStore());
      await tester.pumpWidget(_scoped(container));
      expect(find.text('🏅 0'), findsOneWidget);
      expect(_tileOpacity(tester, 'Mouse Scout'), 0.4);

      await container.read(gameActionsProvider).awardPoints(50);
      await tester.pump();

      expect(find.text('🏅 1'), findsOneWidget);
      expect(_tileOpacity(tester, 'Mouse Scout'), 1);
      expect(find.text('100 more points to unlock 🦊 Fox Explorer'), findsOneWidget);
    });

    testWidgets('a restart finds the same numbers on the shelf', (tester) async {
      // A fresh container over the same store — the "relaunch" seam.
      // `store_test.dart` owns the disk half; what this asks is that nothing on
      // this screen is held only in memory.
      final Store store = MemoryStore(
        points: 320,
        bestStreak: 6,
        badges: const <String>['play', 'mouse', 'fox', 'bear', 'fire'],
        follows: const <String>['2026 AA'],
      );
      await tester.pumpWidget(_app(store));

      expect(find.text('320'), findsOneWidget);
      expect(find.text('🏅 5'), findsOneWidget);
      expect(find.text('🔥 6'), findsOneWidget);
      expect(find.text('🐾 1'), findsOneWidget);
      expect(_tileOpacity(tester, 'Bear Ranger'), 1);
      expect(_tileOpacity(tester, 'Elephant Expert'), 0.4);
    });
  });
}

/// The bar's fill, 0…1, read off the box that actually renders it.
double _barFill(WidgetTester tester) =>
    tester.widget<FractionallySizedBox>(find.byType(FractionallySizedBox))
        .widthFactor!;

/// The opacity a badge tile is drawn at, found through its title — `1` for an
/// earned badge, `0.4` for one still ahead.
double _tileOpacity(WidgetTester tester, String title) => tester
    .widget<Opacity>(
      find.ancestor(of: find.text(title), matching: find.byType(Opacity)),
    )
    .opacity;

Widget _app(Store store) => _scoped(_container(store));

/// A container wired the way the app is. The sound engine is faked because a
/// badge earned mid-test drains its queue and cheers — a host VM is silent
/// either way, and the real engine has no business being reached from here.
ProviderContainer _container(Store store) {
  final ProviderContainer container = ProviderContainer(
    overrides: [
      storeProvider.overrideWithValue(store),
      soundEngineProvider.overrideWithValue(RecordingSoundEngine()),
    ],
  );
  addTearDown(container.dispose);
  // **The app reads this in its first frame and holds it for the session**
  // (`BadgePopupHost`, off `MaterialApp.builder`), which is what keeps the
  // follow listener registered; here the screen's own `ref.watch` does it from
  // the first pump. Read up front anyway so the container is in the same state
  // before a test drives a provider write from outside the tree.
  container.read(badgesProvider);
  return container;
}

/// [UncontrolledProviderScope] rather than a plain [ProviderScope], because the
/// live tests hold the container and write to it from outside the tree — the
/// pattern `watchlist_screen_test.dart` established for exactly that.
Widget _scoped(ProviderContainer container, {double textScale = 1}) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: const Scaffold(body: MySpaceZooScreen()),
        ),
      ),
    );

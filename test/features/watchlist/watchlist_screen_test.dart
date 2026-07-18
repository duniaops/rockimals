import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/core/mascot/rusty.dart';
import 'package:rockimals/core/storage/store.dart';
import 'package:rockimals/data/fallback_asteroids.dart';
import 'package:rockimals/data/models/asteroid.dart';
import 'package:rockimals/data/models/asteroid_feed.dart';
import 'package:rockimals/features/animals/widgets/animal_card.dart';
import 'package:rockimals/features/data/providers.dart';
import 'package:rockimals/features/detail/detail_screen.dart';
import 'package:rockimals/features/watchlist/watchlist_screen.dart';

import '../../support/memory_store.dart';

/// The My Animals tab — the one screen whose entire content is a consequence of
/// a gesture made *somewhere else*. A child follows an animal on the radar's HUD
/// or on the detail screen; this tab is where that goes. So what these pin is
/// the seam: that a follow made anywhere shows up here in the same frame, that
/// it is still here after a restart, and that unfollowing empties it back to the
/// invitation — the item's Done-when, clause for clause.
///
/// The ordering and the filter are tested against [followedAnimals] directly
/// rather than through the widget, for the reason `sky_screen_test.dart` tests
/// `skyAnimals` that way: a sort assertion that needs a pumped frame to make it
/// is a sort assertion that will one day be deleted for being slow.
void main() {
  group('followedAnimals', () {
    test('keeps only the followed animals', () {
      // `asteroids.filter(a => watch.has(a.name))` (`index.html:499`). Keyed by
      // real designation (plan decision 12) — never the derived "Milo the Fox",
      // which points at a different animal in a build where the pool changed.
      expect(
        followedAnimals(_sky, <String>{'2026 CC', '2026 AA'})
            .map((Asteroid a) => a.name),
        <String>['2026 AA', '2026 CC'],
      );
    });

    test('orders them closest first', () {
      // `sort((a,b) => a.missLunar - b.missLunar)` (`index.html:499`) — the one
      // ordering that answers "who is visiting next?". The fixture's follow set
      // is deliberately given in the *wrong* order, so a dropped sort fails
      // rather than accidentally matching insertion order.
      expect(
        followedAnimals(_sky, <String>{'2026 CC', '2026 BB', '2026 AA'})
            .map((Asteroid a) => a.missLunar),
        <double>[0.5, 2, 9],
      );
    });

    test('never reorders the sky it was handed', () {
      // The source is the shared, unmodifiable `asteroids` list (plan decision
      // 9) — the very list the radar seeds its orbits from. An in-place sort
      // here would silently move the radar's field, which is the kind of bug
      // that shows up two screens away from its cause.
      final List<Asteroid> source = <Asteroid>[..._sky];
      followedAnimals(source, <String>{'2026 AA', '2026 BB', '2026 CC'});
      expect(source.map((Asteroid a) => a.name), _sky.map((Asteroid a) => a.name));
    });

    test('drops a followed animal that has left the window', () {
      // A follow outlives any one feed window: NASA's three days move on, and
      // the rock a child starred last week is simply not in today's sky. There
      // is nothing persisted about it but its designation — no size, no
      // distance, no approach — so there is no card to build, and the prototype
      // drops it too. The follow itself is untouched in the store; the animal
      // comes back the day its rock does.
      expect(followedAnimals(_sky, <String>{'1999 ZZ'}), isEmpty);
    });

    test('is empty when nothing is followed', () {
      expect(followedAnimals(_sky, const <String>{}), isEmpty);
    });
  });

  group('approachNote', () {
    test('shows a real approach date', () {
      expect(approachNote('2026-07-17'), '⏳ approach 2026-07-17');
    });

    test('shows an em-dash for a bundled sample record', () {
      // `a.date === 'sample' ? '—' : a.date` (`index.html:506`). This is a
      // refusal, not a formatting nicety: a sample record carries a deliberate
      // non-date precisely so nothing can pass it off as live data
      // (`fallback_asteroids.dart:202`), and printing the literal "sample"
      // would do exactly that to a child reading it.
      expect(approachNote(sampleDate), '⏳ approach —');
    });
  });

  group('WatchlistScreen', () {
    testWidgets('invites a first follow when nothing is followed', (
      tester,
    ) async {
      // The only screen in the app that is empty by design rather than by
      // failure — so it is the one place the follow gesture has to be *taught*.
      // A child who has never tapped ⭐ Follow has no way to know this tab is
      // where it leads.
      await tester.pumpWidget(_app(MemoryStore()));

      expect(
        find.textContaining('not following any space animals yet'),
        findsOneWidget,
      );
      expect(find.textContaining('⭐ Follow'), findsOneWidget);
      expect(find.byType(AnimalCard), findsNothing);
      // The mascot fronts the invitation (`specs/06-title-polish-safety.md:18`)
      // — Rusty where the prototype had paw prints.
      expect(find.byType(Rusty), findsOneWidget);
    });

    testWidgets('lists the followed animals closest first', (tester) async {
      await tester.pumpWidget(
        _app(MemoryStore(follows: const <String>['2026 CC', '2026 AA'])),
      );

      expect(find.byType(AnimalCard), findsNWidgets(2));
      // Read off the rendered tree rather than the model, so this fails if the
      // list is built in a different order from the one `followedAnimals`
      // returns — the sort being right and the *cards* being right are two
      // facts, and only the second is what a child sees.
      expect(
        tester
            .widgetList<AnimalCard>(find.byType(AnimalCard))
            .map((AnimalCard c) => c.asteroid.name),
        <String>['2026 AA', '2026 CC'],
      );
    });

    testWidgets('captions each card with its approach date', (tester) async {
      // The one thing a watchlist card shows that a Sky card does not
      // (`index.html:505-507`), and the reason `AnimalCard` has a footer slot.
      await tester.pumpWidget(
        _app(MemoryStore(follows: const <String>['2026 AA', '2026 SAMPLE'])),
      );

      expect(find.text('⏳ approach 2026-07-17'), findsOneWidget);
      expect(find.text('⏳ approach —'), findsOneWidget);
    });

    testWidgets('speaks the approach date as well as showing it', (
      tester,
    ) async {
      // The card says its whole meaning through one semantics label and hides
      // the visual behind `ExcludeSemantics` — so a footer added to that visual
      // is silent unless the card is told what it means. Without
      // `AnimalCard.footerLabel` this line renders for a child who can see it
      // and does not exist at all for one using a screen reader, which is the
      // failure mode that looks like nothing in a screenshot.
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(MemoryStore(follows: const <String>['2026 AA'])),
      );

      expect(
        tester.getSemantics(find.byType(AnimalCard)).label,
        contains('⏳ approach 2026-07-17'),
      );

      handle.dispose();
    });

    testWidgets('fills the moment an animal is followed anywhere', (
      tester,
    ) async {
      // The item's "following from either the radar HUD or the detail screen
      // populates it immediately". Neither of those surfaces knows this tab
      // exists — they write `followsProvider`, and this screen watches it. So
      // the seam is tested at the provider rather than by driving a HUD button
      // that `selected_animal_card_test.dart` already owns: what is being
      // pinned is that this screen is *live*, not that the button works.
      final ProviderContainer container = _container(MemoryStore());
      addTearDown(container.dispose);
      await tester.pumpWidget(_scoped(container));

      expect(find.byType(AnimalCard), findsNothing);

      await container.read(followsProvider.notifier).toggle('2026 BB');
      await tester.pump();

      expect(find.byType(AnimalCard), findsOneWidget);
      expect(find.textContaining('not following'), findsNothing);
      // The whole empty state goes, mascot included — a Rusty left over a list
      // would read as the screen contradicting itself.
      expect(find.byType(Rusty), findsNothing);
    });

    testWidgets('empties back to the invitation when the last is unfollowed', (
      tester,
    ) async {
      // The other half of the same Done-when, and not a mirror image of it: a
      // screen can grow a list and still fail to shed it, because the empty
      // branch and the list branch are different code. Unfollowing the *last*
      // animal is the crossing that has to work.
      final ProviderContainer container = _container(
        MemoryStore(follows: const <String>['2026 BB']),
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(_scoped(container));

      expect(find.byType(AnimalCard), findsOneWidget);

      await container.read(followsProvider.notifier).toggle('2026 BB');
      await tester.pump();

      expect(find.byType(AnimalCard), findsNothing);
      expect(find.textContaining('not following'), findsOneWidget);
      expect(find.byType(Rusty), findsOneWidget);
    });

    testWidgets('is still filled after a restart', (tester) async {
      // The "and after a restart" clause. A fresh container over a store that
      // already holds the follows is what a relaunch *is* to this screen —
      // `FollowsNotifier.build` seeds `state` from `store.follows`, so a screen
      // that read some in-memory set instead would pass every test above and
      // come up empty on the second launch, which is the one failure a child
      // would read as lost progress.
      //
      // `store_test.dart` owns the other half — that the set really reaches the
      // disk — by closing and reopening a real Hive box. This owns the seam
      // above it.
      final Store store = MemoryStore(follows: const <String>['2026 AA']);
      await tester.pumpWidget(_app(store));
      expect(find.byType(AnimalCard), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_app(store));

      expect(find.byType(AnimalCard), findsOneWidget);
      expect(find.text('⏳ approach 2026-07-17'), findsOneWidget);
    });

    testWidgets('opens the detail screen when a card is tapped', (tester) async {
      // `acardEl`'s own `onclick = () => openDetail(a)` (`index.html:467`),
      // which the watchlist inherits by reusing the card — the same push the
      // Sky tab makes. Worth its own test because the card takes its `onTap`
      // from the caller and would be a silently dead row if this screen passed
      // one that went nowhere.
      await tester.pumpWidget(
        _app(MemoryStore(follows: const <String>['2026 AA'])),
      );

      await tester.tap(find.byType(AnimalCard));
      await tester.pumpAndSettle();

      expect(find.byType(DetailScreen), findsOneWidget);
    });
  });
}

/// The screen with a sky in hand and a [store] behind the follow set — the two
/// things it reads. The feed is resolved rather than in flight because the
/// screen reads `.requireValue`, and is entitled to: the loading gate builds the
/// shell only once there is a sky, so a pending future here would test a state
/// the app cannot be in.
Widget _app(Store store) => _scoped(_container(store));

ProviderContainer _container(Store store) => ProviderContainer(
  overrides: [
    asteroidFeedProvider.overrideWith((Ref ref) => _feed),
    storeProvider.overrideWithValue(store),
  ],
);

/// [UncontrolledProviderScope] rather than a plain [ProviderScope], so a test
/// can hold the container and write a follow from outside the tree — which is
/// exactly what the radar HUD and the detail screen do to this screen in the
/// real app.
Widget _scoped(ProviderContainer container) => UncontrolledProviderScope(
  container: container,
  child: const MaterialApp(home: Scaffold(body: WatchlistScreen())),
);

final AsteroidFeed _feed = AsteroidFeed(
  asteroids: _sky,
  todayList: _sky,
  feedRange: '2026-07-15 → 2026-07-17',
  provenance: FeedProvenance.today,
);

/// Three rocks whose miss distances are deliberately out of order in the list,
/// plus one carrying [sampleDate] — so the sort and the em-dash both have
/// something to bite on.
final List<Asteroid> _sky = <Asteroid>[
  _rock(name: '2026 CC', missLunar: 9),
  _rock(name: '2026 AA', missLunar: 0.5),
  _rock(name: '2026 BB', missLunar: 2),
  _rock(name: '2026 SAMPLE', missLunar: 4, date: sampleDate),
];

Asteroid _rock({
  required String name,
  required double missLunar,
  String date = '2026-07-17',
}) => Asteroid(
  name: name,
  diaMax: 100,
  diaMin: 50,
  hazardous: false,
  missLunar: missLunar,
  missKm: missLunar * 384400,
  velKps: 12,
  mag: 22,
  jpl: 'https://ssd.jpl.nasa.gov/tools/sbdb_lookup.html',
  date: date,
);

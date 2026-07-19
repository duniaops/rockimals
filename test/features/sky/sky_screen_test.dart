import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/core/mascot/rusty.dart';
import 'package:rockimals/core/theme/palette.dart';
import 'package:rockimals/data/models/asteroid.dart';
import 'package:rockimals/data/models/asteroid_feed.dart';
import 'package:rockimals/features/animals/widgets/animal_card.dart';
import 'package:rockimals/features/data/providers.dart';
import 'package:rockimals/features/detail/detail_screen.dart';
import 'package:rockimals/features/sky/sky_screen.dart';

/// The Sky tab (`specs/07-sky-tab.md`, prototype `renderSky`). Two suites:
/// [skyAnimals] pinned as a pure function — the ordering the spec asks to be
/// unit-tested — and the screen itself for the render, the toggles, the footer,
/// the empty state, and the tap-through to the detail screen.
void main() {
  group('skyAnimals (pure sort + filter)', () {
    // Three rocks whose every ordering field is distinct, so a sort that read
    // the wrong field would still reorder them and be caught. Closeness, size,
    // and speed each rank them in a different order.
    final Asteroid near = _rock(
      name: 'Near',
      missLunar: 0.5,
      diaMax: 30,
      velKps: 5,
    );
    final Asteroid mid = _rock(
      name: 'Mid',
      missLunar: 3,
      diaMax: 800,
      velKps: 25,
    );
    final Asteroid far = _rock(
      name: 'Far',
      missLunar: 12,
      diaMax: 120,
      velKps: 15,
    );
    final List<Asteroid> source = <Asteroid>[mid, far, near];

    List<String> names(List<Asteroid> l) =>
        l.map((Asteroid a) => a.name).toList();

    test('Closest orders by missLunar ascending (the default sort)', () {
      expect(
        names(
          skyAnimals(source, sort: SkySort.closest, closeFlybysOnly: false),
        ),
        <String>['Near', 'Mid', 'Far'],
      );
    });

    test('Biggest orders by diaMax descending', () {
      expect(
        names(
          skyAnimals(source, sort: SkySort.biggest, closeFlybysOnly: false),
        ),
        <String>['Mid', 'Far', 'Near'],
      );
    });

    test('Fastest orders by velKps descending', () {
      expect(
        names(
          skyAnimals(source, sort: SkySort.fastest, closeFlybysOnly: false),
        ),
        <String>['Mid', 'Far', 'Near'],
      );
    });

    test(
      'the filter keeps only close flybys, on flybyTag not raw hazardous',
      () {
        // `Near` at 0.5 Moon-distances is a close flyby by distance alone; a
        // hazardous rock at 5 is one by NASA's flag alone. `Far` at 12 and
        // unflagged is not — this is the plan decision 2 fix the raw `hazardous`
        // filter would miss (it would drop `Near`).
        final Asteroid flagged = _rock(
          name: 'Flagged',
          missLunar: 5,
          hazardous: true,
        );
        final List<Asteroid> pool = <Asteroid>[far, near, flagged, mid];

        final List<Asteroid> kept = skyAnimals(
          pool,
          sort: SkySort.closest,
          closeFlybysOnly: true,
        );

        expect(names(kept), <String>['Near', 'Flagged']);
      },
    );

    test('an empty result when no rock is a close flyby', () {
      // `mid` and `far` are both past the Moon and unflagged.
      final List<Asteroid> kept = skyAnimals(
        <Asteroid>[mid, far],
        sort: SkySort.closest,
        closeFlybysOnly: true,
      );
      expect(kept, isEmpty);
    });

    test('does not mutate the source list (it is the shared radar sky)', () {
      final List<Asteroid> original = List<Asteroid>.of(source);
      skyAnimals(source, sort: SkySort.biggest, closeFlybysOnly: false);
      expect(source, original, reason: 'sorted a copy, never the source');
    });
  });

  group('SkyScreen', () {
    testWidgets('lists every animal in the window, one card each', (
      tester,
    ) async {
      await _mount(tester, _sky(<Asteroid>[_a, _b, _c]));

      expect(find.byType(AnimalCard), findsNWidgets(3));
      expect(find.text('The Sky'), findsOneWidget);
      expect(
        find.text('Every asteroid NASA is tracking in this window.'),
        findsOneWidget,
      );
    });

    testWidgets('defaults to Closest and orders nearest first', (tester) async {
      await _mount(tester, _sky(<Asteroid>[_b, _c, _a]));

      // `_a` is nearest (0.5), then `_b` (3), then `_c` (12).
      expect(_cardOrder(tester), <String>[_a.name, _b.name, _c.name]);
      expect(_toggleSelected(tester, 'Closest'), isTrue);
      expect(_toggleSelected(tester, 'Biggest'), isFalse);
    });

    testWidgets('tapping Biggest re-sorts by size and moves the "on" chip', (
      tester,
    ) async {
      await _mount(tester, _sky(<Asteroid>[_a, _b, _c]));

      await tester.tap(find.text('Biggest'));
      await tester.pump();

      // `_b` is 800 m, `_c` 120 m, `_a` 30 m.
      expect(_cardOrder(tester), <String>[_b.name, _c.name, _a.name]);
      expect(_toggleSelected(tester, 'Biggest'), isTrue);
      expect(_toggleSelected(tester, 'Closest'), isFalse);
    });

    testWidgets('the close-flyby filter narrows the list to flybys', (
      tester,
    ) async {
      // Only `_a` (0.5) is a close flyby; `_b` and `_c` are just passing.
      await _mount(tester, _sky(<Asteroid>[_a, _b, _c]));

      await tester.tap(find.text('👋 Close flybys only'));
      await tester.pump();

      expect(find.byType(AnimalCard), findsOneWidget);
      expect(_cardOrder(tester), <String>[_a.name]);
      // The empty state's mascot must not leak onto a list with cards on it.
      expect(find.byType(Rusty), findsNothing);
    });

    testWidgets(
      'shows the friendly empty state when nothing matches the filter',
      (tester) async {
        // A sky with no close flybys at all — the filter empties the list.
        await _mount(tester, _sky(<Asteroid>[_b, _c]));

        await tester.tap(find.text('👋 Close flybys only'));
        await tester.pump();

        expect(find.byType(AnimalCard), findsNothing);
        expect(
          find.text('No close flybys in this window — good news! 🌍'),
          findsOneWidget,
        );
        // The tone guardrail: never the prototype's "hazardous" wording.
        expect(find.textContaining('hazardous'), findsNothing);
        // And the mascot fronts the good news
        // (`specs/06-title-polish-safety.md:18`).
        expect(find.byType(Rusty), findsOneWidget);
      },
    );

    testWidgets('the footer shows the real window for a live sky', (
      tester,
    ) async {
      await _mount(tester, _sky(<Asteroid>[_a]));
      expect(find.text('📅 Showing 2026-07-15 → 2026-07-17'), findsOneWidget);
    });

    testWidgets('the footer says "sample set" offline, never "Time Machine"', (
      tester,
    ) async {
      await _mount(tester, AsteroidFeed.fallback());

      expect(find.text('📅 Showing sample set'), findsOneWidget);
      // The dropped prototype string (spec 07): it advertised a feature that
      // does not exist.
      expect(find.textContaining('Time Machine'), findsNothing);
      // Offline, every fallback record still renders a card.
      expect(find.byType(AnimalCard), findsWidgets);
    });

    testWidgets('tapping a card opens that animal\'s detail screen', (
      tester,
    ) async {
      await _mount(tester, _sky(<Asteroid>[_a, _b, _c]));

      // The nearest card is `_a` under the default Closest sort.
      await tester.tap(find.byType(AnimalCard).first);
      await tester.pumpAndSettle();

      expect(find.byType(DetailScreen), findsOneWidget);
      // The detail screen it opened is the animal that was tapped.
      expect(
        tester.widget<DetailScreen>(find.byType(DetailScreen)).asteroid.name,
        _a.name,
      );
    });
  });
}

/// The visible names of the cards, in tree (list) order — a few small cards all
/// fit on screen, so the lazy `SliverList.builder` has built them all.
List<String> _cardOrder(WidgetTester tester) => tester
    .widgetList<AnimalCard>(find.byType(AnimalCard))
    .map((AnimalCard c) => c.asteroid.name)
    .toList();

/// Whether the sort/filter chip carrying [label] is in its "on" state — read
/// off its text colour, which is `--onAccent` when selected and `--muted`
/// otherwise (`index.html:78-79`).
bool _toggleSelected(WidgetTester tester, String label) {
  final Text text = tester.widget<Text>(find.text(label));
  return text.style?.color == Palette.onAccent;
}

Future<void> _mount(WidgetTester tester, AsteroidFeed feed) async {
  tester.view
    ..physicalSize = const Size(390, 900)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // Resolving the feed here makes the three derived providers the Sky tab
        // reads (`asteroids`, `feedRange`, `usingFallback`) all `AsyncData`, so
        // `requireValue` is safe — the state the app is always in behind the
        // loading gate.
        asteroidFeedProvider.overrideWith((Ref ref) => feed),
        // The detail screen a tapped card opens reads `followsProvider`; an
        // in-memory follows keeps this suite off a Hive box.
        followsProvider.overrideWith(_MemFollows.new),
      ],
      child: const MaterialApp(home: Scaffold(body: SkyScreen())),
    ),
  );
  await tester.pump();
}

/// A live sky. Only the ordering/flyby fields of each rock matter to these
/// tests; the feed's window string is what the footer reads.
AsteroidFeed _sky(List<Asteroid> rocks) => AsteroidFeed(
  asteroids: rocks,
  todayList: rocks,
  feedRange: '2026-07-15 → 2026-07-17',
  provenance: FeedProvenance.today,
);

/// Three rocks whose closeness, size, and speed each rank them differently, so
/// the widget order tests can tell the three sorts apart.
final Asteroid _a = _rock(
  name: '2026 AA',
  missLunar: 0.5,
  diaMax: 30,
  velKps: 5,
);
final Asteroid _b = _rock(
  name: '2026 BB',
  missLunar: 3,
  diaMax: 800,
  velKps: 25,
);
final Asteroid _c = _rock(
  name: '2026 CC',
  missLunar: 12,
  diaMax: 120,
  velKps: 15,
);

Asteroid _rock({
  required String name,
  required double missLunar,
  double diaMax = 100,
  double velKps = 12,
  bool hazardous = false,
}) => Asteroid(
  name: name,
  diaMax: diaMax,
  diaMin: diaMax / 2,
  hazardous: hazardous,
  missLunar: missLunar,
  missKm: missLunar * 384400,
  velKps: velKps,
  mag: 22,
  jpl: 'https://ssd.jpl.nasa.gov/tools/sbdb_lookup.html',
  date: '2026-07-17',
);

/// An in-memory [FollowsNotifier] so a tapped card can open the detail screen
/// without a real store — the pattern `detail_screen_test.dart` uses.
class _MemFollows extends FollowsNotifier {
  @override
  Set<String> build() => <String>{};

  @override
  Future<void> toggle(String designation) async {
    final Set<String> next = <String>{...state};
    if (next.contains(designation)) {
      next.remove(designation);
    } else {
      next.add(designation);
    }
    state = next;
  }
}

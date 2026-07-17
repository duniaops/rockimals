import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/data/models/asteroid.dart';
import 'package:rockimals/data/models/asteroid_feed.dart';
import 'package:rockimals/features/data/providers.dart';
import 'package:rockimals/features/debug/debug_animal_list_screen.dart';

/// The first screen in the app, and the only one that renders the spine, so
/// what these pin is that the pipeline actually reaches a child's eyes: the
/// right *list* (plan decision 10 — the full sky, not `todayList`), the right
/// *count* offline (spec 01's airplane-mode criterion), and the right *fields*
/// per animal (spec 01 §5).
///
/// The feed provider is overridden directly rather than a repository faked
/// underneath it: `providers_test.dart` owns the wiring below this point, and
/// going through a real repository would drag a clock, a window, and a Dio into
/// a test about a list.
void main() {
  group('DebugAnimalListScreen', () {
    testWidgets('shows a spinner while the sky is still loading', (
      tester,
    ) async {
      // The honest answer before the feed lands. An empty list here would read
      // as "space is empty" — the exact lie the providers' `AsyncValue` shape
      // exists to prevent, and it would be this screen that told it.
      await tester.pumpWidget(_app(Completer<AsteroidFeed>().future));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(ListTile), findsNothing);
    });

    testWidgets('draws the whole sky offline — all fourteen sample animals', (
      tester,
    ) async {
      // Spec 01's airplane-mode criterion, and the assertion that catches the
      // screen being wired to `todayList`: offline that list is the first
      // **seven** records (plan decision 10), so a screen reading it would show
      // seven here and look perfectly plausible doing it.
      _tallEnoughForFourteenRows(tester);

      await tester.pumpWidget(_app(Future<AsteroidFeed>.value(_sampleSky())));
      await tester.pump();

      expect(find.byType(ListTile), findsNWidgets(14));
      // The last record specifically: a `take(7)` bug is invisible to a count
      // that a lazily-built list could have satisfied by other means.
      expect(find.textContaining('2013 TX68'), findsOneWidget);
    });

    testWidgets('prints name, species, power, distance, and flyby tag', (
      tester,
    ) async {
      // Spec 01 §5's field list, pinned on one real record end to end —
      // `2011 EW` goes in as a 302 m rock 12.4 Moons out and has to come back
      // as Mango the Elephant at power ⭐ 82. Every value here is one the
      // AnimalSystem's own suite pins against the prototype, so this asserts
      // the screen *asks the right questions*, not that the maths is right.
      await tester.pumpWidget(_app(Future<AsteroidFeed>.value(_sampleSky())));
      await tester.pump();

      expect(find.text('Mango the Elephant · today'), findsOneWidget);
      expect(
        find.text(
          'stadium-sized · 302 m wide · comes 12× Moon · '
          'power ⭐ 82 · 👋 close flyby\n'
          '2011 EW · sample',
        ),
        findsOneWidget,
      );
      expect(find.text('🐘'), findsWidgets);
    });

    testWidgets('marks the seven visiting today, and only those', (
      tester,
    ) async {
      // The two rules differ offline and only offline (plan decision 10:
      // fourteen asteroids, `todayList` the first seven rather than a date
      // filter), so this is the one place the difference is visible. Both
      // halves are asserted: a marker on every row would pass the first
      // expectation alone.
      _tallEnoughForFourteenRows(tester);

      await tester.pumpWidget(_app(Future<AsteroidFeed>.value(_sampleSky())));
      await tester.pump();

      expect(find.textContaining(' · today'), findsNWidgets(7));
      // Index 7 — the first record outside `todayList`, and so the row whose
      // title must be bare. Its name comes from the AnimalSystem's own pinned
      // prototype capture, not from a guess: the first draft of this line
      // invented "Suki the Dino", and Suki is in fact Apophis, an Elephant, and
      // *is* visiting today — a wrong expectation that would have read as a
      // marker bug.
      expect(find.text('Teddy the Elephant'), findsOneWidget);
    });

    testWidgets('captions the sky with its range and provenance', (
      tester,
    ) async {
      await tester.pumpWidget(_app(Future<AsteroidFeed>.value(_sampleSky())));
      await tester.pump();

      expect(
        find.text('14 animals · 7 visiting · sample data · sample'),
        findsOneWidget,
      );
    });

    testWidgets('captions a real window with the days it is actually for', (
      tester,
    ) async {
      // `provenance` is printed raw rather than translated, deliberately: the
      // kid-facing wording for the three cases is an open decision on the
      // home-overlay item, and a guess made here would be a second place for it
      // to be decided. What this pins is that the caption comes from the feed
      // at all — `sample data` is a constant, so the test above it would pass
      // against a hard-coded string.
      await tester.pumpWidget(_app(Future<AsteroidFeed>.value(_liveSky())));
      await tester.pump();

      expect(
        find.text('2 animals · 1 visiting · 2026-07-14 → 2026-07-16 · today'),
        findsOneWidget,
      );
    });

    testWidgets('reports a broken loadData loudly rather than hiding it', (
      tester,
    ) async {
      // `loadData()` promises never to throw — every failure resolves to the
      // sample sky (spec 01 §3). Reaching this branch means that promise broke,
      // and the sample set is exactly what a well-meaning catch here would show
      // instead: the bug would then be invisible to the one screen built to
      // catch it.
      final Completer<AsteroidFeed> broken = Completer<AsteroidFeed>();
      await tester.pumpWidget(_app(broken.future));

      broken.completeError(StateError('the box is on fire'));
      await tester.pump();

      expect(find.textContaining('promises never to do'), findsOneWidget);
      expect(find.byType(ListTile), findsNothing);
    });
  });
}

/// The sample sky, exactly as an offline cold launch produces it: fourteen
/// records with the first seven visiting (plan decision 10).
AsteroidFeed _sampleSky() => AsteroidFeed.fallback();

/// A real window ending today: two rocks, one of them visiting — the ordinary
/// live shape, where `todayList` is a strict subset rather than the whole sky.
AsteroidFeed _liveSky() {
  final List<Asteroid> asteroids = <String>['2011 EW', '2020 SW']
      .map(
        (String name) => Asteroid(
          name: name,
          diaMax: 302,
          diaMin: 135,
          hazardous: false,
          missLunar: 12.4,
          missKm: 4766560,
          velKps: 11.2,
          mag: 20.1,
          jpl: 'https://ssd.jpl.nasa.gov/tools/sbdb_lookup.html',
          date: '2026-07-16',
        ),
      )
      .toList(growable: false);

  return AsteroidFeed(
    asteroids: asteroids,
    todayList: asteroids.take(1).toList(growable: false),
    feedRange: '2026-07-14 → 2026-07-16',
    provenance: FeedProvenance.today,
  );
}

/// Fourteen three-line rows do not fit the 800×600 default, and `ListView`
/// builds lazily — so on the default surface a count assertion would be
/// measuring the viewport rather than the sky.
void _tallEnoughForFourteenRows(WidgetTester tester) {
  tester.view.physicalSize = const Size(600, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Widget _app(Future<AsteroidFeed> feed) {
  return ProviderScope(
    // The override list is left to inference: Riverpod 3 does not export the
    // `Override` type, so there is no name to annotate it with.
    overrides: [asteroidFeedProvider.overrideWith((Ref ref) => feed)],
    child: const MaterialApp(home: DebugAnimalListScreen()),
  );
}

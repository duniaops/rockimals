import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/core/mascot/rusty.dart';
import 'package:rockimals/data/models/asteroid.dart';
import 'package:rockimals/data/models/asteroid_feed.dart';
import 'package:rockimals/features/data/providers.dart';
import 'package:rockimals/features/loading/loading_screen.dart';
import 'package:rockimals/features/shell/app_shell.dart';
import 'package:rockimals/features/title/title_screen.dart';

import '../../support/memory_store.dart';

/// The title screen's two jobs: be the app's front door, and get out of the way
/// (`specs/06-title-polish-safety.md:16, 42`). Everything else here guards the
/// three ways a splash screen can quietly cost something — a load that no longer
/// starts at launch, motion a Calm-motion setting no longer reaches, and a name
/// a screen reader now spells out one letter at a time.
///
/// **Nothing in this file calls `pumpAndSettle`.** The starfield twinkles
/// forever, so a frame is always scheduled and settling never happens; the route
/// transitions are stepped past with an explicit `pump(Duration)` instead, the
/// same way `loading_screen_test.dart` handles its spinner.
void main() {
  group('getting in', () {
    testWidgets('Play reaches the radar', (tester) async {
      // The item's Done-when, end to end: the title, a tap, and the shell. The
      // sky is already resolved because that is the case a warmed feed produces
      // — see the load test below, which is what makes it the normal one.
      await tester.pumpWidget(_app(feed: Future<AsteroidFeed>.value(_sky())));

      expect(find.byType(TitleScreen), findsOneWidget);

      await tester.tap(find.byType(TitleScreen));
      await _settleRoute(tester);

      expect(find.byType(AppShell), findsOneWidget);
      expect(find.byType(TitleScreen), findsNothing);
    });

    testWidgets('the Play button starts the app on its own', (tester) async {
      // **A pointer tap cannot answer this.** The screen-wide "tap anywhere"
      // detector sits under the button and would navigate regardless, so a Play
      // button wired to nothing passes any test that taps it and looks at the
      // result. An *assistive* tap can: it is dispatched to the semantics node
      // that owns it, so this only reaches the gate if `_PlayButton` handles its
      // own activation — which is also the path a child using VoiceOver takes.
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(_app());

      tester.semantics.tap(find.semantics.byLabel('Play'));
      await _settleRoute(tester);

      expect(find.byType(LoadingGate), findsOneWidget);
      handle.dispose();
    });

    testWidgets('and a tap anywhere does too', (tester) async {
      // `title.html:132` promises it in so many words, so the promise is the
      // test: a corner with nothing drawn in it still starts the app.
      await tester.pumpWidget(_app());

      await tester.tapAt(const Offset(4, 4));
      await _settleRoute(tester);

      expect(find.byType(LoadingGate), findsOneWidget);
      expect(find.byType(TitleScreen), findsNothing);
    });

    testWidgets('leaves nothing behind to come back to', (tester) async {
      // `pushReplacement`, not `push`. A splash a child can swipe back to is not
      // a splash — and worse, the back gesture would land them on a screen whose
      // only affordance is to load the app they are already in.
      await tester.pumpWidget(_app());

      await tester.tap(find.byType(TitleScreen));
      await _settleRoute(tester);

      final NavigatorState navigator = tester.state(find.byType(Navigator));
      expect(navigator.canPop(), isFalse);
    });
  });

  group('the sky', () {
    testWidgets('starts loading before anyone taps anything', (tester) async {
      // **The reason a splash in front of a network gate is not a delay.**
      // `LoadingGate` is what used to start the feed, by watching it; putting a
      // screen in front of it moves that first read to whenever the child taps,
      // unless the title asks for the sky itself. Without this test the app
      // would still work and every launch would be a few seconds slower, with
      // nothing anywhere reporting it.
      bool asked = false;
      await tester.pumpWidget(
        _app(
          feed: Completer<AsteroidFeed>().future,
          onFeedRead: () => asked = true,
        ),
      );

      expect(asked, isTrue);
    });

    testWidgets('and the child waits on the gate if it has not landed', (
      tester,
    ) async {
      // The other half: warming the feed must not *replace* the gate. A slow
      // network still has to reach "Contacting NASA…" rather than a blank shell.
      await tester.pumpWidget(_app(feed: Completer<AsteroidFeed>().future));

      await tester.tap(find.byType(TitleScreen));
      await _settleRoute(tester);

      expect(find.text('Contacting NASA…'), findsOneWidget);
      expect(find.byType(AppShell, skipOffstage: false), findsNothing);
    });
  });

  group('Calm motion', () {
    testWidgets('Rusty bobs, and comes back down', (tester) async {
      // `.float` — 13px up over 1.8s and back, forever (`title.html:43-44`). A
      // controller built but never started renders a perfectly correct fox that
      // never moves, and nothing else in this file would notice.
      await tester.pumpWidget(_app());

      await tester.pump(const Duration(milliseconds: 1800));
      expect(_bob(tester).dy, closeTo(-13 / 206, 0.002));

      // Back to rest: the bob reverses rather than saturating at the top, which
      // is what `repeat(reverse: true)` buys and what a plain `repeat()` would
      // get wrong — Rusty would snap to the floor every 1.8s.
      await tester.pump(const Duration(milliseconds: 1800));
      expect(_bob(tester).dy, closeTo(0, 0.002));
    });

    testWidgets('and settles when Calm motion is on', (tester) async {
      // The setting's whole point on this screen: this is the app's only
      // *infinite travel* animation outside the badge popup
      // (`specs/06-title-polish-safety.md:25`).
      await tester.pumpWidget(_app(reducedMotion: true));

      await tester.pump(const Duration(milliseconds: 1800));

      expect(_bob(tester).dy, 0);
    });

    testWidgets('but the stars keep twinkling', (tester) async {
      // **The half that stops a later agent from "finishing the job".** The
      // plan's Calm-motion item draws the line at travel across the screen, and
      // deliberately leaves Earth's glow breathing; the starfield is the same
      // kind of motion — an opacity oscillating in place, no movement at all.
      // A title screen frozen into a still photograph reads as a crash on the
      // one screen a child sees before anything else works.
      await tester.pumpWidget(_app(reducedMotion: true));

      final double before = _twinkle(tester);
      await tester.pump(const Duration(milliseconds: 1500));

      expect(_twinkle(tester), isNot(before));
    });
  });

  group('what it says', () {
    testWidgets('introduces the app by name, not by spelling it', (
      tester,
    ) async {
      // The wordmark is three widgets — `R`, an asteroid, `CKIMALS` — so a
      // screen reader walking it unaided says the app's name wrong at the first
      // moment it could say anything at all.
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(_app());

      expect(find.bySemanticsLabel('Rockimals'), findsOneWidget);
      expect(find.bySemanticsLabel('CKIMALS'), findsNothing);
      // And Play is a button rather than a decorated label, with the play
      // triangle kept out of what gets read aloud.
      expect(find.bySemanticsLabel('Play'), findsOneWidget);

      handle.dispose();
    });

    testWidgets('carries the prototype\'s copy and the NASA attribution', (
      tester,
    ) async {
      // Verbatim from `title.html:72, 127, 131-133`. The last line is also the
      // attribution `specs/06-title-polish-safety.md:60` requires before
      // release, which is why it is pinned here rather than left as decoration.
      await tester.pumpWidget(_app());

      expect(find.text('SPACE · ANIMALS'), findsOneWidget);
      expect(
        find.text('Meet your fuzzy little space-rock friends! 🦊'),
        findsOneWidget,
      );
      expect(find.text('▶ Play'), findsOneWidget);
      expect(find.text('tap anywhere to start'), findsOneWidget);
      expect(find.text('🚀 powered by real NASA space data'), findsOneWidget);
    });

    testWidgets('shows Rusty', (tester) async {
      await tester.pumpWidget(_app());

      expect(find.byType(Rusty), findsOneWidget);
    });

    testWidgets('fits a small phone at a large text scale', (tester) async {
      // **A rendered frame caught this one.** The wordmark is ~300px wide at
      // 46px, which fits the prototype's 356px screen with its 26px gutters and
      // ran off the edge of a 390dp phone the first time it was drawn — the
      // failure mode being the app's own name clipped mid-word on the first
      // screen a child ever sees. Two `FittedBox`es answer it, and this is what
      // keeps them: 320×568 is the smallest phone worth supporting, and 2×
      // is a text scale a grown-up who needs one really does set.
      tester.view.physicalSize = const Size(320 * 2, 568 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_app(textScale: 2));

      // An overflow is reported as an exception in debug builds, which the test
      // framework catches rather than throws — so it has to be asked for.
      expect(tester.takeException(), isNull);
    });

    testWidgets('gives Play a target a small finger can hit', (tester) async {
      // `specs/06-title-polish-safety.md:21` — large, well-spaced targets. The
      // accessibility audit item owns the sweep across every screen; this pins
      // the one control on the one screen every child touches first, so a later
      // tightening of the padding cannot quietly take it below the bar.
      await tester.pumpWidget(_app());

      final Size play = tester.getSize(
        find.ancestor(
          of: find.text('▶ Play'),
          matching: find.byType(Container),
        ),
      );

      expect(play.height, greaterThanOrEqualTo(48));
      expect(play.width, greaterThanOrEqualTo(48));
    });
  });
}

/// Rusty's current bob offset, as a fraction of his height.
Offset _bob(WidgetTester tester) => tester
    .widget<SlideTransition>(
      // Matched by its child rather than by type, because [Scaffold] builds
      // `SlideTransition`s of its own for the bottom sheet and snack bar this
      // screen does not have — so `find.byType` here fails with "Too many
      // elements", which reads as a bug in the bob rather than as Flutter's own
      // furniture.
      find.byWidgetPredicate(
        (Widget w) => w is SlideTransition && w.child is Rusty,
      ),
    )
    .position
    .value;

/// The starfield layer's current opacity.
///
/// Matched by its painted child rather than by type: route transitions build
/// [FadeTransition]s of their own, and the starfield is the only one in this
/// tree whose child is a bare [CustomPaint].
double _twinkle(WidgetTester tester) => tester
    .widget<FadeTransition>(
      find.byWidgetPredicate(
        (Widget w) => w is FadeTransition && w.child is CustomPaint,
      ),
    )
    .opacity
    .value;

/// Steps past a route transition without waiting for the tree to go quiet —
/// which it never does, because the stars are still twinkling behind it.
Future<void> _settleRoute(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

/// The title screen under a scope that keeps the suite off the network and off
/// a Hive box.
///
/// [feed] defaults to a future that never completes: the title reads the feed at
/// mount ([TitleScreen]'s own docs), so a test that overrode nothing would build
/// a live [Dio] and leave the repository's ten-second ceiling pending at
/// teardown. A pending future is safe *here*, unlike under the shell, because
/// nothing on this screen renders the value.
///
/// [onFeedRead] fires when the provider is first initialised, which is the only
/// way to ask whether the load started without also asking what it returned.
Widget _app({
  Future<AsteroidFeed>? feed,
  VoidCallback? onFeedRead,
  bool? reducedMotion,
  double textScale = 1,
}) {
  return ProviderScope(
    // The override list is left to inference: Riverpod 3 does not export the
    // `Override` type, so there is no name to annotate it with.
    overrides: [
      asteroidFeedProvider.overrideWith((Ref ref) {
        onFeedRead?.call();
        return feed ?? Completer<AsteroidFeed>().future;
      }),
      // Calm motion resolves through the store, and so does the shell behind the
      // gate once the sky lands.
      storeProvider.overrideWithValue(
        MemoryStore(reducedMotion: reducedMotion),
      ),
      dayStreakProvider.overrideWithValue(0),
    ],
    // The text scale is applied through `builder`, i.e. *below* the app.
    // `WidgetsApp` inserts its own `MediaQuery.fromView` unconditionally, so a
    // `MediaQuery` wrapped around `MaterialApp` is silently discarded and a test
    // that set the scale there would be testing 1× while claiming to test 2×.
    child: MaterialApp(
      builder: (BuildContext context, Widget? child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: const TitleScreen(),
    ),
  );
}

/// One rock is enough — nothing on the title or the gate reads the list.
AsteroidFeed _sky() {
  const List<Asteroid> asteroids = <Asteroid>[
    Asteroid(
      name: '2011 EW',
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
  ];

  return AsteroidFeed(
    asteroids: asteroids,
    todayList: asteroids,
    feedRange: '2026-07-14 → 2026-07-16',
    provenance: FeedProvenance.today,
  );
}

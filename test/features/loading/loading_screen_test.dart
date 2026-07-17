import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/data/models/asteroid.dart';
import 'package:rockimals/data/models/asteroid_feed.dart';
import 'package:rockimals/features/data/providers.dart';
import 'package:rockimals/features/loading/loading_screen.dart';
import 'package:rockimals/features/shell/app_shell.dart';

/// The gate is a *routing* decision — which of two things the app is — so what
/// these pin is the two halves of the item's Done-when: it shows on a cold
/// launch, and it goes away when there is a sky, whichever kind of sky that is.
///
/// The feed provider is overridden directly rather than a repository faked
/// underneath it, matching `app_shell_test.dart` and the debug screen's suite:
/// `providers_test.dart` owns the wiring below this point, and a real
/// repository would drag a clock, a window, and a Dio into a test about which
/// widget is on screen.
void main() {
  group('LoadingGate', () {
    testWidgets('shows "Contacting NASA…" while the sky is on its way', (
      tester,
    ) async {
      // The state a cold launch is in for as long as NASA takes to answer —
      // up to the repository's ten-second ceiling.
      await tester.pumpWidget(_app(Completer<AsteroidFeed>().future));

      expect(find.text('Contacting NASA…'), findsOneWidget);
      expect(find.byType(LoadingScreen), findsOneWidget);
    });

    testWidgets('and says it in --muted, not in body ink', (tester) async {
      // Added when the palette was hoisted, because a mutation proved the gap:
      // swapping this line's colour from `--muted` to `--ink` passed the entire
      // suite. Nothing else pins it, and the two are not interchangeable —
      // `--muted` is the prototype's secondary text and `--ink` is body copy, so
      // the difference is whether the first words a child ever reads are a calm
      // aside or the loudest thing on the screen. It is also the colour most at
      // risk of being lost by accident: a `Text` with no explicit style inherits
      // the theme, so deleting one line here would swap it silently.
      await tester.pumpWidget(_app(Completer<AsteroidFeed>().future));

      final Text line = tester.widget<Text>(find.text('Contacting NASA…'));
      expect(line.style?.color, _mutedColour);
    });

    testWidgets('keeps the whole app behind it, nav included', (tester) async {
      // The point of the placement, and the half a per-tab spinner would miss.
      // `.loading` covers the entire phone at `z-index:50` (`index.html:165`)
      // and the prototype only calls `switchTab("today")` *after* the await
      // (`index.html:1143-1145`) — so there is no sky yet and nothing to tap
      // towards. `skipOffstage: false` because the failure this guards is a
      // shell mounted under the overlay rather than merely hidden by it: its
      // four tabs would then all be building against a feed that has not
      // landed.
      await tester.pumpWidget(_app(Completer<AsteroidFeed>().future));

      expect(find.byType(AppShell, skipOffstage: false), findsNothing);
      expect(find.text('Radar', skipOffstage: false), findsNothing);
    });

    testWidgets('dismisses onto the shell once the sky lands', (tester) async {
      final Completer<AsteroidFeed> sky = Completer<AsteroidFeed>();
      await tester.pumpWidget(_app(sky.future));

      sky.complete(_liveSky());
      await tester.pump();

      // Both halves: the shell arrives *and* the overlay goes. A gate that
      // stacked the shell under a spinner it never removed would pass the first
      // line alone, and that is what the prototype's `display:none` does — it
      // is a dismissal, not a reveal.
      expect(find.byType(AppShell), findsOneWidget);
      expect(find.byType(LoadingScreen), findsNothing);
      expect(find.text('Contacting NASA…'), findsNothing);
    });

    testWidgets('dismisses on the sample sky too, not just a real one', (
      tester,
    ) async {
      // Spec 01 §3 and the airplane-mode criterion, at the one layer that could
      // still break them after the repository has done its job. Offline,
      // `loadData()` answers with the bundled fourteen — a perfectly good sky
      // that simply is not NASA's — and a gate that waited for
      // `usingFallback == false` would hold the spinner until the ceiling and
      // then hold it forever. Nothing else in the suite would notice: the test
      // above resolves with a live feed and would stay green.
      await tester.pumpWidget(_app(Future<AsteroidFeed>.value(_sampleSky())));
      await tester.pump();

      expect(find.byType(AppShell), findsOneWidget);
      expect(find.byType(LoadingScreen), findsNothing);
    });

    testWidgets('reports a broken loadData loudly rather than spinning on', (
      tester,
    ) async {
      // `loadData()` promises never to throw (spec 01 §3), so this is
      // unreachable and reaching it means the promise broke. The failure this
      // guards is the well-meaning alternative: leaving the child on the
      // spinner, where the bug is reported to nobody and the app simply never
      // starts.
      final Completer<AsteroidFeed> broken = Completer<AsteroidFeed>();
      await tester.pumpWidget(_app(broken.future));

      broken.completeError(StateError('the box is on fire'));
      await tester.pump();

      expect(find.textContaining('promises never to do'), findsOneWidget);
      expect(find.byType(LoadingScreen), findsNothing);
      expect(find.byType(AppShell), findsNothing);
    });
  });

  group('LoadingScreen', () {
    testWidgets('turns the spinner, and keeps turning it', (tester) async {
      // `animation:spin 1s linear infinite` (`index.html:166`). A controller
      // built but never `repeat()`-ed renders a perfectly correct ring that
      // never moves — which looks like a hung app on the one screen whose only
      // job is to say "still working". Nothing else here would catch it: every
      // other assertion in this file is about a static tree.
      await tester.pumpWidget(_app(Completer<AsteroidFeed>().future));

      // A quarter turn in, and then three quarters more. Two samples rather
      // than one because a single non-zero reading is also what a controller
      // that ran once and stopped would give.
      await tester.pump(const Duration(milliseconds: 250));
      expect(_turns(tester), closeTo(0.25, 0.001));

      await tester.pump(const Duration(milliseconds: 750));
      // Back to the top: the loop restarts rather than saturating at 1.
      expect(_turns(tester), closeTo(0, 0.001));
    });

    testWidgets('paints a ring with its top quarter lit', (tester) async {
      // `.spin` is a 40px circle with a translucent white border and
      // `border-top-color:var(--accent)` (`index.html:166`) — so the port is
      // *geometry*, and none of it can be verified on a device yet (no Xcode,
      // no Android SDK). The rest of this file would pass just as happily for a
      // filled orange disc, an empty box, or a ring lit at the bottom.
      //
      // So the pixels are read instead of eyeballed, in the spirit of the
      // technique the AnimalSystem items used against the prototype. The probes
      // are placed relative to the measured rect rather than at hard-coded
      // coordinates, and each sits on the centre-line of the stroke, where
      // antialiasing has nothing to blend.
      await tester.pumpWidget(
        _app(Completer<AsteroidFeed>().future, capture: true),
      );
      await tester.pump();

      final Rect ring = tester.getRect(_spinner);
      final _Pixels px = await _paintedPixels(tester);

      expect(ring.size, const Size(40, 40));
      // Twelve o'clock: `border-top-color`, i.e. `--accent`, opaque.
      expect(px.at(ring.center.dx, ring.top + 2), const Color(0xFFE8571F));
      // Everywhere else on the ring: the track. `rgba(255,255,255,.15)` over
      // the `#070F1F` background composites to exactly this — 0.15×255 +
      // 0.85×0x07 = 44 (0x2C), and likewise 0x33 and 0x40. A head drawn at the
      // wrong angle shows up here rather than above.
      const Color track = Color(0xFF2C3340);
      expect(px.at(ring.center.dx, ring.bottom - 2), track, reason: '6 o’clock');
      expect(px.at(ring.left + 2, ring.center.dy), track, reason: '9 o’clock');
      expect(px.at(ring.right - 2, ring.center.dy), track, reason: '3 o’clock');
      // A ring, not a disc — and one that stays inside its 40px box rather than
      // being stroked 2px proud of it and clipped.
      expect(px.at(ring.center.dx, ring.center.dy), _backgroundColour);
      expect(px.at(ring.left, ring.top), _backgroundColour);
    });
  });
}

/// `#070f1f` (`index.html:165`) — restated rather than imported, because a test
/// that read the same constant the widget reads would pass for any value.
const Color _backgroundColour = Color(0xFF070F1F);

/// `--muted` `#93a8ca` (`index.html:10`) — restated for the same reason, and it
/// matters more now that the widget reads it from the shared `Palette`:
/// importing `Palette.muted` here would assert only that a colour equals itself.
/// `palette_test.dart` is what pins `Palette.muted` to the prototype's digits.
const Color _mutedColour = Color(0xFF93A8CA);

/// The spinner's painted ring, found by the size the prototype gives it.
final Finder _spinner = find.byWidgetPredicate(
  (Widget w) => w is CustomPaint && w.size == const Size(40, 40),
);

/// The rendered frame, read back from the engine.
///
/// This is a real rasterisation — `flutter_tester` runs the same painting
/// pipeline a phone does — so it is the closest this project can currently get
/// to looking at the screen. `toImage` is asynchronous and must go through
/// [WidgetTester.runAsync] for the reason `app_test.dart` documents at length: a
/// `testWidgets` body runs in a fake-async zone where a future waiting on the
/// real engine never completes.
Future<_Pixels> _paintedPixels(WidgetTester tester) async {
  final RenderRepaintBoundary boundary = tester.renderObject(
    find.byType(RepaintBoundary).first,
  );
  final ui.Image image = (await tester.runAsync<ui.Image>(boundary.toImage))!;
  final ByteData data = (await tester.runAsync<ByteData?>(image.toByteData))!;
  return _Pixels(data, image.width);
}

class _Pixels {
  const _Pixels(this._rgba, this._width);

  final ByteData _rgba;
  final int _width;

  Color at(double x, double y) {
    final int i = ((y.round() * _width) + x.round()) * 4;
    return Color.fromARGB(
      _rgba.getUint8(i + 3),
      _rgba.getUint8(i),
      _rgba.getUint8(i + 1),
      _rgba.getUint8(i + 2),
    );
  }
}

/// How far round the spinner is, in turns.
///
/// Matched by its painted child rather than by type, because [Scaffold] builds
/// a [RotationTransition] of its own for the floating action button this screen
/// does not have — so a bare `find.byType` here fails with "Too many elements",
/// which reads as a bug in the spinner rather than as Flutter's own furniture.
double _turns(WidgetTester tester) => tester
    .widget<RotationTransition>(
      find.ancestor(of: _spinner, matching: find.byType(RotationTransition)),
    )
    .turns
    .value;

/// The sample sky, exactly as an offline cold launch produces it (plan
/// decision 10: fourteen records, the first seven visiting).
AsteroidFeed _sampleSky() => AsteroidFeed.fallback();

/// An ordinary real window ending today — one rock is enough, since nothing
/// here reads the list.
AsteroidFeed _liveSky() {
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

/// [capture] wraps the app in a [RepaintBoundary] so the frame can be read back
/// as an image. Off by default: it is scaffolding for the pixel test alone, and
/// the app itself has no such boundary.
Widget _app(Future<AsteroidFeed> feed, {bool capture = false}) {
  const Widget gate = LoadingGate();
  return ProviderScope(
    // The override list is left to inference: Riverpod 3 does not export the
    // `Override` type, so there is no name to annotate it with.
    overrides: [asteroidFeedProvider.overrideWith((Ref ref) => feed)],
    child: MaterialApp(
      home: capture ? const RepaintBoundary(child: gate) : gate,
    ),
  );
}

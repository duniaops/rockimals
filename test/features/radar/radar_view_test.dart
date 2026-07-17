import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/data/models/asteroid.dart';
import 'package:rockimals/data/models/asteroid_feed.dart';
import 'package:rockimals/features/data/providers.dart';
import 'package:rockimals/features/radar/radar_view.dart';

/// The wiring between the sky and the canvas: which list the radar is scaled
/// to, and that something is driving its clock.
///
/// The feed provider is overridden directly rather than a repository faked
/// underneath it, matching every other widget suite here — `providers_test.dart`
/// owns the wiring below this point.
void main() {
  testWidgets('scales the field to the whole sky, not just today', (
    tester,
  ) async {
    // **Plan decision 9, and the one mistake on this screen that would look
    // fine.** `Radar.data = asteroids.slice()` (`index.html:637`) — the radar
    // draws the whole window, and `MAXLD` comes from that same list. A radar
    // scaled to `todayList` would size its rings for a handful of the animals
    // it is drawing, so the far ones would sit outside the outer ring with no
    // ring to read them against. Nothing about the screen would look broken;
    // the distances would just be wrong.
    //
    // The sky here separates the two: today's animals are all close, and the
    // one 40× animal is in the window but not in today's list. Scaled to
    // `todayList` the field would stop at 8.4 and show three rings; scaled to
    // the full list it reaches 42 and shows five.
    await _mount(tester, _skyWhereTodayIsCloser());

    expect(
      _painter(tester),
      paintsExactlyCountTimes(#drawPath, 5),
      reason: 'maxLd 42 reaches 1×, 2×, 5×, 10× and 20×',
    );
  });

  testWidgets('keeps drawing after the first frame', (tester) async {
    // The Ticker is the whole reason this widget exists rather than the painter
    // being mounted directly. Earth's glow is the only thing moving today, so
    // it is what proves the loop is running: a radar painted once and left
    // there would hold the same radius forever, and every other assertion in
    // this file would still pass.
    await _mount(tester, _sky(<double>[3]));
    expect(_painter(tester), _glowRadius(closeTo(27.5, 0.001)));

    await tester.pump(const Duration(milliseconds: 471));
    expect(_painter(tester), _glowRadius(closeTo(29, 0.001)));

    await tester.pump(const Duration(milliseconds: 942));
    expect(_painter(tester), _glowRadius(closeTo(26, 0.001)));
  });

  testWidgets('stops its ticker when it leaves the tree', (tester) async {
    // A Ticker outliving its State is a hard error in debug and a leak in
    // release. Worth a test of its own because the failure surfaces at the next
    // frame after the radar is gone — nowhere near the cause.
    await _mount(tester, _sky(<double>[3]));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
  });
}

Future<void> _mount(WidgetTester tester, AsteroidFeed feed) async {
  tester.view
    ..physicalSize = const Size(390, 700)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [asteroidFeedProvider.overrideWith((Ref ref) => feed)],
      child: const MaterialApp(home: RadarView()),
    ),
  );
  // The override resolves a frame later; the radar only ever builds behind the
  // loading gate, so `requireValue` would throw before this.
  await tester.pump();
}

RenderBox _painter(WidgetTester tester) =>
    tester.renderObject<RenderBox>(find.byType(CustomPaint).last);

/// Matches a `drawCircle` whose radius satisfies [radius] — Earth's glow, the
/// one thing on this layer that moves.
PaintPattern _glowRadius(Matcher radius) =>
    paints..something((Symbol method, List<dynamic> arguments) =>
        method == #drawCircle &&
        radius.matches(arguments[1], <dynamic, dynamic>{}));

/// A sky whose window reaches 40× Moon but whose *today* list does not get past
/// 2×. The two lists disagree by design; see the test that reads it.
AsteroidFeed _skyWhereTodayIsCloser() {
  final List<Asteroid> today = _rocks(<double>[0.8, 2]);
  return AsteroidFeed(
    asteroids: <Asteroid>[...today, ..._rocks(<double>[40])],
    todayList: today,
    feedRange: '2026-07-15 → 2026-07-17',
    provenance: FeedProvenance.today,
  );
}

AsteroidFeed _sky(List<double> missLunar) {
  final List<Asteroid> rocks = _rocks(missLunar);
  return AsteroidFeed(
    asteroids: rocks,
    todayList: rocks,
    feedRange: '2026-07-15 → 2026-07-17',
    provenance: FeedProvenance.today,
  );
}

/// Nothing but `missLunar` reaches the radar's base layer, so the rest is
/// plausible filler rather than a real capture.
List<Asteroid> _rocks(List<double> missLunar) => <Asteroid>[
  for (final double ld in missLunar)
    Asteroid(
      name: '2026 LD$ld',
      diaMax: 100,
      diaMin: 50,
      hazardous: false,
      missLunar: ld,
      missKm: ld * 384400,
      velKps: 12,
      mag: 22,
      jpl: 'https://ssd.jpl.nasa.gov/tools/sbdb_lookup.html',
      date: '2026-07-17',
    ),
];

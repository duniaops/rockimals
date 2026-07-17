import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/features/radar/radar_painter.dart';

/// What the radar's base layer actually puts on the screen.
///
/// Split by what each thing can honestly be checked with. The dash pattern is
/// path geometry, so it is measured. Earth is a stack of circles, so the
/// recorded draw calls are asserted. And the whole frame is rasterised and
/// probed, because everything above would pass just as happily for a canvas
/// that painted all of it off the bottom of the screen — the technique
/// `loading_screen_test.dart` established, for the same reason: there is no
/// device here to look at (no Xcode, no Android SDK — see the plan's
/// human-gated item).
void main() {
  group('dashedCircle', () {
    test('lays dashes along the circumference, not around the angle', () {
      // The distinction the port hinges on. `setLineDash([3, 5])` measures in
      // pixels of arc, so doubling the radius gives twice as many dashes of the
      // same length — not the same dashes stretched. Getting this backwards
      // looks fine on one ring and wrong across six.
      final small = dashedCircle(Offset.zero, 50, on: 3, off: 5).computeMetrics().toList();
      final big = dashedCircle(Offset.zero, 100, on: 3, off: 5).computeMetrics().toList();

      expect(small.length, closeTo(2 * math.pi * 50 / 8, 1));
      expect(big.length, closeTo(2 * math.pi * 100 / 8, 1));

      // All but the last, which the loop cuts short — its own test, below.
      for (final ui.PathMetric dash in small.take(small.length - 1)) {
        expect(dash.length, closeTo(3, 0.01));
      }
      for (final ui.PathMetric dash in big.take(big.length - 1)) {
        expect(dash.length, closeTo(3, 0.01));
      }
    });

    test('honours the gap as well as the dash', () {
      // A pattern of [2, 7] is a period of 9, not of 2.
      final dashes = dashedCircle(Offset.zero, 90, on: 2, off: 7).computeMetrics().toList();

      expect(dashes.length, closeTo(2 * math.pi * 90 / 9, 1));
      expect(dashes.first.length, closeTo(2, 0.01));
    });

    test('closes the loop exactly once, without overlapping itself', () {
      // The one deliberate deviation from `index.html:829`, whose `arc(…, 0, 7)`
      // sweeps 0.72 radians past a full turn. On a solid stroke that overshoot
      // is invisible; under a dash pattern it lays a second run of dashes over
      // the first at a different phase, brightening an arc of every ring. So
      // what is ported is the circle that `0, 7` means.
      //
      // Measured as: total dash length is the circumference's 3/8 (the pattern
      // is 3 on, 5 off), not 7/2π of it.
      const double radius = 80;
      final dashes = dashedCircle(Offset.zero, radius, on: 3, off: 5);
      final double inked = dashes
          .computeMetrics()
          .fold(0.0, (double sum, ui.PathMetric m) => sum + m.length);

      expect(inked, closeTo(2 * math.pi * radius * 3 / 8, 1.5));
    });

    test('cuts the last dash at the top of the loop rather than wrapping it', () {
      // Canvas restarts a dash pattern per sub-path and simply stops at the
      // path's end, so the final dash is whatever is left. 2π×50 = 314.16, and
      // 314.16 / 8 = 39.27 periods — the last one has 0.27×8 = 2.16px of room
      // for a 3px dash.
      final dashes = dashedCircle(Offset.zero, 50, on: 3, off: 5).computeMetrics().toList();

      expect(dashes.last.length, closeTo(2.16, 0.05));
      expect(dashes.last.length, lessThan(3));
    });
  });

  group('ringLabelText', () {
    test('names the Moon, then counts against it', () {
      // `CLAUDE.md:66`: every distance in this app is a Moon-distance and
      // nothing else. There is no unit to learn here and no big number to be
      // scared of — "20× Moon" is twenty times as far as the thing in the sky
      // tonight.
      expect(ringLabelText(1), '🌙 Moon');
      expect(ringLabelText(2), '2× Moon');
      expect(ringLabelText(50), '50× Moon');
    });

    test('says nothing an astronomer would say', () {
      // The guardrail, pinned so no future edit reintroduces "LD", "lunar
      // distances", or a raw kilometre count onto the one screen every child
      // opens the app to.
      for (final int ld in <int>[1, 2, 5, 10, 20, 50]) {
        final String label = ringLabelText(ld).toLowerCase();
        expect(label, isNot(contains('lunar')));
        expect(label, isNot(contains('ld')));
        expect(label, isNot(contains('km')));
      }
    });
  });

  group('RadarPainter', () {
    testWidgets('draws space, then the rings, then Earth on top', (tester) async {
      // `index.html:870` — Earth is drawn last because it is the smallest and
      // most important object on the screen, so nothing is allowed to cover it.
      // The order *is* the assertion: the space rect, a ring, then the planet.
      await _radar(tester);

      expect(
        _painterOf(tester),
        paints
          ..rect()
          ..path()
          ..circle(x: _centre.dx, y: _centre.dy, radius: 27.5)
          ..circle(x: _centre.dx, y: _centre.dy, radius: 15),
      );
    });

    testWidgets('breathes the glow without moving the planet', (tester) async {
      // The "calm" of `specs/02-live-radar.md:28`, made literal: a ~1.9s breath
      // over three pixels, `26 + pulse*3` where `pulse = (sin(ts/300)+1)/2`
      // (`index.html:820`, `873`). At rest the sine is 0, so the glow starts
      // mid-breath at 27.5 — a quarter period later (471ms) it is at its 29px
      // peak. The planet underneath never moves: it is 15px however far in you
      // are (`index.html:874`).
      await _radar(tester);
      expect(_painterOf(tester), _drawsCircle(radius: closeTo(27.5, 0.001)));

      await tester.pump(const Duration(milliseconds: 471));
      expect(_painterOf(tester), _drawsCircle(radius: closeTo(29, 0.001)));
      // The planet is untouched by the breath — same 15px, same frame.
      expect(_painterOf(tester), _drawsCircle(radius: equals(15.0)));
    });

    testWidgets('paints the rings the sky reaches and no others', (tester) async {
      // One `drawPath` per visible ring — nothing else on this layer draws a
      // path — so the count is the legend's honesty. A sky that only reaches
      // 8.4 Moon-distances must not be drawn with a 50× ring on it.
      await _radar(tester, maxLd: 8.4);
      expect(
        _painterOf(tester),
        paintsExactlyCountTimes(#drawPath, 3),
        reason: 'maxLd 8.4 reaches 1×, 2× and 5×',
      );

      // The default field reaches 60, where every ring the prototype offers
      // exists.
      await _radar(tester);
      expect(_painterOf(tester), paintsExactlyCountTimes(#drawPath, 6));
    });

    testWidgets('strokes the rings dashed, the Moon\'s more solidly than the rest',
        (tester) async {
      // `setLineDash([3,5])` on the 1× and `[2,7]` on the others
      // (`index.html:828`) — the Moon's own ring gets longer dashes and smaller
      // gaps, so it reads as the one real thing out there and the rest as the
      // measuring marks they are.
      //
      // Asserted through the painter rather than on `dashedCircle` alone,
      // because the pure function being right says nothing about this file
      // calling it with the prototype's numbers: solid rings would satisfy
      // every other test here.
      await _radar(tester);

      final List<List<double>> rings = _ringDashes(tester);
      final List<double> radii = _ringRadii(tester);
      expect(rings, hasLength(6));

      for (int i = 0; i < rings.length; i++) {
        // The 1× ring is [3, 5]; every ring beyond it is [2, 7] — shorter
        // marks, wider gaps.
        final double on = i == 0 ? 3 : 2;
        final double period = i == 0 ? 8 : 9;

        // The dash length, on every dash but the last (which the loop cuts).
        expect(
          rings[i].take(rings[i].length - 1),
          everyElement(closeTo(on, 0.01)),
          reason: 'ring $i dash length',
        );
        // And the gap, which only shows up as *how many* dashes fit round the
        // ring — the dash length alone is the same for two different patterns.
        expect(
          rings[i].length,
          closeTo(2 * math.pi * radii[i] / period, 1),
          reason: 'ring $i dash count',
        );
      }
    });

    testWidgets('zooms the rings without zooming Earth', (tester) async {
      // The prototype scales ring radii by `zoom` (`index.html:826`) and strokes
      // Earth at a flat 15px (`index.html:874`). So zooming in spreads the
      // animals out to read them, and the planet they are measured against stays
      // put — a radar that scaled Earth too would swallow the field at 6.5.
      await _radar(tester, zoom: 2);

      expect(_painterOf(tester), _drawsCircle(radius: equals(15.0)));
      // The 1× ring at 78.68 × 2. Measured off the path the painter drew.
      expect(_ringRadii(tester).first, closeTo(78.68 * 2, 0.5));
    });

    testWidgets('renders as an Earth the right size in the right place', (
      tester,
    ) async {
      // The rasterised frame, read back byte by byte. Everything above this
      // asserts what the painter *asked* the canvas for; this is the only thing
      // in the file that knows whether any of it landed.
      await _radar(tester);
      final _Pixels px = await _paintedPixels(tester);

      // The planet: a 15px disc. Lit from up and to the left, so its own centre
      // is not its brightest point — what is pinned is that it is bright, blue,
      // and opaque, at a radius where nothing else on this layer draws.
      final Color surface = px.at(_centre.dx, _centre.dy);
      expect(surface.a, 1.0);
      expect(surface.b, greaterThan(surface.g), reason: 'a blue planet');
      expect(surface.g, greaterThan(surface.r));
      expect(surface.b, greaterThan(0.5), reason: 'daylight, not deep space');

      // Just outside the disc but inside the glow — dimmer than the planet, and
      // still brighter than the space beyond it.
      final Color glow = px.at(_centre.dx, _centre.dy - 20);
      final Color space = px.at(_centre.dx, _centre.dy - 60);
      expect(glow.b, lessThan(surface.b));
      expect(glow.b, greaterThan(space.b));
    });

    testWidgets('leaves the inner floor clear for the closest animals', (
      tester,
    ) async {
      // Why `radiusFor` has a floor at all, verified in pixels rather than
      // argued: at 42px from Earth — where a zero-distance animal is drawn —
      // the planet and its glow are both finished, so an animal chip there
      // lands on clean space rather than on the planet.
      //
      // Probed as a *step*, not as an absolute colour, because space is itself
      // a gradient: two points at different radii differ slightly no matter
      // what Earth does. The glow is a flat disc, so its edge is a hard jump —
      // find the jump, and show there is none at the floor. Straight up from
      // Earth, which is clear all the way to the 1× ring at ~79px.
      await _radar(tester);
      final _Pixels px = await _paintedPixels(tester);

      double blueAt(double up) => px.at(_centre.dx, _centre.dy - up).b;

      // Across the glow's edge (27.5px): the atmosphere is 12% of a near-white
      // blue over near-black space, so this is a large, unmistakable step.
      expect(blueAt(24) - blueAt(32), greaterThan(0.05));
      // Across the inner floor: nothing. Whatever tiny difference is left is
      // the space gradient, which drifts by well under a percent over 4px.
      expect((blueAt(42) - blueAt(46)).abs(), lessThan(0.01));
      expect((blueAt(32) - blueAt(42)).abs(), lessThan(0.01));
    });

    testWidgets('fills the field with space rather than leaving it blank', (
      tester,
    ) async {
      // `.radarwrap`'s own background (`index.html:170`), which the prototype
      // puts behind the canvas rather than on it. Painted here so the radar is
      // one self-contained thing; the corner is where its gradient bottoms out,
      // and `#040a17` is the darkest colour in the app.
      await _radar(tester);
      final _Pixels px = await _paintedPixels(tester);

      expect(px.at(1, _size.height - 2), const Color(0xFF040A17));
      // Brighter towards the middle, which is what makes it a glow.
      expect(px.at(_size.width / 2, _size.height * 0.44 - 60).b,
          greaterThan(px.at(1, _size.height - 2).b));
    });
  });
}

/// A phone-shaped field. The default test view is 800×600, which would clamp
/// this and quietly move every coordinate below, so [_radar] resizes the view
/// rather than wrapping the radar in a box the view can squash.
const Size _size = Size(390, 700);
final Offset _centre = Offset(_size.width / 2, _size.height * 0.46);

/// The painter under test, filling a field of a known size, so every coordinate
/// above is one the painter computed rather than one the test invented.
Future<void> _radar(
  WidgetTester tester, {
  double maxLd = 60,
  double zoom = 1,
}) async {
  tester.view
    ..physicalSize = _size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    RepaintBoundary(child: _Ticking(maxLd: maxLd, zoom: zoom)),
  );
}

/// Drives [RadarPainter] with a clock a test can advance by pumping, standing in
/// for the `Ticker` that `RadarView` gives it in the app.
class _Ticking extends StatefulWidget {
  const _Ticking({required this.maxLd, required this.zoom});

  final double maxLd;
  final double zoom;

  @override
  State<_Ticking> createState() => _TickingState();
}

class _TickingState extends State<_Ticking> with SingleTickerProviderStateMixin {
  final ValueNotifier<Duration> _clock = ValueNotifier<Duration>(Duration.zero);
  late final Ticker _ticker = createTicker((Duration d) => _clock.value = d);

  @override
  void initState() {
    super.initState();
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: RadarPainter(clock: _clock, maxLd: widget.maxLd, zoom: widget.zoom),
    size: Size.infinite,
  );
}

RenderBox _painterOf(WidgetTester tester) =>
    tester.renderObject<RenderBox>(find.byType(CustomPaint).last);

/// Every `drawPath` the painter recorded, outward — one per ring.
List<Path> _ringPaths(WidgetTester tester) {
  final List<Path> paths = <Path>[];
  // `something` is the only supported way to see the call list; it wants a
  // predicate, so this collects as a side effect and always declines. The
  // matcher then fails to match, which is why the result is read from `paths`
  // rather than from `expect`.
  final Matcher collector = (paints
    ..something((Symbol method, List<dynamic> arguments) {
      if (method == #drawPath) paths.add(arguments[0] as Path);
      return false;
    })) as Matcher;
  collector.matches(_painterOf(tester), <dynamic, dynamic>{});
  return paths;
}

/// The length of each dash on each ring, outward.
List<List<double>> _ringDashes(WidgetTester tester) => <List<double>>[
  for (final Path ring in _ringPaths(tester))
    <double>[for (final ui.PathMetric dash in ring.computeMetrics()) dash.length],
];

/// The radius of each ring, taken from the path the painter actually drew
/// rather than from anything it was asked for.
List<double> _ringRadii(WidgetTester tester) => <double>[
  for (final Path ring in _ringPaths(tester)) ring.getBounds().width / 2,
];

/// Matches a `drawCircle` at Earth's centre whose radius satisfies [radius].
///
/// The `paints` pattern's own `circle(radius:)` compares exactly, which the
/// glow cannot be held to: its radius is the output of a sine, so the only
/// frames with a clean value are the ones a test would have to contrive.
PaintPattern _drawsCircle({required Matcher radius}) =>
    paints..something((Symbol method, List<dynamic> arguments) {
      if (method != #drawCircle) return false;
      final Offset centre = arguments[0] as Offset;
      return centre == _centre && radius.matches(arguments[1], <dynamic, dynamic>{});
    });

/// The rendered frame, read back from the engine — a real rasterisation through
/// `flutter_tester`, the same painting pipeline a phone runs. `toImage` must go
/// through [WidgetTester.runAsync] because a `testWidgets` body runs in a
/// fake-async zone where a future waiting on the real engine never completes.
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

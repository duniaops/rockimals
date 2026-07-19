import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/data/models/asteroid.dart';
import 'package:rockimals/features/radar/planet_backdrop.dart';
import 'package:rockimals/features/radar/radar_clock.dart';
import 'package:rockimals/features/radar/radar_layers.dart';
import 'package:rockimals/features/radar/radar_orbits.dart';
import 'package:rockimals/features/radar/radar_painter.dart';

/// One frame of the radar, and the four ways a test is allowed to look at it.
///
/// **Shared rather than per-suite, because there are now two suites asking the
/// same questions.** `radar_painter_test.dart` wrote all of this to check *what*
/// the painter draws; `radar_colours_test.dart` needs the identical mounting,
/// the identical recording canvas and the identical rasteriser to check what
/// colour it draws it in. A second copy would be the drift `Palette` and the
/// radar's label cache were each written to end — and worse here, because two
/// harnesses that disagree by a pixel would send a reader hunting for a bug in
/// the painter.
///
/// The four ways, in increasing order of how much they know:
///  * [radarCalls] — every canvas call, in order. Cheap, and the only way to see
///    paint *order*.
///  * [radarCircles] / [radarParagraphs] — the two shapes the radar is mostly
///    made of, with the [Paint] or the width each was drawn with.
///  * [rasteriseRadar] — the frame actually rendered by the engine. The only one
///    that knows whether any of it landed on screen.

/// A phone-shaped field. The default test view is 800×600, which would clamp
/// this and quietly move every coordinate a test computes, so [pumpRadar]
/// resizes the view rather than wrapping the radar in a box the view can squash.
const Size radarSize = Size(390, 700);

/// Where Earth is — `RadarGeometry`'s own 46% of the height.
final Offset radarCentre = Offset(radarSize.width / 2, radarSize.height * 0.46);

/// The painter under test, filling a field of a known size, so every coordinate
/// a test asserts is one the painter computed rather than one the test invented.
Future<void> pumpRadar(
  WidgetTester tester, {
  double maxLd = 60,
  double zoom = 1,
  double viewRot = 0,
  List<Asteroid> sky = const <Asteroid>[],
  Asteroid? selected,
  PlanetBackdrop? backdrop,
  RadarLayers layers = const RadarLayers(),
}) async {
  tester.view
    ..physicalSize = radarSize
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    RepaintBoundary(
      child: _Ticking(
        // A fresh key per call, so a test that mounts two radars in a row really
        // gets two. Without it the second `pumpWidget` reuses the first's
        // `State` — and the sky is seeded in a `late final` there, exactly as it
        // is in the app, so the new asteroids would be silently ignored and the
        // test would be asserting against the previous frame's sky.
        key: UniqueKey(),
        maxLd: maxLd,
        zoom: zoom,
        viewRot: viewRot,
        asteroids: sky,
        selected: selected,
        backdrop: backdrop,
        layers: layers,
      ),
    ),
  );
}

/// The render object the radar's painter is attached to — what every collector
/// below replays.
RenderBox radarPainterOf(WidgetTester tester) =>
    tester.renderObject<RenderBox>(find.byType(CustomPaint).last);

/// Every canvas call the painter recorded, in order.
List<({Symbol method, List<dynamic> args})> radarCalls(WidgetTester tester) {
  final List<({Symbol method, List<dynamic> args})> calls =
      <({Symbol method, List<dynamic> args})>[];
  recordRadar(tester, (Symbol method, List<dynamic> arguments) {
    calls.add((method: method, args: arguments));
  });
  return calls;
}

/// Replays the frame, handing [onCall] every canvas call the painter made.
///
/// `something` is the only supported way to see the call list; it wants a
/// predicate, so every collector here gathers as a side effect and always
/// declines. The matcher then fails to match, which is why results are read from
/// the list rather than from `expect`.
void recordRadar(
  WidgetTester tester,
  void Function(Symbol method, List<dynamic> arguments) onCall,
) {
  final Matcher collector =
      (paints..something((Symbol method, List<dynamic> arguments) {
            onCall(method, arguments);
            return false;
          }))
          as Matcher;
  collector.matches(radarPainterOf(tester), <dynamic, dynamic>{});
}

/// Every `drawCircle` the painter recorded, in order, with the [Paint] it used.
///
/// **The recorded paints really are per-call**, even though `_paintAnimals`
/// reuses two [Paint] objects across every animal to keep per-frame allocation
/// down (`CLAUDE.md:80`): the recording canvas snapshots each one. Worth knowing
/// before trusting any colour asserted here — if it did not, every ring in a
/// frame would read back as the last colour set and these tests would quietly
/// agree with themselves.
List<({Offset at, double radius, Paint paint})> radarCircles(
  WidgetTester tester,
) {
  final List<({Offset at, double radius, Paint paint})> circles =
      <({Offset at, double radius, Paint paint})>[];
  recordRadar(tester, (Symbol method, List<dynamic> arguments) {
    if (method == #drawCircle) {
      circles.add((
        at: arguments[0] as Offset,
        radius: arguments[1] as double,
        paint: arguments[2] as Paint,
      ));
    }
  });
  return circles;
}

/// Every `drawPath` the painter recorded, with the [Paint] it used.
List<({Path path, Paint paint})> radarPaths(WidgetTester tester) {
  final List<({Path path, Paint paint})> paths = <({Path path, Paint paint})>[];
  recordRadar(tester, (Symbol method, List<dynamic> arguments) {
    if (method == #drawPath) {
      paths.add((path: arguments[0] as Path, paint: arguments[1] as Paint));
    }
  });
  return paths;
}

/// Where every string the painter laid down this frame was drawn, and how wide
/// it is.
///
/// A [ui.Paragraph] does not carry its text, so *which* label this is has to be
/// read from where it landed — which is worth pinning anyway, since a name drawn
/// in the right style at the wrong place is still wrong. The offset is the
/// text's **left edge**, not its centre: `RadarLabel.paint` does the centring
/// itself (canvas's `textAlign="center"`), so recovering the centre needs the
/// width.
List<({Offset at, double width})> radarParagraphs(WidgetTester tester) {
  final List<({Offset at, double width})> offsets =
      <({Offset at, double width})>[];
  recordRadar(tester, (Symbol method, List<dynamic> arguments) {
    if (method == #drawParagraph) {
      offsets.add((
        at: arguments[1] as Offset,
        width: (arguments[0] as ui.Paragraph).longestLine,
      ));
    }
  });
  return offsets;
}

/// The rendered frame, read back from the engine — a real rasterisation through
/// `flutter_tester`, the same painting pipeline a phone runs. `toImage` must go
/// through [WidgetTester.runAsync] because a `testWidgets` body runs in a
/// fake-async zone where a future waiting on the real engine never completes.
Future<RadarPixels> rasteriseRadar(WidgetTester tester) async {
  final RenderRepaintBoundary boundary = tester.renderObject(
    find.byType(RepaintBoundary).first,
  );
  final ui.Image image = (await tester.runAsync<ui.Image>(boundary.toImage))!;
  return imagePixels(tester, image);
}

/// The same read-back for an image a test painted itself — see
/// `radar_colours_test.dart`, which renders reference gradients from the
/// prototype's own literals and compares them with the frame.
Future<RadarPixels> imagePixels(WidgetTester tester, ui.Image image) async {
  final ByteData data = (await tester.runAsync<ByteData?>(image.toByteData))!;
  return RadarPixels(data, image.width);
}

class RadarPixels {
  const RadarPixels(this._rgba, this._width);

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

/// Drives [RadarPainter] with a clock a test can advance by pumping, standing in
/// for the `Ticker` that `RadarView` gives it in the app.
class _Ticking extends StatefulWidget {
  const _Ticking({
    super.key,
    required this.maxLd,
    required this.zoom,
    this.viewRot = 0,
    this.asteroids = const <Asteroid>[],
    this.selected,
    this.backdrop,
    this.layers = const RadarLayers(),
  });

  final double maxLd;
  final double zoom;

  /// Defaults to an empty sky, so the base-layer tests see exactly the frame
  /// they were written against: no asteroids, no chips.
  final List<Asteroid> asteroids;
  final Asteroid? selected;
  final double viewRot;

  final PlanetBackdrop? backdrop;

  /// Defaults to every layer on and Close-flybys off — the prototype's opening
  /// state (`index.html:625`). Toggle tests pass their own.
  final RadarLayers layers;

  @override
  State<_Ticking> createState() => _TickingState();
}

class _TickingState extends State<_Ticking>
    with SingleTickerProviderStateMixin {
  final ValueNotifier<Duration> _clock = ValueNotifier<Duration>(Duration.zero);
  late final RadarOrbits _orbits = RadarOrbits.seed(widget.asteroids);

  late final PlanetBackdrop _backdrop =
      widget.backdrop ?? PlanetBackdrop.seed();

  /// The app's own wiring (`radar_view.dart`): one step per frame, measured once.
  final FrameClock _frame = FrameClock();

  late final Ticker _ticker = createTicker((Duration d) {
    _orbits.advance(_frame.step(d));
    _clock.value = d;
  });

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
    painter: RadarPainter(
      clock: _clock,
      orbits: _orbits,
      backdrop: _backdrop,
      maxLd: widget.maxLd,
      zoom: widget.zoom,
      viewRot: widget.viewRot,
      selected: widget.selected,
      layers: widget.layers,
    ),
    size: Size.infinite,
  );
}

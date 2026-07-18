/// **Rusty the fox** — the Rockimals mascot, ported path-for-path from the
/// inline SVG in `title.html:78-125`.
///
/// **In `core/` rather than under `features/title/`, and the spec is what puts
/// it there.** `specs/06-title-polish-safety.md:18` asks for Rusty on three
/// surfaces — the title, the loading screen, and the empty states — so he is
/// shared by the same test `Palette` passes: the artifact being ported already
/// declares itself shared, rather than a Dart file guessing that a second caller
/// might turn up. The plan carries the other two surfaces as their own item; the
/// only thing done ahead of it here is *where the file lives*, which costs
/// nothing now and a cross-feature move later.
///
/// **A [CustomPainter] rather than an SVG asset**, per `CLAUDE.md:34-36`: no
/// `flutter_svg` dependency, no asset to keep in sync with `title.html`, and the
/// same painting primitives the radar already uses. The transcription is
/// mechanical — `C` becomes [Path.cubicTo], `Q` becomes
/// [Path.quadraticBezierTo], `<ellipse>` becomes [Canvas.drawOval] — so the SVG
/// stays readable as the source next to it.
library;

import 'package:flutter/widgets.dart';

/// The SVG's `viewBox` (`title.html:78`), and so Rusty's intrinsic size.
///
/// Everything below is written in these coordinates and scaled at paint time, so
/// the numbers in this file can be diffed against `title.html` line by line.
const Size kRustySize = Size(212, 206);

/// Rusty, at [size] (defaulting to his intrinsic [kRustySize]).
///
/// He does not move: the 3.6s bob is `.float` (`title.html:43-44`), a *wrapper*
/// around the SVG in the prototype and a wrapper here too, so that the surface
/// showing him owns whether he bobs at all. That matters because Calm motion
/// stops the bob (`title_screen.dart`) and because the loading screen will want
/// him next to a spinner that already turns.
class Rusty extends StatelessWidget {
  const Rusty({super.key, this.size = kRustySize});

  /// The box he is painted into. Scaled uniformly from [kRustySize]; a
  /// non-proportional size squashes him rather than cropping him, exactly as an
  /// `<svg width height viewBox>` would.
  final Size size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: size,
      painter: const _RustyPainter(),
      // Thirty-odd draws that never change, so the raster cache can hold him as
      // one layer and the bob above him becomes a transform of a cached picture
      // rather than a repaint (`CLAUDE.md:80`). `willChange` is left at its
      // `false` default, which is the other half of the same claim.
      isComplex: true,
    );
  }
}

// ── The fur, and why each shape gets its own gradient ────────────────────────
//
// `fill="url(#fox)"` on five separate paths, with `<radialGradient>` in its
// default `gradientUnits="objectBoundingBox"` — so SVG maps the gradient onto
// *each shape's own bounding box*, not onto the drawing as a whole. The tail,
// both ears and the body are each independently shaded, which is what stops
// Rusty reading as one flat orange blob. [_fur] reproduces that by taking the
// bounds of the path it is about to fill.
//
// One approximation, stated rather than hidden: SVG's `r="50%"` in
// object-bounding-box units is an *ellipse* on a non-square bbox, while
// [RadialGradient.radius] is a fraction of the shortest side and stays circular.
// The body — by far the largest of the five — is 118×118, square to the pixel,
// so it is exact where it counts; the ears and tail are off by a few percent of
// a gradient nobody can see the edge of.

/// `#ffc99b` at 0%, `#ef6a2a` at 48%, `#b83f12` at 100%, centred at 38%/28%
/// (`title.html:80-82`).
const RadialGradient _furGradient = RadialGradient(
  // CSS/SVG percentages are 0…1 across the box; [Alignment] is -1…1, so
  // `38% → 2·0.38-1`.
  center: Alignment(-0.24, -0.44),
  colors: <Color>[Color(0xFFFFC99B), Color(0xFFEF6A2A), Color(0xFFB83F12)],
  stops: <double>[0, 0.48, 1],
);

Paint _fur(Rect bounds) => Paint()..shader = _furGradient.createShader(bounds);

/// The warm halo behind him — `rgba(255,150,70,.45)` fading to nothing
/// (`title.html:83-85, 88`). `.45×255 = 114.75`, which Chrome rounds to 115.
const RadialGradient _glowGradient = RadialGradient(
  colors: <Color>[Color(0x73FF9646), Color(0x00FF9646)],
);

/// `#fff2e2` — the tail tip and the muzzle (`title.html:91, 111`).
const Color _cream = Color(0xFFFFF2E2);

/// `#c24a18` — the feet (`title.html:93-94`).
const Color _paw = Color(0xFFC24A18);

/// `#7a2a0a` — the dark ear tips (`title.html:99-100`).
const Color _earTip = Color(0xFF7A2A0A);

/// `#ffc4ad` at `opacity=".85"` (`title.html:102-103`). Baked into the alpha
/// rather than pushed through a layer: `.85×255 = 216.75 → 217 (0xD9)`, and one
/// opaque draw beats a `saveLayer` for a shape this small.
const Color _innerEar = Color(0xD9FFC4AD);

/// `#000` at `opacity=".1"` — the craters that keep the "rock" reading
/// (`title.html:107-109`). `.1×255 = 25.5 → 26 (0x1A)`.
const Color _crater = Color(0x1A000000);

/// `#ff8f6b` at `opacity=".65"` — the rosy cheeks (`title.html:113-114`).
/// `.65×255 = 165.75 → 166 (0xA6)`.
const Color _cheek = Color(0xA6FF8F6B);

/// `#2a1a12` — the eyes' pupils, the nose, and the smile (`title.html:117-122`).
const Color _ink = Color(0xFF2A1A12);

const Color _white = Color(0xFFFFFFFF);

class _RustyPainter extends CustomPainter {
  const _RustyPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(
      size.width / kRustySize.width,
      size.height / kRustySize.height,
    );

    _paintGlow(canvas);
    _paintTail(canvas);
    _paintFeet(canvas);
    _paintEars(canvas);
    // The SVG's order, kept exactly (`title.html:88-125`). Two joins depend on
    // it and one of them is checked: the ears and the body overlap in a band a
    // few pixels tall where each carries its own gradient, so swapping them
    // shifts a seam — subtle, and left to the eye. The face over the body is the
    // opposite: paint it first and Rusty has no muzzle and no eyes at all, which
    // is what `rusty_test.dart` reads back off the rasterised frame.
    _paintBody(canvas);
    _paintFace(canvas);
    _paintSparkle(canvas);

    canvas.restore();
  }

  /// `<circle cx="106" cy="108" r="100" fill="url(#glow)"/>` (`title.html:88`).
  void _paintGlow(Canvas canvas) {
    const Offset centre = Offset(106, 108);
    canvas.drawCircle(
      centre,
      100,
      Paint()
        ..shader = _glowGradient.createShader(
          Rect.fromCircle(center: centre, radius: 100),
        ),
    );
  }

  /// The bushy tail and its cream tip (`title.html:90-91`).
  void _paintTail(Canvas canvas) {
    final Path tail = Path()
      ..moveTo(150, 158)
      ..cubicTo(198, 150, 206, 100, 176, 82)
      ..cubicTo(192, 116, 168, 146, 138, 144)
      ..close();
    canvas.drawPath(tail, _fur(tail.getBounds()));

    canvas.drawOval(
      Rect.fromCenter(center: const Offset(186, 88), width: 32, height: 28),
      Paint()..color = _cream,
    );
  }

  /// `<ellipse cx="86|126" cy="182" rx="15" ry="9"/>` (`title.html:93-94`).
  void _paintFeet(Canvas canvas) {
    final Paint paw = Paint()..color = _paw;
    for (final double x in <double>[86, 126]) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(x, 182), width: 30, height: 18),
        paw,
      );
    }
  }

  /// Three layers per ear — the furred outer, the dark tip, the pink inner
  /// (`title.html:96-103`).
  void _paintEars(Canvas canvas) {
    final Path left = Path()
      ..moveTo(66, 68)
      ..lineTo(52, 18)
      ..quadraticBezierTo(70, 30, 92, 54)
      ..close();
    final Path right = Path()
      ..moveTo(146, 68)
      ..lineTo(160, 18)
      ..quadraticBezierTo(142, 30, 120, 54)
      ..close();
    canvas.drawPath(left, _fur(left.getBounds()));
    canvas.drawPath(right, _fur(right.getBounds()));

    final Paint tip = Paint()..color = _earTip;
    canvas.drawPath(
      Path()
        ..moveTo(60, 50)
        ..lineTo(53, 24)
        ..quadraticBezierTo(63, 32, 76, 46)
        ..close(),
      tip,
    );
    canvas.drawPath(
      Path()
        ..moveTo(152, 50)
        ..lineTo(159, 24)
        ..quadraticBezierTo(149, 32, 136, 46)
        ..close(),
      tip,
    );

    final Paint inner = Paint()..color = _innerEar;
    canvas.drawPath(
      Path()
        ..moveTo(69, 60)
        ..lineTo(60, 34)
        ..quadraticBezierTo(69, 40, 81, 54)
        ..close(),
      inner,
    );
    canvas.drawPath(
      Path()
        ..moveTo(143, 60)
        ..lineTo(152, 34)
        ..quadraticBezierTo(143, 40, 131, 54)
        ..close(),
      inner,
    );
  }

  /// The rock body and its three craters (`title.html:105-109`).
  void _paintBody(Canvas canvas) {
    final Path body = Path()
      ..moveTo(106, 48)
      ..cubicTo(142, 46, 168, 72, 166, 106)
      ..cubicTo(165, 140, 142, 164, 106, 164)
      ..cubicTo(70, 164, 48, 140, 48, 106)
      ..cubicTo(48, 72, 70, 50, 106, 48)
      ..close();
    canvas.drawPath(body, _fur(body.getBounds()));

    final Paint crater = Paint()..color = _crater;
    // `(cx, cy, rx, ry)`, as written on `title.html:107-109`.
    for (final (double, double, double, double) c
        in const <(double, double, double, double)>[
          (70, 86, 8, 6),
          (150, 120, 7, 5),
          (60, 128, 6, 4),
        ]) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(c.$1, c.$2),
          width: c.$3 * 2,
          height: c.$4 * 2,
        ),
        crater,
      );
    }
  }

  /// Muzzle, cheeks, eyes, nose and smile (`title.html:111-122`).
  void _paintFace(Canvas canvas) {
    canvas.drawPath(
      Path()
        ..moveTo(106, 156)
        ..cubicTo(84, 156, 72, 142, 72, 120)
        ..cubicTo(72, 106, 82, 98, 95, 99)
        ..cubicTo(99, 103, 113, 103, 117, 99)
        ..cubicTo(130, 98, 140, 106, 140, 120)
        ..cubicTo(140, 142, 128, 156, 106, 156)
        ..close(),
      Paint()..color = _cream,
    );

    final Paint cheek = Paint()..color = _cheek;
    canvas.drawCircle(const Offset(80, 130), 7.5, cheek);
    canvas.drawCircle(const Offset(132, 130), 7.5, cheek);

    // Whites, then pupils, then the catchlights that make him look *at* a child
    // rather than through them. Order is the SVG's and is the whole effect.
    final Paint white = Paint()..color = _white;
    canvas.drawCircle(const Offset(88, 98), 13, white);
    canvas.drawCircle(const Offset(124, 98), 13, white);

    final Paint ink = Paint()..color = _ink;
    canvas.drawCircle(const Offset(91, 101), 7, ink);
    canvas.drawCircle(const Offset(121, 101), 7, ink);

    canvas.drawCircle(const Offset(94, 98), 2.5, white);
    canvas.drawCircle(const Offset(124, 98), 2.5, white);

    canvas.drawPath(
      Path()
        ..moveTo(99, 118)
        ..quadraticBezierTo(106, 126, 113, 118)
        ..quadraticBezierTo(106, 124, 99, 118)
        ..close(),
      ink,
    );

    // The two strokes: the philtrum under the nose, then the smile.
    final Paint stroke = Paint()
      ..color = _ink
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      const Offset(106, 124),
      const Offset(106, 130),
      stroke..strokeWidth = 2.4,
    );
    canvas.drawPath(
      Path()
        ..moveTo(96, 132)
        ..quadraticBezierTo(106, 140, 116, 132),
      stroke..strokeWidth = 2.8,
    );
  }

  /// `<text x="40" y="60" font-size="16">✨</text>` (`title.html:124`).
  ///
  /// SVG's `y` is the *baseline*, so the glyph is lifted by its ascent rather
  /// than drawn from `y` as a top-left corner — otherwise the sparkle sits a
  /// whole line lower than in the prototype.
  void _paintSparkle(Canvas canvas) {
    final TextPainter sparkle = TextPainter(
      text: const TextSpan(text: '✨', style: TextStyle(fontSize: 16)),
      textDirection: TextDirection.ltr,
    )..layout();
    sparkle.paint(
      canvas,
      Offset(
        40,
        60 - sparkle.computeDistanceToActualBaseline(TextBaseline.alphabetic),
      ),
    );
    sparkle.dispose();
  }

  /// He never changes. The bob is a transform applied above him, so the layer is
  /// reused frame to frame and nothing here re-runs — the low-allocation shape
  /// `CLAUDE.md:80` asks for, and free at this size.
  @override
  bool shouldRepaint(covariant _RustyPainter oldDelegate) => false;

  /// Decoration, never a target — stated rather than left to
  /// `RenderCustomPaint.hitTestSelf`'s `?? true`, which would make Rusty
  /// hit-testable purely because nobody overrode this. Nothing depends on it
  /// today (every surface that shows him handles taps on an ancestor, and hits
  /// bubble up either way); it is here so that the first surface to put a
  /// *control* beside him does not have to discover the default first.
  @override
  bool hitTest(Offset position) => false;
}

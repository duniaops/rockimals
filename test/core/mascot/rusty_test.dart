import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/core/mascot/rusty.dart';

/// Rusty is *geometry*, and geometry is the one thing a widget test normally
/// cannot see: `find.byType(Rusty)` passes just as happily for an empty canvas,
/// for a fox drawn at half scale, or for a face painted underneath the body it
/// should sit on. So the frame is rasterised and read back, exactly as
/// `loading_screen_test.dart` does for the spinner — the closest this project
/// can get to looking at the screen while the toolchain item is open.
///
/// The exact-colour probes sit on flat, opaque parts of the face, so each has a
/// single answer that can be read straight off `title.html` without reproducing
/// the gradient maths here. The fur is asked a different kind of question, for
/// the same reason.
void main() {
  group('Rusty', () {
    testWidgets('has a face, in the right place, at his intrinsic size', (
      tester,
    ) async {
      await tester.pumpWidget(_mascot());

      final Rect box = tester.getRect(find.byType(Rusty));
      final _Pixels px = await _paintedPixels(tester);

      expect(box.size, kRustySize, reason: 'the SVG viewBox (title.html:78)');

      // **These three also pin the draw order**, which is the difference between
      // a fox and an orange rock: each layer is only its own colour because it
      // was painted after the one under it.
      //
      // The muzzle, low on the face where no cheek, nose or smile reaches —
      // `#fff2e2`, and the page background if the body were painted over it
      // (`title.html:111`).
      expect(px.at(box.left + 106, box.top + 148), const Color(0xFFFFF2E2));
      // The left eye's white, clear of both the pupil at (91,101) r7 and the
      // catchlight at (94,98) r2.5 — pure `#fff` (`title.html:116`).
      expect(px.at(box.left + 84, box.top + 94), const Color(0xFFFFFFFF));
      // ...and the pupil inside it, `#2a1a12` (`title.html:117`).
      expect(px.at(box.left + 91, box.top + 101), const Color(0xFF2A1A12));
    });

    testWidgets('is fur rather than a flat orange, and lit from the top left', (
      tester,
    ) async {
      // The body's fill is `url(#fox)`, a three-stop radial gradient centred at
      // 38%/28% of the shape (`title.html:80-82`) — the thing that stops him
      // reading as a traffic cone. A port that dropped the shader for its middle
      // stop would pass every other test in this file, so the question asked
      // here is *comparative*: two points on bare fur, one near the light and
      // one far from it, must differ, and in the direction the gradient says.
      await tester.pumpWidget(_mascot());

      final Rect box = tester.getRect(find.byType(Rusty));
      final _Pixels px = await _paintedPixels(tester);

      // High on the forehead, close to the gradient's centre; and low on the
      // left flank, out past its `#b83f12` end. Both are clear of every crater,
      // ear, cheek and the muzzle.
      final Color lit = px.at(box.left + 100, box.top + 60);
      final Color shaded = px.at(box.left + 58, box.top + 100);

      expect(lit.a, 1.0, reason: 'opaque fur, not the backdrop showing through');
      expect(shaded.a, 1.0);
      expect(
        lit.r + lit.g + lit.b,
        greaterThan(shaded.r + shaded.g + shaded.b),
        reason: 'the light point is at 38%/28%, i.e. up and to the left',
      );
      // ...and it is an orange either way, not a grey ramp.
      for (final Color fur in <Color>[lit, shaded]) {
        expect(fur.r, greaterThan(fur.g));
        expect(fur.g, greaterThan(fur.b));
      }
    });

    test('kRustyHalfSize is exactly half of him', () {
      // The one size the loading screen and both empty states share
      // (`specs/06-title-polish-safety.md:18`). It is a const restatement of
      // `kRustySize / 2` — restated because a `Size`'s fields are not constant
      // expressions — so this is the only thing stopping the two sets of
      // digits drifting apart.
      expect(kRustyHalfSize, kRustySize / 2);
    });

    testWidgets('scales whole rather than cropping', (tester) async {
      // The loading screen and the empty states each want him at their own size
      // (`specs/06-title-polish-safety.md:18`), so the painter has to be a scale
      // of the viewBox rather than a fixed drawing in a resizable box. At half
      // size every feature sits at half the offset; a painter that ignored
      // `size` would leave the pupil where the first test found it.
      await tester.pumpWidget(
        _mascot(size: Size(kRustySize.width / 2, kRustySize.height / 2)),
      );

      final Rect box = tester.getRect(find.byType(Rusty));
      final _Pixels px = await _paintedPixels(tester);

      expect(box.size, Size(kRustySize.width / 2, kRustySize.height / 2));
      expect(px.at(box.left + 45.5, box.top + 50.5), const Color(0xFF2A1A12));
    });
  });
}

/// Rusty alone on a black field, under a boundary covering the whole surface so
/// that image coordinates and screen coordinates are the same thing.
///
/// Black rather than the title screen's sky: every probe here is on an opaque
/// shape, so the backdrop only has to be something no probe could be mistaken
/// for.
Widget _mascot({Size size = kRustySize}) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: RepaintBoundary(
      child: ColoredBox(
        color: const Color(0xFF000000),
        child: Center(child: Rusty(size: size)),
      ),
    ),
  );
}

/// The rendered frame, read back from the engine — see the long note on the
/// identical helper in `loading_screen_test.dart` for why `toImage` has to go
/// through [WidgetTester.runAsync]. It defaults to a pixel ratio of 1, so image
/// coordinates are logical ones.
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

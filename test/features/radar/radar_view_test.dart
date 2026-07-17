import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/data/models/asteroid.dart';
import 'package:rockimals/data/models/asteroid_feed.dart';
import 'package:rockimals/features/data/providers.dart';
import 'package:rockimals/features/radar/radar_geometry.dart';
import 'package:rockimals/features/radar/radar_layers.dart';
import 'package:rockimals/features/radar/radar_painter.dart';
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
      _ringPaths(tester),
      hasLength(5),
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

  group('drag', () {
    testWidgets('spins the field by the angle the finger travelled', (
      tester,
    ) async {
      // The rotation is the *change* in the finger's bearing from Earth
      // (`index.html:686-687`), not its distance — so a drag round the field
      // keeps the animal under the fingertip, and a drag straight at Earth does
      // nothing at all. Here: due east of Earth round to due south is a clean
      // quarter turn, whatever route the finger takes to get there.
      await _mount(tester, _sky(<double>[3]));
      expect(_view(tester).viewRot, 0);

      final Offset centre = _centre(tester);
      await tester.dragFrom(centre + const Offset(120, 0), const Offset(-120, 120));
      await tester.pump();

      expect(_view(tester).viewRot, closeTo(math.pi / 2, 1e-6));
    });

    testWidgets('accumulates, rather than snapping back between drags', (
      tester,
    ) async {
      // Two quarter-turns is a half-turn. `viewRot += ang - dragAng`
      // (`index.html:687`) — each drag starts from wherever the last one left
      // the sky, because letting go is not an event the field knows about.
      await _mount(tester, _sky(<double>[3]));
      final Offset centre = _centre(tester);

      await tester.dragFrom(centre + const Offset(120, 0), const Offset(-120, 120));
      await tester.pump();
      await tester.dragFrom(centre + const Offset(0, 120), const Offset(-120, -120));
      await tester.pump();

      expect(_view(tester).viewRot, closeTo(math.pi, 1e-6));
    });

    testWidgets('leaves the sky alone: it moves the view, not the animals', (
      tester,
    ) async {
      // The drag is a camera, and this is the assertion that says so. If a drag
      // ever wrote into an animal's own phase, the sky would keep orbiting from
      // wherever the child let go and the ⤢ button could not put it back by
      // setting one number to zero.
      await _mount(tester, _sky(<double>[3]));
      final double phase = _view(tester).orbits.orbits.single.phase;

      await tester.dragFrom(_centre(tester) + const Offset(120, 0), const Offset(-120, 120));
      await tester.pump();

      expect(_view(tester).orbits.orbits.single.phase, phase);
    });
  });

  group('pinch', () {
    testWidgets('zooms by how much the fingers spread', (tester) async {
      // `zoom *= nd/pinchDist` (`index.html:689`) — the field follows the
      // fingers, so pulling them twice as far apart makes everything twice as
      // far apart.
      await _mount(tester, _sky(<double>[3]));
      expect(_view(tester).zoom, 1);

      await _pinch(tester, from: 100, to: 200);

      expect(_view(tester).zoom, closeTo(2, 1e-6));
    });

    testWidgets('cannot be flung past the frame, in either direction', (
      tester,
    ) async {
      // `clamp(…, 0.35, 6.5)` (`index.html:689`). The clamp is not tidiness: a
      // child who pinches the sky down to nothing, or blows it up until every
      // animal is off the edge, is left holding a screen with nothing on it and
      // no way to know what to do — `specs/02-live-radar.md:34` asks for a range
      // the content cannot leave.
      await _mount(tester, _sky(<double>[3]));

      await _pinch(tester, from: 8, to: 300); // ×37.5
      expect(_view(tester).zoom, 6.5);

      await _pinch(tester, from: 300, to: 8); // ÷37.5
      expect(_view(tester).zoom, 0.35);
    });

    testWidgets('survives two fingers landing on the same spot', (tester) async {
      // `if(Radar.pinchDist)` (`index.html:689`) skips a zero gap as well as a
      // null one, and the zero is reachable: two fingertips can be reported at
      // the same point. Without the guard the first move divides by it, and a
      // `zoom` of Infinity or NaN is a radar that goes blank and never comes
      // back — there is no gesture that can undo a NaN.
      await _mount(tester, _sky(<double>[3]));

      await _pinch(tester, from: 0, to: 200);

      // The first move is skipped as the gap it would have been measured
      // against, so the zoom is what the *second* move asked for, and it is a
      // real number.
      expect(_view(tester).zoom, closeTo(2, 1e-6));
    });

    testWidgets('a finger lifting while another is still down is not a tap', (
      tester,
    ) async {
      // `Radar.pointers.size===1` at the up (`index.html:691`) — the clause that
      // stops a two-finger gesture selecting an animal halfway through itself.
      // A child pinching with one fingertip resting on an animal lifts the other
      // finger first; that release must not be read as having tapped it.
      //
      // **The order here is the whole test, and the obvious arrangement proves
      // nothing.** The hit is tested at the *last* down position
      // (`index.html:693`), so the animal has to be the second finger down and
      // the first one lifted — otherwise the tap is answered at an empty spot,
      // comes back null, and the test passes just as happily with the clause
      // deleted. (It did, until a mutation said so.)
      await _mount(tester, _sky(<double>[3]));
      final Offset animal = _animalAt(tester);

      // Towards Earth: the animal is out on the right of the field and the zoom
      // buttons are further right still, so a finger placed that way would land
      // on a button and never reach the radar at all.
      final TestGesture resting =
          await tester.startGesture(animal - const Offset(40, 0));
      final TestGesture onAnimal = await tester.startGesture(animal);

      await resting.up();
      await tester.pump();
      expect(_view(tester).selected, isNull);

      // Lifted past the tap window, so this release cannot select either and the
      // assertion above stays the only thing being read.
      await onAnimal.up(timeStamp: const Duration(milliseconds: 400));
      await tester.pump();
      expect(_view(tester).selected, isNull);
    });
  });

  group('the zoom buttons', () {
    testWidgets('step in and out by the prototype’s own factors', (tester) async {
      // ×1.45 and ×0.69 (`index.html:697-698`), which are near-inverses — so a
      // child who taps ＋ and then − is back where they started rather than
      // slightly adrift.
      await _mount(tester, _sky(<double>[3]));

      await tester.tap(find.bySemanticsLabel('Zoom in'));
      await tester.pump();
      expect(_view(tester).zoom, closeTo(1.45, 1e-9));

      await tester.tap(find.bySemanticsLabel('Zoom out'));
      await tester.pump();
      expect(_view(tester).zoom, closeTo(1.0005, 1e-9));
    });

    testWidgets('hold the same clamp the fingers do', (tester) async {
      await _mount(tester, _sky(<double>[3]));

      for (int i = 0; i < 10; i++) {
        await tester.tap(find.bySemanticsLabel('Zoom in'));
        await tester.pump();
      }
      expect(_view(tester).zoom, 6.5);

      for (int i = 0; i < 20; i++) {
        await tester.tap(find.bySemanticsLabel('Zoom out'));
        await tester.pump();
      }
      expect(_view(tester).zoom, 0.35);
    });

    testWidgets('⤢ puts back the rotation as well as the zoom', (tester) async {
      // `{Radar.zoom=1; Radar.viewRot=0;}` (`index.html:699`) — both, and this
      // is the whole reason the button is worth having. A child who has spun the
      // field until they cannot find Earth needs one control that gives them
      // back the sky they opened the app to; a reset that fixed only the zoom
      // would leave them exactly as lost.
      await _mount(tester, _sky(<double>[3]));
      await tester.dragFrom(_centre(tester) + const Offset(120, 0), const Offset(-120, 120));
      await _pinch(tester, from: 100, to: 300);
      await tester.pump();
      expect(_view(tester).viewRot, isNot(0));
      expect(_view(tester).zoom, isNot(1));

      await tester.tap(find.bySemanticsLabel('Reset the view'));
      await tester.pump();

      expect(_view(tester).viewRot, 0);
      expect(_view(tester).zoom, 1);
    });

    testWidgets('take their own taps rather than the field underneath', (
      tester,
    ) async {
      // The buttons sit on top of a [Listener] that treats every tap on empty
      // space as "deselect". If a tap on ＋ reached both, zooming in would
      // silently throw away the animal the child was looking at.
      await _mount(tester, _sky(<double>[3]));
      await tester.tapAt(_animalAt(tester));
      await tester.pump();
      expect(_view(tester).selected, isNotNull, reason: 'the premise');

      await tester.tap(find.bySemanticsLabel('Zoom in'));
      await tester.pump();

      expect(_view(tester).selected, isNotNull);
    });
  });

  group('tap', () {
    testWidgets('selects the animal under it', (tester) async {
      await _mount(tester, _sky(<double>[3]));

      await tester.tapAt(_animalAt(tester));
      await tester.pump();

      expect(_view(tester).selected?.name, '2026 LD3.0');
    });

    testWidgets('finds an animal the field has been spun away from', (
      tester,
    ) async {
      // The hit test and the painter have to agree about where an animal *is*
      // after a drag, not where it was seeded. They ask the same function, and
      // this is what says so from the outside.
      await _mount(tester, _sky(<double>[3]));
      await tester.dragFrom(_centre(tester) + const Offset(120, 0), const Offset(-120, 120));
      await tester.pump();

      await tester.tapAt(_animalAt(tester));
      await tester.pump();

      expect(_view(tester).selected?.name, '2026 LD3.0');
    });

    testWidgets('on empty space clears the selection', (tester) async {
      // `else {Radar.selected=null; …}` (`index.html:712`). Tapping nothing is
      // how a child puts an animal down — the one gesture that closes the card
      // without hunting for a ✕.
      await _mount(tester, _sky(<double>[3]));
      await tester.tapAt(_animalAt(tester));
      await tester.pump();
      expect(_view(tester).selected, isNotNull, reason: 'the premise');

      // Earth's own centre: the 42px inner floor means no animal can be here.
      await tester.tapAt(_centre(tester));
      await tester.pump();

      expect(_view(tester).selected, isNull);
    });

    testWidgets('a drag across an animal spins the sky instead of selecting it', (
      tester,
    ) async {
      // `moved < 8` (`index.html:691`). Without it every drag that happened to
      // start on an animal would also select it, and a child who spins the field
      // would find the card popping up over and over.
      await _mount(tester, _sky(<double>[3]));

      // Sideways across the animal, not out through it: the animal sits due east
      // of Earth, so a drag *along* that line changes the finger's bearing by
      // nothing and would spin the field by nothing — correctly, and uselessly
      // for this test.
      final TestGesture gesture = await tester.startGesture(_animalAt(tester));
      await gesture.moveBy(const Offset(0, 9));
      await gesture.up();
      await tester.pump();

      expect(_view(tester).selected, isNull);
      expect(_view(tester).viewRot, isNot(0), reason: 'it was a drag, so it spun');
    });

    testWidgets('a wander that comes back to where it started is still a drag', (
      tester,
    ) async {
      // `moved` sums |dx|+|dy| per move rather than measuring the straight line
      // home (`index.html:683`), so this 12px round trip is over budget even
      // though it ends 2px from where it began. That is the prototype's rule and
      // it is the right one: the hand was dragging.
      await _mount(tester, _sky(<double>[3]));

      final TestGesture gesture = await tester.startGesture(_animalAt(tester));
      await gesture.moveBy(const Offset(5, 0));
      await gesture.moveBy(const Offset(-5, 0));
      await gesture.moveBy(const Offset(2, 0));
      await gesture.up();
      await tester.pump();

      expect(_view(tester).selected, isNull);
    });

    testWidgets('a 4px nudge still selects — fingers are not styluses', (
      tester,
    ) async {
      // The other side of the same threshold, and the side that matters for a
      // five-year-old: a tap that slides a little is still a tap.
      await _mount(tester, _sky(<double>[3]));

      final TestGesture gesture = await tester.startGesture(_animalAt(tester));
      await gesture.moveBy(const Offset(2, 2));
      await gesture.up();
      await tester.pump();

      expect(_view(tester).selected, isNotNull);
    });

    testWidgets('a finger that rests too long is not a tap', (tester) async {
      // `< 350ms` (`index.html:691`) — the other half of the rule, and the one
      // that stops a thinking finger resting on an animal from selecting it on
      // release.
      await _mount(tester, _sky(<double>[3]));
      final Offset animal = _animalAt(tester);

      final TestGesture held = await tester.startGesture(animal);
      await held.up(timeStamp: const Duration(milliseconds: 351));
      await tester.pump();
      expect(_view(tester).selected, isNull);

      // And a hair under the same threshold does select, so the test is pinning
      // the boundary rather than just the far side of it.
      final TestGesture quick = await tester.startGesture(animal);
      await quick.up(timeStamp: const Duration(milliseconds: 349));
      await tester.pump();
      expect(_view(tester).selected, isNotNull);
    });
  });

  group('the toggle chips', () {
    testWidgets('open on the prototype\'s state', (tester) async {
      // `showHaz:false … the rest true` (`index.html:625`). The five chips are
      // there and lit as the prototype opens them: Close-flybys off, all else on.
      await _mount(tester, _sky(<double>[3]));

      for (final String label in <String>[
        '👋 Close flybys', 'Planets', 'Labels', 'Rings', 'Moon',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }

      final RadarLayers layers = _view(tester).layers;
      expect(layers.closeFlybysOnly, isFalse);
      expect(layers.planets, isTrue);
      expect(layers.labels, isTrue);
      expect(layers.rings, isTrue);
      expect(layers.moon, isTrue);
    });

    testWidgets('a tap flips one chip and leaves the others', (tester) async {
      // `Radar[k] = !Radar[k]` (`index.html:672`). Turning off the Rings must not
      // take the Moon with it.
      await _mount(tester, _sky(<double>[3]));

      await tester.tap(find.text('Rings'));
      await tester.pump();
      expect(_view(tester).layers.rings, isFalse);
      expect(_view(tester).layers.moon, isTrue);

      // And a second tap turns it back on — the chip is a plain flip.
      await tester.tap(find.text('Rings'));
      await tester.pump();
      expect(_view(tester).layers.rings, isTrue);
    });

    testWidgets('the Close-flybys chip turns the filter on', (tester) async {
      await _mount(tester, _sky(<double>[3]));
      expect(_view(tester).layers.closeFlybysOnly, isFalse);

      await tester.tap(find.text('👋 Close flybys'));
      await tester.pump();
      expect(_view(tester).layers.closeFlybysOnly, isTrue);
    });

    testWidgets('a filtered-out animal cannot be tapped', (tester) async {
      // The coupling the plan flagged: with no frame cache, the painter and the
      // hit test must be filtered by the same list or a child taps an animal that
      // is not on screen (`index.html:843`, `710`). Here the one rock is just
      // passing (1.5 Moon-distances — not a close flyby, since that is `< 1`), so
      // switching the filter on hides it, and a tap where it sits must then
      // select nothing. 1.5 rather than a far-off value keeps the animal
      // mid-field and clear of the zoom column on the right.
      await _mount(tester, _sky(<double>[1.5]));
      final Offset animal = _animalAt(tester);

      // The premise: unfiltered, tapping it selects it.
      await tester.tapAt(animal);
      await tester.pump();
      expect(_view(tester).selected, isNotNull);

      // Deselect, switch the filter on, and tap the same spot: nothing, because
      // the animal is no longer drawn there.
      await tester.tapAt(_centre(tester));
      await tester.pump();
      await tester.tap(find.text('👋 Close flybys'));
      await tester.pump();
      await tester.tapAt(animal);
      await tester.pump();
      expect(_view(tester).selected, isNull);
    });

    testWidgets('no chip anywhere says hazard', (tester) async {
      // `CLAUDE.md:64` and plan decision 2 — the radar is the one screen every
      // child opens, and it must never leak NASA's word for a close flyby.
      await _mount(tester, _sky(<double>[3]));
      expect(find.textContaining(RegExp('hazard', caseSensitive: false)), findsNothing);
    });
  });

  group('play / pause', () {
    testWidgets('freezes the orbits, and lets them go again', (tester) async {
      // `Radar.playing` (`index.html:701`, `731`) — pausing is "stop calling
      // advance", so the animals hold the phase they were at. Observed through
      // the orbit the painter is drawing rather than a private flag.
      await _mount(tester, _sky(<double>[3]));

      await tester.pump(const Duration(seconds: 1));
      final double moving = _view(tester).orbits.orbits.single.phase;
      expect(moving, greaterThan(0), reason: 'the premise: it was orbiting');

      await tester.tap(find.bySemanticsLabel('Pause the animals'));
      await tester.pump();
      final double paused = _view(tester).orbits.orbits.single.phase;

      await tester.pump(const Duration(seconds: 2));
      expect(
        _view(tester).orbits.orbits.single.phase,
        paused,
        reason: 'a paused sky holds still',
      );

      // Press play and it moves again.
      await tester.tap(find.bySemanticsLabel('Play the animals'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(_view(tester).orbits.orbits.single.phase, greaterThan(paused));
    });

    testWidgets('keeps drawing while paused — the app is not frozen', (tester) async {
      // The prototype steps the clock and calls `radarDraw` every frame, inside
      // *or* out of the pause (`index.html:730-735`). So a paused radar still
      // breathes: Earth's glow reads `ts` directly, and `ts` keeps advancing.
      await _mount(tester, _sky(<double>[3]));
      await tester.tap(find.bySemanticsLabel('Pause the animals'));
      await tester.pump();

      // At rest the glow is mid-breath at 27.5; a quarter period on (471ms) it is
      // at its 29px peak — even though nothing is orbiting.
      expect(_painter(tester), _glowRadius(closeTo(27.5, 0.05)));
      await tester.pump(const Duration(milliseconds: 471));
      expect(_painter(tester), _glowRadius(closeTo(29, 0.05)));
    });
  });
}

/// Earth, and the centre of the field.
Offset _centre(WidgetTester tester) {
  final Size size = tester.getSize(_radarCanvas());
  return Offset(size.width / 2, size.height * 0.46);
}

/// Where the sole animal of a one-rock sky currently is.
///
/// Asked of the same [RadarOrbits] the painter is drawing rather than computed
/// here, so a test taps the animal a child would see rather than one this file
/// believes in.
Offset _animalAt(WidgetTester tester) {
  final RadarPainter painter = _view(tester);
  final Size size = tester.getSize(_radarCanvas());
  return painter.orbits.positionOf(
    painter.orbits.orbits.single,
    geometry: RadarGeometry(size: size, maxLd: painter.maxLd),
    zoom: painter.zoom,
    viewRot: painter.viewRot,
  );
}

/// Two fingers, [from] apart, spread or squeezed to [to] apart, centred on the
/// field.
///
/// Both move, symmetrically, because the prototype measures only the gap between
/// them (`radarPinch`, `index.html:704`) — a real pinch that also slides is the
/// same zoom.
///
/// **Vertical, and that is not arbitrary.** The zoom buttons run down the right
/// edge of the field and take their own taps, so a wide horizontal pinch puts a
/// fingertip on ＋ and the radar never sees it — which looks exactly like a
/// broken clamp from the outside. A pinch up the middle is clear of them.
///
/// **Centred low on the field, not on Earth**, so the upper fingertip of a wide
/// pinch clears the home overlay's top column — the wordmark, strip, and toggle
/// chips, which take their own taps the same way the zoom buttons do. The zoom
/// is a function of the gap alone (`radarPinch`, `index.html:704`), so where on
/// the field it happens is immaterial; only that both fingertips reach the
/// canvas.
Future<void> _pinch(
  WidgetTester tester, {
  required double from,
  required double to,
}) async {
  final Size size = tester.getSize(_radarCanvas());
  final Offset centre = Offset(size.width / 2, size.height * 0.62);
  final TestGesture top = await tester.startGesture(centre - Offset(0, from / 2));
  final TestGesture bottom = await tester.startGesture(centre + Offset(0, from / 2));

  await top.moveTo(centre - Offset(0, to / 2));
  await bottom.moveTo(centre + Offset(0, to / 2));
  await top.up();
  await bottom.up();
  await tester.pump();
}

Future<void> _mount(WidgetTester tester, AsteroidFeed feed) async {
  tester.view
    ..physicalSize = const Size(390, 700)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        asteroidFeedProvider.overrideWith((Ref ref) => feed),
        // The home overlay reads the day streak; standing a number in front of
        // it keeps these radar tests off a Hive box, the same way the feed
        // override keeps them off a repository.
        dayStreakProvider.overrideWithValue(0),
      ],
      child: const MaterialApp(home: RadarView()),
    ),
  );
  // The override resolves a frame later; the radar only ever builds behind the
  // loading gate, so `requireValue` would throw before this.
  await tester.pump();
}

/// The radar's own canvas.
///
/// **Named by its painter rather than found by position.** This used to be
/// `find.byType(CustomPaint).last`, which was true right up until the field grew
/// its zoom buttons: a `Material` paints its own ink through a `CustomPaint`, so
/// `.last` silently became a button's and every assertion below started reading
/// an empty canvas.
Finder _radarCanvas() => find.byWidgetPredicate(
  (Widget w) => w is CustomPaint && w.painter is RadarPainter,
);

RenderBox _painter(WidgetTester tester) =>
    tester.renderObject<RenderBox>(_radarCanvas());

/// The distance rings: the paths the painter drew **around Earth**.
///
/// **The centre filter is what makes this the rings and not "the paths".** The
/// planet backdrop draws underneath the field and Saturn's three ring arcs are
/// `drawPath`s too, so a raw `drawPath` count answers 8 where the legend has 5.
/// A distance ring is a circle centred on Earth; Saturn is 460px from there.
List<Path> _ringPaths(WidgetTester tester) {
  final Offset centre = _centre(tester);
  final List<Path> paths = <Path>[];
  final Matcher collector = (paints
    ..something((Symbol method, List<dynamic> arguments) {
      if (method == #drawPath) {
        final Path path = arguments[0] as Path;
        if ((path.getBounds().center - centre).distance < 1) paths.add(path);
      }
      return false;
    })) as Matcher;
  collector.matches(_painter(tester), <dynamic, dynamic>{});
  return paths;
}

/// What the view is currently telling the painter to draw. The painter suite
/// owns what each of these *looks* like; this suite owns whether a child's
/// fingers can set them.
RadarPainter _view(WidgetTester tester) =>
    tester.widget<CustomPaint>(_radarCanvas()).painter! as RadarPainter;

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

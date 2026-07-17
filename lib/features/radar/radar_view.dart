import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rockimals/core/theme/palette.dart';
import 'package:rockimals/data/models/asteroid.dart';
import 'package:rockimals/features/data/providers.dart';
import 'package:rockimals/features/radar/planet_backdrop.dart';
import 'package:rockimals/features/radar/radar_clock.dart';
import 'package:rockimals/features/radar/radar_geometry.dart';
import 'package:rockimals/features/radar/radar_orbits.dart';
import 'package:rockimals/features/radar/radar_painter.dart';

/// The live approach radar — Earth, the rings around it, the Moon, and the
/// animals orbiting on them.
///
/// **The source list is every asteroid in the window, not `todayList`** — the
/// prototype's `Radar.data = asteroids.slice()` (`index.html:637`, plan
/// decision 9). The distinction is easy to get backwards and expensive when it
/// is: the home overlay's stat strip is the one surface on this screen that
/// counts today's animals, while the radar itself draws the whole three-day
/// sky. Feeding it `todayList` would quietly re-scale the field to a handful of
/// the animals it is drawing.
///
/// [asteroidsProvider] is read with `requireValue` because this only ever
/// builds behind the loading gate, which is the licence that gate exists to
/// grant (`lib/features/loading/loading_screen.dart`). That licence is now
/// load-bearing rather than theoretical: this is the Radar tab's body, so
/// anything that mounts `AppShell` with the sky still in flight builds this
/// widget into a `requireValue` on an `AsyncLoading`. In the app that cannot
/// happen — the gate builds the shell only once there is a sky — and in a test
/// it means the feed override has to be a *resolved* one, not the
/// never-completing future that stands in for a cold launch elsewhere.
class RadarView extends ConsumerWidget {
  const RadarView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<Asteroid> asteroids = ref.watch(asteroidsProvider).requireValue;

    // Sized and seeded once per load rather than per frame, matching the
    // prototype: `MAXLD` and `Radar.seeds` are both set in `homeInit()`
    // (`index.html:638-645`) and read by every frame after it.
    return _RadarField(
      maxLd: RadarGeometry.maxLdFor(asteroids),
      asteroids: asteroids,
    );
  }
}

/// The canvas, the clock that drives it (`radarLoop()`, `index.html:729`), and
/// the child's hands on it (`bindRadar()`, `index.html:675-703`).
class _RadarField extends StatefulWidget {
  const _RadarField({required this.maxLd, required this.asteroids});

  final double maxLd;
  final List<Asteroid> asteroids;

  @override
  State<_RadarField> createState() => _RadarFieldState();
}

class _RadarFieldState extends State<_RadarField>
    with SingleTickerProviderStateMixin {
  /// The frame clock, handed to the painter as its `repaint` [Listenable].
  ///
  /// **Deliberately not `setState`.** A radar that rebuilt its subtree sixty
  /// times a second would walk the element tree for a value only one `paint`
  /// reads; this way a frame is one repaint of one render object and nothing
  /// else (`CLAUDE.md:79-80`).
  final ValueNotifier<Duration> _clock = ValueNotifier<Duration>(Duration.zero);

  /// Where every animal is. Seeded once, then moved by the ticker below and read
  /// by the painter — never rebuilt, which is the point of it being mutable.
  late final RadarOrbits _orbits = RadarOrbits.seed(widget.asteroids);

  /// The scenery: six planets and the Sun (`PLANETS`, `index.html:789`). Seeded,
  /// drifted and read exactly as [_orbits] is, and for the same reasons — the
  /// prototype places them in `homeInit()` alongside the animals' seeds
  /// (`index.html:646`) and moves them on the same line of the same loop.
  ///
  /// It knows nothing about [_viewRot], deliberately: the backdrop is what the
  /// field turns *in front of*.
  late final PlanetBackdrop _backdrop = PlanetBackdrop.seed();

  /// How far this frame moves the sky — `radarLoop`'s own first line
  /// (`index.html:730`). Distinct from [_clock] above, which publishes the time
  /// itself to the painter: this measures the *step* between two of its values.
  final FrameClock _frame = FrameClock();

  /// **The order inside this callback is the whole contract with the painter.**
  /// The sky is advanced first and the clock published second, so the notify
  /// that triggers the repaint always follows the state that repaint will read.
  /// Swapped, every frame would draw the sky one frame stale.
  ///
  /// **One step, spent on both** (`index.html:730-735`) — the animals and the
  /// backdrop are moved by the same [FrameClock.step], because they are two
  /// things moving through one frame and not two clocks.
  late final Ticker _ticker = createTicker((Duration elapsed) {
    final double dt = _frame.step(elapsed);
    _orbits.advance(dt);

    // The backdrop drifts in the field's own pixels and wraps at its edge, so
    // unlike the animals it cannot move until there *is* an edge. This is the
    // prototype's own lazy answer to the same problem — `if (p.x == null) p.x =
    // Radar.W * p.xf`, checked at the top of every frame (`index.html:734`).
    final double? width = _fieldWidth;
    if (width != null) _backdrop.advance(dt, width: width);

    _clock.value = elapsed;
  });

  /// The field's width as it was last laid out, or null before it ever has been.
  ///
  /// **Read off the render object rather than through `context.size`, and the
  /// reason is that this runs in a `Ticker`.** Tickers fire in a frame's
  /// transient callbacks, which run *before* that frame's build and layout —
  /// so on the first frame after mount, and on every frame that a rotation or a
  /// resize has dirtied, `context.size` either has no size to give or throws
  /// outright for being asked while the box is marked dirty. Reading [RenderBox]
  /// directly answers with the previous frame's width instead, which is exactly
  /// the right answer: one frame of staleness in a decorative planet's drift is
  /// a third of a pixel, and nobody has ever seen it.
  double? get _fieldWidth {
    final RenderObject? box = context.findRenderObject();
    return box is RenderBox && box.hasSize ? box.size.width : null;
  }

  // ── The view transform: what the child has done to the field, as opposed to
  // what the sky is doing on its own. Both are read by the painter and by the
  // hit test, and neither touches an animal's own phase — see
  // [RadarOrbits.positionOf].

  /// `Radar.viewRot = 0` (`index.html:640`) — how far the field has been spun.
  double _viewRot = 0;

  /// `Radar.zoom = 1` (`index.html:640`) — where the field rests before anyone
  /// touches it.
  double _zoom = _restingZoom;

  /// `Radar.selected` (`index.html:640`) — the animal a child has tapped.
  ///
  /// **Deliberately this widget's own state rather than a provider.** Nothing
  /// outside the radar reads it yet; the HUD card that will (`index.html:718`,
  /// its own plan item) is a sibling in the home overlay, so that item lifts this
  /// where it can see it. Doing that now would be inventing the shape of a screen
  /// nobody has built — the speculative-helper trap this plan has paid for twice
  /// (`usingDemoKey`, `isCloseFlyby`).
  Asteroid? _selected;

  // ── Pointer bookkeeping — `Radar.pointers`, `dragAng`, `pinchDist`, `moved`,
  // `downT`, `downXY` (`index.html:627`).
  //
  // **Raw [Listener] rather than [GestureDetector], and the reason is the tap.**
  // A `GestureDetector` would bring Flutter's gesture arena, whose drag slop
  // (~18 logical px) and tap rules are its own — good defaults, and *different*
  // numbers from the prototype's, which decides a tap by `moved < 8` and
  // `< 350ms` (`index.html:691`). Those two thresholds are the whole difference
  // between spinning the sky and meeting an animal, so they are ported rather
  // than approximated. `setPointerCapture` (`index.html:677`) has no port and
  // needs none: Flutter routes every event of a pointer to the same path its
  // down event hit, which is what the capture is asking the browser for.

  /// Where each pointer that is currently down last was, in this widget's
  /// coordinates. Insertion-ordered, which [_pinchSpan] relies on.
  final Map<int, Offset> _pointers = <int, Offset>{};

  /// The angle of the one dragging finger, from Earth, at the last event —
  /// `null` when nothing is dragging.
  double? _dragAngle;

  /// The gap between two pinching fingers at the last event.
  double? _pinchSpanAtLastEvent;

  /// Manhattan distance travelled since the pointer went down, summed across
  /// every pointer (`index.html:683`). Compared against [_tapSlop] to tell a tap
  /// from a drag.
  double _moved = 0;

  /// When and where the gesture started (`index.html:678`).
  ///
  /// **Both are overwritten by *every* pointer going down, not just the first**,
  /// which is the prototype's own behaviour and is easy to read past: with two
  /// fingers on the glass, "where the gesture started" is where the *second* one
  /// landed. It only shows up in gestures too gentle to be a pinch and too
  /// multi-fingered to be a tap, and the `_pointers.length == 1` clause in
  /// [_onPointerUp] is what keeps those from selecting an animal mid-gesture.
  ///
  /// [_downAt] is the event's own timestamp rather than a wall clock. It is
  /// what `performance.now()` is in the prototype — time as the framework
  /// measured it, not as `DateTime.now()` would guess it — and it means the
  /// 350ms rule can be tested by handing a release a timestamp instead of by
  /// sleeping through it.
  Duration _downAt = Duration.zero;
  Offset? _downPosition;

  /// The field's geometry right now. Cheap — it is two divisions and a `min` —
  /// and derived rather than stored so it cannot disagree with the size the
  /// painter is handed.
  RadarGeometry get _geometry =>
      RadarGeometry(size: context.size!, maxLd: widget.maxLd);

  /// Where a point is, as an angle around Earth (`index.html:680`).
  double _angleOf(Offset at) {
    final Offset center = _geometry.center;
    return math.atan2(at.dy - center.dy, at.dx - center.dx);
  }

  /// The gap between the first two fingers down — `radarPinch()`
  /// (`index.html:704-705`).
  ///
  /// *First two*, not "the two": a third finger landing on the field is ignored
  /// rather than changing which pair is measured, because `Radar.pointers` is a
  /// `Map` and the prototype reads `[...values()][0]` and `[1]` off it. Dart's
  /// `Map` iterates in insertion order too, so the port is the same pair.
  double? _pinchSpan() {
    if (_pointers.length < 2) return null;
    final Iterator<Offset> points = _pointers.values.iterator;
    final Offset first = (points..moveNext()).current;
    final Offset second = (points..moveNext()).current;
    return (first - second).distance;
  }

  void _onPointerDown(PointerDownEvent event) {
    _pointers[event.pointer] = event.localPosition;
    _moved = 0;
    _downAt = event.timeStamp;
    _downPosition = event.localPosition;

    if (_pointers.length == 1) _dragAngle = _angleOf(event.localPosition);
    if (_pointers.length == 2) _pinchSpanAtLastEvent = _pinchSpan();
  }

  void _onPointerMove(PointerMoveEvent event) {
    final Offset? previous = _pointers[event.pointer];
    if (previous == null) return;

    // `+=`, and across every pointer at once (`index.html:683`). It is a
    // budget for how much the hand has *wandered*, not how far it has got: a
    // finger that goes out 50px and comes back to where it started has moved
    // 100, and meant to drag.
    _moved += (event.localPosition.dx - previous.dx).abs() +
        (event.localPosition.dy - previous.dy).abs();
    _pointers[event.pointer] = event.localPosition;

    if (_pointers.length == 1 && _dragAngle != null) {
      // Rotation is the *change* in the finger's angle around Earth, so the
      // animal under the fingertip stays under it however far round the field
      // it is dragged. There is no slop to overcome first: the sky answers the
      // first pixel of movement.
      final double angle = _angleOf(event.localPosition);
      final double delta = angle - _dragAngle!;
      _dragAngle = angle;
      setState(() => _viewRot += delta);
    } else if (_pointers.length == 2) {
      final double span = _pinchSpan()!;
      // `if(Radar.pinchDist)` (`index.html:689`) — JS truthiness, so this skips
      // a `null` *and* a zero. The zero is not pedantry: two fingertips reported
      // at the same point would otherwise divide by it and hand `zoom` a NaN,
      // and a NaN zoom is a blank radar that never comes back.
      final double? was = _pinchSpanAtLastEvent;
      if (was != null && was != 0) {
        setState(() => _zoom = _clampZoom(_zoom * span / was));
      }
      _pinchSpanAtLastEvent = span;
    }
  }

  /// **The tap is decided before the pointer is forgotten** (`index.html:691`),
  /// which is why this reads `_pointers.length` first: the finger lifting is
  /// still down at this instant, so `== 1` means it was the only one on the
  /// glass. A pinch never selects an animal, however still the fingers were.
  void _onPointerUp(PointerUpEvent event) {
    final bool tap = _moved < _tapSlop &&
        (event.timeStamp - _downAt) < _tapWindow &&
        _pointers.length == 1;
    _endGesture(event.pointer);

    // The *down* point, not the up (`index.html:693`). They are within 8px of
    // each other by the test above, so this is not about accuracy: it is that a
    // child aims when they put their finger down.
    final Offset? at = _downPosition;
    if (tap && at != null) _hit(at);
  }

  void _onPointerCancel(PointerCancelEvent event) => _endGesture(event.pointer);

  /// Both halves of the gesture state are cleared on *any* pointer leaving, not
  /// just the last (`index.html:692`, `694`). So lifting one finger of a pinch
  /// leaves the other one resting rather than snapping the sky round to it: the
  /// remaining finger cannot drag until it is lifted and put back down, which is
  /// [_dragAngle] being `null` doing exactly its job.
  void _endGesture(int pointer) {
    _pointers.remove(pointer);
    _dragAngle = null;
    _pinchSpanAtLastEvent = null;
  }

  /// A tap that landed: select the animal under it, or clear the selection if
  /// the tap was on open space (`radarHit`, `index.html:707-713`).
  void _hit(Offset at) {
    final RadarOrbit? under = _orbits.hitTest(
      at,
      geometry: _geometry,
      zoom: _zoom,
      viewRot: _viewRot,
    );
    setState(() => _selected = under?.asteroid);
  }

  /// The ＋ and − buttons (`index.html:697-698`).
  void _zoomBy(double factor) =>
      setState(() => _zoom = _clampZoom(_zoom * factor));

  /// ⤢ — **the reset puts the rotation back too**, not just the zoom
  /// (`index.html:699`). A child who has spun the field round and lost Earth
  /// under their thumb has one button that gives them the sky they opened the
  /// app to. It deliberately leaves [_selected] alone: it is a way home, not a
  /// way to lose the animal you were looking at.
  void _resetView() => setState(() {
    _zoom = _restingZoom;
    _viewRot = 0;
  });

  @override
  void initState() {
    super.initState();
    // Runs from mount. Stopping it when the Radar tab is not the visible one is
    // its own item, and a real one: the shell holds the tabs in an
    // `IndexedStack`, which hides a child without stopping its tickers.
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The canvas and the buttons are siblings, exactly as the prototype's
    // `#radarCv` and `.rzoom` are (`index.html:277-288`) — and that is what
    // keeps them out of each other's way. A `Stack` hit-tests its children
    // front-to-back and stops at the first one it lands in, so a tap on ＋ never
    // reaches the [Listener] underneath and cannot also deselect an animal. The
    // buttons being *inside* the pointer handling is the bug this shape rules
    // out rather than guards against.
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Listener(
          // The canvas is a wall: every pointer that lands anywhere on the
          // field is the radar's, including on empty space, because a tap on
          // nothing is what deselects.
          //
          // The default `deferToChild` happens to do the same thing here, and
          // for a reason too subtle to rest on: `RenderCustomPaint.hitTestSelf`
          // is `_painter != null && (_painter!.hitTest(position) ?? true)`, so a
          // canvas is hit-testable purely because nobody overrode
          // `CustomPainter.hitTest`. This says the thing directly instead — the
          // field's reach should not be a side effect of a default in a class
          // this file does not own.
          behavior: HitTestBehavior.opaque,
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerCancel,
          // The radar repaints every frame and the home overlay that lands on
          // top of it does not, so it gets its own layer rather than dragging
          // the overlay's text through sixty re-records a second.
          child: RepaintBoundary(
            child: CustomPaint(
              painter: RadarPainter(
                clock: _clock,
                orbits: _orbits,
                backdrop: _backdrop,
                maxLd: widget.maxLd,
                zoom: _zoom,
                viewRot: _viewRot,
                selected: _selected,
              ),
              // Fills the tab. With no child, `CustomPaint` takes the largest
              // size its constraints allow.
              size: Size.infinite,
              // Every frame is different, so there is nothing here worth the
              // raster cache trying to hold on to.
              willChange: true,
            ),
          ),
        ),
        _ZoomControls(
          onIn: () => _zoomBy(_zoomInStep),
          onOut: () => _zoomBy(_zoomOutStep),
          onReset: _resetView,
        ),
      ],
    );
  }
}

/// The ＋ − ⤢ column down the right of the field (`.rzoom`,
/// `index.html:283-288`).
///
/// **The prototype's play button belongs in this column too** (`index.html:284`)
/// and is not here: it is the "toggle chips and play/pause" item's, which owns
/// the whole idea of a stopped sky. It slots in above the ＋.
///
/// Vertically centred rather than at the top, because the radar *is* the home
/// view and `#view-today .rzoom` overrides `top:10px` to `top:50%` with a
/// `translateY(-50%)` (`index.html:199`) — the top-right corner is where the
/// home overlay's title and stat strip go.
class _ZoomControls extends StatelessWidget {
  const _ZoomControls({
    required this.onIn,
    required this.onOut,
    required this.onReset,
  });

  final VoidCallback onIn;
  final VoidCallback onOut;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.only(right: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // The glyphs are `＋ － ⤢` and mean nothing to a screen reader, so
            // each says in words what it does — the nav's `Semantics(button:
            // true)` precedent, which the accessibility item will hold the whole
            // app to.
            _ZoomButton(glyph: '＋', label: 'Zoom in', onTap: onIn),
            const SizedBox(height: _zoomButtonGap),
            _ZoomButton(glyph: '－', label: 'Zoom out', onTap: onOut),
            const SizedBox(height: _zoomButtonGap),
            _ZoomButton(glyph: '⤢', label: 'Reset the view', onTap: onReset),
          ],
        ),
      ),
    );
  }
}

class _ZoomButton extends StatelessWidget {
  const _ZoomButton({
    required this.glyph,
    required this.label,
    required this.onTap,
  });

  final String glyph;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: SizedBox.square(
        dimension: _zoomButtonSize,
        child: Material(
          color: _zoomButtonSurface,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(10)),
            side: BorderSide(color: Palette.line),
          ),
          child: InkWell(
            borderRadius: const BorderRadius.all(Radius.circular(10)),
            onTap: onTap,
            child: Center(
              child: ExcludeSemantics(
                child: Text(
                  glyph,
                  style: const TextStyle(
                    fontSize: 17,
                    color: Color(0xFFFFFFFF),
                    height: 1,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `width:38px;height:38px` (`index.html:177`, and `:200` for the home view's
/// square play button).
///
/// Comfortably past the 44px minimum? No — and that is the accessibility item's
/// to answer for the whole app rather than this file's to decide alone. Noted
/// here because it is the prototype's number and it is under the bar.
const double _zoomButtonSize = 38;

/// `gap:6px` (`index.html:176`).
const double _zoomButtonGap = 6;

/// `rgba(19,42,77,.85)` (`index.html:177`) — `--card` at .85, the same
/// translucent chrome the toggle chips and the home strip are made of.
///
/// **`backdrop-filter:blur(4px)` is not ported, and this is the decision the
/// toggle-chips item should reuse.** Every one of these panels asks the browser
/// to blur what is behind it; Flutter's `BackdropFilter` does the same and costs
/// a `saveLayer` over the region beneath it, *per frame*, on a screen that is
/// already redrawing sixty times a second (`CLAUDE.md:80`). What it buys here is
/// close to nothing: the thing being blurred is deep space and a few one-pixel
/// dashed rings, under a fill that is already 85% opaque. The blur is a browser
/// idiom for making chrome legible over busy content, and this content is not
/// busy.
final Color _zoomButtonSurface = Palette.card.withValues(alpha: 0.85);

/// `Radar.zoom = 1` (`index.html:625`, `640`) — where the field rests before
/// anyone touches it, and what ⤢ puts it back to.
const double _restingZoom = 1;

/// `clamp(…, 0.35, 6.5)` (`index.html:689`, `697-698`) — the framed range
/// `specs/02-live-radar.md:34` asks for, so the field can never be flung
/// somewhere a child cannot get back from. Out at 0.35 the whole sky is on
/// screen; in at 6.5 the animals crowding the inner floor come apart far enough
/// to tap one.
const double _minZoom = 0.35;
const double _maxZoom = 6.5;

double _clampZoom(double zoom) => zoom.clamp(_minZoom, _maxZoom);

/// `×1.45` in, `×0.69` out (`index.html:697-698`) — near-inverses (1.45 × 0.69 =
/// 1.0005), so ＋ then − lands back where it started rather than drifting.
const double _zoomInStep = 1.45;
const double _zoomOutStep = 0.69;

/// A tap is a gesture that wandered less than 8px and was over inside 350ms
/// (`index.html:691`).
///
/// **Both bounds exist to protect the drag, not the tap.** The field spins from
/// the first pixel of movement, so without the slop every tap would also nudge
/// the sky, and without the time limit a finger resting on an animal while the
/// child thinks — then sliding off — would still select it on release.
const double _tapSlop = 8;
const Duration _tapWindow = Duration(milliseconds: 350);

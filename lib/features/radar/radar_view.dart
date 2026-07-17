import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rockimals/core/animals/animal_system.dart';
import 'package:rockimals/core/theme/palette.dart';
import 'package:rockimals/data/models/asteroid.dart';
import 'package:rockimals/data/models/asteroid_feed.dart';
import 'package:rockimals/features/data/providers.dart';
import 'package:rockimals/features/detail/detail_screen.dart';
import 'package:rockimals/features/radar/planet_backdrop.dart';
import 'package:rockimals/features/radar/radar_clock.dart';
import 'package:rockimals/features/radar/radar_focus.dart';
import 'package:rockimals/features/radar/radar_geometry.dart';
import 'package:rockimals/features/radar/radar_layers.dart';
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
class _RadarField extends ConsumerStatefulWidget {
  const _RadarField({required this.maxLd, required this.asteroids});

  final double maxLd;
  final List<Asteroid> asteroids;

  @override
  ConsumerState<_RadarField> createState() => _RadarFieldState();
}

class _RadarFieldState extends ConsumerState<_RadarField>
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
  ///
  /// **[_playing] gates the movement, not the frame** — the prototype steps the
  /// clock outside its `if (Radar.playing)` guard and calls `radarDraw` every
  /// frame regardless (`index.html:730-735`). So pausing is "stop calling
  /// advance": [_orbits] and [_backdrop] are accumulators, so a step skipped is a
  /// step never taken and the sky simply holds still, while [_clock] keeps
  /// publishing — Earth's glow keeps breathing and the planets keep bobbing off
  /// `ts`, because "paused" means the sky has stopped *going* anywhere, not that
  /// the app has frozen. Stepping [_frame] even while paused is what stops the
  /// frame play is pressed on from being a clamped 50ms lurch (see [FrameClock]).
  late final Ticker _ticker = createTicker((Duration elapsed) {
    final double dt = _frame.step(elapsed);
    if (_playing) {
      _orbits.advance(dt);

      // The backdrop drifts in the field's own pixels and wraps at its edge, so
      // unlike the animals it cannot move until there *is* an edge. This is the
      // prototype's own lazy answer to the same problem — `if (p.x == null) p.x =
      // Radar.W * p.xf`, checked at the top of every frame (`index.html:734`).
      final double? width = _fieldWidth;
      if (width != null) _backdrop.advance(dt, width: width);
    }

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

  /// `Radar.selected` (`index.html:640`) — the animal a child has tapped, and
  /// what the [_SelectedAnimalCard] slides up to name.
  ///
  /// **Still this widget's own state, not a provider, and now for a concrete
  /// reason rather than a deferred one.** The card that reads it is a sibling in
  /// this same [build], so the selection never has to leave the widget that owns
  /// the field — the only thing that ever changes it is a tap on the canvas this
  /// state also owns. A provider would put it where the shell or another tab
  /// could reach in, which nothing needs to; the Show-on-radar action (task 03)
  /// crosses tabs the other way, by pushing a *new* selection *into* the radar,
  /// and will lift this only if and when it has to.
  Asteroid? _selected;

  /// Which of the five toggle chips are on (`Radar.showHaz`/`showLabels`/
  /// `showRings`/`showMoon`/`showPlanets`, `index.html:625`). Starts on the
  /// prototype's opening state — Close-flybys off, the rest on — and is flipped
  /// a chip at a time by [_toggle].
  RadarLayers _layers = const RadarLayers();

  /// `Radar.playing` (`index.html:625`). Whether the sky is *moving* — a paused
  /// radar keeps drawing and keeps breathing (see the ticker below), it just
  /// stops orbiting. Starts true; the play/pause button flips it.
  bool _playing = true;

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
      // The Close-flybys chip hides some animals, and a hidden animal must not
      // answer a tap — the hit test walks the same filtered list the painter
      // draws (`index.html:843`, `710`).
      onlyCloseFlybys: _layers.closeFlybysOnly,
    );
    setState(() => _selected = under?.asteroid);
  }

  /// Flip one chip's layer (`Radar[k] = !Radar[k]`, `index.html:672`).
  void _toggle(RadarLayer layer) =>
      setState(() => _layers = _layers.toggle(layer));

  /// The play/pause button (`index.html:701`): freeze the sky where it is, or
  /// let it move again.
  void _togglePlay() => setState(() => _playing = !_playing);

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

  /// **Show-on-radar's radar half** (`openRadarFocus` → `radarSelect`,
  /// `index.html:657`; `specs/03-meet-animal.md:23`): a focus request from the
  /// detail screen selects [asteroid] and puts the field back to its resting
  /// view, so the animal a child picked lands on screen and selected.
  ///
  /// **The view reset is the plan's addition, not the prototype's.**
  /// `openRadarFocus` only selects; it leaves whatever zoom and rotation the
  /// child last left the field at, which can have the selection sitting off
  /// screen. Putting [_zoom] and [_viewRot] back — the ⤢ reset ([_resetView]),
  /// minus keeping the selection — is what makes "lands with the animal
  /// visible" true rather than merely likely.
  ///
  /// The animal is looked up in the field's own list by designation (the
  /// asteroid's identity everywhere, plan decision 12) so the painter — which
  /// highlights by [Asteroid.name] — and the HUD card select the same instance
  /// the radar is drawing. It falls back to the request's own asteroid if the
  /// designation is somehow not in the current window, which keeps the card up
  /// even in that off-nominal case.
  void _focusOnRadar(Asteroid asteroid) {
    final Asteroid target = widget.asteroids.firstWhere(
      (Asteroid a) => a.name == asteroid.name,
      orElse: () => asteroid,
    );
    setState(() {
      _selected = target;
      _zoom = _restingZoom;
      _viewRot = 0;
    });
  }

  /// The card's **Meet** button (`openDetail(a)`, `index.html:724`): push the
  /// animal's detail screen ([DetailScreen], `features/detail/detail_screen.dart`).
  ///
  /// The asteroid is passed in rather than read off [_selected] so a selection
  /// that changes between the tap and the push cannot open the wrong animal.
  void _openDetail(Asteroid asteroid) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => DetailScreen(asteroid: asteroid),
      ),
    );
  }

  /// The home overlay's Play button (`$("playBtn").onclick = openGames`,
  /// `index.html:457`): push the games hub.
  ///
  /// **A stub route until task 04 builds `lib/features/games/games_hub.dart`.**
  /// The push is real — the hub opens and comes back today, so the CTA is not a
  /// dead end on any build the radar is in — and only its destination is a
  /// placeholder. This is the same shape as [_openDetail]: task 04 swaps
  /// [_GamesStubScreen] for the real hub at this one call site, and nothing else
  /// about the button changes.
  void _openGames() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => const _GamesStubScreen(),
      ),
    );
  }

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
    // **Show-on-radar's radar half** (`specs/03-meet-animal.md:23`). The detail
    // screen publishes a focus request; this selects the animal and re-centres
    // the field ([_focusOnRadar]). Listened here rather than in [RadarView]
    // because the field owns [_selected], [_zoom] and [_viewRot]. The field is
    // always mounted in the shell's IndexedStack, so this fires even while the
    // radar is not the visible tab — by the time the shell brings the tab
    // forward the animal is already selected and the view already reset.
    ref.listen<RadarFocus?>(radarFocusProvider, (
      RadarFocus? previous,
      RadarFocus? next,
    ) {
      if (next != null) _focusOnRadar(next.asteroid);
    });

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
                layers: _layers,
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
        // The home overlay: the wordmark and streak, the stat strip, the toggle
        // chips restacked into its flow (`index.html:278-282`), and the hint
        // along the bottom. It reads static providers and does not animate, so
        // it stays off the canvas's per-frame `RepaintBoundary`. The hint gives
        // way to the selected-animal card, which takes the same bottom strip —
        // the prototype hides `#rHint` while the HUD is up (`index.html:719`).
        _HomeOverlay(
          layers: _layers,
          onToggle: _toggle,
          showHint: _selected == null,
          onPlay: _openGames,
        ),
        // The selected-animal card, above the canvas so its Meet/Follow buttons
        // take their own taps rather than falling through to a deselect — the
        // same layering the zoom buttons rely on. Keyed on the designation so a
        // new selection is a new element and re-runs the slide-up, while a Follow
        // toggle (same animal, same key) rebuilds the card in place.
        if (_selected != null)
          Positioned(
            left: _homeSideGap,
            right: _homeSideGap,
            bottom: _hudBottomGap,
            child: _SelectedAnimalCard(
              key: ValueKey<String>(_selected!.name),
              asteroid: _selected!,
              onMeet: () => _openDetail(_selected!),
            ),
          ),
        _ZoomControls(
          playing: _playing,
          onPlayPause: _togglePlay,
          onIn: () => _zoomBy(_zoomInStep),
          onOut: () => _zoomBy(_zoomOutStep),
          onReset: _resetView,
        ),
      ],
    );
  }
}

/// The row of toggle chips (`.rchips` / `radarChips()`, `index.html:281`,
/// `669-672`).
///
/// **Now the third row of the home overlay's top column**, below the wordmark
/// and the stat strip, which is where the prototype restacks them for the home
/// view (`#view-today .rchips{position:static}`, `index.html:198`). Until the
/// overlay landed they were a positioned top-left overlay of their own; that
/// position was always a placeholder for this one.
///
/// A [Wrap] rather than a [Row] because five chips plus their padding can be
/// wider than a narrow phone, and the prototype's `flex-wrap:wrap`
/// (`index.html:173`) lets them spill onto a second line rather than overflow.
class _RadarChips extends StatelessWidget {
  const _RadarChips({required this.layers, required this.onToggle});

  final RadarLayers layers;
  final ValueChanged<RadarLayer> onToggle;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: _chipGap,
      runSpacing: _chipGap,
      children: <Widget>[
        for (final RadarLayer layer in RadarLayer.values)
          _RadarChip(
            label: layer.label,
            on: layers.isOn(layer),
            onTap: () => onToggle(layer),
          ),
      ],
    );
  }
}

/// The home overlay laid over the radar (`.homeTop` + `.rhint2`,
/// `index.html:278-287`): the brand row, the stat strip, and the toggle chips
/// stacked down the top-left, with the drag/pinch/tap hint along the bottom.
///
/// A [ConsumerWidget] because the strip and the flame are data — today's
/// animals, the closest approach, the close-flyby count, and the day streak.
/// It reads them behind the loading gate, so [AsyncValue.requireValue] is safe
/// for the same reason [RadarView] uses it: nothing builds this until there is a
/// sky (see the class doc on [RadarView]).
///
/// It carries the chips' [layers] and [onToggle] through rather than reading
/// them, because those are the field's own mutable state, not the feed's — the
/// same split [RadarView] keeps between what the sky is doing and what the child
/// has done to the view.
class _HomeOverlay extends ConsumerWidget {
  const _HomeOverlay({
    required this.layers,
    required this.onToggle,
    required this.showHint,
    required this.onPlay,
  });

  final RadarLayers layers;
  final ValueChanged<RadarLayer> onToggle;

  /// Whether the drag/pinch/tap hint is shown. Off while the selected-animal
  /// card is up, which sits in the same bottom strip (`index.html:719`).
  final bool showHint;

  /// Tapping the Play CTA (`$("playBtn").onclick = openGames`,
  /// `index.html:457`) — pushes the games hub. Carried through from
  /// [_RadarFieldState] rather than pushed here so the navigation stays with the
  /// widget that owns the route, next to [_RadarFieldState._openDetail].
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<Asteroid> today = ref.watch(todayListProvider).requireValue;
    final FeedProvenance provenance = ref.watch(provenanceProvider).requireValue;
    final int streak = ref.watch(dayStreakProvider);

    return SafeArea(
      // The bottom inset is the nav bar's, and the Scaffold above already keeps
      // the radar body clear of it; taking it again here would float the hint a
      // whole nav-bar's height off the bottom.
      bottom: false,
      child: Stack(
        children: <Widget>[
          Positioned(
            top: _homeTopGap,
            left: _homeSideGap,
            right: _homeSideGap,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _BrandRow(streak: streak),
                const SizedBox(height: _homeRowGap),
                _StatStrip(today: today, provenance: provenance),
                const SizedBox(height: _homeRowGap),
                _RadarChips(layers: layers, onToggle: onToggle),
              ],
            ),
          ),
          if (showHint)
            const Positioned(
              left: 0,
              right: 0,
              bottom: _hintBottomGap,
              child: _RadarHint(),
            ),
          // The persistent Play CTA along the very bottom (`.homeCTA`,
          // `index.html:196`, `291`) — shown whether or not an animal is
          // selected, exactly as the prototype keeps it beneath both the hint
          // and the HUD. It is the full-width hero button the hint and the
          // selected-animal card both clear by sitting a strip above it.
          Positioned(
            left: _homeSideGap,
            right: _homeSideGap,
            bottom: _ctaBottomGap,
            child: _PlayCta(onTap: onPlay),
          ),
        ],
      ),
    );
  }
}

/// The brand row: the sun dot, the **ROCKIMALS** wordmark (plan decision 5 — not
/// the prototype's `ASTEROID WATCH`, `index.html:279`), and the streak pill
/// pushed to the far end.
class _BrandRow extends StatelessWidget {
  const _BrandRow({required this.streak});

  final int streak;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        const _BrandDot(),
        const SizedBox(width: 9),
        const Text(
          'ROCKIMALS',
          style: TextStyle(
            // `.brandrow b` — 14px, `letter-spacing:1px`, bold, on the body
            // `--ink` (`index.html:41`, `9`).
            color: Palette.ink,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
            height: 1,
          ),
        ),
        const Spacer(),
        _StreakPill(streak: streak),
      ],
    );
  }
}

/// The little sun beside the wordmark (`.dot`, `index.html:40`) — a 24px orange
/// orb with the prototype's off-centre radial gradient and a soft glow. Purely
/// decorative, so its colours stay local literals rather than joining [Palette]
/// (the same membership test the palette's own doc sets out).
class _BrandDot extends StatelessWidget {
  const _BrandDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        // `radial-gradient(circle at 32% 30%, #ffd9a8, #b5651d 55%, #6b3a12)`.
        gradient: RadialGradient(
          center: Alignment(-0.36, -0.4),
          radius: 0.9,
          colors: <Color>[Color(0xFFFFD9A8), Color(0xFFB5651D), Color(0xFF6B3A12)],
          stops: <double>[0, 0.55, 1],
        ),
        // `box-shadow:0 0 16px rgba(232,87,31,.6)` — `--accent` at .6 (0x99).
        boxShadow: <BoxShadow>[
          BoxShadow(color: Color(0x99E8571F), blurRadius: 16),
        ],
      ),
    );
  }
}

/// The streak flame (`.streakpill` / `#homeStreak`, `index.html:42`, `279`).
///
/// Shows the persisted consecutive-days-played count (plan decision 3), which is
/// **not** the prototype's demo `streak`: that seeded at 3 and counted Challenge
/// reveals. A fresh install's first launch reads `🔥 1`, its store default of 0
/// having been advanced by the launch itself ([DayStreak]).
class _StreakPill extends StatelessWidget {
  const _StreakPill({required this.streak});

  final int streak;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: streak == 1 ? '1 day streak' : '$streak day streak',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: Palette.card,
          borderRadius: const BorderRadius.all(Radius.circular(20)),
          border: Border.all(color: Palette.line),
        ),
        child: ExcludeSemantics(
          child: Text(
            '🔥 $streak',
            style: const TextStyle(
              color: Palette.accent2,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}

/// The slim stat strip (`.homeStrip` / `updateHomeOverlay`, `index.html:190`,
/// `450-458`): three chips over `todayList` — the one `todayList`-based surface
/// on this screen (plan decision 9) — for the animals visiting, the closest
/// approach, and the close-flyby count.
class _StatStrip extends StatelessWidget {
  const _StatStrip({required this.today, required this.provenance});

  final List<Asteroid> today;
  final FeedProvenance provenance;

  @override
  Widget build(BuildContext context) {
    // `[...todayList].sort(...)[0]` (`index.html:452`) — the nearest approach in
    // today's sky. `<=` keeps the earlier rock on a tie, matching a stable sort
    // taking `[0]`. `todayList` is never empty behind the gate: the fallback
    // seeds seven and the live path pads to at least one.
    final Asteroid closest = today.reduce(
      (Asteroid a, Asteroid b) => a.missLunar <= b.missLunar ? a : b,
    );
    // `todayList.filter(a=>a.hazardous||a.missLunar<1)` (`index.html:453`) —
    // read through `flybyTag` so the count and the chips agree on what "close"
    // means (plan decision 2).
    final int flybys =
        today.where((Asteroid a) => flybyTag(a) == FlybyTag.closeFlyby).length;

    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: <Widget>[
        _HomeChip(
          spoken: '${today.length} animals visiting ${_spokenWhen(provenance)}',
          child: _chipText(
            '🐾 ',
            '${today.length}',
            ' visiting ${_visitingSuffix(provenance)}',
            warn: false,
          ),
        ),
        _HomeChip(
          spoken: 'Closest comes ${distLabel(closest.missLunar)}',
          child: _chipText('📏 closest ', distLabel(closest.missLunar), '',
              warn: false),
        ),
        _HomeChip(
          // The `warn` treatment when the count is non-zero (`index.html:456`) —
          // still a gentle "👋 close flyby", never a hazard (`CLAUDE.md:64`).
          warn: flybys > 0,
          spoken: '$flybys close ${flybys == 1 ? 'flyby' : 'flybys'}',
          child: _chipText(
            '👋 ',
            '$flybys',
            ' close flyby${flybys == 1 ? '' : 's'}',
            warn: flybys > 0,
          ),
        ),
      ],
    );
  }
}

/// The `${usingFallback?'(sample)':'today'}` ternary (`index.html:454`) grown to
/// the three [FeedProvenance] cases (the strip-copy plan item). A `switch` with
/// no default, so a fourth sky could not slip through untranslated.
///
/// `earlier` says **"recently"** — a friendlier form than a raw date, honest for
/// a window `AsteroidRepository` bounds to a few days old, and free of the raw
/// designation the strip-copy item asks to keep off this surface.
String _visitingSuffix(FeedProvenance provenance) => switch (provenance) {
  FeedProvenance.today => 'today',
  FeedProvenance.earlier => 'recently',
  FeedProvenance.sample => '(sample)',
};

/// The same three cases said for a screen reader, where the visual `(sample)`
/// parentheses would be read aloud as punctuation.
String _spokenWhen(FeedProvenance provenance) => switch (provenance) {
  FeedProvenance.today => 'today',
  FeedProvenance.earlier => 'recently',
  FeedProvenance.sample => 'in the sample sky',
};

/// One strip chip's text (`.hchip`, `index.html:44-45`): a muted base with its
/// number in white, or — when [warn] — the base in the soft red the prototype
/// uses for a non-zero close-flyby count, the number still white.
Widget _chipText(String prefix, String strong, String suffix,
    {required bool warn}) {
  return Text.rich(
    TextSpan(
      style: TextStyle(
        color: warn ? _homeChipWarnInk : _homeChipInk,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        height: 1,
      ),
      children: <InlineSpan>[
        TextSpan(text: prefix),
        // `.hchip b{color:#fff}` — the number stays white even inside a warn
        // chip, so the count reads first.
        TextSpan(text: strong, style: const TextStyle(color: _homeChipStrong)),
        TextSpan(text: suffix),
      ],
    ),
  );
}

/// One pill of the stat strip (`.hchip`, `index.html:45`) — the translucent card
/// chrome the toggle chips and zoom buttons share, at the strip's own .82 alpha,
/// with the soft-red border when [warn].
///
/// [spoken] carries the chip's meaning in words so a screen reader is not left
/// sounding out `🐾` and `👋`; the visual glyphs are excluded from semantics,
/// the pattern the nav, the toggle chips, and the zoom buttons all follow.
class _HomeChip extends StatelessWidget {
  const _HomeChip({
    required this.child,
    required this.spoken,
    this.warn = false,
  });

  final Widget child;
  final String spoken;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: spoken,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: _homeStripSurface,
          borderRadius: const BorderRadius.all(Radius.circular(14)),
          border: Border.all(color: warn ? _homeChipWarnBorder : Palette.line),
        ),
        child: ExcludeSemantics(child: child),
      ),
    );
  }
}

/// The drag/pinch/tap hint along the bottom (`.rhint2` / `#rHint`,
/// `index.html:196`, `287`).
///
/// **"tap an animal", softened from the prototype's "tap a rock"** — the whole
/// point of Rockimals is that the rocks are animals (`CLAUDE.md`). Non-
/// interactive, matching the prototype's `pointer-events:none`, so an animal
/// drifting under it stays tappable.
class _RadarHint extends StatelessWidget {
  const _RadarHint();

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: Text(
        'rings = distance vs the 🌙 Moon · drag · pinch · tap an animal',
        textAlign: TextAlign.center,
        style: TextStyle(color: Palette.muted, fontSize: 10.5, height: 1.2),
      ),
    );
  }
}

/// The home view's big Play button (`.homeCTA` > `.btn`, `index.html:196`,
/// `291`, `52`): the full-width call to action that opens the games hub.
///
/// **This is the prototype's full-width `.btn` in the one place it belongs — a
/// hero CTA — so it carries the soft orange halo the card's smaller buttons drop
/// (see [_HudButton]).** `box-shadow:0 8px 22px rgba(232,87,31,.32)` is cheap
/// here: this button sits on the static home overlay, off the canvas's per-frame
/// [RepaintBoundary], so the shadow is rasterised once rather than sixty times a
/// second.
///
/// The label glyph is decoration, so it is excluded from semantics and the
/// button's meaning is spoken in words — the same pattern the nav, the chips,
/// and the zoom buttons all follow.
class _PlayCta extends StatelessWidget {
  const _PlayCta({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Play, 4 games',
      child: DecoratedBox(
        decoration: BoxDecoration(
          // `linear-gradient(180deg, var(--accent2), var(--accent))`
          // (`index.html:52`) — top to bottom, lighter orange into the accent.
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[Palette.accent2, Palette.accent],
          ),
          borderRadius: const BorderRadius.all(Radius.circular(14)),
          boxShadow: <BoxShadow>[
            // `0 8px 22px rgba(232,87,31,.32)` — `--accent` at .32 alpha (0x52).
            BoxShadow(
              color: Palette.accent.withValues(alpha: 0.32),
              offset: const Offset(0, 8),
              blurRadius: 22,
            ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: const BorderRadius.all(Radius.circular(14)),
            onTap: onTap,
            child: const Padding(
              // `padding:14px` (`index.html:52`). The enclosing [Positioned]
              // gives the button its full width, so the padded [Text] receives a
              // tight width and `textAlign` centres it — no [Center] wrapper,
              // which an unbounded-height [Positioned] child would over-run.
              padding: EdgeInsets.all(14),
              child: ExcludeSemantics(
                child: Text(
                  '🎮 Play · 4 games',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    // `.btn` — `color:#1a0d05`, `font-weight:800`,
                    // `letter-spacing:.3px`, `font-size:15px` (`index.html:51-52`).
                    color: Palette.onAccent,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
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

/// The selected-animal HUD card (`.rhud` / `radarSelect`, `index.html:181-183`,
/// `715-726`): the card that slides up from the bottom when a child taps an
/// animal, naming it and offering **Meet** and **Follow**.
///
/// A [ConsumerWidget] because the Follow button both reads and writes the
/// persisted follow set ([followsProvider]) — the one thing on this card that
/// changes without a new selection, so its label has to track the set live. The
/// stats are all pure functions of the [asteroid] and never change under it.
///
/// The slide-up is the prototype's `hudup` keyframe (`index.html:180`):
/// `translateY(8px) → 0` with `opacity 0 → 1` over 200ms. It plays once per
/// selection because [RadarView] keys the card on the designation, so a new
/// animal is a new element and re-runs it, while a Follow toggle rebuilds in
/// place. There is no exit animation, matching the prototype's instant
/// `display:none` on deselect.
class _SelectedAnimalCard extends ConsumerWidget {
  const _SelectedAnimalCard({
    super.key,
    required this.asteroid,
    required this.onMeet,
  });

  final Asteroid asteroid;
  final VoidCallback onMeet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Critter c = critter(asteroid);
    final bool following = ref.watch(followsProvider).contains(asteroid.name);

    return TweenAnimationBuilder<double>(
      // One shared tween instance, not a fresh one per build: a
      // [TweenAnimationBuilder] restarts whenever its tween changes by `==`, and
      // `Tween` has no value equality, so building a new one each time would
      // replay the slide on every Follow toggle. Reused, the slide plays only
      // when the card is a new element — a new selection (see the key in
      // [RadarView]).
      tween: _slideTween,
      duration: const Duration(milliseconds: 200),
      curve: Curves.ease,
      builder: (BuildContext context, double t, Widget? child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, 8 * (1 - t)), child: child),
      ),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _hudSurface,
          borderRadius: const BorderRadius.all(Radius.circular(14)),
          border: Border.all(color: Palette.line),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // `.rn` — the name row. The flyby badge is pushed to the far end by
            // `margin-left:auto` (`index.html:721`), which an [Expanded] name
            // reproduces: it fills the row and left-aligns, so the badge ends at
            // the right edge whatever the name's own width, and a long name
            // ellipsises rather than shoving the badge off.
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '${c.animal.emoji} ${c.name}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Palette.ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      height: 1,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  flybyTag(asteroid).label,
                  style: const TextStyle(
                    color: Palette.muted,
                    fontSize: 12,
                    height: 1,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            // `.rm` — the five-field stat line (`index.html:722`). Every field
            // reads through the AnimalSystem's single-source formatters, so the
            // card cannot phrase a size, distance, or power differently from the
            // detail screen or the games.
            Text(
              '${sizeLabel(asteroid.diaMax)} · ${asteroid.diaMax.round()} m wide'
              ' · comes ${distLabel(asteroid.missLunar)}'
              ' · zooms ${asteroid.velKps.toStringAsFixed(1)} km/s'
              ' · power ⭐ ${powerStars(asteroid)}',
              style: const TextStyle(
                color: Palette.muted,
                fontSize: 12,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 10),
            // `.ra` — the actions (`index.html:723`). Meet is personalised with
            // the animal's first name; Follow shows whether it is already in the
            // watchlist.
            Row(
              children: <Widget>[
                _HudButton(label: 'Meet ${c.first}', onTap: onMeet),
                const SizedBox(width: 8),
                _HudButton(
                  label: following ? '✓ Following' : '⭐ Follow',
                  ghost: true,
                  onTap: () =>
                      ref.read(followsProvider.notifier).toggle(asteroid.name),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A small pill button, filled or [ghost] (`.btn.sm` / `.btn.sm.ghost`,
/// `index.html:51-56`). Filled is the accent2 → accent vertical gradient on the
/// dark [Palette.onAccent] glyph; ghost is transparent on [Palette.ink] with a
/// [Palette.line] border.
///
/// **The `.btn` box-shadow is not ported here.** On the card it would throw a
/// soft orange halo onto the translucent HUD over a live radar — the same
/// per-frame cost `_zoomButtonSurface` declines the backdrop blur for, on a
/// surface that is chrome, not a hero CTA. The Play button (its own item) is the
/// prototype's full-width `.btn`, and is where that shadow belongs.
class _HudButton extends StatelessWidget {
  const _HudButton({
    required this.label,
    required this.onTap,
    this.ghost = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool ghost;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: ghost
              ? null
              : const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[Palette.accent2, Palette.accent],
                ),
          borderRadius: const BorderRadius.all(Radius.circular(11)),
          border: ghost ? Border.all(color: Palette.line) : null,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: const BorderRadius.all(Radius.circular(11)),
            onTap: onTap,
            child: Padding(
              // `padding:9px 16px` (`index.html:55`).
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              child: Text(
                label,
                style: TextStyle(
                  color: ghost ? Palette.ink : Palette.onAccent,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3,
                  height: 1,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A placeholder for the games hub until task 04 builds
/// `lib/features/games/games_hub.dart` (`specs/04-games.md`, the "Build the Play
/// hub" item).
///
/// The Play CTA pushes this so the route exists and returns today; task 04
/// replaces the destination in [_RadarFieldState._openGames]. Titled **"Play"**,
/// matching the prototype's games overlay header (`.otitle`, `index.html:323`),
/// and kid-toned rather than "not implemented" (`CLAUDE.md:63`) — but none of
/// this copy is load-bearing, since the screen is deleted whole by task 04.
class _GamesStubScreen extends StatelessWidget {
  const _GamesStubScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.pageBackground,
      appBar: AppBar(
        backgroundColor: Palette.pageBackground,
        foregroundColor: Palette.ink,
        title: const Text('Play'),
      ),
      body: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('🎮', style: TextStyle(fontSize: 72)),
            SizedBox(height: 12),
            Text(
              'Four games are on their way — coming soon!',
              style: TextStyle(color: Palette.muted, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

/// One pill (`.rchip`, `index.html:174-175`).
///
/// Lit when [on]: the accent fill and dark glyph the app uses everywhere for
/// "this is selected" (`.rchip.on`, `index.html:175`); otherwise the translucent
/// card the zoom buttons and the home strip share. A [Semantics] `toggled` so a
/// screen reader announces the chip's state, not just its name — the nav's
/// `Semantics(button:)` precedent, one layer on.
class _RadarChip extends StatelessWidget {
  const _RadarChip({required this.label, required this.on, required this.onTap});

  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      toggled: on,
      label: label,
      child: Material(
        color: on ? Palette.accent : _chipSurface,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(16)),
          side: BorderSide(color: on ? Palette.accent : Palette.line),
        ),
        child: InkWell(
          borderRadius: const BorderRadius.all(Radius.circular(16)),
          onTap: onTap,
          child: Padding(
            // `padding:5px 10px` (`index.html:174`).
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: ExcludeSemantics(
              child: Text(
                label,
                style: TextStyle(
                  // `color:var(--muted)` off, `#1a0d05` on (`index.html:174-175`).
                  color: on ? Palette.onAccent : Palette.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The ⏸ ＋ − ⤢ column down the right of the field (`.rzoom`,
/// `index.html:283-288`).
///
/// **The play/pause button leads the column** (`index.html:284`, `rPlay` above
/// the ＋), because stopping the sky is the control a child reaches for first —
/// the others are all about *where* they are looking, this one is about whether
/// the looking has to keep up.
///
/// Vertically centred rather than at the top, because the radar *is* the home
/// view and `#view-today .rzoom` overrides `top:10px` to `top:50%` with a
/// `translateY(-50%)` (`index.html:199`) — the top-right corner is where the
/// home overlay's title and stat strip go.
class _ZoomControls extends StatelessWidget {
  const _ZoomControls({
    required this.playing,
    required this.onPlayPause,
    required this.onIn,
    required this.onOut,
    required this.onReset,
  });

  final bool playing;
  final VoidCallback onPlayPause;
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
            // `⏸` while the sky moves, `▶` once it is stopped (`index.html:701`) —
            // the glyph shows the action the tap performs' opposite, i.e. the
            // state it is in, so the label is what actually says what pressing
            // does.
            _ZoomButton(
              glyph: playing ? '⏸' : '▶',
              label: playing ? 'Pause the animals' : 'Play the animals',
              onTap: onPlayPause,
            ),
            const SizedBox(height: _zoomButtonGap),
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

/// `rgba(19,42,77,.85)` (`index.html:174`) — the same translucent card the zoom
/// buttons use, which is why an unlit chip and a zoom button read as the same
/// chrome. `backdrop-filter:blur(4px)` is dropped for the reason spelled out on
/// [_zoomButtonSurface].
final Color _chipSurface = Palette.card.withValues(alpha: 0.85);

/// `gap:6px` between chips (`index.html:173`).
const double _chipGap = 6;

/// The home overlay's own metrics (`.homeTop` / `.homeStrip` / `.rhint2`,
/// `index.html:190-196`). `_homeTopGap` is small because the enclosing
/// [SafeArea] already clears the status bar the prototype's fixed frame did not
/// have.
const double _homeTopGap = 10;
const double _homeSideGap = 12;
const double _homeRowGap = 8;

/// Where the Play CTA rests from the bottom of the field (`.homeCTA` `bottom:14`,
/// `index.html:196`). The button beneath everything else on the home view.
const double _ctaBottomGap = 14;

/// Where the drag/pinch/tap hint sits — a strip **above** the Play CTA, matching
/// the prototype's `.rhint2{bottom:73px}` (`index.html:197`) clearing the
/// `.homeCTA` at `bottom:14`. Shares the strip with the selected-animal card
/// ([_hudBottomGap]); the two never show together (`showHint = _selected ==
/// null`), so one number places both.
const double _hintBottomGap = 70;

/// Where the selected-animal card rests from the bottom of the field
/// (`#view-today .rhud{bottom:70px}`, `index.html:201`). It takes the same strip
/// the hint does, a step above the persistent Play CTA — the prototype floats
/// the HUD clear of its own `.rbottom` play/pause bar, and this port keeps the
/// card clear of the Play CTA the same way (play/pause itself having moved to the
/// zoom column).
const double _hudBottomGap = 70;

/// `.rhud` fill — `rgba(12,26,50,.95)` (`index.html:181`), a heavier, more
/// opaque panel than the chips' translucent card because the card carries the
/// most reading on the screen and sits over a moving field. `.95` alpha rounds
/// to 242 (`0xF2`). A one-off literal, so it stays local rather than joining
/// [Palette]. `backdrop-filter:blur(6px)` is dropped for the reason on
/// [_zoomButtonSurface].
const Color _hudSurface = Color(0xF20C1A32);

/// The card's slide-up (`hudup`, `index.html:180`): `translateY(8px) → 0` with
/// `opacity 0 → 1`. Held as one instance so a Follow toggle's rebuild does not
/// restart it — see the note at its use in [_SelectedAnimalCard].
final Tween<double> _slideTween = Tween<double>(begin: 0, end: 1);

/// `.hchip` fill — `rgba(19,42,77,.82)` (`index.html:45`), `--card` at the
/// strip's own alpha, a shade heavier than the toggle chips' .85.
final Color _homeStripSurface = Palette.card.withValues(alpha: 0.82);

/// `.hchip.warn` border — `rgba(240,82,82,.4)` (`index.html:47`), `--bad` at .4.
final Color _homeChipWarnBorder = Palette.bad.withValues(alpha: 0.4);

/// `.hchip` text — `#cddcf5` (`index.html:45`). A one-off literal, so it stays
/// local rather than joining [Palette].
const Color _homeChipInk = Color(0xFFCDDCF5);

/// `.hchip.warn` text — `#ff9a9a` (`index.html:47`).
const Color _homeChipWarnInk = Color(0xFFFF9A9A);

/// `.hchip b` — `#fff` (`index.html:46`), the number that reads first.
const Color _homeChipStrong = Color(0xFFFFFFFF);

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

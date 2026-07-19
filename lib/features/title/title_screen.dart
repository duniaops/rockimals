/// The Rockimals title screen — the app's front door
/// (`title.html`, `specs/06-title-polish-safety.md:15-18`).
///
/// **What moved when this landed: the app now opens here, not on the loading
/// gate.** `main.dart`'s `home` was [LoadingGate] and is now [TitleScreen]; Play
/// (or a tap anywhere) replaces this route with the gate, which is unchanged and
/// still owns "Contacting NASA…" and the shell behind it. Nothing about the boot
/// sequence in `bootstrap()` changed — the store is still open before the first
/// frame, so the title paints against a live store like every other screen.
///
/// **And one thing that would otherwise have got slower: the sky.** [LoadingGate]
/// is what *starts* the feed load, by watching it. Putting a screen in front of
/// the gate would therefore have moved the start of the request from the first
/// frame to the child's tap — turning every second spent admiring Rusty into a
/// second not spent loading, and adding the whole round trip *after* the tap.
/// [_TitleScreenState.initState] reads [asteroidFeedProvider] instead, so the
/// request is already in flight while the title is on screen and the gate it
/// hands over to has usually already resolved. [asteroidFeedProvider] is
/// deliberately not `autoDispose` (see its own docs: one load per process), so
/// the in-flight future survives this route being replaced — that property is
/// load-bearing here, not incidental.
///
/// **The trap that grew a third half.** The plan already warns that mounting the
/// app in a test starts a real network load. It is now *this* screen that starts
/// it rather than the gate, so a test that pumps `RockimalsApp` or [TitleScreen]
/// and overrides nothing builds a live Dio at mount. Override
/// [asteroidFeedProvider]; unlike under the shell, a never-completing future is
/// fine here, because nothing on this screen reads the value.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rockimals/core/mascot/rusty.dart';
import 'package:rockimals/core/theme/palette.dart';
import 'package:rockimals/features/data/providers.dart';
import 'package:rockimals/features/loading/loading_screen.dart';
import 'package:rockimals/features/settings/calm_motion.dart';

/// The prototype's screen, in CSS pixels: `.phone` is 380×780 with a 12px border
/// and the page's global `box-sizing:border-box` (`title.html:8, 14`), so the
/// `.screen` inside it is 356×756.
///
/// Every absolute position in `title.html` is measured against this box, and the
/// backdrop below scales those numbers to whatever a real phone is — positions
/// as fractions of each axis, radii as a fraction of the width, so a taller
/// screen spreads the scenery out rather than stretching the rings into ellipses.
const Size kPrototypeScreen = Size(356, 756);

class TitleScreen extends ConsumerStatefulWidget {
  const TitleScreen({super.key});

  @override
  ConsumerState<TitleScreen> createState() => _TitleScreenState();
}

class _TitleScreenState extends ConsumerState<TitleScreen> {
  /// Whether the handover has already been asked for.
  ///
  /// Two taps a frame apart — the Play button and the "tap anywhere" surface
  /// under a thumb that rolled, or simply an excited four-year-old — would
  /// otherwise push two routes and leave a second, dead loading gate underneath
  /// the first, watching the same feed.
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    // Warm the sky. See the library doc above: this is why the title costs
    // nothing, and it is a `read` rather than a `watch` because nothing here
    // renders the result — the gate does, one route later.
    ref.read(asteroidFeedProvider);
    // And stamp which day that sky is for, here, while the answer is still the
    // day it was asked on. A resume compares against this stamp to decide
    // whether the child has crossed midnight; created lazily at that resume
    // instead — it is nothing else's dependency — it would stamp *then* and
    // report a two-day-old sky as today's. See `skyDayProvider`'s own docs.
    ref.read(skyDayProvider);
  }

  /// Play, or a tap anywhere (`title.html:131-132`).
  ///
  /// [Navigator.pushReplacement] rather than a push: a splash a child can swipe
  /// back to is not a splash. Android's back gesture from the radar then leaves
  /// the app, which is what a home screen should do.
  void _start() {
    if (_leaving) return;
    _leaving = true;
    Navigator.of(context).pushReplacement<void, void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => const LoadingGate(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // `.screen`'s last gradient stop, so an overscroll or a rotation mid-frame
      // shows space rather than white.
      backgroundColor: _skyFloor,
      body: GestureDetector(
        // "tap anywhere to start" is a promise about the *whole* screen,
        // including the parts with nothing drawn on them.
        behavior: HitTestBehavior.opaque,
        // **But not a promise to a screen reader.** An opaque, screen-sized tap
        // target publishes one enormous node, and the framework merges every
        // label on the screen into it: the app's name, its tagline and its
        // attribution are announced as a single run-on sentence, and the Play
        // button is the only thing left with an edge. "Tap anywhere" is a
        // sighted affordance and is not discoverable without sight anyway —
        // Play is, and it is a real labelled button. So the gesture stays and
        // its semantics do not.
        excludeFromSemantics: true,
        onTap: _start,
        child: DecoratedBox(
          decoration: const BoxDecoration(gradient: _skyGradient),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              const _StarField(),
              // Rings, planets and the two friends already in orbit
              // (`title.html:63-68`) — painted rather than laid out as widgets,
              // because they are scenery with no semantics: a screen reader
              // announcing "rabbit, elephant" over the app's front door would be
              // reading the wallpaper aloud.
              const CustomPaint(painter: _BackdropPainter()),
              _TitleContent(onStart: _start),
            ],
          ),
        ),
      ),
    );
  }
}

// ── The content column ───────────────────────────────────────────────────────

/// The three blocks `.screen` spaces apart: wordmark, mascot, buttons
/// (`title.html:16, 70-134`).
///
/// [onStart] is threaded down to the Play button rather than left to the
/// screen-wide [GestureDetector] that would also catch it. The button works
/// either way today, and a button that only worked because something behind it
/// was listening is one refactor from silence.
class _TitleContent extends StatelessWidget {
  const _TitleContent({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        // `.screen{padding:66px 26px 36px}` (`title.html:16`) — but the 66 is
        // measured from the top of a *simulated* phone whose notch is 26px tall
        // (`title.html:15`), so 40 of it is real clearance and 26 of it is the
        // notch. [SafeArea] already inset the real one, so re-adding 66 here
        // would double-count it and push the wordmark down a notch's worth on
        // every device.
        padding: const EdgeInsets.fromLTRB(26, 40, 26, 36),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            const _Wordmark(),
            // Rusty is the one block with slack in it. On a short screen, or at
            // a large system text scale, `scaleDown` shrinks the mascot instead
            // of overflowing the column — the failure it prevents is a yellow
            // stripe across the app's front door, on exactly the devices least
            // likely to be tested.
            const Flexible(
              child: FittedBox(fit: BoxFit.scaleDown, child: _Mascot()),
            ),
            _Bottom(onStart: onStart),
          ],
        ),
      ),
    );
  }
}

/// `R⬤CKIMALS` — the wordmark, with an asteroid for its O (`title.html:71-72`).
class _Wordmark extends StatelessWidget {
  const _Wordmark();

  /// `.w2{font-size:46px;font-weight:900;letter-spacing:2px;color:#fff;
  /// text-shadow:0 3px 0 rgba(0,0,0,.3)}` (`title.html:37`). `.3×255 = 76.5`,
  /// which Chrome rounds to 77 (`0x4D`); `blurRadius` stays 0, so it is a hard
  /// drop shadow and not a glow.
  static const TextStyle _letters = TextStyle(
    fontSize: 46,
    fontWeight: FontWeight.w900,
    letterSpacing: 2,
    color: Color(0xFFFFFFFF),
    shadows: <Shadow>[Shadow(offset: Offset(0, 3), color: Color(0x4D000000))],
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        // **The one block that must never be clipped, and nearly was.** At 46px
        // the wordmark is ~300px wide, which fits the prototype's 356px screen
        // with its 26px gutters and does *not* fit a 360dp phone, or any phone
        // at a large system text scale — a first render at 390dp put the tail of
        // "CKIMALS" over the edge with the overflow stripe to prove it. Bounded
        // by the screen and scaled down to suit, rather than trusting a number
        // measured against one hard-coded viewport.
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            children: <Widget>[
              // **One label for the three widgets that spell it.** A screen reader
              // walking this tree unaided reads "R", then a circle it cannot describe,
              // then "CKIMALS" — the app introducing itself by spelling its name
              // wrong. `excludeSemantics` drops those three and puts one name in their
              // place, which keeps the O an asteroid rather than making it a letter.
              // Not `const`: `Semantics` builds its properties in the initializer
              // list, so its constructor is not one.
              Semantics(
                label: 'Rockimals',
                header: true,
                // A node of its own. Without it this is an *annotation* on whatever
                // node encloses the wordmark, so the name would be glued to the front
                // of the next thing on the screen rather than announced as the name.
                container: true,
                excludeSemantics: true,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text('R', style: _letters),
                    // `.oo{margin:0 2px;position:relative;top:2px}`
                    // (`title.html:38-39`).
                    Padding(
                      padding: EdgeInsets.fromLTRB(2, 2, 2, 0),
                      child: _AsteroidO(),
                    ),
                    Text('CKIMALS', style: _letters),
                  ],
                ),
              ),
              // `.sub{margin-top:8px}` (`title.html:40`).
              const SizedBox(height: 8),
              const Text(
                // `title.html:72`, verbatim. The `·` is the prototype's.
                'SPACE · ANIMALS',
                style: TextStyle(
                  fontSize: 12,
                  letterSpacing: 5,
                  // `#ff9f43` — a one-off in `title.html` and named by nothing, so it
                  // stays here rather than joining `Palette`, whose membership test is
                  // that the prototype named it.
                  color: Color(0xFFFF9F43),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The glowing rock standing in for the O (`title.html:38-39`).
class _AsteroidO extends StatelessWidget {
  const _AsteroidO();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: _cssLightPoint,
          radius: kCssFarthestCorner,
          // `#ffd9a8` → `#e8571f` at 55% → `#8f3a12`. The middle stop is
          // `--accent` itself, which is why the app's one interactive colour is
          // also the first thing on its front door.
          colors: <Color>[Color(0xFFFFD9A8), Palette.accent, Color(0xFF8F3A12)],
          stops: <double>[0, 0.55, 1],
        ),
        boxShadow: <BoxShadow>[
          // `box-shadow:0 0 18px rgba(232,87,31,.7)` (`title.html:39`).
          // `.7×255 = 178.5 → 179 (0xB3)`. The 18 is the prototype's number
          // kept as written; CSS and Flutter parameterise blur differently
          // (CSS's radius is ~2σ, Flutter's is ~1.73σ), so this reads a little
          // softer than Chrome rather than a little harder — the safe direction
          // for a glow.
          BoxShadow(color: Color(0xB3E8571F), blurRadius: 18),
        ],
      ),
    );
  }
}

/// Rusty and his line (`title.html:75-128`).
class _Mascot extends ConsumerWidget {
  const _Mascot();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _Bob(calm: calmMotionOf(context, ref), child: const Rusty()),
        // `.mid{gap:12px}` (`title.html:42`).
        const SizedBox(height: 12),
        const SizedBox(
          // `.tagline{max-width:240px}` (`title.html:45`).
          width: 240,
          child: Text(
            // `title.html:127`, verbatim.
            'Meet your fuzzy little space-rock friends! 🦊',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              height: 1.4,
              color: Color(0xFFFFE4CC),
            ),
          ),
        ),
      ],
    );
  }
}

/// `.float` — 13px up and back down, forever, on a 3.6s ease-in-out
/// (`title.html:43-44`).
///
/// **This is the one thing on the screen Calm motion stops.** It is travel — the
/// mascot leaves and returns to his position — and it never ends, which is the
/// combination `specs/06-title-polish-safety.md:25`'s setting exists for. The
/// starfield's twinkle is left running for the reason the plan gives for Earth's
/// glow: an opacity that breathes in place is not movement across a screen, and
/// a title that froze into a still photograph would read as a crash on the one
/// screen a child sees before anything works.
///
/// **The controller is driven from [didUpdateWidget], not from `build`.**
/// `calmMotionOf` needs a `BuildContext`, so the setting can only be read in a
/// build — but `AnimationController.value = 0` notifies its listeners, and doing
/// that from the build of a widget those listeners are already mounted under is
/// how a "setState during build" assertion happens. Taking the answer as a
/// parameter moves the mutation to the frame *before* the child rebuilds, where
/// it is legal and obvious.
class _Bob extends StatefulWidget {
  const _Bob({required this.calm, required this.child});

  final bool calm;
  final Widget child;

  @override
  State<_Bob> createState() => _BobState();
}

class _BobState extends State<_Bob> with SingleTickerProviderStateMixin {
  /// Half of `3.6s`, because [AnimationController.repeat] with `reverse: true`
  /// plays the return leg itself. The CSS keyframes are `0%,100%{0} 50%{-13px}`,
  /// so one controller period is one half of one CSS iteration.
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  /// `translateY(-13px)` against Rusty's 206px height — [SlideTransition] works
  /// in fractions of the child, so the bob keeps its proportions when
  /// [FittedBox] shrinks him on a small screen.
  late final Animation<Offset> _offset =
      Tween<Offset>(
        begin: Offset.zero,
        end: Offset(0, -13 / kRustySize.height),
      ).animate(
        // `ease-in-out`, and symmetric, so the same curve serves the return leg.
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      );

  @override
  void initState() {
    super.initState();
    if (!widget.calm) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_Bob oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.calm == oldWidget.calm) return;
    if (widget.calm) {
      _controller.stop();
      // Settled at rest rather than stopped wherever the tap landed — a mascot
      // frozen mid-hop looks broken, which is the opposite of calm.
      _controller.value = 0;
    } else {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      SlideTransition(position: _offset, child: widget.child);
}

/// Play, the tap hint, and the NASA attribution (`title.html:130-134`).
class _Bottom extends StatelessWidget {
  const _Bottom({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _PlayButton(onStart: onStart),
        // `.bot{gap:11px}` (`title.html:47`).
        const SizedBox(height: 11),
        const Text(
          // `title.html:132`, verbatim — and true: [TitleScreen]'s
          // [GestureDetector] is opaque over the whole screen.
          'tap anywhere to start',
          style: TextStyle(fontSize: 11, color: Color(0xFFC7A98D)),
        ),
        const SizedBox(height: 11),
        const Text(
          // `title.html:133`, verbatim — and the app's NASA attribution, which
          // `specs/06-title-polish-safety.md:60` requires before release. It
          // says "powered by", not "by NASA": the fuller
          // "not affiliated with NASA" line lives in Settings' About block,
          // where a grown-up will read it.
          '🚀 powered by real NASA space data',
          style: TextStyle(fontSize: 11, color: Color(0xFF9DB2D3)),
        ),
      ],
    );
  }
}

/// `.playbtn` (`title.html:48-49, 131`).
///
/// Hand-built rather than an [ElevatedButton], for the reason the rest of this
/// app's chrome is hand-built: the fill is a vertical gradient, which no
/// `ButtonStyle` expresses, and a Material button would bring an ink ripple to
/// the one screen in the app that has no other Material furniture on it. The
/// three things a real button gives that matter — a semantic role, a comfortable
/// target, and a tap — are added explicitly instead.
class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    // `excludeSemantics` rather than a wrapper that keeps them: the label would
    // otherwise be "▶ Play", and a screen reader pronouncing a play triangle is
    // noise. `onTap` here is what keeps it *activatable* once its own gesture
    // detector is hidden — dropping the descendants would otherwise drop the
    // action with them.
    return Semantics(
      button: true,
      label: 'Play',
      excludeSemantics: true,
      onTap: onStart,
      child: GestureDetector(
        onTap: onStart,
        child: Container(
          // `padding:16px 46px` on a 19px/900 line — comfortably past the
          // 48dp minimum `specs/06-title-polish-safety.md:21` asks for, which
          // is checked rather than asserted in `title_screen_test.dart`.
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 46),
          decoration: const BoxDecoration(
            borderRadius: BorderRadius.all(Radius.circular(32)),
            gradient: LinearGradient(
              // `linear-gradient(180deg, …)` — top to bottom.
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[Color(0xFFFFA25A), Palette.accent],
            ),
            boxShadow: <BoxShadow>[
              // `0 12px 28px rgba(232,87,31,.45)` — `.45×255 = 114.75 → 115`.
              BoxShadow(
                color: Color(0x73E8571F),
                offset: Offset(0, 12),
                blurRadius: 28,
              ),
            ],
          ),
          child: const Text(
            // `title.html:131`, verbatim, glyph included.
            '▶ Play',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
              // `#2a0f03` — the prototype's own answer here, and *not*
              // `Palette.onAccent` (`#1a0d05`), which is `index.html`'s. Two
              // near-blacks on the same orange; the one written down for this
              // button is the one used.
              color: Color(0xFF2A0F03),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Scenery ──────────────────────────────────────────────────────────────────

/// `.screen`'s background:
/// `radial-gradient(120% 70% at 50% 8%, #5a3a1e 0%, #24284f 30%, #0e1b3a 60%,
/// #070f24 100%)` (`title.html:17`) — the warm sunrise at the top of the sky
/// that the wordmark sits in.
const RadialGradient _skyGradient = RadialGradient(
  // `at 50% 8%`.
  center: Alignment(0, -0.84),
  // `120%` of the width. The `70%` of the height is the other half of an
  // *ellipse*, which [RadialGradient] has no field for — see [_EllipticalSky].
  radius: 1.2,
  colors: <Color>[
    Color(0xFF5A3A1E),
    Color(0xFF24284F),
    Color(0xFF0E1B3A),
    Color(0xFF070F24),
  ],
  stops: <double>[0, 0.3, 0.6, 1],
  transform: _EllipticalSky(),
);

/// The gradient's last stop, restated for [Scaffold.backgroundColor].
const Color _skyFloor = Color(0xFF070F24);

/// Squashes [_skyGradient] into the ellipse CSS asked for.
///
/// [RadialGradient.radius] is a single fraction of the box's *shortest* side, so
/// it can only describe circles. CSS gave two radii — `120%` of the width and
/// `70%` of the height — so the vertical one is applied here as a local matrix:
/// scale y about the gradient's centre until the circle of radius `1.2·w` has
/// height `0.7·h`. A shader's matrix maps gradient space, so scaling by `k`
/// stretches the gradient by `k`; the centre is a fixed point, which is what the
/// translate terms are for.
///
/// Without this the sunrise is a circle 1.2 screen-widths across — far too tall
/// on a phone, and the warm band that should sit behind the wordmark alone would
/// wash over Rusty as well.
class _EllipticalSky extends GradientTransform {
  const _EllipticalSky();

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    // The horizontal radius the gradient will actually be built with.
    final double rx = 1.2 * bounds.shortestSide;
    if (rx == 0) return null;
    final double k = (0.7 * bounds.height) / rx;
    // `at 50% 8%`, in absolute coordinates.
    final double cy = bounds.top + bounds.height * 0.08;
    // y' = k·y + cy·(1-k): a scale by k about y = cy, with x untouched.
    return Matrix4.identity()
      ..setEntry(1, 1, k)
      ..setEntry(1, 3, cy * (1 - k));
  }
}

/// The ten fixed stars, twinkling together (`title.html:19-30`).
///
/// The whole layer's opacity oscillates between `.55` and `.95` on a 3s
/// `ease-in-out alternate`, which is one [FadeTransition] over a painter that
/// never repaints — not ten animations, and not a repaint per frame.
class _StarField extends StatefulWidget {
  const _StarField();

  @override
  State<_StarField> createState() => _StarFieldState();
}

class _StarFieldState extends State<_StarField>
    with SingleTickerProviderStateMixin {
  /// `animation: tw 3s ease-in-out infinite alternate` — 3s is one *iteration*,
  /// and `alternate` makes the return leg a second one, so the controller's
  /// period is the CSS duration and `reverse: true` supplies the rest.
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat(reverse: true);

  late final Animation<double> _twinkle = Tween<double>(
    begin: 0.55,
    end: 0.95,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _twinkle,
      child: const CustomPaint(painter: _StarPainter()),
    );
  }
}

/// One star: where it sits as a fraction of the screen, how big, and what
/// colour — `radial-gradient(1.5px 1.5px at 15% 14%, #fff, transparent)` and its
/// nine siblings (`title.html:19-29`).
typedef _Star = (double fx, double fy, double radius, Color colour);

const List<_Star> _stars = <_Star>[
  (0.15, 0.14, 1.5, _starWhite),
  (0.74, 0.10, 1.5, _starWarm),
  (0.40, 0.24, 1.3, _starWhite),
  (0.86, 0.34, 1.6, _starWhite),
  (0.25, 0.44, 1.2, _starCool),
  (0.62, 0.50, 1.4, _starWhite),
  (0.84, 0.66, 1.3, _starWhite),
  (0.12, 0.72, 1.2, _starWarm),
  (0.50, 0.86, 1.5, _starWhite),
  (0.90, 0.90, 1.3, _starWhite),
];

const Color _starWhite = Color(0xFFFFFFFF);

/// `#ffe6c0` — the two warm ones.
const Color _starWarm = Color(0xFFFFE6C0);

/// `#dfeaff` — the one cold one.
const Color _starCool = Color(0xFFDFEAFF);

class _StarPainter extends CustomPainter {
  const _StarPainter();

  @override
  void paint(Canvas canvas, Size size) {
    for (final _Star star in _stars) {
      final Offset centre = Offset(star.$1 * size.width, star.$2 * size.height);
      final double radius = star.$3;
      // Each CSS star is a radial gradient from its colour to `transparent` over
      // its full radius, not a hard dot — at 1.2–1.6px that difference is the
      // whole of how a star reads against a dark sky rather than as a speck of
      // dust, so the falloff is painted rather than approximated away.
      canvas.drawCircle(
        centre,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: <Color>[star.$4, star.$4.withAlpha(0)],
          ).createShader(Rect.fromCircle(center: centre, radius: radius)),
      );
    }
  }

  /// The stars never move; the layer above fades. Sizes change only on a
  /// rotation, which rebuilds the painter anyway.
  @override
  bool shouldRepaint(covariant _StarPainter oldDelegate) => false;

  @override
  bool hitTest(Offset position) => false;
}

/// The two dashed orbits, the two planets, and the two friends already up there
/// (`title.html:63-68`).
class _BackdropPainter extends CustomPainter {
  const _BackdropPainter();

  /// `border:1px dashed rgba(255,175,110,.16)` (`title.html:32`).
  /// `.16×255 = 40.8 → 41 (0x29)`.
  static const Color _ringColour = Color(0x29FFAF6E);

  @override
  void paint(Canvas canvas, Size size) {
    // Everything below is `title.html`'s pixel position on a 356×756 screen,
    // turned into a fraction of this one. Positions scale per axis; radii scale
    // with the width alone, so the rings stay circles.
    final double sx = size.width / kPrototypeScreen.width;
    final double sy = size.height / kPrototypeScreen.height;
    Offset at(double x, double y) => Offset(x * sx, y * sy);

    // Both rings are `left:50%` with a matching negative margin and tops of
    // 150/100 for diameters of 250/350 — i.e. concentric on (178, 275).
    final Offset orbitCentre = at(178, 275);
    final Paint ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = _ringColour;
    _dashedCircle(canvas, orbitCentre, 125 * sx, ring);
    _dashedCircle(canvas, orbitCentre, 175 * sx, ring);

    // `top:130;right:30` on a 26px circle → centre (356-30-13, 130+13). Its
    // gradient is Mars's, digit for digit (`radar/planet_painters.dart`), but it
    // is not Mars and is not drawn by that file: those painters render *named*
    // bodies with bands, rings and labels for the radar's solar-system backdrop,
    // and this is anonymous scenery that happens to be the same orange.
    _planet(
      canvas,
      at(313, 143),
      13 * sx,
      const Color(0xFFF0A878),
      const Color(0xFFD1440E),
    );
    // `bottom:150;left:-16` on a 46px circle → centre (7, 756-150-23), half of
    // it off the left edge exactly as in the prototype.
    _planet(
      canvas,
      at(7, 583),
      23 * sx,
      const Color(0xFFF4E6C4),
      const Color(0xFFC9A25A),
    );

    // `.friend{font-size:20px;opacity:.9}` at `top:180;left:38` and
    // `top:330;right:32` — the CSS positions are the glyph's top-left corner.
    _friend(canvas, '🐰', at(38, 180), sx);
    _friend(canvas, '🐘', at(304, 330), sx);
  }

  /// A 1px dashed circle, the way a browser draws one: the dash length is
  /// adjusted so a whole number of them goes round, rather than leaving a short
  /// dash butted against the start. Chrome's dash for a 1px border is about 3px
  /// on, 3px off.
  void _dashedCircle(Canvas canvas, Offset centre, double radius, Paint paint) {
    const double dash = 3;
    const double gap = 3;
    final Rect box = Rect.fromCircle(center: centre, radius: radius);
    final int count = math.max(
      1,
      (2 * math.pi * radius / (dash + gap)).round(),
    );
    final double step = 2 * math.pi / count;
    final double sweep = step * dash / (dash + gap);
    for (int i = 0; i < count; i++) {
      canvas.drawArc(box, i * step, sweep, false, paint);
    }
  }

  /// `radial-gradient(circle at 34% 30%, lit, dark)` — a lit sphere, the same
  /// two-stop idiom the radar's planets use.
  void _planet(
    Canvas canvas,
    Offset centre,
    double radius,
    Color lit,
    Color dark,
  ) {
    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..shader = RadialGradient(
          center: _cssLightPoint,
          radius: kCssFarthestCorner,
          colors: <Color>[lit, dark],
        ).createShader(Rect.fromCircle(center: centre, radius: radius)),
    );
  }

  void _friend(Canvas canvas, String emoji, Offset topLeft, double scale) {
    final TextPainter glyph = TextPainter(
      text: TextSpan(
        text: emoji,
        style: TextStyle(
          fontSize: 20 * scale,
          // `opacity:.9` → `.9×255 = 229.5 → 230 (0xE6)`. Applied to the glyph
          // rather than as a layer, for the reason `rusty.dart` gives.
          color: const Color(0xE6FFFFFF),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    glyph.paint(canvas, topLeft);
    glyph.dispose();
  }

  @override
  bool shouldRepaint(covariant _BackdropPainter oldDelegate) => false;

  @override
  bool hitTest(Offset position) => false;
}

/// `at 34% 30%` — where the light hits, for both planets and the asteroid O
/// (`title.html:39, 65-66`), in [Alignment]'s -1…1.
const Alignment _cssLightPoint = Alignment(-0.32, -0.4);

/// **CSS's default radial-gradient size is `farthest-corner`, and it is not
/// 0.5.** [RadialGradient.radius] is a fraction of the box's shortest side and
/// defaults to 0.5, which would end the gradient halfway to the edge and leave
/// every one of these shapes ringed in its darkest stop. For a light point at
/// (34%, 30%) of a square box the farthest corner is the opposite one, at
/// `√(0.66² + 0.70²) = 0.9622` of a side.
///
/// The SVG gradients in `rusty.dart` keep 0.5, and correctly: SVG's default `r`
/// really is 50%. The two formats disagree, and the port has to say which it is
/// reading each time.
const double kCssFarthestCorner = 0.9622;

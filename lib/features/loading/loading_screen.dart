import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rockimals/core/mascot/rusty.dart';
import 'package:rockimals/core/theme/palette.dart';
import 'package:rockimals/data/models/asteroid_feed.dart';
import 'package:rockimals/features/data/providers.dart';
import 'package:rockimals/features/settings/calm_motion.dart';
import 'package:rockimals/features/shell/app_shell.dart';

/// The cold-launch gate: "Contacting NASA…" until the sky is ready, then the
/// app (`index.html:1143-1145`).
///
/// **This sits above the shell rather than inside a tab, because that is what
/// the prototype does and the placement is the whole behaviour.** `.loading` is
/// `position:absolute; inset:0; z-index:50` (`index.html:165`) over the entire
/// phone — the nav included — and the boot sequence is `await loadData(); hide
/// the overlay; switchTab("today")`. So there is no moment where a child can
/// tap Sky and find it empty, and no tab needs a loading branch of its own. A
/// per-tab spinner would have been the easier port and a different app: four
/// screens each deciding what "not yet" looks like, and a nav that invites taps
/// onto them.
///
/// The consequence worth knowing: **everything behind this gate can assume the
/// feed is loaded.** That is the licence [asteroidFeedProvider]'s own docs grant
/// with `.requireValue`, and it only became true here.
///
/// It is also what starts the load. Watching [asteroidFeedProvider] is the first
/// read in the app, so the fetch begins when this builds — the prototype's
/// single `loadData()` call (`index.html:1143`), moved to the one widget whose
/// job is to wait for it.
class LoadingGate extends ConsumerWidget {
  const LoadingGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(asteroidFeedProvider)
        .when(
          loading: () => const LoadingScreen(),
          error: (Object error, StackTrace stack) => _BootBroke(error: error),
          // "Data" here is *any* sky, and the fallback is one of them: the
          // repository turns a dead network, a rate-limited key, and a feed too
          // thin to play with into the bundled sample set (spec 01 §3), so
          // offline reaches this branch exactly as a good day does. A gate that
          // held the spinner until NASA specifically answered would strand the
          // one child this app promises to keep playing.
          data: (AsteroidFeed feed) => const AppShell(),
        );
  }
}

/// Rusty, the spinner, and the line under it (`index.html:271`,
/// `specs/06-title-polish-safety.md:18`).
///
/// The mascot is the spec's addition, not the prototype's — `.loading` is only
/// the ring and the words. He stands *beside* the spinner rather than replacing
/// it: the ring is what says "still working", the one job this screen has, and
/// its motion is already pinned by this screen's tests. Rusty himself does not
/// move here — the bob is the title screen's wrapper, not his — so this surface
/// adds no new motion for the Calm-motion setting to reach. The ring does, and
/// takes it.
///
/// **A [ConsumerWidget] only so the ring can ask.** Nothing else on this screen
/// reads a provider, and the setting is resolved here rather than inside
/// [_Spinner] for the reason that widget's own doc gives: a controller cannot
/// be driven from the build of the widget whose listeners it notifies, so the
/// answer is resolved a level up and handed down as a parameter.
///
/// **A [Scaffold] rather than the [ColoredBox] this screen's contents would
/// suggest, and that is not boilerplate.** `Text` outside a [Material] silently
/// falls back to monospace, weight 900, with a yellow double underline — a
/// debug affordance that renders in release too. It was verified here rather
/// than assumed: the first draft was a `ColoredBox`, and a probe showed the
/// fallback style resolving on exactly this line. The cost is that [Scaffold]
/// brings its floating-action-button transition along with no button to
/// animate; that costs nothing at runtime but is why this screen has two
/// `RotationTransition`s in its tree and its test has to say which one it means.
class LoadingScreen extends ConsumerWidget {
  const LoadingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool calm = calmMotionOf(context, ref);

    return Scaffold(
      backgroundColor: Palette.pageBackground,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // The brand's face on the wait. A painter publishes no semantics,
            // so a screen reader hears "Contacting NASA…" alone rather than a
            // description of a fox.
            const Rusty(size: kRustyHalfSize),
            // `.loading{gap:14px}` (`index.html:165`) is a flex gap, so the
            // spec's new child inherits the same spacing as the two it joins.
            const SizedBox(height: 14),
            _Spinner(calm: calm),
            const SizedBox(height: 14),
            const Text(
              // The only words in the app a child reads before anything else,
              // and they are the prototype's verbatim. "Contacting" rather than
              // "Loading" is doing real work: it says a real telescope is being
              // asked, which is the premise the whole app rests on.
              'Contacting NASA…',
              style: TextStyle(color: Palette.muted, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

// The loading screen's palette (`index.html:165-166`). The named colours now
// come from `Palette`; this file used to keep its own copies of the page
// background, `--muted`, and `--accent`, which is what the plan's "extract the
// palette" item existed to undo.
//
// `Palette.pageBackground` is what `.loading` restates by hand
// (`index.html:165`) so that neither the starfield behind it nor the phone frame
// shows through — flat, not the body's radial gradient. It stays set explicitly
// here rather than left to the theme's `scaffoldBackgroundColor`, because the
// prototype states it explicitly too, for that reason.

/// `rgba(255,255,255,.15)` — .15 alpha is 38.25, and Chrome rounds it to 38
/// (`0x26`).
///
/// Stays local: a one-off literal, appearing exactly once in the prototype and
/// named by nothing. `Palette`'s membership test is that the prototype named it.
const Color _spinnerTrack = Color(0x26FFFFFF);

/// `width:40px;height:40px` with the page's global `box-sizing:border-box`
/// (`index.html:12`), so the 4px border is inside the 40, not added to it.
const double _spinnerSize = 40;
const double _spinnerStroke = 4;

/// `animation:spin 1s linear infinite` (`index.html:166-167`).
const Duration kSpinnerPeriod = Duration(seconds: 1);

/// The same turn under 🐢 Calm motion: five seconds, still linear, still
/// endless.
///
/// **Slowed rather than stopped, and that is the whole decision on this
/// surface** — see [kCalmDriftScale], which this divides by because a spinner's
/// period is the reciprocal of its speed. A ring at a fifth speed is
/// unmistakably still turning, so the screen keeps the one thing it is for;
/// a ring at zero says the fetch died, to a child who has no other signal on
/// the screen to contradict it and no way to retry.
///
/// Derived rather than written out as five, so it cannot drift from the factor
/// the radar turns at. `final` and not `const` only because [Duration] has no
/// const multiply.
final Duration kSpinnerCalmPeriod = Duration(
  milliseconds: (kSpinnerPeriod.inMilliseconds / kCalmDriftScale).round(),
);

/// `.spin` — a linear clockwise loop, forever (`index.html:166-167`), at
/// [kSpinnerPeriod] or [kSpinnerCalmPeriod].
///
/// Hand-rolled rather than [CircularProgressIndicator], which animates a
/// growing-and-shrinking arc and would read as a different app's spinner.
/// `CLAUDE.md:47` asks for the prototype to be ported rather than reinvented,
/// and this is a ring with one lit quarter turning at a constant rate — the
/// Material indicator is not that shape or that motion.
///
/// **[calm] arrives as a parameter rather than being read here**, the shape
/// `title_screen.dart`'s `_Bob` and the badge popup's hopping emoji both use:
/// the setting can only be read in a build, and re-driving a controller from
/// the build of the widget its listeners sit under is a "setState during build"
/// assertion. `didUpdateWidget` runs a frame earlier, where the mutation is
/// legal.
class _Spinner extends StatefulWidget {
  const _Spinner({required this.calm});

  final bool calm;

  @override
  State<_Spinner> createState() => _SpinnerState();
}

class _SpinnerState extends State<_Spinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _turns = AnimationController(
    vsync: this,
    duration: kSpinnerPeriod,
  );

  Duration get _period => widget.calm ? kSpinnerCalmPeriod : kSpinnerPeriod;

  @override
  void initState() {
    super.initState();
    _turns.repeat(period: _period);
  }

  @override
  void didUpdateWidget(_Spinner oldWidget) {
    super.didUpdateWidget(oldWidget);
    // `repeat` resumes from the controller's current value, so the ring changes
    // speed from wherever it had turned to rather than snapping back to twelve
    // o'clock. Unlike the mascot's bob there is no "at rest" to settle to here —
    // every angle of a spinner is as good as every other, and the one thing a
    // child would notice is a jump.
    if (widget.calm != oldWidget.calm) _turns.repeat(period: _period);
  }

  @override
  void dispose() {
    _turns.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // [RotationTransition] rather than a painter that reads the clock: the ring
    // never changes, only its angle, so this repaints nothing per frame and
    // just hands the same layer a new transform — the low-allocation shape
    // `CLAUDE.md:80` asks of the radar, and free here.
    return RotationTransition(
      turns: _turns,
      child: const CustomPaint(
        size: Size(_spinnerSize, _spinnerSize),
        painter: _SpinnerPainter(),
      ),
    );
  }
}

class _SpinnerPainter extends CustomPainter {
  const _SpinnerPainter();

  /// CSS paints `border-top-color` over the quarter of the ring the top border
  /// owns: 90°, centred on twelve o'clock. Flutter's zero angle is three
  /// o'clock and sweeps clockwise, so that quarter starts at -135°.
  static const double _headStart = -math.pi * 3 / 4;
  static const double _headSweep = math.pi / 2;

  @override
  void paint(Canvas canvas, Size size) {
    // A stroke straddles its path, so the path is the circle *through the
    // middle* of the border — inset by half the stroke, or the ring would be
    // drawn 4px wider than the 40px box and clipped.
    final Rect ring = (Offset.zero & size).deflate(_spinnerStroke / 2);

    final Paint stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _spinnerStroke
      ..color = _spinnerTrack;
    canvas.drawOval(ring, stroke);

    // Over the track rather than instead of it: the head is opaque, so it hides
    // the quarter beneath exactly as `border-top-color` replaces it. Drawing
    // only the other 270° in the track colour would look identical here and
    // stop looking identical the moment the head gains any transparency.
    // `--accent`, i.e. `border-top-color` (`index.html:166`) — the lit quarter.
    stroke.color = Palette.accent;
    canvas.drawArc(ring, _headStart, _headSweep, false, stroke);
  }

  @override
  bool shouldRepaint(covariant _SpinnerPainter oldDelegate) => false;
}

/// [AsteroidRepository.loadData] promises never to throw — a dead network, a
/// rate-limited key, an empty feed, and a corrupt record all resolve to the
/// bundled sample sky (spec 01 §3). So this is unreachable, and reaching it
/// means that promise broke.
///
/// **It is loud on purpose, and the two quiet alternatives are both worse.**
/// Falling through to the shell would hand every screen an [AsyncError] to
/// crash on, one at a time, far from the cause. Staying on the spinner would
/// leave a child watching a ring turn forever with nothing, anywhere, reporting
/// a problem — the exact outcome [asteroidFeedProvider]'s docs refuse. A child
/// can only ever see this if the app is already broken, and then the fastest
/// way to unbreak it is worth more than a gentle face on it.
///
/// This is now the app's **only** report of that broken promise — the task-01
/// debug screen carried the other copy and was deleted 2026-07-18. The two were
/// deliberately never factored together, which is what let that one go without
/// touching this one.
class _BootBroke extends StatelessWidget {
  const _BootBroke({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.pageBackground,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            'loadData() threw, which it promises never to do:\n\n$error',
            style: const TextStyle(color: Palette.accent, fontSize: 13),
          ),
        ),
      ),
    );
  }
}

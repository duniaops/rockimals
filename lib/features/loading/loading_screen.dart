import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rockimals/data/models/asteroid_feed.dart';
import 'package:rockimals/features/data/providers.dart';
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

/// The spinner and the line under it (`index.html:271`).
///
/// Task 06 re-skins this with Rusty the fox
/// (`specs/06-title-polish-safety.md`) and reuses it for empty states, which is
/// why it is a widget of its own rather than a branch inside [LoadingGate].
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
class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: _background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _Spinner(),
            // `gap:14px` (`index.html:165`).
            SizedBox(height: 14),
            Text(
              // The only words in the app a child reads before anything else,
              // and they are the prototype's verbatim. "Contacting" rather than
              // "Loading" is doing real work: it says a real telescope is being
              // asked, which is the premise the whole app rests on.
              'Contacting NASA…',
              style: TextStyle(color: _muted, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

// The loading screen's palette, ported from the prototype (`index.html:9-10`,
// `165-166`). Private and local, matching `app_shell.dart` — the plan item to
// hoist a shared palette is deliberately waiting for the radar or the animal
// card, which are the surfaces that can answer how the twelve CSS variables map
// onto a Flutter `ColorScheme`. This screen is the second holder of private
// colour consts and does not answer that question either; it only strengthens
// the case for the item.

/// The page background (`index.html:16`), which `.loading` restates
/// (`index.html:165`) so that neither the starfield behind it nor the phone
/// frame shows through. Flat, not the body's radial gradient.
const Color _background = Color(0xFF070F1F);

/// `--muted` (`index.html:10`).
const Color _muted = Color(0xFF93A8CA);

/// `rgba(255,255,255,.15)` — .15 alpha is 38.25, and Chrome rounds it to 38
/// (`0x26`).
const Color _spinnerTrack = Color(0x26FFFFFF);

/// `--accent` (`index.html:9`) — `border-top-color`, the one lit quarter.
const Color _spinnerHead = Color(0xFFE8571F);

/// `width:40px;height:40px` with the page's global `box-sizing:border-box`
/// (`index.html:12`), so the 4px border is inside the 40, not added to it.
const double _spinnerSize = 40;
const double _spinnerStroke = 4;

/// `.spin` — a 1s linear clockwise loop, forever (`index.html:166-167`).
///
/// Hand-rolled rather than [CircularProgressIndicator], which animates a
/// growing-and-shrinking arc and would read as a different app's spinner.
/// `CLAUDE.md:47` asks for the prototype to be ported rather than reinvented,
/// and this is a ring with one lit quarter turning at a constant rate — the
/// Material indicator is not that shape or that motion.
class _Spinner extends StatefulWidget {
  const _Spinner();

  @override
  State<_Spinner> createState() => _SpinnerState();
}

class _SpinnerState extends State<_Spinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _turns = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  )..repeat();

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
    stroke.color = _spinnerHead;
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
/// This is the app's copy of the branch the debug screen also has; when that
/// screen is deleted this becomes the only one. Not shared with it deliberately
/// — the two say different things (that one is about the screen it is in) and
/// factoring them together would point a shipping file at a doomed one.
class _BootBroke extends StatelessWidget {
  const _BootBroke({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            'loadData() threw, which it promises never to do:\n\n$error',
            style: const TextStyle(color: _spinnerHead, fontSize: 13),
          ),
        ),
      ),
    );
  }
}

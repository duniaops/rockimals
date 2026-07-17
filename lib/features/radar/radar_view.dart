import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rockimals/data/models/asteroid.dart';
import 'package:rockimals/features/data/providers.dart';
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

/// The canvas and the clock that drives it — `radarLoop()` (`index.html:729`).
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

  /// **The order inside this callback is the whole contract with the painter.**
  /// The sky is advanced first and the clock published second, so the notify
  /// that triggers the repaint always follows the state that repaint will read.
  /// Swapped, every frame would draw the sky one frame stale.
  late final Ticker _ticker = createTicker((Duration elapsed) {
    _orbits.advance(elapsed);
    _clock.value = elapsed;
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
    // The radar repaints every frame and the home overlay that lands on top of
    // it does not, so it gets its own layer rather than dragging the overlay's
    // text through sixty re-records a second.
    return RepaintBoundary(
      child: CustomPaint(
        painter: RadarPainter(
          clock: _clock,
          orbits: _orbits,
          maxLd: widget.maxLd,
          zoom: _restingZoom,
          viewRot: _restingRotation,
        ),
        // Fills the tab. With no child, `CustomPaint` takes the largest size
        // its constraints allow.
        size: Size.infinite,
        // Every frame is different, so there is nothing here worth the raster
        // cache trying to hold on to.
        willChange: true,
      ),
    );
  }
}

/// `Radar.zoom = 1` (`index.html:625`, `640`) — where the field rests before
/// anyone touches it. Constant until the interactions item makes pinch, scroll,
/// and the ± buttons drive it between 0.35 and 6.5.
const double _restingZoom = 1;

/// `Radar.viewRot = 0` (`index.html:625`, `640`) — the field unspun. Constant
/// for the same reason [_restingZoom] is: the drag handler that gives it a value
/// is the interactions item's. The painter takes it as a *required* parameter
/// even so, which is deliberate — a rotation that reaches the animals but not
/// the Moon spins the sky around a stationary Moon, and the way to make that not
/// happen is to make it not compile.
const double _restingRotation = 0;

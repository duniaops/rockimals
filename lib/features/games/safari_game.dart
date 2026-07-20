/// Radar Safari — find real animals on the live radar from their NASA facts.
library;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rockimals/core/animals/animal_system.dart';
import 'package:rockimals/core/chrome/panel.dart';
import 'package:rockimals/core/streak/day_streak.dart';
import 'package:rockimals/core/theme/palette.dart';
import 'package:rockimals/data/models/asteroid.dart';
import 'package:rockimals/features/data/providers.dart';
import 'package:rockimals/features/games/game_shell.dart';
import 'package:rockimals/features/games/safari_missions.dart';
import 'package:rockimals/features/radar/planet_backdrop.dart';
import 'package:rockimals/features/radar/radar_clock.dart';
import 'package:rockimals/features/radar/radar_geometry.dart';
import 'package:rockimals/features/radar/radar_layers.dart';
import 'package:rockimals/features/radar/radar_orbits.dart';
import 'package:rockimals/features/radar/radar_painter.dart';
import 'package:rockimals/features/settings/calm_motion.dart';

/// A no-lives exploration game: a miss teaches, then the radar stays open.
///
/// The field deliberately owns its own [RadarOrbits] instead of reimplementing
/// touch geometry. It therefore asks the exact same [RadarOrbits.hitTest] the
/// home radar uses, while keeping Safari's mission state separate from a home
/// selection card.
class SafariGame extends ConsumerStatefulWidget {
  const SafariGame({super.key});

  @override
  ConsumerState<SafariGame> createState() => _SafariGameState();
}

class _SafariGameState extends ConsumerState<SafariGame>
    with SingleTickerProviderStateMixin {
  late final List<Asteroid> _sky;
  late final RadarOrbits _orbits;
  late final List<SafariMission> _missions;
  late final Ticker _ticker = createTicker(_tick);

  final ValueNotifier<Duration> _clock = ValueNotifier<Duration>(Duration.zero);
  final FrameClock _frame = FrameClock();
  final PlanetBackdrop _backdrop = PlanetBackdrop.seed();

  int _missionIndex = 0;
  int _misses = 0;
  Asteroid? _selected;
  String? _hint;
  bool _calmMotion = false;

  SafariMission get _mission => _missions[_missionIndex];

  @override
  void initState() {
    super.initState();
    // Games launch from the shell's resolved sky, and intentionally freeze that
    // snapshot for a whole mission. A refresh must not replace the radar under
    // a child's finger or reset a Safari already in progress.
    _sky = List<Asteroid>.unmodifiable(
      ref.read(asteroidsProvider).requireValue,
    );
    _orbits = RadarOrbits.seed(_sky);
    _missions = generateSafariMissions(
      asteroids: _sky,
      dayKey: DayStreak.keyOf(ref.read(dayClockProvider)()),
    );
    _ticker.start();
  }

  void _tick(Duration elapsed) {
    _orbits.advance(_frame.step(elapsed) * (_calmMotion ? kCalmDriftScale : 1));
    _clock.value = elapsed;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _clock.dispose();
    super.dispose();
  }

  void _hit(Offset at, Size size) {
    if (_selected != null) return;
    final RadarGeometry geometry = RadarGeometry(
      size: size,
      maxLd: RadarGeometry.maxLdFor(_sky),
    );
    final RadarOrbit? orbit = _orbits.hitTest(
      at,
      geometry: geometry,
      zoom: 1,
      viewRot: 0,
      onlyCloseFlybys: false,
    );
    if (orbit == null) {
      setState(() => _hint = 'Try tapping an animal on the radar.');
      return;
    }

    final Asteroid asteroid = orbit.asteroid;
    if (_mission.accepts(asteroid)) {
      ref.read(gameReactionProvider.notifier).react(correct: true);
      setState(() {
        _selected = asteroid;
        _hint = null;
      });
      return;
    }

    ref.read(gameReactionProvider.notifier).react(correct: false);
    setState(() {
      _misses++;
      _hint = _misses >= 2
          ? 'Good exploring! Look near the ${_targetRegion(geometry)} of the radar.'
          : 'Not this animal yet — read the clue and try another one.';
    });
  }

  String _targetRegion(RadarGeometry geometry) {
    final RadarOrbit target = _orbits.orbits.firstWhere(
      (RadarOrbit orbit) => _mission.accepts(orbit.asteroid),
    );
    final Offset at = _orbits.positionOf(
      target,
      geometry: geometry,
      zoom: 1,
      viewRot: 0,
    );
    final bool top = at.dy < geometry.center.dy;
    final bool left = at.dx < geometry.center.dx;
    return '${top ? 'top' : 'bottom'} ${left ? 'left' : 'right'}';
  }

  void _nextMission() {
    if (_missionIndex == _missions.length - 1) {
      setState(() {
        _missionIndex = 0;
        _misses = 0;
        _selected = null;
      });
      return;
    }
    setState(() {
      _missionIndex++;
      _misses = 0;
      _selected = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    _calmMotion = calmMotionOf(context, ref);
    final Asteroid? selected = _selected;
    return GameShell(
      title: '🧭 Radar Safari',
      feedback: selected == null
          ? null
          : GameFeedback(
              correct: true,
              headline: '✓ You found ${critter(selected).first}!',
              explanation: _mission.supportingFact(selected),
            ),
      onNext: selected == null ? null : _nextMission,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          GameScoreBar(
            scores: <GameScore>[
              GameScore(value: '${_missionIndex + 1}', label: 'MISSION'),
              GameScore(value: '${_missions.length}', label: 'IN SAFARI'),
            ],
          ),
          Panel(
            child: Text(
              _mission.prompt,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Palette.ink,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 320,
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final Size size = constraints.biggest;
                return GestureDetector(
                  key: const ValueKey<String>('safari-radar'),
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (TapDownDetails details) =>
                      _hit(details.localPosition, size),
                  child: CustomPaint(
                    painter: RadarPainter(
                      clock: _clock,
                      orbits: _orbits,
                      backdrop: _backdrop,
                      maxLd: RadarGeometry.maxLdFor(_sky),
                      zoom: 1,
                      viewRot: 0,
                      selected: selected,
                      layers: const RadarLayers(),
                    ),
                    size: Size.infinite,
                  ),
                );
              },
            ),
          ),
          if (_hint case final String hint) ...<Widget>[
            const SizedBox(height: 12),
            Panel(
              child: Text(
                hint,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Palette.ink, height: 1.35),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

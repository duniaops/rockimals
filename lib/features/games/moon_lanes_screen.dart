/// Moon Lanes — sort real space animals by how far they miss the Moon.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rockimals/core/a11y/tap_target.dart';
import 'package:rockimals/core/animals/animal_system.dart';
import 'package:rockimals/core/chrome/action_button.dart';
import 'package:rockimals/core/chrome/panel.dart';
import 'package:rockimals/core/streak/day_streak.dart';
import 'package:rockimals/core/theme/palette.dart';
import 'package:rockimals/data/models/asteroid.dart';
import 'package:rockimals/features/data/providers.dart';
import 'package:rockimals/features/games/game_round_timer.dart';
import 'package:rockimals/features/games/game_shell.dart';
import 'package:rockimals/features/games/moon_lanes.dart';
import 'package:rockimals/features/settings/calm_motion.dart';

/// The maximum length of one Moon Lanes trip.
const Duration kMoonLanesRoundDuration = Duration(seconds: 60);

/// The gentle return motion after a lane miss.
const Duration kMoonLanesBounceDuration = Duration(milliseconds: 260);

/// Calm motion shortens the one-shot return, consistently with reactions.
const Duration kMoonLanesCalmBounceDuration = Duration(milliseconds: 130);

/// A no-lives drag game that teaches Moon-relative distances from real data.
class MoonLanesScreen extends ConsumerStatefulWidget {
  const MoonLanesScreen({super.key});

  @override
  ConsumerState<MoonLanesScreen> createState() => _MoonLanesScreenState();
}

class _MoonLanesScreenState extends ConsumerState<MoonLanesScreen>
    with SingleTickerProviderStateMixin {
  late final List<Asteroid> _deal;
  late final AnimationController _bounce = AnimationController(vsync: this);
  final MoonLanesDifficulty _difficulty = MoonLanesDifficulty();

  Timer? _ticker;
  int _dealIndex = 0;
  int _correct = 0;
  int _secondsLeft = kMoonLanesRoundDuration.inSeconds;
  bool _timeUp = false;
  GameFeedback? _feedback;

  Asteroid get _asteroid => _deal[_dealIndex % _deal.length];

  @override
  void initState() {
    super.initState();
    final List<Asteroid> sky =
        ref.read(asteroidsProvider).value ?? const <Asteroid>[];
    _deal = generateMoonLanesDeal(
      asteroids: sky,
      dayKey: DayStreak.keyOf(ref.read(dayClockProvider)()),
    );
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (mounted) unawaited(ref.read(gameActionsProvider).markPlayed());
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), _tick);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _bounce.dispose();
    super.dispose();
  }

  void _tick(Timer _) {
    if (!mounted || _timeUp || ref.read(gameRoundTimerPausedProvider)) return;
    setState(() {
      _secondsLeft--;
      if (_secondsLeft <= 0) {
        _secondsLeft = 0;
        _timeUp = true;
        _feedback = null;
      }
    });
  }

  void _drop(MoonLaneChoice choice, bool calmMotion) {
    if (_feedback != null || _timeUp) return;
    final Asteroid asteroid = _asteroid;
    final bool correct =
        moonLaneChoiceFor(
          missLunar: asteroid.missLunar,
          laneCount: _difficulty.laneCount,
        ) ==
        choice;
    _difficulty.recordDrop(correct: correct);
    ref.read(gameReactionProvider.notifier).react(correct: correct);
    if (!correct) {
      _bounce.duration = calmMotion
          ? kMoonLanesCalmBounceDuration
          : kMoonLanesBounceDuration;
      _bounce.forward(from: 0);
    }
    setState(() {
      if (correct) _correct++;
      _feedback = GameFeedback(
        correct: correct,
        headline: correct
            ? '✓ Great Moon sorting!'
            : 'Nice try — your animal bounced back!',
        explanation: correct
            ? '${critter(asteroid).first} passes ${distLabel(asteroid.missLunar)} away. '
                  'That belongs in ${choice.label}.'
            : '${critter(asteroid).first} really passes ${distLabel(asteroid.missLunar)} away. '
                  'Try another lane. There are no lives to lose.',
      );
    });
  }

  void _nextAfterFeedback() {
    if (_feedback?.correct ?? false) _dealIndex++;
    setState(() => _feedback = null);
  }

  void _playAgain() {
    _bounce.stop();
    setState(() {
      _dealIndex = 0;
      _correct = 0;
      _secondsLeft = kMoonLanesRoundDuration.inSeconds;
      _timeUp = false;
      _feedback = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool calmMotion = calmMotionOf(context, ref);
    final List<MoonLaneChoice> choices = moonLaneChoicesFor(
      _difficulty.laneCount,
    );
    final GameFeedback? feedback = _feedback;

    return GameShell(
      title: '🌙 Moon Lanes',
      feedback: feedback,
      onNext: feedback == null ? null : _nextAfterFeedback,
      body: _timeUp
          ? _RoundComplete(correct: _correct, onPlayAgain: _playAgain)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                GameScoreBar(
                  scores: <GameScore>[
                    GameScore(value: '$_correct', label: 'SORTED'),
                    GameScore(value: '${_secondsLeft}s', label: 'LEFT'),
                    GameScore(
                      value: '${_difficulty.laneCount}',
                      label: 'LANES',
                    ),
                  ],
                ),
                const Panel(
                  child: Text(
                    'Drag the space animal into the lane that matches how far it misses the Moon.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Palette.ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _MoonAnimalDraggable(
                  asteroid: _asteroid,
                  enabled: feedback == null,
                  bounce: _bounce,
                ),
                const SizedBox(height: 12),
                for (final MoonLaneChoice choice in choices) ...<Widget>[
                  _MoonLaneTarget(
                    choice: choice,
                    accepting: feedback == null,
                    onDrop: () => _drop(choice, calmMotion),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
    );
  }
}

class _RoundComplete extends StatelessWidget {
  const _RoundComplete({required this.correct, required this.onPlayAgain});

  final int correct;
  final VoidCallback onPlayAgain;

  @override
  Widget build(BuildContext context) {
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Text(
            'Moon trip complete!',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Palette.good,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'You sorted $correct ${correct == 1 ? 'animal' : 'animals'} by real Moon distance.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Palette.ink, height: 1.35),
          ),
          const SizedBox(height: 14),
          ActionButton(label: 'Take another moon trip', onTap: onPlayAgain),
        ],
      ),
    );
  }
}

class _MoonAnimalDraggable extends StatelessWidget {
  const _MoonAnimalDraggable({
    required this.asteroid,
    required this.enabled,
    required this.bounce,
  });

  final Asteroid asteroid;
  final bool enabled;
  final Animation<double> bounce;

  @override
  Widget build(BuildContext context) {
    final Critter animal = critter(asteroid);
    final Widget card = Panel(
      child: Row(
        children: <Widget>[
          Text(animal.animal.emoji, style: const TextStyle(fontSize: 42)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  animal.name,
                  style: const TextStyle(
                    color: Palette.ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                const Text(
                  'Drag me to a Moon lane',
                  style: TextStyle(color: Palette.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return AnimatedBuilder(
      animation: bounce,
      builder: (BuildContext context, Widget? child) => Transform.translate(
        key: const ValueKey<String>('moon-lanes-bounce'),
        offset: Offset(12 * (1 - bounce.value), 0),
        child: child,
      ),
      child: Draggable<Asteroid>(
        data: asteroid,
        maxSimultaneousDrags: enabled ? 1 : 0,
        feedback: Material(
          color: Colors.transparent,
          child: SizedBox(
            width: 300,
            child: Opacity(opacity: 0.9, child: card),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.35, child: card),
        child: Semantics(
          label: '${animal.name}, drag to a Moon distance lane',
          child: KeyedSubtree(
            key: const ValueKey<String>('moon-lanes-animal'),
            child: card,
          ),
        ),
      ),
    );
  }
}

class _MoonLaneTarget extends StatelessWidget {
  const _MoonLaneTarget({
    required this.choice,
    required this.accepting,
    required this.onDrop,
  });

  final MoonLaneChoice choice;
  final bool accepting;
  final VoidCallback onDrop;

  @override
  Widget build(BuildContext context) {
    return DragTarget<Asteroid>(
      onWillAcceptWithDetails: (DragTargetDetails<Asteroid> _) => accepting,
      onAcceptWithDetails: (DragTargetDetails<Asteroid> _) => onDrop(),
      builder:
          (
            BuildContext context,
            List<Asteroid?> candidates,
            List<dynamic> rejected,
          ) => Semantics(
            label: 'Drop zone: ${choice.label}',
            child: Material(
              color: candidates.isNotEmpty
                  ? Palette.accent.withValues(alpha: 0.2)
                  : Palette.card,
              shape: RoundedRectangleBorder(
                borderRadius: kPanelRadius,
                side: BorderSide(
                  color: candidates.isNotEmpty ? Palette.accent2 : Palette.line,
                  width: candidates.isNotEmpty ? 2 : 1,
                ),
              ),
              child: TapTarget(
                key: ValueKey<String>('moon-lane-${choice.name}'),
                child: SizedBox(
                  width: double.infinity,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    child: Text(
                      choice.label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Palette.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
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

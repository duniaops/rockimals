/// Flyby Snap — photograph an animal as its real-speed-inspired flight crosses
/// the camera window.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rockimals/core/animals/animal_system.dart';
import 'package:rockimals/core/chrome/action_button.dart';
import 'package:rockimals/core/chrome/panel.dart';
import 'package:rockimals/core/streak/day_streak.dart';
import 'package:rockimals/core/theme/palette.dart';
import 'package:rockimals/data/models/asteroid.dart';
import 'package:rockimals/features/data/providers.dart';
import 'package:rockimals/features/games/flyby_snap.dart';
import 'package:rockimals/features/games/game_round_timer.dart';
import 'package:rockimals/features/games/game_shell.dart';
import 'package:rockimals/features/settings/calm_motion.dart';

/// A two-attempt, no-lives speed lesson using the shared asteroid feed.
class FlybySnapScreen extends ConsumerStatefulWidget {
  const FlybySnapScreen({super.key});

  @override
  ConsumerState<FlybySnapScreen> createState() => _FlybySnapScreenState();
}

class _FlybySnapScreenState extends ConsumerState<FlybySnapScreen>
    with SingleTickerProviderStateMixin {
  late final List<Asteroid> _deal;
  late final AnimationController _flight = AnimationController(vsync: this)
    ..addStatusListener(_restartFlight);

  int _dealIndex = 0;
  int _attempt = 1;
  int _shots = 0;
  bool _timerPaused = false;
  bool _calmMotion = false;
  GameFeedback? _feedback;

  Asteroid get _asteroid => _deal[_dealIndex % _deal.length];

  @override
  void initState() {
    super.initState();
    final List<Asteroid> sky =
        ref.read(asteroidsProvider).value ?? const <Asteroid>[];
    _deal = generateFlybySnapDeal(
      asteroids: sky,
      dayKey: DayStreak.keyOf(ref.read(dayClockProvider)()),
    );
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (mounted) unawaited(ref.read(gameActionsProvider).markPlayed());
    });
  }

  @override
  void dispose() {
    _flight
      ..removeStatusListener(_restartFlight)
      ..dispose();
    super.dispose();
  }

  void _restartFlight(AnimationStatus status) {
    if (status == AnimationStatus.completed &&
        mounted &&
        !_timerPaused &&
        _feedback == null) {
      _flight.forward(from: 0);
    }
  }

  void _syncFlight({required bool paused, required bool calmMotion}) {
    final Duration nextDuration = flybySnapCrossingDuration(
      velocityKps: _asteroid.velKps,
      calmMotion: calmMotion,
    );
    final bool durationChanged = _flight.duration != nextDuration;
    _flight.duration = nextDuration;
    if (paused || _feedback != null) {
      _flight.stop(canceled: false);
      return;
    }
    if (_timerPaused || durationChanged || !_flight.isAnimating) {
      _flight.forward(from: durationChanged ? 0 : _flight.value);
    }
  }

  void _takePhoto() {
    if (_timerPaused || _feedback != null) return;
    final Asteroid asteroid = _asteroid;
    final bool correct = isFlybySnapPhotoInWindow(_flight.value);
    _flight.stop(canceled: false);
    ref.read(gameReactionProvider.notifier).react(correct: correct);
    setState(() {
      if (correct) _shots++;
      _feedback = GameFeedback(
        correct: correct,
        headline: correct
            ? '✓ Great shot!'
            : _attempt == 1
            ? 'Almost! Your photo gets one more try.'
            : 'Nice try — let’s meet another flyer!',
        explanation:
            '${critter(asteroid).first} was travelling ${speedLabel(asteroid.velKps)}. '
            'This crossing is inspired by that real speed.',
      );
    });
  }

  void _nextAfterFeedback() {
    final bool retry = !(_feedback?.correct ?? false) && _attempt == 1;
    setState(() {
      if (retry) {
        _attempt = 2;
      } else {
        _dealIndex++;
        _attempt = 1;
      }
      _feedback = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool paused = ref.watch(gameRoundTimerPausedProvider);
    final bool calmMotion = calmMotionOf(context, ref);
    if (_flight.duration == null ||
        _timerPaused != paused ||
        _calmMotion != calmMotion) {
      WidgetsBinding.instance.addPostFrameCallback((Duration _) {
        if (!mounted) return;
        _syncFlight(paused: paused, calmMotion: calmMotion);
      });
      _timerPaused = paused;
      _calmMotion = calmMotion;
    }
    final GameFeedback? feedback = _feedback;
    final Asteroid asteroid = _asteroid;
    final Critter animal = critter(asteroid);

    return GameShell(
      title: '📸 Flyby Snap',
      feedback: feedback,
      onNext: feedback == null ? null : _nextAfterFeedback,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          GameScoreBar(
            scores: <GameScore>[
              GameScore(value: '$_shots', label: 'SHOTS'),
              GameScore(value: '$_attempt/2', label: 'TRY'),
            ],
          ),
          const Panel(
            child: Text(
              'Tap PHOTO when the animal is inside the camera window. You always get two tries!',
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
          SizedBox(
            height: 190,
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                return AnimatedBuilder(
                  animation: _flight,
                  builder: (BuildContext context, Widget? _) {
                    final double available = constraints.maxWidth - 64;
                    final double left = -32 + available * _flight.value;
                    return Stack(
                      clipBehavior: Clip.none,
                      children: <Widget>[
                        Align(
                          child: Container(
                            key: const ValueKey<String>('flyby-camera-window'),
                            width:
                                constraints.maxWidth *
                                (kFlybySnapWindowEnd - kFlybySnapWindowStart),
                            height: 132,
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: Palette.accent2,
                                width: 3,
                              ),
                              borderRadius: BorderRadius.circular(18),
                              color: Palette.accent.withValues(alpha: 0.12),
                            ),
                            alignment: Alignment.topCenter,
                            padding: const EdgeInsets.only(top: 6),
                            child: const Text(
                              'CAMERA WINDOW',
                              style: TextStyle(
                                color: Palette.ink,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: left,
                          top: 69,
                          child: Semantics(
                            label: animal.name,
                            child: Text(
                              animal.animal.emoji,
                              style: const TextStyle(fontSize: 52),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          KeyedSubtree(
            key: const ValueKey<String>('flyby-photo-button'),
            child: ActionButton(
              label: '📸 PHOTO',
              // The action remains visibly present during feedback, but the
              // handler is intentionally a no-op until the shared shell
              // dismisses it. This keeps the large target stable on screen.
              onTap: _takePhoto,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            calmMotion
                ? '🐢 Calm Motion makes the crossing slower.'
                : 'Watch the window, then snap!',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Palette.muted, height: 1.3),
          ),
        ],
      ),
    );
  }
}

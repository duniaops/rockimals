/// Size Stack — build a stable big-to-small tower from real asteroid sizes.
library;

import 'dart:async';
import 'dart:math';

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
import 'package:rockimals/features/games/game_shell.dart';
import 'package:rockimals/features/games/size_stack.dart';
import 'package:rockimals/features/settings/calm_motion.dart';

const Duration kSizeStackWobbleDuration = Duration(milliseconds: 420);
const Duration kSizeStackCalmWobbleDuration = Duration(milliseconds: 180);

/// A recoverable drag game which introduces the animal-size ladder first.
class SizeStackScreen extends ConsumerStatefulWidget {
  const SizeStackScreen({super.key});

  @override
  ConsumerState<SizeStackScreen> createState() => _SizeStackScreenState();
}

class _SizeStackScreenState extends ConsumerState<SizeStackScreen>
    with SingleTickerProviderStateMixin {
  late final List<Asteroid> _sky;
  late final String _dayKey;
  late final AnimationController _wobble;
  final SizeStackDifficulty _difficulty = SizeStackDifficulty();

  SizeStackRound? _round;
  List<Asteroid> _available = <Asteroid>[];
  List<Asteroid> _placed = <Asteroid>[];
  int _roundNumber = 0;
  int _combo = 0;
  bool _ladderShown = false;
  bool _complete = false;
  GameFeedback? _feedback;

  @override
  void initState() {
    super.initState();
    _wobble = AnimationController(vsync: this);
    _sky = ref.read(asteroidsProvider).value ?? const <Asteroid>[];
    _dayKey = DayStreak.keyOf(ref.read(dayClockProvider)());
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (mounted) {
        unawaited(ref.read(gameActionsProvider).markPlayed());
      }
    });
  }

  @override
  void dispose() {
    _wobble.dispose();
    super.dispose();
  }

  void _startTower() {
    _round = generateSizeStackRound(
      asteroids: _sky,
      dayKey: '$_dayKey|$_roundNumber',
      towerSize: _difficulty.towerSize,
    );
    setState(() {
      _ladderShown = true;
      _available = List<Asteroid>.of(_round!.offerOrder);
      _placed = <Asteroid>[];
      _complete = false;
      _feedback = null;
    });
  }

  void _drop(Asteroid asteroid, bool calmMotion) {
    if (_feedback != null || _complete || !_available.contains(asteroid)) {
      return;
    }
    final Asteroid expected = _round!.stackingOrder[_placed.length];
    final bool correct = asteroid.name == expected.name;
    ref.read(gameReactionProvider.notifier).react(correct: correct);
    if (!correct) {
      _wobble.duration = calmMotion
          ? kSizeStackCalmWobbleDuration
          : kSizeStackWobbleDuration;
      _wobble.forward(from: 0);
    }
    setState(() {
      if (correct) {
        _placed = <Asteroid>[..._placed, asteroid];
        _available = _available
            .where((Asteroid candidate) => candidate.name != asteroid.name)
            .toList(growable: false);
        _combo++;
      }
      _feedback = GameFeedback(
        correct: correct,
        headline: correct
            ? '✓ Stable stack! Combo $_combo'
            : 'Whoops — wobble, wobble!',
        explanation: correct
            ? '${critter(asteroid).first} is ${asteroid.diaMax.round()} m wide, '
                  'so ${_placed.length == 1 ? 'it makes a strong base' : 'it fits above the bigger animals'}.'
            : '${critter(expected).first} is ${expected.diaMax.round()} m wide and belongs next. '
                  'The tower recovered — try again!',
      );
    });
  }

  void _nextAfterFeedback() {
    final bool towerDone = _placed.length == _difficulty.towerSize;
    setState(() {
      _feedback = null;
      _complete = towerDone;
    });
  }

  void _nextTower() {
    _difficulty.recordCompletedTower();
    _roundNumber++;
    _startTower();
  }

  void _playAgain() {
    _roundNumber = 0;
    _combo = 0;
    _startTower();
  }

  @override
  Widget build(BuildContext context) {
    final bool calmMotion = calmMotionOf(context, ref);
    if (!_ladderShown) {
      return GameShell(
        title: '🧱 Size Stack',
        body: _SizeLadderIntro(onStart: _startTower),
      );
    }
    final SizeStackRound round = _round!;
    return GameShell(
      title: '🧱 Size Stack',
      feedback: _feedback,
      onNext: _feedback == null ? null : _nextAfterFeedback,
      body: _complete
          ? _SizeStackResult(
              round: round,
              onNextTower: _nextTower,
              onPlayAgain: _playAgain,
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                GameScoreBar(
                  scores: <GameScore>[
                    GameScore(value: '$_combo', label: 'COMBO'),
                    GameScore(
                      value: '${_placed.length}/${_difficulty.towerSize}',
                      label: 'STACKED',
                    ),
                  ],
                ),
                const Panel(
                  child: Text(
                    'Drag the biggest animal to the base, then stack smaller ones on top.',
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
                _TowerDropZone(
                  placed: _placed,
                  wobble: _wobble,
                  accepting: _feedback == null,
                  onDrop: (Asteroid asteroid) => _drop(asteroid, calmMotion),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: _available
                      .map(
                        (Asteroid asteroid) => _SizeStackDraggable(
                          asteroid: asteroid,
                          enabled: _feedback == null,
                        ),
                      )
                      .toList(growable: false),
                ),
              ],
            ),
    );
  }
}

class _SizeLadderIntro extends StatelessWidget {
  const _SizeLadderIntro({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Text(
            'Build from big to small',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Palette.ink,
              fontWeight: FontWeight.w800,
              fontSize: 20,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'A Whale-sized animal makes a strong base. Mouse-sized animals belong near the top!',
            textAlign: TextAlign.center,
            style: TextStyle(color: Palette.ink, height: 1.35),
          ),
          const SizedBox(height: 12),
          Text(
            kAnimals.reversed.map((Animal animal) => animal.emoji).join('  '),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 28),
          ),
          const SizedBox(height: 16),
          ActionButton(label: 'Start stacking', onTap: onStart),
        ],
      ),
    );
  }
}

class _TowerDropZone extends StatelessWidget {
  const _TowerDropZone({
    required this.placed,
    required this.wobble,
    required this.accepting,
    required this.onDrop,
  });

  final List<Asteroid> placed;
  final Animation<double> wobble;
  final bool accepting;
  final ValueChanged<Asteroid> onDrop;

  @override
  Widget build(BuildContext context) {
    return DragTarget<Asteroid>(
      onWillAcceptWithDetails: (DragTargetDetails<Asteroid> _) => accepting,
      onAcceptWithDetails: (DragTargetDetails<Asteroid> details) =>
          onDrop(details.data),
      builder:
          (
            BuildContext context,
            List<Asteroid?> candidates,
            List<dynamic> rejected,
          ) => AnimatedBuilder(
            animation: wobble,
            builder: (BuildContext context, Widget? child) => Transform.rotate(
              key: const ValueKey<String>('size-stack-wobble'),
              angle: sin(wobble.value * pi * 4) * (1 - wobble.value) * 0.075,
              child: child,
            ),
            child: Semantics(
              label: 'Tower drop zone',
              child: Panel(
                child: TapTarget(
                  key: const ValueKey<String>('size-stack-tower'),
                  child: SizedBox(
                    height: 180,
                    child: Center(
                      child: placed.isEmpty
                          ? Text(
                              candidates.isEmpty
                                  ? 'Drop the biggest animal here'
                                  : 'Build it here!',
                              style: const TextStyle(
                                color: Palette.muted,
                                fontWeight: FontWeight.w700,
                              ),
                            )
                          : Wrap(
                              alignment: WrapAlignment.center,
                              crossAxisAlignment: WrapCrossAlignment.end,
                              children: placed
                                  .map(
                                    (Asteroid asteroid) => Text(
                                      critter(asteroid).animal.emoji,
                                      textScaler: TextScaler.noScaling,
                                      style: TextStyle(
                                        fontSize: sizeStackSpriteSize(
                                          asteroid.diaMax,
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(growable: false),
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

class _SizeStackDraggable extends StatelessWidget {
  const _SizeStackDraggable({required this.asteroid, required this.enabled});

  final Asteroid asteroid;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final Critter animal = critter(asteroid);
    final Widget card = Panel(
      child: SizedBox(
        width: 132,
        height: 140,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              animal.animal.emoji,
              textScaler: TextScaler.noScaling,
              style: TextStyle(fontSize: sizeStackSpriteSize(asteroid.diaMax)),
            ),
            Text(
              animal.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Palette.ink,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
    return Draggable<Asteroid>(
      data: asteroid,
      maxSimultaneousDrags: enabled ? 1 : 0,
      feedback: Material(
        color: Colors.transparent,
        child: Opacity(opacity: 0.9, child: card),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: card),
      child: Semantics(
        label: '${animal.name}, drag to the tower',
        child: KeyedSubtree(
          key: ValueKey<String>('size-stack-${asteroid.name}'),
          child: card,
        ),
      ),
    );
  }
}

class _SizeStackResult extends StatelessWidget {
  const _SizeStackResult({
    required this.round,
    required this.onNextTower,
    required this.onPlayAgain,
  });

  final SizeStackRound round;
  final VoidCallback onNextTower;
  final VoidCallback onPlayAgain;

  @override
  Widget build(BuildContext context) {
    final Asteroid largest = round.stackingOrder.first;
    final Asteroid smallest = round.stackingOrder.last;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Text(
            'What a steady tower!',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Palette.good,
              fontSize: 19,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${critter(largest).first} is the largest at ${largest.diaMax.round()} m. '
            '${critter(smallest).first} is the smallest at ${smallest.diaMax.round()} m.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Palette.ink, height: 1.35),
          ),
          const SizedBox(height: 14),
          ActionButton(label: 'Build a taller tower', onTap: onNextTower),
          const SizedBox(height: 8),
          ActionButton(label: 'Start over', ghost: true, onTap: onPlayAgain),
        ],
      ),
    );
  }
}

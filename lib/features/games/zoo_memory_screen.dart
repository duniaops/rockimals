/// Space Zoo Memory — reconnect friendly animals with real NASA facts.
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
import 'package:rockimals/features/games/game_shell.dart';
import 'package:rockimals/features/games/zoo_memory.dart';

class ZooMemoryScreen extends ConsumerStatefulWidget {
  const ZooMemoryScreen({super.key});

  @override
  ConsumerState<ZooMemoryScreen> createState() => _ZooMemoryScreenState();
}

class _ZooMemoryScreenState extends ConsumerState<ZooMemoryScreen> {
  late final List<Asteroid> _today;
  late final String _dayKey;
  final ZooMemoryDifficulty _difficulty = ZooMemoryDifficulty();

  ZooMemoryRound? _round;
  final Set<String> _paired = <String>{};
  Asteroid? _selectedFact;
  GameFeedback? _feedback;
  int _roundNumber = 0;
  bool _factsHidden = false;
  bool _complete = false;

  @override
  void initState() {
    super.initState();
    _today = ref.read(todayListProvider).value ?? const <Asteroid>[];
    _dayKey = DayStreak.keyOf(ref.read(dayClockProvider)());
    _startRound();
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (mounted) unawaited(ref.read(gameActionsProvider).markPlayed());
    });
  }

  void _startRound() {
    try {
      final ZooMemoryRound round = generateZooMemoryRound(
        asteroids: _today,
        dayKey: '$_dayKey|$_roundNumber',
        animalCount: _difficulty.animalCount,
      );
      setState(() {
        _round = round;
        _paired.clear();
        _selectedFact = null;
        _feedback = null;
        _factsHidden = false;
        _complete = false;
      });
    } on ArgumentError {
      setState(() => _round = null);
    }
  }

  void _chooseFact(Asteroid asteroid) {
    if (_feedback != null || _complete || _paired.contains(asteroid.name)) {
      return;
    }
    setState(() => _selectedFact = asteroid);
  }

  void _chooseAnimal(Asteroid asteroid) {
    final Asteroid? factAnimal = _selectedFact;
    if (factAnimal == null ||
        _feedback != null ||
        _paired.contains(asteroid.name)) {
      return;
    }
    final bool correct = factAnimal.name == asteroid.name;
    ref.read(gameReactionProvider.notifier).react(correct: correct);
    final ZooMemoryFact fact = _round!.fact;
    setState(() {
      if (correct) _paired.add(asteroid.name);
      _feedback = GameFeedback(
        correct: correct,
        headline: correct
            ? '✓ You found a pair!'
            : 'Nice try — keep remembering!',
        explanation: correct
            ? fact.recapFor(asteroid, ref.read(dayClockProvider)())
            : '${critter(asteroid).first} matches a different fact. '
                  'There are no lives to lose — try another pair!',
      );
    });
  }

  void _nextAfterFeedback() {
    setState(() {
      _complete = _paired.length == _round!.animals.length;
      _selectedFact = null;
      _feedback = null;
    });
  }

  void _nextRound() {
    _difficulty.recordCompletedRound();
    _roundNumber++;
    _startRound();
  }

  void _startOver() {
    _difficulty.reset();
    _roundNumber = 0;
    _startRound();
  }

  @override
  Widget build(BuildContext context) {
    final ZooMemoryRound? round = _round;
    if (round == null) {
      return const GameShell(
        title: '🧠 Space Zoo Memory',
        body: Panel(
          child: Text(
            'Today\'s zoo needs a few more animals before it can make a memory game. Come back after the sky refreshes!',
            textAlign: TextAlign.center,
            style: TextStyle(color: Palette.ink, height: 1.35),
          ),
        ),
      );
    }
    return GameShell(
      title: '🧠 Space Zoo Memory',
      feedback: _feedback,
      onNext: _feedback == null ? null : _nextAfterFeedback,
      body: _complete
          ? _MemoryResult(
              round: round,
              today: ref.read(dayClockProvider)(),
              onNextRound: _nextRound,
              onStartOver: _startOver,
            )
          : _factsHidden
          ? _MemoryBoard(
              round: round,
              paired: _paired,
              selectedFact: _selectedFact,
              showAvatars: _difficulty.animalCount <= 3,
              today: ref.read(dayClockProvider)(),
              onFact: _chooseFact,
              onAnimal: _chooseAnimal,
            )
          : _MemoryPreview(
              round: round,
              today: ref.read(dayClockProvider)(),
              easy: _difficulty.animalCount <= 3,
              onHideFacts: () => setState(() => _factsHidden = true),
            ),
    );
  }
}

class _MemoryPreview extends StatelessWidget {
  const _MemoryPreview({
    required this.round,
    required this.today,
    required this.easy,
    required this.onHideFacts,
  });

  final ZooMemoryRound round;
  final DateTime today;
  final bool easy;
  final VoidCallback onHideFacts;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      Panel(
        child: Column(
          children: <Widget>[
            const Text(
              'Remember these pairs!',
              style: TextStyle(
                color: Palette.ink,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${round.fact.question} Facts will hide, then you can reconnect them.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Palette.ink, height: 1.3),
            ),
            if (easy) ...<Widget>[
              const SizedBox(height: 6),
              const Text(
                'Easy round: the animal pictures will stay visible.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Palette.muted),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 12),
      ...round.animals.map(
        (Asteroid asteroid) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Panel(
            child: Row(
              children: <Widget>[
                Text(
                  critter(asteroid).animal.emoji,
                  style: const TextStyle(fontSize: 28),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${critter(asteroid).name} · ${round.fact.valueFor(asteroid, today)}',
                    style: const TextStyle(
                      color: Palette.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      ActionButton(label: 'Hide facts and play', onTap: onHideFacts),
    ],
  );
}

class _MemoryBoard extends StatelessWidget {
  const _MemoryBoard({
    required this.round,
    required this.paired,
    required this.selectedFact,
    required this.showAvatars,
    required this.today,
    required this.onFact,
    required this.onAnimal,
  });

  final ZooMemoryRound round;
  final Set<String> paired;
  final Asteroid? selectedFact;
  final bool showAvatars;
  final DateTime today;
  final ValueChanged<Asteroid> onFact;
  final ValueChanged<Asteroid> onAnimal;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      Panel(
        child: Text(
          selectedFact == null
              ? 'Pick a fact, then choose its animal.'
              : 'Now choose the animal that matches this fact.',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Palette.ink,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: round.factOfferOrder
            .where((Asteroid a) => !paired.contains(a.name))
            .map(
              (Asteroid asteroid) => _MemoryTile(
                key: ValueKey<String>('zoo-memory-fact-${asteroid.name}'),
                label: round.fact.valueFor(asteroid, today),
                selected: selectedFact?.name == asteroid.name,
                onTap: () => onFact(asteroid),
              ),
            )
            .toList(growable: false),
      ),
      const SizedBox(height: 14),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: round.animalOfferOrder
            .where((Asteroid a) => !paired.contains(a.name))
            .map(
              (Asteroid asteroid) => _MemoryTile(
                key: ValueKey<String>('zoo-memory-animal-${asteroid.name}'),
                label:
                    '${showAvatars ? '${critter(asteroid).animal.emoji} ' : ''}${critter(asteroid).name}',
                onTap: selectedFact == null ? null : () => onAnimal(asteroid),
              ),
            )
            .toList(growable: false),
      ),
    ],
  );
}

class _MemoryTile extends StatelessWidget {
  const _MemoryTile({
    super.key,
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: Ink(
      decoration: kPanelSurface.copyWith(
        border: Border.all(
          color: selected ? Palette.accent : Palette.line,
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: kPanelRadius,
        onTap: onTap,
        child: TapTarget(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 145),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Palette.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _MemoryResult extends StatelessWidget {
  const _MemoryResult({
    required this.round,
    required this.today,
    required this.onNextRound,
    required this.onStartOver,
  });

  final ZooMemoryRound round;
  final DateTime today;
  final VoidCallback onNextRound;
  final VoidCallback onStartOver;

  @override
  Widget build(BuildContext context) => Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const Text(
          'You remembered the whole zoo!',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Palette.good,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        ...round.animals.map(
          (Asteroid asteroid) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              round.fact.recapFor(asteroid, today),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Palette.ink, height: 1.3),
            ),
          ),
        ),
        const SizedBox(height: 10),
        ActionButton(label: 'Try a trickier round', onTap: onNextRound),
        const SizedBox(height: 8),
        ActionButton(label: 'Start over', ghost: true, onTap: onStartOver),
      ],
    ),
  );
}

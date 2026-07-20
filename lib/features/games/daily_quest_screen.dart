/// The playable Daily Data Quest: explore, compare a NASA fact, then dash.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rockimals/core/a11y/tap_target.dart';
import 'package:rockimals/core/animals/animal_system.dart';
import 'package:rockimals/core/chrome/action_button.dart';
import 'package:rockimals/core/chrome/panel.dart';
import 'package:rockimals/core/storage/store.dart';
import 'package:rockimals/core/streak/day_streak.dart';
import 'package:rockimals/core/theme/palette.dart';
import 'package:rockimals/data/models/asteroid.dart';
import 'package:rockimals/features/data/providers.dart';
import 'package:rockimals/features/games/daily_quest.dart';
import 'package:rockimals/features/games/game_shell.dart';

class DailyQuestScreen extends ConsumerStatefulWidget {
  const DailyQuestScreen({super.key});

  @override
  ConsumerState<DailyQuestScreen> createState() => _DailyQuestScreenState();
}

class _DailyQuestScreenState extends ConsumerState<DailyQuestScreen> {
  late final DailyQuest _quest;
  int _step = 0;
  int _dashTaps = 0;
  GameFeedback? _feedback;
  bool _complete = false;

  @override
  void initState() {
    super.initState();
    final List<Asteroid> sky =
        ref.read(todayListProvider).value ??
        ref.read(asteroidsProvider).value ??
        const <Asteroid>[];
    _quest = generateDailyQuest(
      asteroids: sky,
      dayKey: DayStreak.keyOf(ref.read(dayClockProvider)()),
    );
  }

  void _chooseRadar(Asteroid asteroid) {
    final bool correct = asteroid.name == _quest.target.name;
    _answer(
      correct: correct,
      headline: correct
          ? '✓ Radar find complete!'
          : 'Nice scan — look for ${critter(_quest.target).first}.',
      explanation: correct
          ? '${critter(asteroid).first} is on today’s real radar.'
          : 'That blip is ${critter(asteroid).first}; try another radar blip.',
    );
  }

  void _chooseChallenge(Asteroid asteroid) {
    final bool correct = asteroid.name == _quest.target.name;
    _answer(
      correct: correct,
      headline: correct
          ? '✓ You used the real data!'
          : 'Good thinking — try again.',
      explanation: correct
          ? _factFor(asteroid)
          : '${_factFor(_quest.target)} That is the clue to follow.',
    );
  }

  void _answer({
    required bool correct,
    required String headline,
    required String explanation,
  }) {
    ref.read(gameReactionProvider.notifier).react(correct: correct);
    setState(() {
      _feedback = GameFeedback(
        correct: correct,
        headline: headline,
        explanation: explanation,
      );
    });
  }

  void _next() {
    if (_feedback?.correct ?? false) _step++;
    setState(() => _feedback = null);
  }

  void _tapDash() {
    final int next = _dashTaps + 1;
    if (next < _quest.actionTapGoal) {
      setState(() => _dashTaps = next);
      return;
    }
    setState(() {
      _dashTaps = next;
      _complete = true;
    });
    ref.read(gameReactionProvider.notifier).react(correct: true);
    final Store store = ref.read(storeProvider);
    final List<String> patches = recordDailyQuestPatch(
      store.dailyQuestPatches,
      _quest.dayKey,
    );
    if (patches.length != store.dailyQuestPatches.length) {
      // The date-key ledger only ever grows; a missed day has nothing to erase.
      store.setDailyQuestPatches(patches);
    }
  }

  String _factFor(Asteroid asteroid) => switch (_quest.challenge) {
    DailyQuestChallenge.size =>
      '${critter(asteroid).first} is ${critter(asteroid).animal.sizeLabel}-sized from its real width.',
    DailyQuestChallenge.speed =>
      '${critter(asteroid).first} zooms ${speedLabel(asteroid.velKps)} from NASA’s flyby data.',
    DailyQuestChallenge.distance =>
      '${critter(asteroid).first} passes ${distLabel(asteroid.missLunar)} away.',
  };

  @override
  Widget build(BuildContext context) {
    return GameShell(
      title: '🗓️ Daily Data Quest',
      feedback: _feedback,
      onNext: _feedback == null ? null : _next,
      body: _complete ? _QuestComplete(dayKey: _quest.dayKey) : _body(),
    );
  }

  Widget _body() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        GameScoreBar(
          scores: <GameScore>[
            GameScore(value: '${_step + 1}', label: 'OF 3'),
            GameScore(value: '${_quest.actionTapGoal}', label: 'DASH BEATS'),
          ],
        ),
        if (_step == 0) ...<Widget>[
          const Panel(
            child: Text(
              'Part 1 · Radar find\nFind the animal matching this radar clue.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Palette.ink, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Find ${critter(_quest.target).first}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Palette.ink,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          for (final Asteroid asteroid in _quest.radarChoices) ...<Widget>[
            _QuestChoice(
              key: ValueKey<String>('daily-quest-radar-${asteroid.name}'),
              asteroid: asteroid,
              label: 'Radar blip',
              onTap: _feedback == null ? () => _chooseRadar(asteroid) : null,
            ),
            const SizedBox(height: 8),
          ],
        ] else if (_step == 1) ...<Widget>[
          Panel(
            child: Text(
              'Part 2 · Data challenge\n${_quest.challengePrompt}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Palette.ink,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 12),
          for (final Asteroid asteroid in _quest.challengeChoices) ...<Widget>[
            _QuestChoice(
              key: ValueKey<String>('daily-quest-data-${asteroid.name}'),
              asteroid: asteroid,
              label: critter(asteroid).first,
              onTap: _feedback == null
                  ? () => _chooseChallenge(asteroid)
                  : null,
            ),
            const SizedBox(height: 8),
          ],
        ] else ...<Widget>[
          Panel(
            child: Text(
              'Part 3 · ${_quest.actionTitle}\nTap to help ${critter(_quest.target).first} finish a ${_quest.actionTapGoal}-beat real-data dash.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Palette.ink,
                fontWeight: FontWeight.w800,
                height: 1.35,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '$_dashTaps / ${_quest.actionTapGoal} beats',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Palette.muted,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          ActionButton(
            label: 'Dash!',
            onTap: _tapDash,
            key: const ValueKey<String>('daily-quest-dash'),
          ),
        ],
      ],
    );
  }
}

class _QuestChoice extends StatelessWidget {
  const _QuestChoice({
    super.key,
    required this.asteroid,
    required this.label,
    required this.onTap,
  });

  final Asteroid asteroid;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Critter animal = critter(asteroid);
    return InkWell(
      onTap: onTap,
      borderRadius: const BorderRadius.all(Radius.circular(20)),
      child: TapTarget(
        child: Panel(
          child: Row(
            children: <Widget>[
              Text(animal.animal.emoji, style: const TextStyle(fontSize: 34)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Palette.ink,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuestComplete extends StatelessWidget {
  const _QuestComplete({required this.dayKey});

  final String dayKey;

  @override
  Widget build(BuildContext context) => Panel(
    child: Column(
      children: <Widget>[
        const Text(
          'Daily mission patch earned! 🏅',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Palette.good,
            fontSize: 19,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Your patch stays in your collection. Come back tomorrow for a fresh real-space mission.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Palette.ink, height: 1.35),
        ),
        const SizedBox(height: 8),
        Text('Patch: $dayKey', style: const TextStyle(color: Palette.muted)),
      ],
    ),
  );
}

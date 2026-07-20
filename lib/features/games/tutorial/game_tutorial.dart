/// The short first-play guide and the one-round practice gate shared by every
/// game in the Play hub.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rockimals/core/chrome/action_button.dart';
import 'package:rockimals/core/chrome/panel.dart';
import 'package:rockimals/core/storage/store.dart';
import 'package:rockimals/core/theme/palette.dart';
import 'package:rockimals/features/data/providers.dart';
import 'package:rockimals/features/games/game_shell.dart';

/// A game whose first completed round is a safe, unscored practice.
enum GameTutorialId { daily, duel, closer, match }

extension GameTutorialIdProgress on GameTutorialId {
  String get progressToken => switch (this) {
    GameTutorialId.daily => 'daily',
    GameTutorialId.duel => 'duel',
    GameTutorialId.closer => 'closer',
    GameTutorialId.match => 'match',
  };
}

const String kGameGuideProgressToken = 'guide';

/// Decides whether a Play-hub launch needs the shared guide, an unscored first
/// round, or the normal scored game. The progress is deliberately read from the
/// one store rather than mirrored in four game widgets.
class GameTutorialGate extends ConsumerStatefulWidget {
  const GameTutorialGate({
    required this.game,
    required this.builder,
    super.key,
  });

  final GameTutorialId game;
  final Widget Function({
    required bool practice,
    required VoidCallback onPracticeComplete,
  })
  builder;

  @override
  ConsumerState<GameTutorialGate> createState() => _GameTutorialGateState();
}

enum _GateStage { guide, practice, play }

class _GameTutorialGateState extends ConsumerState<GameTutorialGate> {
  late _GateStage _stage;

  @override
  void initState() {
    super.initState();
    final List<String> progress = ref.read(storeProvider).gameTutorialProgress;
    _stage = !progress.contains(kGameGuideProgressToken)
        ? _GateStage.guide
        : progress.contains(widget.game.progressToken)
        ? _GateStage.play
        : _GateStage.practice;
  }

  Future<void> _recordAndMove(String token, _GateStage next) async {
    final Store store = ref.read(storeProvider);
    final Set<String> progress = store.gameTutorialProgress.toSet()..add(token);
    await store.setGameTutorialProgress(progress);
    if (mounted) setState(() => _stage = next);
  }

  @override
  Widget build(BuildContext context) {
    return switch (_stage) {
      _GateStage.guide => GameTutorialScreen(
        onFinished: () => unawaited(
          _recordAndMove(kGameGuideProgressToken, _GateStage.practice),
        ),
      ),
      _GateStage.practice => widget.builder(
        practice: true,
        onPracticeComplete: () => unawaited(
          _recordAndMove(widget.game.progressToken, _GateStage.play),
        ),
      ),
      _GateStage.play => widget.builder(
        practice: false,
        onPracticeComplete: () {},
      ),
    };
  }
}

/// A replayable, three-beat guide. It is intentionally brief enough to skim in
/// about 30 seconds and every slide has the same escape hatch.
class GameTutorialScreen extends StatefulWidget {
  const GameTutorialScreen({required this.onFinished, super.key});

  final VoidCallback onFinished;

  @override
  State<GameTutorialScreen> createState() => _GameTutorialScreenState();
}

class _GameTutorialScreenState extends State<GameTutorialScreen> {
  int _page = 0;

  static const List<_TutorialPage> _pages = <_TutorialPage>[
    _TutorialPage(
      title: 'Welcome to Play!',
      body:
          'Every space animal is a real asteroid. Let’s learn the two clues that make the games easy to play.',
    ),
    _TutorialPage(
      title: 'Power is a team-up',
      body:
          'Power = bigger + closer + faster. Look for all three clues before you choose.',
    ),
    _TutorialPage(
      title: 'Meet the size ladder',
      body:
          '🐭 Mouse → 🐰 Rabbit → 🦊 Fox → 🐯 Tiger → 🐻 Bear → 🐘 Elephant → 🦕 Dino → 🐋 Whale',
    ),
  ];

  void _next() {
    if (_page == _pages.length - 1) {
      widget.onFinished();
    } else {
      setState(() => _page++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final _TutorialPage page = _pages[_page];
    final bool last = _page == _pages.length - 1;
    return GameShell(
      title: '🎓 How to play',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            '${_page + 1} of ${_pages.length}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Palette.muted,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  page.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Palette.accent2,
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  page.body,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Palette.ink,
                    fontSize: 16,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ActionButton(
            label: last ? 'Try a practice round' : 'Next',
            onTap: _next,
          ),
          const SizedBox(height: 8),
          ActionButton(
            label: 'Skip tutorial',
            ghost: true,
            onTap: widget.onFinished,
          ),
        ],
      ),
    );
  }
}

class _TutorialPage {
  const _TutorialPage({required this.title, required this.body});

  final String title;
  final String body;
}

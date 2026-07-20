/// Power Duel (`specs/04`, game 2) — a port of the prototype's `startDuel` /
/// `duelRound` (`index.html:1034-1057`).
///
/// Two space animals side by side; tap the one with more power. Right answers
/// keep the streak alive and mistakes spend one of three lives. Every answer
/// waits for the shared Next action (with its six-second inactivity fallback)
/// before dealing again. The deal and the winner test live next door in
/// `duel_pairing.dart`; this file is the screen.
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rockimals/core/animals/animal_system.dart';
import 'package:rockimals/core/theme/palette.dart';
import 'package:rockimals/data/models/asteroid.dart';
import 'package:rockimals/features/data/providers.dart';
import 'package:rockimals/features/games/duel_pairing.dart';
import 'package:rockimals/features/games/game_shell.dart';
import 'package:rockimals/features/rewards/reaction.dart';

/// Power Duel: an endless streak game with three lives.
///
/// **Unlike Today's Challenge, this one does finish through [GameOverPanel]** —
/// it is a run with a length, so the shared end screen is exactly right (the
/// challenge is a single round that reveals in place instead).
///
/// **No injected [Random] seed**, following the challenge's rule: the tests play
/// by animal *name* and pin the deal by handing the game a sky it can only draw
/// one pair from, so a seed would be an unused parameter.
class DuelGame extends ConsumerStatefulWidget {
  const DuelGame({super.key});

  @override
  ConsumerState<DuelGame> createState() => _DuelGameState();
}

class _DuelGameState extends ConsumerState<DuelGame> {
  final Random _random = Random();

  late DuelPair _pair;

  /// Correct answers in a row this run (`duelStreak`, `index.html:1034`).
  int _streak = 0;

  /// The persisted best, mirrored locally so the BEST cell can tick up the
  /// moment it is beaten (`bestDuel`, `index.html:1053`).
  int _best = 0;

  /// Which card the child tapped, or null while the round is still open. Once
  /// set, the pair is revealed and both cards are inert.
  bool? _pickedA;

  /// Recoverable mistakes remaining in this run (Games v2 design rule 4).
  int _lives = 3;

  /// Set when the run is over; the end screen replaces the board.
  bool _over = false;

  @override
  void initState() {
    super.initState();
    _best = ref.read(gameActionsProvider).bestDuel;
    _pair = _deal();
    // `markPlayed()` before the first round, as `startDuel` does
    // (`index.html:1035`). Deferred a frame so the store write cannot run
    // during initialisation.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(ref.read(gameActionsProvider).markPlayed());
    });
  }

  /// The whole sky, not today's list — the prototype duels across the full
  /// window (`rand(asteroids)`, `index.html:1037`), which is also the only pool
  /// wide enough for the deal's power-gap rule to be satisfiable.
  ///
  /// Read rather than watched: a round is dealt and then frozen, so a feed
  /// refresh cannot swap the cards under a child's finger mid-answer.
  DuelPair _deal() {
    final List<Asteroid> sky =
        ref.read(asteroidsProvider).value ?? const <Asteroid>[];
    return dealDuelPair(sky, _random);
  }

  /// A fresh run — "Play again" is `startDuel` again (`index.html:1030`): the
  /// streak resets to zero and another play is counted.
  void _restart() {
    unawaited(ref.read(gameActionsProvider).markPlayed());
    setState(() {
      _streak = 0;
      _lives = 3;
      _over = false;
      _pickedA = null;
      _pair = _deal();
    });
  }

  /// The next pair of an unbroken run — no `markPlayed`, because it is the same
  /// game still going.
  void _nextRound() {
    if (!mounted) return;
    setState(() {
      _pickedA = null;
      _pair = _deal();
    });
  }

  /// Dismiss the shared feedback. A third mistake ends the run only after the
  /// child has had time to read why; every earlier answer deals another pair.
  void _finishFeedback() {
    if (_pickedA == null || _over) return;
    if (_lives == 0) {
      setState(() => _over = true);
    } else {
      _nextRound();
    }
  }

  void _pick({required bool isA}) {
    // The prototype clears both cards' handlers on the first tap
    // (`cards.forEach(x=>x.onclick=null)`, `index.html:1047`), so a second tap
    // during the reveal does nothing.
    if (_pickedA != null || _over) return;

    final GameActions actions = ref.read(gameActionsProvider);
    final bool win = isA == _pair.winnerIsA;
    ref.read(gameReactionProvider.notifier).react(correct: win);

    if (win) {
      final int streak = _streak + 1;
      if (streak > _best) {
        _best = streak;
        unawaited(actions.setBestDuel(streak));
      }
      unawaited(actions.noteStreak(streak));
      unawaited(actions.awardPoints(10));
      setState(() {
        _streak = streak;
        _pickedA = isA;
      });
    } else {
      setState(() {
        _pickedA = isA;
        _streak = 0;
        _lives--;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return GameShell(
      // The overlay title `startDuel` sets (`index.html:1035`).
      title: '⚔️ Power Duel',
      lives: _over ? null : _lives,
      feedback: _over || _pickedA == null
          ? null
          : GameFeedback(
              correct: _pickedA == _pair.winnerIsA,
              headline: _pickedA == _pair.winnerIsA
                  ? '✓ Correct!  +10 ⭐'
                  : 'So close — $_lives ${_lives == 1 ? 'life' : 'lives'} left',
              explanation: _duelExplanation(),
            ),
      onNext: _over || _pickedA == null ? null : _finishFeedback,
      body: _over ? _endPanel() : _board(),
    );
  }

  Widget _endPanel() {
    final GameActions actions = ref.read(gameActionsProvider);
    return GameOverPanel(
      title: 'What a flight!',
      score: '$_streak',
      // The lifetime total and personal best make a gentle, celebratory wrap-up
      // once a run ends.
      subtitle: '⭐ ${actions.points} points · best streak $_best',
      onPlayAgain: _restart,
    );
  }

  Widget _board() {
    final bool? picked = _pickedA;
    final bool revealed = picked != null;
    final bool win = revealed && picked == _pair.winnerIsA;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        GameScoreBar(
          scores: <GameScore>[
            GameScore(value: '$_streak', label: 'STREAK'),
            GameScore(value: '$_best', label: 'BEST'),
          ],
        ),
        const _DuelInstruction(),
        // `.duel{gap:12px;margin:12px 0}` (`index.html:211`).
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          // `.duel` is a two-column CSS grid, whose cells are the same height
          // whatever is in them (`index.html:211`). Inside the shell's scroll
          // view the height is unbounded, so `stretch` alone cannot mean
          // anything — [IntrinsicHeight] gives the row the taller card's height
          // to stretch the shorter one to, which is what the grid does.
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(
                  child: _DuelCard(
                    asteroid: _pair.a,
                    // Both cards reveal together, and the colours mark the
                    // *true* winner rather than what the child picked
                    // (`index.html:1049-1051`) — so a wrong answer still shows
                    // which animal was stronger.
                    isWinner: revealed ? _pair.winnerIsA : null,
                    // But only the card the child *tapped* reacts: the
                    // prototype hands `react()` the avatar inside the tapped
                    // card (`index.html:1052`), so the other animal holds
                    // still even though it is revealed too.
                    reaction: reactionFor(picked == true ? win : null),
                    onTap: () => _pick(isA: true),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _DuelCard(
                    asteroid: _pair.b,
                    isWinner: revealed ? !_pair.winnerIsA : null,
                    reaction: reactionFor(picked == false ? win : null),
                    onTap: () => _pick(isA: false),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Explain the real measurements that favour this round's winner. Power is
  /// a weighted combination, so every favourable term is named rather than
  /// reducing the lesson to the already-visible star total.
  String _duelExplanation() {
    final Asteroid winner = _pair.winner;
    final Asteroid loser = identical(winner, _pair.a) ? _pair.b : _pair.a;
    final List<String> reasons = <String>[
      if (winner.diaMax > loser.diaMax) 'bigger',
      if (winner.missLunar < loser.missLunar) 'passed closer',
      if (winner.velKps > loser.velKps) 'flew faster',
    ];
    final String rule = switch (reasons) {
      <String>[] => 'had the stronger mix of size, closeness, and speed',
      <String>[final String only] => only,
      <String>[final String first, final String second] => '$first and $second',
      _ => '${reasons[0]}, ${reasons[1]}, and ${reasons[2]}',
    };
    return '${critter(winner).name} wins — $rule. '
        'Power = bigger + closer + faster ⭐.';
  }
}

/// The one-line rule of the game (`.h-sub`, `index.html:1042`), centred, with
/// the question in accent.
class _DuelInstruction extends StatelessWidget {
  const _DuelInstruction();

  @override
  Widget build(BuildContext context) {
    return const Text.rich(
      TextSpan(
        children: <InlineSpan>[
          TextSpan(text: 'Which space animal has '),
          TextSpan(
            text: 'more power? ⭐',
            style: TextStyle(
              color: Palette.accent2,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
      textAlign: TextAlign.center,
      style: TextStyle(color: Palette.muted, fontSize: 13, height: 1.35),
    );
  }
}

/// One of the two animals (`.dcard`, `index.html:212-218`).
///
/// Three states in one widget, as the prototype's one element gaining classes:
/// open (plain border), the revealed winner (`.win` — green border) and the
/// revealed loser (`.lose` — red border at 65% opacity). The power that decided
/// it appears on both cards only once revealed, so the child compares the two
/// numbers after committing rather than reading the answer off the board.
class _DuelCard extends StatelessWidget {
  const _DuelCard({
    required this.asteroid,
    required this.isWinner,
    required this.reaction,
    required this.onTap,
  });

  final Asteroid asteroid;

  /// Null while the round is open; whether this card is the stronger animal
  /// once revealed.
  final bool? isWinner;

  /// The motion this card's avatar plays — non-null only on the tapped card,
  /// and only once the round is revealed.
  final Reaction? reaction;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Critter c = critter(asteroid);
    final bool? winner = isWinner;
    // `${sizeLabel(x.diaMax)}<br>${distLabel(x.missLunar)} · ${x.velKps
    // .toFixed(0)} km/s` (`index.html:1039`) — every field through the
    // AnimalSystem formatters, so a duel cannot phrase a size or a distance
    // differently from the card that opened the animal.
    final String size = sizeLabel(asteroid.diaMax);
    final String journey =
        '${distLabel(asteroid.missLunar)} · ${speedLabel(asteroid.velKps)}';
    final String powerLine = 'power ⭐ ${powerStars(asteroid)}';

    final Widget card = Material(
      color: Palette.card,
      shape: RoundedRectangleBorder(
        // `.dcard{border-radius:16px}` (`index.html:212`).
        borderRadius: const BorderRadius.all(Radius.circular(16)),
        side: BorderSide(
          color: switch (winner) {
            true => Palette.good,
            false => Palette.bad,
            null => Palette.line,
          },
        ),
      ),
      child: InkWell(
        borderRadius: const BorderRadius.all(Radius.circular(16)),
        onTap: onTap,
        child: Padding(
          // `.dcard{padding:14px 10px}` (`index.html:212`).
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ReactionAvatar(
                reaction: reaction,
                child: _DuelAvatar(emoji: c.animal.emoji),
              ),
              // `.dcard .mini{margin:0 auto 8px}` (`index.html:215`).
              const SizedBox(height: 8),
              Text(
                c.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                // `.dcard .nm{font-weight:800;font-size:14px}`.
                style: const TextStyle(
                  color: Palette.ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
              // `.dcard .st{margin-top:6px}`.
              const SizedBox(height: 6),
              Text(
                '$size\n$journey',
                textAlign: TextAlign.center,
                // `.dcard .st{font-size:11.5px;line-height:1.55}`.
                style: const TextStyle(
                  color: Palette.muted,
                  fontSize: 11.5,
                  height: 1.55,
                ),
              ),
              if (winner != null)
                Text(
                  powerLine,
                  textAlign: TextAlign.center,
                  // Appended to the same stat block on reveal, green on the
                  // winner and muted on the loser (`index.html:1051`).
                  style: TextStyle(
                    color: winner ? Palette.good : Palette.muted,
                    fontSize: 11.5,
                    height: 1.55,
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    return Semantics(
      button: true,
      // Spoken as a sentence: the emoji and the ⭐ are decoration, so the visual
      // is excluded and the state is said in words (the challenge card's
      // pattern).
      label: <String>[
        c.name,
        size,
        journey,
        if (winner != null)
          '$powerLine, ${winner ? 'the stronger animal' : 'not the stronger one'}',
      ].join(', '),
      child: ExcludeSemantics(
        child: winner == false
            // `.dcard.lose{opacity:.65}` (`index.html:218`) — the loser fades
            // rather than being marked wrong; it is still somebody's favourite
            // animal.
            ? Opacity(opacity: 0.65, child: card)
            : card,
      ),
    );
  }
}

/// The duel's animal avatar (`.dcard .mini.avatar`, `index.html:215,228`) — the
/// same navy disc every animal wears, at 56px with a 30px emoji.
class _DuelAvatar extends StatelessWidget {
  const _DuelAvatar({required this.emoji});

  final String emoji;

  @override
  Widget build(BuildContext context) {
    return Container(
      // `.dcard .mini{width:56px;height:56px}` (`index.html:215`).
      width: 56,
      height: 56,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        // `.avatar` wins the grey `.mini` rock gradient with `!important`
        // (`index.html:226`): animals are navy discs everywhere.
        gradient: RadialGradient(
          center: Alignment(0, -0.16),
          radius: 0.9,
          colors: <Color>[Palette.line, Color(0xFF14284A)],
        ),
        border: Border.fromBorderSide(BorderSide(color: Palette.line)),
      ),
      child: Text(emoji, style: const TextStyle(fontSize: 30, height: 1)),
    );
  }
}

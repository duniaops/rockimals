/// Closer or Farther (`specs/04`, game 3) — a port of the prototype's
/// `startCloser` / `closerRound` (`index.html:1059-1083`).
///
/// One animal sits on a card with its distance spelled out; the child says
/// whether the *next* animal flies closer to Earth or farther away. A right
/// answer promotes that animal to the card and asks again, so the run is a chain
/// of comparisons; one wrong answer ends it.
///
/// The deal and the comparison live next door in `closer_pairing.dart`; this
/// file is the screen.
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rockimals/core/animals/animal_system.dart';
import 'package:rockimals/core/theme/palette.dart';
import 'package:rockimals/data/models/asteroid.dart';
import 'package:rockimals/features/data/providers.dart';
import 'package:rockimals/features/games/closer_pairing.dart';
import 'package:rockimals/features/games/game_shell.dart';
import 'package:rockimals/features/rewards/reaction.dart';

/// How long the reveal sits before the next challenger is dealt
/// (`setTimeout(closerRound,1250)`, `index.html:1079`).
///
/// Longer than Power Duel's 950ms, and it should be: the reveal here is a
/// *sentence* naming the animal and its distance, not a tick, so the child needs
/// time to read the thing they are about to be quizzed against next.
const Duration kCloserAdvanceDelay = Duration(milliseconds: 1250);

/// How long the wrong-answer reveal sits before the end screen
/// (`setTimeout(…,1350)`, `index.html:1080`) — a touch longer than a win, so the
/// run does not close before the child has read where the animal really flew.
const Duration kCloserGameOverDelay = Duration(milliseconds: 1350);

/// Closer or Farther: a streak game that ends on the first wrong answer.
///
/// Like Power Duel it finishes through [GameOverPanel], and like Power Duel it
/// takes **no injected [Random]** — the suite plays by animal name against a sky
/// small enough that the deal has only one challenger to find, so a seed would
/// be an unused parameter.
class CloserGame extends ConsumerStatefulWidget {
  const CloserGame({super.key});

  @override
  ConsumerState<CloserGame> createState() => _CloserGameState();
}

class _CloserGameState extends ConsumerState<CloserGame> {
  final Random _random = Random();

  late CloserRound _round;

  /// Correct answers in a row this run (`closerScore`, `index.html:1060`).
  int _score = 0;

  /// The persisted best, mirrored locally so the BEST cell can tick up the
  /// moment it is beaten (`bestCloser`, `index.html:1079`).
  int _best = 0;

  /// What the child answered, or null while the round is still open. Once set,
  /// the round is revealed and both buttons are inert.
  bool? _guessedCloser;

  /// Set when the run is over; the end screen replaces the board.
  bool _over = false;

  /// The pending advance-or-end timer, cancelled if the screen goes away first.
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _best = ref.read(gameActionsProvider).bestCloser;
    _round = _dealFrom(_pickAnchor());
    // `markPlayed()` before the first round, as `startCloser` does
    // (`index.html:1061`). Deferred a frame so the store write cannot run
    // during initialisation.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(ref.read(gameActionsProvider).markPlayed());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// The whole sky, not today's list — the prototype draws both the anchor and
  /// every challenger from the full window (`rand(asteroids)`,
  /// `index.html:1061,1063`), which is also the only pool wide enough for the
  /// deal's distance-gap rule to be satisfiable on a quiet day.
  ///
  /// Read rather than watched: a round is dealt and then frozen, so a feed
  /// refresh cannot swap the question under a child's finger mid-answer.
  List<Asteroid> get _sky =>
      ref.read(asteroidsProvider).value ?? const <Asteroid>[];

  Asteroid _pickAnchor() => pickCloserAnchor(_sky, _random);

  CloserRound _dealFrom(Asteroid anchor) =>
      dealCloserRound(_sky, anchor, _random);

  /// A fresh run — "Play again" is `startCloser` again (`index.html:1080`): the
  /// score resets, a new anchor is drawn, and another play is counted.
  void _restart() {
    _timer?.cancel();
    unawaited(ref.read(gameActionsProvider).markPlayed());
    setState(() {
      _score = 0;
      _over = false;
      _guessedCloser = null;
      _round = _dealFrom(_pickAnchor());
    });
  }

  /// The next link in an unbroken chain: **the challenger just guessed becomes
  /// the anchor** (`closerAnchor=ch`, `index.html:1079`), so each answer is
  /// measured against the animal the child just learned about. No `markPlayed`,
  /// because it is the same game still going.
  void _nextRound() {
    if (!mounted) return;
    setState(() {
      _guessedCloser = null;
      _round = _dealFrom(_round.challenger);
    });
  }

  void _guess({required bool closer}) {
    // The prototype disables both buttons on the first tap
    // (`$("cCl").disabled=$("cFar").disabled=true`, `index.html:1074`), so an
    // excited double-tap cannot bank two answers or end the run by hitting the
    // other button next.
    if (_guessedCloser != null || _over) return;

    final GameActions actions = ref.read(gameActionsProvider);
    final bool win = closer == _round.challengerIsCloser;
    ref.read(gameReactionProvider.notifier).react(correct: win);

    if (win) {
      final int score = _score + 1;
      if (score > _best) {
        _best = score;
        unawaited(actions.setBestCloser(score));
      }
      unawaited(actions.noteStreak(score));
      unawaited(actions.awardPoints(10));
      setState(() {
        _score = score;
        _guessedCloser = closer;
      });
      _timer = Timer(kCloserAdvanceDelay, _nextRound);
    } else {
      setState(() => _guessedCloser = closer);
      _timer = Timer(kCloserGameOverDelay, () {
        if (mounted) setState(() => _over = true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return GameShell(
      // The overlay title `startCloser` sets (`index.html:1061`).
      title: '📏 Closer or Farther',
      body: _over ? _endPanel() : _board(),
    );
  }

  Widget _endPanel() {
    final GameActions actions = ref.read(gameActionsProvider);
    return GameOverPanel(
      title: 'GAME OVER',
      score: '$_score',
      // `"best streak "+bestCloser+" · ⭐ "+points+" points"`
      // (`index.html:1080`) — the run is over, so the totals are read once here.
      subtitle: 'best streak $_best · ⭐ ${actions.points} points',
      onPlayAgain: _restart,
    );
  }

  Widget _board() {
    final bool? guessed = _guessedCloser;
    final bool revealed = guessed != null;
    final bool win = revealed && guessed == _round.challengerIsCloser;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        GameScoreBar(
          scores: <GameScore>[
            GameScore(value: '$_score', label: 'STREAK'),
            GameScore(value: '$_best', label: 'BEST'),
          ],
        ),
        _CloserQuestion(challenger: _round.challenger),
        // The anchor's is the only `.avatar` element in this game's body, so it
        // is the one `$("gameBody").querySelector('.avatar')` finds and the one
        // the prototype reacts (`index.html:1076`). The challenger appears as
        // inline text in the question and the banner, never as a disc.
        _AnchorCard(
          anchor: _round.anchor,
          reaction: reactionFor(revealed ? win : null),
        ),
        // `<div style="display:flex;gap:10px">` (`index.html:1071`) — the two
        // answers side by side, equal width.
        Row(
          children: <Widget>[
            Expanded(
              child: GameButton(
                label: '⬇ Closer',
                onTap: () => _guess(closer: true),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GameButton(
                label: '⬆ Farther',
                onTap: () => _guess(closer: false),
              ),
            ),
          ],
        ),
        _CloserBanner(round: revealed ? _round : null, win: win),
      ],
    );
  }
}

/// The question (`.h-sub`, `index.html:1067`): *Does {animal} fly **closer** or
/// **farther** than…*, trailing off into the card below it.
///
/// The challenger is named and pictured but its distance is not — that is the
/// answer, and it only appears in the reveal.
class _CloserQuestion extends StatelessWidget {
  const _CloserQuestion({required this.challenger});

  final Asteroid challenger;

  @override
  Widget build(BuildContext context) {
    final Critter c = critter(challenger);
    const TextStyle emphasis = TextStyle(
      color: Palette.ink,
      fontWeight: FontWeight.w700,
    );
    const TextStyle accent = TextStyle(
      color: Palette.accent2,
      fontWeight: FontWeight.w700,
    );

    return Semantics(
      label: 'Does ${c.name} fly closer or farther than the animal below?',
      child: ExcludeSemantics(
        child: Text.rich(
          TextSpan(
            children: <InlineSpan>[
              const TextSpan(text: 'Does '),
              TextSpan(text: '${c.animal.emoji} ${c.name}', style: emphasis),
              const TextSpan(text: ' fly '),
              const TextSpan(text: 'closer', style: accent),
              const TextSpan(text: ' or '),
              const TextSpan(text: 'farther', style: accent),
              const TextSpan(text: ' than…'),
            ],
          ),
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Palette.muted,
            fontSize: 13,
            height: 1.35,
          ),
        ),
      ),
    );
  }
}

/// The animal being compared against (`.dcard`, `index.html:1069-1070`).
///
/// Laid out differently from the duel's card, as the prototype has it: the
/// avatar and the name sit on one line (a 44px inline disc with the name beside
/// it) with the distance underneath — because this card is a *reference*, not
/// something to tap.
class _AnchorCard extends StatelessWidget {
  const _AnchorCard({required this.anchor, required this.reaction});

  final Asteroid anchor;

  /// The motion the anchor's avatar plays once the guess is revealed.
  final Reaction? reaction;

  @override
  Widget build(BuildContext context) {
    final Critter c = critter(anchor);
    // The one place a distance is stated outright: the child is told exactly
    // where this animal flies so they have something to measure against.
    final String distance = 'flies ${distLabel(anchor.missLunar)} from Earth';

    return Semantics(
      label: '${c.name}, $distance',
      child: ExcludeSemantics(
        child: Padding(
          // `style="margin:10px 0 14px"` (`index.html:1069`).
          padding: const EdgeInsets.only(top: 10, bottom: 14),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              color: Palette.card,
              // `.dcard{border-radius:16px;border:1px solid var(--line)}`
              // (`index.html:212`).
              borderRadius: BorderRadius.all(Radius.circular(16)),
              border: Border.fromBorderSide(BorderSide(color: Palette.line)),
            ),
            child: Padding(
              // `.dcard{padding:14px 10px}`.
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      ReactionAvatar(
                        reaction: reaction,
                        child: _AnchorAvatar(emoji: c.animal.emoji),
                      ),
                      // `margin-left:8px` on the name (`index.html:1070`).
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          c.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          // `.dcard .nm{font-weight:800;font-size:14px}`.
                          style: const TextStyle(
                            color: Palette.ink,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            height: 1.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                  // `.st{margin-top:8px}` (`index.html:1070`).
                  const SizedBox(height: 8),
                  Text(
                    distance,
                    textAlign: TextAlign.center,
                    // `.dcard .st{font-size:11.5px;line-height:1.55}`.
                    style: const TextStyle(
                      color: Palette.muted,
                      fontSize: 11.5,
                      height: 1.55,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The anchor's avatar — the same navy disc every animal wears, at the inline
/// 44px/24px this card uses (`index.html:1069`) rather than the duel's 56/30.
class _AnchorAvatar extends StatelessWidget {
  const _AnchorAvatar({required this.emoji});

  final String emoji;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
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
      child: Text(emoji, style: const TextStyle(fontSize: 24, height: 1)),
    );
  }
}

/// The reveal (`.banner`, `index.html:1078`): *{animal} flies **{distance}** —
/// {closer|farther}.* followed by the outcome.
///
/// **It says where the challenger flew before it says whether the child was
/// right**, which is the whole teaching move of this game — the answer is a real
/// fact about a real rock, not a verdict. Empty but still 22px tall while the
/// round is open, so revealing does not shift the buttons up the screen
/// (`min-height:22px`, `index.html:159`).
class _CloserBanner extends StatelessWidget {
  const _CloserBanner({required this.round, required this.win});

  /// The round being revealed, or null while it is still open.
  final CloserRound? round;

  final bool win;

  @override
  Widget build(BuildContext context) {
    final CloserRound? r = round;
    final Widget content;
    String? semantics;

    if (r == null) {
      content = const SizedBox.shrink();
    } else {
      final Critter c = critter(r.challenger);
      final String distance = distLabel(r.challenger.missLunar);
      final String direction = r.challengerIsCloser ? 'closer' : 'farther';
      // `${win?'✓ +10 ⭐':'✗ good try!'}` (`index.html:1078`) — the wrong-answer
      // half is a nudge, never a telling-off (`CLAUDE.md:70`).
      final String outcome = win ? '✓ +10 ⭐' : '✗ good try!';
      final Color color = win ? Palette.good : Palette.bad;

      semantics = '${c.name} flies $distance — $direction. $outcome';
      content = Text.rich(
        TextSpan(
          children: <InlineSpan>[
            TextSpan(text: '${c.animal.emoji} ${c.name} flies '),
            // The distance is the answer, so it is the one bold thing in the
            // sentence (`<b>${distLabel(ch.missLunar)}</b>`).
            TextSpan(
              text: distance,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            TextSpan(text: ' — $direction. $outcome'),
          ],
        ),
        textAlign: TextAlign.center,
        style: TextStyle(
          color: color,
          fontSize: 16,
          fontWeight: FontWeight.w800,
          height: 1.2,
        ),
      );
    }

    return Padding(
      // `.banner{margin:12px 0}` (`index.html:159`).
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 22),
        child: Semantics(
          liveRegion: semantics != null,
          label: semantics,
          child: ExcludeSemantics(child: Center(child: content)),
        ),
      ),
    );
  }
}

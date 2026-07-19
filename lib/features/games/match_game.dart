/// Animal Match (`specs/04`, game 4) — a port of the prototype's
/// `startSize` / `sizeRound` (`index.html:1086-1119`).
///
/// A mystery rock zooms past showing nothing but its width in metres; the child
/// picks which of three space animals it is. Eight rounds, +10 a correct answer,
/// and the run always finishes — unlike the two streak games, a wrong answer
/// costs the point and nothing else.
///
/// The deal lives next door in `match_round.dart`; this file is the screen.
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rockimals/core/a11y/tap_target.dart';
import 'package:rockimals/core/animals/animal_system.dart';
import 'package:rockimals/core/chrome/action_button.dart';
import 'package:rockimals/core/theme/palette.dart';
import 'package:rockimals/data/models/asteroid.dart';
import 'package:rockimals/features/data/providers.dart';
import 'package:rockimals/features/games/game_shell.dart';
import 'package:rockimals/features/games/match_round.dart';
import 'package:rockimals/features/rewards/reaction.dart';

/// How long the reveal sits before the next round is dealt
/// (`setTimeout(sizeRound,1400)`, `index.html:1116`).
///
/// The longest pause of the four games, and it earns it: the reveal turns the
/// "❓" into the real animal *and* names the species, so this is the beat where
/// the child actually learns the size→animal link the game exists to teach.
const Duration kMatchAdvanceDelay = Duration(milliseconds: 1400);

/// Animal Match: an eight-round quiz that always plays to the end.
///
/// Takes **no injected [Random]** — the suite plays by species name, reading the
/// three option buttons off the board and tapping the one the ladder says is
/// right, so a seed would be an unused parameter (the challenge suite's rule).
class MatchGame extends ConsumerStatefulWidget {
  const MatchGame({super.key});

  @override
  ConsumerState<MatchGame> createState() => _MatchGameState();
}

class _MatchGameState extends ConsumerState<MatchGame> {
  final Random _random = Random();

  late MatchRound _round;

  /// Which question is on screen, 1-based (`sizeQ` *after* its increment,
  /// `index.html:1094`). The score bar shows it as `{question}/8`.
  int _question = 1;

  /// Correct answers so far (`sizeScore`, `index.html:1087`).
  int _score = 0;

  /// The persisted best out of 8, mirrored locally so the end screen can report
  /// a best this run has just beaten (`bestSize`, `index.html:1091`).
  int _best = 0;

  /// The species the child tapped, or null while the round is still open. Once
  /// set, the round is revealed and every option is inert.
  Animal? _picked;

  /// Set when all eight rounds are done; the end screen replaces the board.
  bool _over = false;

  /// The pending advance-or-end timer, cancelled if the screen goes away first.
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _best = ref.read(gameActionsProvider).bestSize;
    _round = dealMatchRound(_sky, _random);
    // `markPlayed()` before the first round, as `startSize` does
    // (`index.html:1088`). Deferred a frame so the store write cannot run
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

  /// The whole sky, not today's list — `rand(asteroids)` (`index.html:1095`),
  /// and the wider pool is what keeps eight rounds from repeating a rock.
  ///
  /// Read rather than watched, so a feed refresh cannot swap the question under
  /// a child's finger mid-answer.
  List<Asteroid> get _sky =>
      ref.read(asteroidsProvider).value ?? const <Asteroid>[];

  /// A fresh run — "Play again" is `startSize` again (`index.html:1093`): the
  /// round counter and score reset, a new rock is dealt, and another play is
  /// counted.
  void _restart() {
    _timer?.cancel();
    unawaited(ref.read(gameActionsProvider).markPlayed());
    setState(() {
      _question = 1;
      _score = 0;
      _over = false;
      _picked = null;
      _round = dealMatchRound(_sky, _random);
    });
  }

  /// What the 1400ms timer does: deal the next question, or — once eight have
  /// been answered — bank the run and show the end screen.
  ///
  /// **The run's two persisted records are written here, not at the last
  /// answer**, exactly where `sizeRound`'s guard puts them
  /// (`index.html:1090-1093`). So a child who backs out of the game on the
  /// eighth reveal banks nothing, which is the prototype's behaviour too.
  void _advance() {
    if (!mounted) return;
    if (_question >= kMatchRounds) {
      _finish();
      return;
    }
    setState(() {
      _question += 1;
      _picked = null;
      _round = dealMatchRound(_sky, _random);
    });
  }

  void _finish() {
    final GameActions actions = ref.read(gameActionsProvider);
    // `if(sizeScore>bestSize)` (`index.html:1091`) — the caller owns the "is
    // this a best?" test, as it does in the two streak games, because it also
    // has to update what the end screen says.
    if (_score > _best) {
      _best = _score;
      unawaited(actions.setBestSize(_score));
    }
    // `if(sizeScore>=SIZE_ROUNDS){prog.perfect++}` (`index.html:1092`) — only a
    // flawless 8/8 counts, and it is a *tally* of perfect runs, not a flag, so
    // the Perfect Match badge can read `perfect > 0` and a profile could one day
    // show how many.
    if (_score >= kMatchRounds) {
      unawaited(actions.notePerfectRun());
    }
    setState(() => _over = true);
  }

  void _pick(Animal option) {
    // The prototype disables every option on the first tap
    // (`x.disabled=true`, `index.html:1110`), so an excited double-tap cannot
    // bank two answers or overwrite a right one with a wrong one.
    if (_picked != null || _over) return;

    final bool win = _round.isCorrect(option);
    ref.read(gameReactionProvider.notifier).react(correct: win);

    if (win) {
      unawaited(ref.read(gameActionsProvider).awardPoints(10));
    }
    setState(() {
      _picked = option;
      if (win) _score += 1;
    });
    _timer = Timer(kMatchAdvanceDelay, _advance);
  }

  @override
  Widget build(BuildContext context) {
    return GameShell(
      // The overlay title `startSize` sets (`index.html:1088`).
      title: '🐾 Animal Match',
      body: _over ? _endPanel() : _board(),
    );
  }

  Widget _endPanel() {
    final GameActions actions = ref.read(gameActionsProvider);
    return GameOverPanel(
      // Not "GAME OVER": nobody loses this one, they finish it
      // (`index.html:1093`).
      title: 'ALL DONE!',
      score: '$_score/$kMatchRounds',
      // `"best "+bestSize+"/"+SIZE_ROUNDS+" · ⭐ "+points+" points"`.
      subtitle: 'best $_best/$kMatchRounds · ⭐ ${actions.points} points',
      onPlayAgain: _restart,
    );
  }

  Widget _board() {
    final Animal? picked = _picked;
    final bool revealed = picked != null;
    final bool win = revealed && _round.isCorrect(picked);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        GameScoreBar(
          scores: <GameScore>[
            GameScore(value: '$_question/$kMatchRounds', label: 'ROUND'),
            GameScore(value: '$_score', label: 'CORRECT'),
          ],
        ),
        _MysteryRock(
          rock: _round.rock,
          revealed: revealed,
          answer: _round.answer,
          // `$("szRock").textContent=an.emoji; react($("szRock"),ok)`
          // (`index.html:1112`) — the reveal and the reaction are the same
          // beat, so the animal appears and celebrates in one motion.
          reaction: reactionFor(revealed ? win : null),
        ),
        for (final Animal option in _round.options)
          _OptionButton(
            option: option,
            // Once revealed the right answer is always marked, whichever way
            // the child went (`if(…endsWith(correct))…add("correct")`,
            // `index.html:1110`) — the teaching beat, not the verdict.
            correct: revealed && _round.isCorrect(option),
            // Only the tapped option is marked wrong; the untouched third
            // stays neutral (`if(!ok)btn.classList.add("wrong")`).
            wrong: revealed && identical(option, picked) && !win,
            onTap: revealed ? null : () => _pick(option),
          ),
        _MatchBanner(answer: revealed ? _round.answer : null, win: win),
      ],
    );
  }
}

/// The mystery rock (`#szRock`, `index.html:1101`) and the question under it.
///
/// **It is a navy animal disc, not a grey rock, even while it shows "❓"** — the
/// element carries `class="grock avatar"` and `.avatar`'s background wins with
/// `!important` (`index.html:226`), the same override the detail and duel
/// avatars take. So the reveal changes only the glyph: the child was always
/// looking at an animal, they just could not see which.
class _MysteryRock extends StatelessWidget {
  const _MysteryRock({
    required this.rock,
    required this.revealed,
    required this.answer,
    required this.reaction,
  });

  final Asteroid rock;
  final bool revealed;
  final Animal answer;

  /// The motion the rock plays as it turns into an animal.
  final Reaction? reaction;

  @override
  Widget build(BuildContext context) {
    // `Math.round(a.diaMax)` (`index.html:1102`) — whole metres, because a
    // decimetre of a space rock means nothing to a six-year-old.
    final String width = '${rock.diaMax.round()} m';

    return Padding(
      // `margin:12px 0` on the centred block (`index.html:1100`).
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        children: <Widget>[
          Semantics(
            label: revealed
                ? 'It is a ${answer.species}'
                : 'A mystery space rock',
            child: ExcludeSemantics(
              child: ReactionAvatar(
                reaction: reaction,
                child: Container(
                  // `width:96px;height:96px;margin:0 auto 12px` — bigger than
                  // any other avatar in the app, because it is the whole
                  // question.
                  width: 96,
                  height: 96,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      center: Alignment(0, -0.16),
                      radius: 0.9,
                      colors: <Color>[Palette.line, Color(0xFF14284A)],
                    ),
                    border: Border.fromBorderSide(
                      BorderSide(color: Palette.line),
                    ),
                  ),
                  child: Text(
                    revealed ? answer.emoji : '❓',
                    // `font-size:46px` (`index.html:1101`).
                    style: const TextStyle(fontSize: 46, height: 1),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Semantics(
            label:
                'A space rock $width wide zooms past! '
                'Which animal is it?',
            child: ExcludeSemantics(
              child: Text.rich(
                TextSpan(
                  children: <InlineSpan>[
                    const TextSpan(text: 'A space rock '),
                    // The one clue the child gets, so it is the one bold white
                    // thing on the screen (`<b style="color:#fff">`,
                    // `index.html:1102`).
                    TextSpan(
                      text: width,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const TextSpan(
                      text: ' wide zooms past!\nWhich animal is it? 🐾',
                    ),
                  ],
                ),
                textAlign: TextAlign.center,
                // `.h-sub{color:var(--muted);font-size:13px;line-height:1.35}`.
                style: const TextStyle(
                  color: Palette.muted,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One answer button (`.opt`, `index.html:221-223`): a full-width, left-aligned
/// card pill holding the species' emoji and name.
///
/// Unlike [ActionButton] these are quiet by default and only colour on the reveal
/// — green on the true answer, red on a wrong tap — which is why they are their
/// own widget rather than a variant of the shared button.
class _OptionButton extends StatelessWidget {
  const _OptionButton({
    required this.option,
    required this.correct,
    required this.wrong,
    required this.onTap,
  });

  final Animal option;

  /// This is the true answer and the round has been revealed.
  final bool correct;

  /// This is what the child tapped, and it was not the answer.
  final bool wrong;

  /// Null once the round is revealed, which is what makes the button inert.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // `.opt.correct{border-color:var(--good);background:rgba(49,196,141,.14)}`
    // and `.opt.wrong{…var(--bad)…rgba(240,82,82,.14)}` (`index.html:223`) —
    // the two rgba fills are exactly `--good`/`--bad` at 14%.
    final Color border = correct
        ? Palette.good
        : wrong
        ? Palette.bad
        : Palette.line;
    final Color fill = correct
        ? Palette.good.withValues(alpha: 0.14)
        : wrong
        ? Palette.bad.withValues(alpha: 0.14)
        : Palette.card;

    return Padding(
      // `.opt{margin-bottom:9px}` (`index.html:221`).
      padding: const EdgeInsets.only(bottom: 9),
      child: Semantics(
        button: true,
        enabled: onTap != null,
        label: option.species,
        child: Material(
          color: fill,
          shape: RoundedRectangleBorder(
            borderRadius: const BorderRadius.all(Radius.circular(12)),
            side: BorderSide(color: border),
          ),
          child: InkWell(
            borderRadius: const BorderRadius.all(Radius.circular(12)),
            onTap: onTap,
            // 47dp — one short, and an answer card is the thing a child taps
            // most in this game.
            child: TapTarget(
              child: Padding(
                // `.opt{padding:13px 14px}` (`index.html:221`).
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 13,
                ),
                child: ExcludeSemantics(
                  child: Text(
                    // `${o.emoji}&nbsp;&nbsp;${o.species}` (`index.html:1108`) —
                    // two **non-breaking** spaces, written as escapes rather than
                    // typed so the gap is visible in the source. They are not
                    // decorative: a plain space is a wrap opportunity, and a
                    // species name that wrapped would strand the emoji alone at
                    // the end of the line.
                    '${option.emoji}\u00A0\u00A0${option.species}',
                    // `text-align:left` — the prototype's one left-aligned
                    // button, so three species names line up to be compared.
                    textAlign: TextAlign.left,
                    style: const TextStyle(
                      color: Palette.ink,
                      // `font-size:15px` from the inline override
                      // (`index.html:1107`), over `.opt`'s 14px.
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
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

/// The reveal (`#szB`, `index.html:1115`): *Yes! 🐘 It's an **Elephant**! +10 ⭐*
/// or *It's 🐘 an **Elephant** — you'll get the next one!*
///
/// **Both halves name the animal**, which is the point: a wrong answer is not a
/// dead end but the moment the child is told what the rock actually was
/// (`CLAUDE.md:70` — never harsh). Empty but still 22px tall while the round is
/// open, so revealing does not shift the buttons up the screen
/// (`min-height:22px`, `index.html:159`).
class _MatchBanner extends StatelessWidget {
  const _MatchBanner({required this.answer, required this.win});

  /// The true species, or null while the round is still open.
  final Animal? answer;

  final bool win;

  @override
  Widget build(BuildContext context) {
    final Animal? a = answer;
    final Widget content;
    String? semantics;

    if (a == null) {
      content = const SizedBox.shrink();
    } else {
      // The prototype writes `a` unconditionally (`It’s a Elephant`); the
      // article is picked here instead, because reading it aloud to a child is
      // exactly what this line is for. Curly apostrophes are the prototype's.
      final String article = _startsWithVowel(a.species) ? 'an' : 'a';
      final Color color = win ? Palette.good : Palette.bad;

      semantics = win
          ? 'Yes! It’s $article ${a.species}! Plus 10 points'
          : 'It’s $article ${a.species} — you’ll get the next one!';
      content = Text.rich(
        TextSpan(
          children: <InlineSpan>[
            TextSpan(
              text: win
                  ? 'Yes! ${a.emoji} It’s $article '
                  : 'It’s ${a.emoji} $article ',
            ),
            // The species is the answer, so it is the one bold word.
            TextSpan(
              text: a.species,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            TextSpan(text: win ? '! +10 ⭐' : ' — you’ll get the next one!'),
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

  /// Of the eight species only "Elephant" takes *an*, but hard-coding that one
  /// name would break the moment the ladder gains a rung.
  static bool _startsWithVowel(String species) => const <String>[
    'a',
    'e',
    'i',
    'o',
    'u',
  ].contains(species[0].toLowerCase());
}

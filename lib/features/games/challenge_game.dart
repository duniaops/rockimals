/// Today's Challenge (`specs/04`, game 1) — a port of the prototype's
/// `startChallenge` / `renderChallenge` / `revealChallenge`
/// (`index.html:880-949`).
///
/// Four of today's space animals in a 2×2 grid; the child taps them in order,
/// strongest power first, then reveals the truth. The scoring lives next door in
/// `challenge_grader.dart`; this file is the screen.
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rockimals/core/animals/animal_system.dart';
import 'package:rockimals/core/theme/palette.dart';
import 'package:rockimals/data/models/asteroid.dart';
import 'package:rockimals/features/data/providers.dart';
import 'package:rockimals/features/games/challenge_grader.dart';
import 'package:rockimals/features/games/game_shell.dart';
import 'package:rockimals/features/rewards/reaction.dart';

/// Today's Challenge, the Play hub's featured game.
///
/// **The one game that does not end through [GameOverPanel].** The other three
/// are runs that finish, so they show the shared `gameOver` screen; this is a
/// single round that *reveals* in place — the grid stays on screen wearing its
/// ✓/✗ marks and the banner turns into the score (`index.html:942-947`). That is
/// the whole point of the game: the child sees which animal was really the
/// strongest, next to where they put it. It still uses [GameShell] and the
/// shared [GameActions] seams like every other game.
///
/// **No injected shuffle seed, deliberately.** The obvious testing hook here is
/// a `Random` the suite can seed, but the game's tests play by *animal name*
/// rather than by grid position, so they hold whatever order the deal produces
/// — which makes a seed an unused parameter, and this plan's rule is that a
/// helper waits for a real caller.
class ChallengeGame extends ConsumerStatefulWidget {
  const ChallengeGame({super.key});

  @override
  ConsumerState<ChallengeGame> createState() => _ChallengeGameState();
}

class _ChallengeGameState extends ConsumerState<ChallengeGame> {
  /// How many animals a round shows (`slice(0, 4)`, `index.html:883`).
  static const int _roundSize = 4;

  late List<Asteroid> _cards;

  /// Card indices in the order the child tapped them (`chPicks`).
  List<int> _picks = <int>[];

  /// Null until "Reveal the truth"; the round's result after.
  ChallengeGrade? _grade;

  @override
  void initState() {
    super.initState();
    _cards = _dealCards();
    // `markPlayed()` before the first render, exactly as `startChallenge` does
    // (`index.html:884`). Deferred a frame so the store write cannot run during
    // initialisation.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(ref.read(gameActionsProvider).markPlayed());
    });
  }

  /// Four animals from today's sky, shuffled (`index.html:882-883`).
  ///
  /// **The pool falls back to the whole window when today is thin**
  /// (`todayList.length >= 4 ? todayList : asteroids`): a quiet day can leave
  /// fewer than four rocks approaching today, and a three-card challenge would
  /// be a different game. `asteroids` is never thin — the repository falls back
  /// to the 14 sample records before it would hand over fewer than six (plan
  /// decision 10) — so there are always four to deal.
  ///
  /// Read rather than watched: a round is dealt once and then frozen, so a feed
  /// refresh mid-round must not swap the cards under a child's fingers.
  List<Asteroid> _dealCards() {
    final List<Asteroid> today =
        ref.read(todayListProvider).value ?? const <Asteroid>[];
    final List<Asteroid> all =
        ref.read(asteroidsProvider).value ?? const <Asteroid>[];
    final List<Asteroid> pool = today.length >= _roundSize ? today : all;
    final List<Asteroid> shuffled = List<Asteroid>.of(pool)..shuffle(Random());
    return shuffled.take(_roundSize).toList(growable: false);
  }

  /// A fresh round — "Play again" is `startChallenge` again
  /// (`index.html:946`), so it deals **new** animals and counts another play.
  void _startOver() {
    unawaited(ref.read(gameActionsProvider).markPlayed());
    setState(() {
      _cards = _dealCards();
      _picks = <int>[];
      _grade = null;
    });
  }

  /// "Start over" mid-round keeps the **same four** and only clears the ranking
  /// (`chPicks=[]`, `index.html:910`) — the child is re-thinking the order, not
  /// asking for a different puzzle.
  void _clearPicks() => setState(() => _picks = <int>[]);

  void _pick(int index) {
    // Already placed, or the ranking is full (`index.html:904`). After a reveal
    // the ranking is full by definition, so the grid goes inert — the
    // prototype's behaviour, and the reason a revealed card cannot be re-tapped.
    if (_picks.contains(index) || _picks.length >= _cards.length) return;
    setState(() => _picks = <int>[..._picks, index]);
  }

  void _reveal() {
    final ChallengeGrade grade = gradeChallenge(cards: _cards, picks: _picks);
    unawaited(ref.read(gameActionsProvider).awardPoints(grade.gain));
    // One reaction for the round, on the prototype's `acc >= 60` threshold
    // (`index.html:939`). The per-card avatar hops (`index.html:937`) are task
    // 05's reaction animations; this is the framework hook they listen on.
    ref.read(gameReactionProvider.notifier).react(correct: grade.isWin);
    setState(() => _grade = grade);
  }

  /// "Done" closes the challenge *and* the Play hub behind it and returns to the
  /// radar (`closeOverlay("ov-ch"); closeOverlay("ov-games"); switchTab("today")`,
  /// `index.html:947`). Both overlays sit above the shell, so popping back to
  /// the first route is the same two closes plus the same landing tab: the child
  /// reached Play from the radar, so that is the tab underneath.
  void _done() =>
      Navigator.of(context).popUntil((Route<void> route) => route.isFirst);

  @override
  Widget build(BuildContext context) {
    final ChallengeGrade? grade = _grade;
    final bool ranked = _picks.length == _cards.length;

    return GameShell(
      // The overlay's own title (`index.html:318`) — not the hub card's
      // "Today's Challenge", which is the card's copy.
      title: 'Daily Challenge',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const _ChallengeInstruction(),
          // `.ch-grid{margin:10px 0}` (`index.html:130`).
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: _ChallengeGrid(
              cards: _cards,
              picks: _picks,
              grade: grade,
              onPick: _pick,
            ),
          ),
          _ChallengeBanner(
            text: grade?.banner ?? '${_picks.length}/${_cards.length} ranked',
            // `.banner.correct` / `.banner.wrong` (`index.html:161`); plain ink
            // while the round is still being ranked.
            color: grade == null
                ? Palette.ink
                : grade.isWin
                ? Palette.good
                : Palette.bad,
          ),
          // `#chActions` (`index.html:908-915,942`): what the child can do next
          // depends only on how far through the round they are.
          if (grade != null) ...<Widget>[
            GameButton(label: 'Play again', onTap: _startOver),
            const SizedBox(height: 8),
            GameButton(label: 'Done', ghost: true, onTap: _done),
          ] else if (ranked) ...<Widget>[
            GameButton(label: 'Reveal the truth', onTap: _reveal),
            const SizedBox(height: 8),
            GameButton(label: 'Start over', ghost: true, onTap: _clearPicks),
          ] else if (_picks.isNotEmpty)
            GameButton(label: 'Start over', ghost: true, onTap: _clearPicks),
        ],
      ),
    );
  }
}

/// The one-line rule of the game (`.h-sub`, `index.html:899`), with the part
/// that matters in accent.
class _ChallengeInstruction extends StatelessWidget {
  const _ChallengeInstruction();

  @override
  Widget build(BuildContext context) {
    return const Text.rich(
      TextSpan(
        children: <InlineSpan>[
          TextSpan(text: 'Tap the space animals in order — '),
          TextSpan(
            text: 'strongest power first ⭐',
            style: TextStyle(
              color: Palette.accent2,
              fontWeight: FontWeight.w700,
            ),
          ),
          TextSpan(text: '.'),
        ],
      ),
      textAlign: TextAlign.center,
      style: TextStyle(color: Palette.muted, fontSize: 13, height: 1.35),
    );
  }
}

/// The 2×2 board (`.ch-grid`, `index.html:130`).
class _ChallengeGrid extends StatelessWidget {
  const _ChallengeGrid({
    required this.cards,
    required this.picks,
    required this.grade,
    required this.onPick,
  });

  final List<Asteroid> cards;
  final List<int> picks;
  final ChallengeGrade? grade;
  final void Function(int) onPick;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      // Inside the shell's scroll view, so the grid sizes to its content
      // instead of competing for the scroll.
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      // `gap:10px` (`index.html:130`).
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      // Taller than square: the card carries an avatar, a name, two stat lines
      // and (after the reveal) the power line, and the rank badge overhangs the
      // top edge.
      childAspectRatio: 0.82,
      children: <Widget>[
        for (int i = 0; i < cards.length; i++)
          _ChallengeCard(
            asteroid: cards[i],
            pickedRank: picks.indexOf(i),
            trueRank: grade?.truthRank[i],
            onTap: () => onPick(i),
          ),
      ],
    );
  }
}

/// One animal in the grid (`.chcard`, `index.html:131-142`).
///
/// Three states in one widget, because the prototype's is one element that gains
/// classes: unpicked, picked (accent border, the rank the child gave it), and
/// revealed (a green or red border, the *true* rank, and the power that decided
/// it).
class _ChallengeCard extends StatelessWidget {
  const _ChallengeCard({
    required this.asteroid,
    required this.pickedRank,
    required this.trueRank,
    required this.onTap,
  });

  final Asteroid asteroid;

  /// Zero-based position the child gave this card, or `-1` if unplaced
  /// (`chPicks.indexOf(i)`, `index.html:890`).
  final int pickedRank;

  /// Zero-based true position, once revealed; null while the round is live.
  final int? trueRank;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Critter c = critter(asteroid);
    final int? revealed = trueRank;
    final bool isPicked = pickedRank >= 0;
    // Exact-position match — the same strict rule the grader's `exactlyCorrect`
    // counts (`ok = userPos === truePos`, `index.html:933`).
    final bool? isCorrect = revealed == null ? null : pickedRank == revealed;

    final Color borderColour = switch (isCorrect) {
      true => Palette.good,
      false => Palette.bad,
      null => isPicked ? Palette.accent : Palette.line,
    };
    // `${sizeLabel(a.diaMax)}<br>${distLabel(a.missLunar)} · ${velKps.toFixed(0)}
    // km/s` (`index.html:892`) — every field through the AnimalSystem
    // formatters, so the game cannot phrase a size or a distance differently
    // from the card that opened it.
    final String size = sizeLabel(asteroid.diaMax);
    final String journey =
        '${distLabel(asteroid.missLunar)} · ${asteroid.velKps.round()} km/s';

    return Semantics(
      button: true,
      // Spoken as a sentence: the emoji, the badge digit and the ⭐ are
      // decoration, so the visual is excluded and the state is said in words
      // (the AnimalCard / nav-bar pattern).
      label: <String>[
        c.name,
        size,
        journey,
        if (revealed != null)
          'power ${powerStars(asteroid)}, really number ${revealed + 1}, '
              '${isCorrect! ? 'you got it right' : 'not quite'}'
        else if (isPicked)
          'you ranked it number ${pickedRank + 1}',
      ].join(', '),
      child: ExcludeSemantics(
        child: Stack(
          // The rank badge overhangs the card's corner (`top:-9px;right:-9px`,
          // `index.html:137`), so it must not be clipped away.
          clipBehavior: Clip.none,
          children: <Widget>[
            Positioned.fill(
              child: Material(
                color: Palette.card,
                shape: RoundedRectangleBorder(
                  // `.chcard{border-radius:16px}` (`index.html:131`).
                  borderRadius: const BorderRadius.all(Radius.circular(16)),
                  side: BorderSide(color: borderColour),
                ),
                child: InkWell(
                  borderRadius: const BorderRadius.all(Radius.circular(16)),
                  onTap: onTap,
                  child: Padding(
                    // `.chcard{padding:12px 10px}` (`index.html:131`).
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 12,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        // Each card reacts to **its own** placement, not to
                        // the round's verdict: `ok = userPos === truePos` per
                        // card (`index.html:937`). So a 3-of-4 reveal is three
                        // hops and one wobble at once — the child sees exactly
                        // which animal they misjudged.
                        ReactionAvatar(
                          reaction: reactionFor(isCorrect),
                          child: _ChallengeAvatar(emoji: c.animal.emoji),
                        ),
                        // `.chcard .mini{margin:0 auto 8px}`.
                        const SizedBox(height: 8),
                        // `.chcard .nm{font-size:13px;font-weight:700}` on one
                        // ellipsised line.
                        Text(
                          c.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Palette.ink,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            height: 1.2,
                          ),
                        ),
                        // `.chcard .st{font-size:11px;margin-top:3px}`.
                        const SizedBox(height: 3),
                        Text(
                          '$size\n$journey',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Palette.muted,
                            fontSize: 11,
                            height: 1.3,
                          ),
                        ),
                        if (revealed != null) ...<Widget>[
                          // `.chcard .reveal{margin-top:6px;font-size:11px;
                          // font-weight:700}` (`index.html:140`).
                          const SizedBox(height: 6),
                          Text(
                            'power ⭐ ${powerStars(asteroid)} · #${revealed + 1}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: isCorrect! ? Palette.good : Palette.bad,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              height: 1.2,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // The rank badge: the child's guess while ranking, the truth after
            // the reveal (`index.html:935-936`).
            if (isPicked || revealed != null)
              Positioned(
                top: -9,
                right: -9,
                child: _RankBadge(
                  rank: (revealed ?? pickedRank) + 1,
                  colour: switch (isCorrect) {
                    true => Palette.good,
                    false => Palette.bad,
                    null => Palette.accent,
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The corner rank pill (`.rankbadge`, `index.html:137`).
class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.rank, required this.colour});

  /// One-based, as shown.
  final int rank;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    return Container(
      // `width:28px;height:28px;border-radius:50%`.
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colour,
        shape: BoxShape.circle,
        boxShadow: <BoxShadow>[
          // `0 3px 10px rgba(0,0,0,.4)`.
          BoxShadow(
            color: const Color(0xFF000000).withValues(alpha: 0.4),
            offset: const Offset(0, 3),
            blurRadius: 10,
          ),
        ],
      ),
      child: Text(
        '$rank',
        // `color:#1a0d05;font-weight:900;font-size:14px`.
        style: const TextStyle(
          color: Palette.onAccent,
          fontSize: 14,
          fontWeight: FontWeight.w900,
          height: 1,
        ),
      ),
    );
  }
}

/// The challenge card's animal avatar (`.chcard .mini.avatar`,
/// `index.html:133,226,229`) — the same navy disc every animal wears, at 52px
/// with a 28px emoji.
///
/// A third local avatar (the list card's is 44px, the detail screen's 56px), and
/// still not extracted: this plan's rule is that a helper waits for a real
/// second *caller*, and these three differ in size and live in three features.
class _ChallengeAvatar extends StatelessWidget {
  const _ChallengeAvatar({required this.emoji});

  final String emoji;

  @override
  Widget build(BuildContext context) {
    return Container(
      // `.chcard .mini{width:52px;height:52px}` (`index.html:133`).
      width: 52,
      height: 52,
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
      child: Text(emoji, style: const TextStyle(fontSize: 28, height: 1)),
    );
  }
}

/// The line under the grid (`.banner`, `index.html:160-161`): the ranking
/// progress while playing, the result once revealed.
class _ChallengeBanner extends StatelessWidget {
  const _ChallengeBanner({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // `.banner{margin:12px 0;min-height:22px}`.
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: SizedBox(
        height: 22,
        child: Center(
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}

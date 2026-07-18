/// The shared game framework (`specs/04`, "Game framework"): the common surface
/// the four games sit inside ([GameShell]), the score bar they share
/// ([GameScoreBar]), the one end screen they all finish through
/// ([GameOverPanel]), and the two seams every game routes an outcome to — points
/// ([GameActions]) and a happy/sad avatar reaction ([gameReactionProvider]).
///
/// **This is the prototype's `ov-game` overlay plumbing, factored out.** In
/// `index.html` every game rewrites the one `#gameBody` element by hand and each
/// calls `markPlayed`, `addPoints`, `react`, and `gameOver` inline
/// (`index.html:1023-1092`). Porting that as four copies would put the scoring
/// rule, the end-screen markup, and the reaction call in four places to drift;
/// this file is the single home for all of it, so a game item below is only the
/// game's own rules (its rounds, its retry loop, its copy) rendered into
/// [GameShell] and finished through [GameOverPanel].
///
/// **The reaction and sound *bodies* are not here** — they are task 05's (`specs/
/// 05`, "Build the reaction animations" / "Build the sound engine"). What is here
/// is the hook: [gameReactionProvider], the single channel a game publishes
/// "right/wrong" to, which those two items consume. See its own doc.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rockimals/core/storage/store.dart';
import 'package:rockimals/core/theme/palette.dart';
import 'package:rockimals/features/data/providers.dart';

/// The two store writes a game makes as it plays: it counts the play
/// ([markPlayed]) and it awards points ([awardPoints]).
///
/// **A plain store-writer, not a `Notifier`, on purpose.** Nothing on screen
/// watches the *lifetime* points total while a game is running — the score bar
/// shows the game's own round score (local state), and the [GameOverPanel]'s
/// subtitle is a string the game builds once. So these are fire-and-forget
/// writes through [storeProvider], the same shape [dayStreakProvider]'s writer
/// would be; the "Wire points" item (`specs/05`) owns lifting the *total* to a
/// reactive read if a surface ever needs it live.
///
/// **`checkBadges()` is deliberately not called yet.** The prototype's
/// `markPlayed`/`addPoints` both end in `checkBadges()` (`index.html:997,999`),
/// but the badge system does not exist (`specs/05`, "Build the badge system").
/// Rather than half-build it here, this leaves the seam to that item, which will
/// run a badge check after these writes land — every badge condition it cares
/// about (Lift Off is `played > 0`, the points badges read the total) is already
/// persisted by the time it does.
class GameActions {
  const GameActions(this._store);

  final Store _store;

  /// Count one game played (`markPlayed`, `index.html:999`). Called once when a
  /// game starts, so `played` is the number of games *begun* — which is what the
  /// prototype counts (every `start*` calls it before the first round) and what
  /// the Lift Off badge (`played > 0`) reads.
  Future<void> markPlayed() => _store.setPlayed(_store.played + 1);

  /// Award [n] points and persist the new total (`addPoints`,
  /// `index.html:997`). Points only ever go up: [n] is required non-negative, so
  /// there is no path here that lowers the total (spec 05, "Points never
  /// decrease").
  Future<void> awardPoints(int n) {
    assert(n >= 0, 'points are only ever awarded, never taken away (spec 05)');
    // A zero award is a real call site (a wrong answer scores 0), and it must
    // not cost a disk write for nothing.
    if (n <= 0) return Future<void>.value();
    return _store.setPoints(_store.points + n);
  }
}

/// The games' two store writes. See [GameActions].
final Provider<GameActions> gameActionsProvider = Provider<GameActions>(
  (Ref ref) => GameActions(ref.watch(storeProvider)),
  name: 'gameActions',
);

/// A right-or-wrong outcome a game just produced, for the avatar to react to —
/// the port of the prototype's `react(el, ok)` call (`index.html:968`), minus
/// the body.
///
/// **This is the reaction *hook*; task 05 is the body.** `specs/04` builds the
/// single place a game says "the child got this right/wrong"; `specs/05` builds
/// what happens then — the hop-and-spin / wobble animation ("Build the reaction
/// animations") and the happy/sad tones ("Build the sound engine", gated on
/// [soundOnProvider]). Both read this channel; until they land, publishing a
/// reaction is silent, which is exactly the framework-without-its-effects this
/// item is scoped to.
///
/// **Modelled on [RadarFocus], and for the same reason: it is a one-shot event
/// held as state, so it carries no value equality.** A game fires a reaction on
/// nearly every tap, and two correct answers in a row are two separate cheers —
/// if this held a bare `bool`, the second `react(true)` would be `==` the first
/// and a `ref.listen` would not fire, swallowing the cue. A fresh [GameReaction]
/// each call is a new event whichever way Riverpod compares.
@immutable
class GameReaction {
  const GameReaction({required this.correct});

  /// Whether the answer was right — happy when true, sad when false. The only
  /// thing the sound engine needs; the reaction animation reads it the same way.
  final bool correct;
}

/// Holds the latest [GameReaction], or null before any answer. Written through
/// [react]; read via `ref.listen` by task 05's reaction and sound systems.
class GameReactionNotifier extends Notifier<GameReaction?> {
  @override
  GameReaction? build() => null;

  /// Publish a reaction to [correct]. A new [GameReaction] every call, so a run
  /// of same-sign answers still fires an event each time (see the class doc).
  void react({required bool correct}) =>
      state = GameReaction(correct: correct);
}

/// The reaction channel every game publishes to. Its own provider — rather than
/// a field on a game — because a reaction spans the game (which fires it) and
/// task 05's avatar and sound (which listen), and none of them owns the others;
/// the [radarFocusProvider] shape, applied to games.
final NotifierProvider<GameReactionNotifier, GameReaction?>
gameReactionProvider = NotifierProvider<GameReactionNotifier, GameReaction?>(
  GameReactionNotifier.new,
  name: 'gameReaction',
);

/// The common game surface (`specs/04`, "a common game surface with a back
/// button and a score bar") — the prototype's `#ov-game`: an `.obar` back-bar
/// carrying the game's [title] over an `.obody` that holds whatever the game is
/// showing right now (`index.html:327-330`).
///
/// The game supplies [body] and swaps it as it plays — a round, then the next
/// round, then a [GameOverPanel] — exactly as the prototype rewrites `#gameBody`
/// (`index.html:1040,1024`). [GameShell] owns only the chrome around it.
class GameShell extends StatelessWidget {
  const GameShell({required this.title, required this.body, super.key});

  /// The bar title, emoji included (`⚔️ Power Duel`, `index.html:1035`).
  final String title;

  /// The game's current screen — a round or the end panel.
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.pageBackground,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _GameTopBar(title: title),
          Expanded(
            child: SingleChildScrollView(
              // `.obody{padding:16px 16px 30px}` (`index.html:95`).
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
              child: body,
            ),
          ),
        ],
      ),
    );
  }
}

/// One cell of a [GameScoreBar]: a big [value] over a small [label].
@immutable
class GameScore {
  const GameScore({required this.value, required this.label});

  /// The number, shown large and white (`.gscore .s b`, `index.html:220`).
  final String value;

  /// Its caption, small, muted, and upper-case-spaced (`STREAK`, `BEST`).
  final String label;
}

/// The shared score bar (`.gscore`, `index.html:219-220`): a centered row of
/// [scores], each a bold number over a spaced caption. Power Duel shows
/// `STREAK` / `BEST`; the other games fill it with their own tallies.
class GameScoreBar extends StatelessWidget {
  const GameScoreBar({required this.scores, super.key});

  final List<GameScore> scores;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // `.gscore{margin:4px 0 8px}` (`index.html:219`).
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          for (int i = 0; i < scores.length; i++) ...<Widget>[
            // `.gscore{gap:22px}` — spacing between cells only.
            if (i > 0) const SizedBox(width: 22),
            _ScoreCell(score: scores[i]),
          ],
        ],
      ),
    );
  }
}

class _ScoreCell extends StatelessWidget {
  const _ScoreCell({required this.score});

  final GameScore score;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          score.value,
          // `.gscore .s b{font-size:22px;color:#fff}` (`index.html:220`).
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w800,
            height: 1,
          ),
        ),
        Text(
          score.label,
          // `.gscore .s span{font-size:10px;color:var(--muted);letter-spacing:1px}`.
          style: const TextStyle(
            color: Palette.muted,
            fontSize: 10,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }
}

/// The one end screen every game finishes through (`gameOver`,
/// `index.html:1023-1031`): a spaced [title], the big accent [score], a muted
/// [subtitle], then **Play again** (which re-runs the game via [onPlayAgain])
/// and **Back to games** (which pops back to the Play hub).
///
/// A game builds this and hands it to its [GameShell] as the body when a run
/// ends — the port of `gameOver` swapping `#gameBody` for the end markup.
class GameOverPanel extends StatelessWidget {
  const GameOverPanel({
    required this.title,
    required this.score,
    required this.subtitle,
    required this.onPlayAgain,
    super.key,
  });

  /// The spaced caption above the score (`GAME OVER`, `ALL DONE!`).
  final String title;

  /// The result, shown huge (`.big2`) — a streak count, an `n/8`, a total.
  /// A string so both a bare number and `6/8` render the same way.
  final String score;

  /// The muted line under it (`best streak 4 · ⭐ 120 points`).
  final String subtitle;

  /// Re-run the game (`$("gAgain").onclick=again`, `index.html:1029`) — the
  /// game's own `start*` again.
  final VoidCallback onPlayAgain;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // `padding-top:26px` on the end block (`index.html:1024`).
      padding: const EdgeInsets.only(top: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            title,
            textAlign: TextAlign.center,
            // `letter-spacing:2px;color:var(--muted)` (`index.html:1025`).
            style: const TextStyle(color: Palette.muted, letterSpacing: 2),
          ),
          Padding(
            // `.big2{margin:8px 0}` (`index.html:224`).
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              score,
              textAlign: TextAlign.center,
              // `.big2{font-size:52px;font-weight:900;color:var(--accent2);
              // line-height:1}`.
              style: const TextStyle(
                color: Palette.accent2,
                fontSize: 52,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
          ),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Palette.muted),
          ),
          // `margin-top:22px` on the button block (`index.html:1027`).
          const SizedBox(height: 22),
          _GameButton(
            label: 'Play again',
            onTap: onPlayAgain,
          ),
          // `#gBack{margin-top:9px}` (`index.html:1028`).
          const SizedBox(height: 9),
          _GameButton(
            label: 'Back to games',
            ghost: true,
            // `closeOverlay("ov-game")` (`index.html:1029`): back to the hub.
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }
}

/// A full-width `.btn` (`index.html:51-56`), filled by default and [ghost] for
/// the secondary action.
///
/// A local clone of the detail screen's `_ActionButton` — the same `.btn` CSS,
/// but stacked full-width here rather than in a row. It is the second `.btn`
/// site in the app; extracting one shared button now has a case, but that is a
/// refactor across the detail module and is left to its own item (the same
/// clone-then-extract rule the shared `.obar` and `.panel` header follow).
class _GameButton extends StatelessWidget {
  const _GameButton({
    required this.label,
    required this.onTap,
    this.ghost = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool ghost;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: DecoratedBox(
        decoration: BoxDecoration(
          // `background:linear-gradient(180deg,var(--accent2),var(--accent))`
          // (`index.html:52`), dropped for the ghost's transparent fill.
          gradient: ghost
              ? null
              : const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[Palette.accent2, Palette.accent],
                ),
          borderRadius: const BorderRadius.all(Radius.circular(14)),
          // `.btn.ghost{border:1px solid var(--line)}` (`index.html:56`).
          border: ghost ? Border.all(color: Palette.line) : null,
          boxShadow: ghost
              ? null
              : <BoxShadow>[
                  // `0 8px 22px rgba(232,87,31,.32)` — `--accent` at .32.
                  BoxShadow(
                    color: Palette.accent.withValues(alpha: 0.32),
                    offset: const Offset(0, 8),
                    blurRadius: 22,
                  ),
                ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: const BorderRadius.all(Radius.circular(14)),
            onTap: onTap,
            child: Padding(
              // `padding:14px` (`index.html:52`).
              padding: const EdgeInsets.all(14),
              child: ExcludeSemantics(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    // `.btn{color:#1a0d05}`; `.btn.ghost{color:var(--ink)}`.
                    color: ghost ? Palette.ink : Palette.onAccent,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                    height: 1,
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

/// The overlay back-bar (`.obar`, `index.html:92-94,328`): a card-pill back
/// button and the game title over a bottom rule.
///
/// A third local copy of the detail screen's `_Obar` (the Play hub holds the
/// second). Three callers now more than justify one shared back-bar, but that
/// extraction spans completed, tested modules and stays its own plan item; this
/// is one game-framework file and keeps to it.
class _GameTopBar extends StatelessWidget {
  const _GameTopBar({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        // `border-bottom:1px solid var(--line2)` (`index.html:92`).
        border: Border(bottom: BorderSide(color: Palette.line2)),
      ),
      child: Padding(
        // `.obar{padding:36px 14px 10px}` — the 36px clears the status bar; the
        // real device inset is added so it clears the notch too.
        padding: EdgeInsets.fromLTRB(
          14,
          36 + MediaQuery.of(context).padding.top,
          14,
          10,
        ),
        child: Row(
          children: <Widget>[
            const _GameBackButton(),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Palette.ink,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The `.back` pill (`index.html:93,328`).
class _GameBackButton extends StatelessWidget {
  const _GameBackButton();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Back',
      child: Material(
        color: Palette.card,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(11)),
          side: BorderSide(color: Palette.line),
        ),
        child: InkWell(
          borderRadius: const BorderRadius.all(Radius.circular(11)),
          onTap: () => Navigator.of(context).maybePop(),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: ExcludeSemantics(
              child: Text(
                '‹ Back',
                style: TextStyle(
                  color: Palette.ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

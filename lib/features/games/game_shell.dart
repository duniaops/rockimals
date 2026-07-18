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
import 'package:rockimals/core/streak/day_streak.dart';
import 'package:rockimals/core/theme/palette.dart';
import 'package:rockimals/features/data/providers.dart';
import 'package:rockimals/features/games/games_providers.dart';

/// Every store write a game makes as it plays: it counts the play
/// ([markPlayed]), awards points ([awardPoints]), and banks its records.
///
/// **A plain store-writer, not a `Notifier`, on purpose.** Nothing on screen
/// watches the *lifetime* points total while a game is running — the score bar
/// shows the game's own round score (local state), and the [GameOverPanel]'s
/// subtitle is a string the game builds once. So these stay fire-and-forget
/// writes through [storeProvider].
///
/// **What the "Wire points" item (`specs/05`) added is [_onStatsChanged].** The
/// Play hub sits one route *below* a running game and shows the points total and
/// each best (`index.html:1010,1004-1006`); those come from
/// [gamesHubStatsProvider], which memoised its read of the store and so kept
/// showing a child their pre-game numbers until the app was relaunched. Every
/// write below that moves one of those four numbers now tells the hub its
/// snapshot is stale, and Riverpod recomputes it before the child sees it again.
///
/// **The callback rather than a `Ref`**, so this class knows nothing about which
/// screen is watching — the games' one seam stays a store-writer, and the four
/// `implements GameActions` fakes in the suites stay trivial.
///
/// **Refreshing synchronously after an un-awaited write is safe, and it is worth
/// recording why**, because it looks like a race: [awardPoints] hands the store
/// a write it does not await and then immediately asks the hub to re-read it.
/// Hive's `_writeFrames` calls `keystore.beginTransaction`, which `insert`s
/// every frame into the in-memory keystore *before* awaiting the disk write
/// (`hive/lib/src/box/box_impl.dart:82-96`, `keystore.dart:184-203`). So the new
/// total is readable the moment [Store.setPoints] returns, and only a disk
/// failure — which reverts the keystore in the same place — could make the
/// refreshed snapshot a lie.
///
/// **`checkBadges()` is deliberately still not called.** The prototype's
/// `markPlayed`/`addPoints` both end in `checkBadges()` (`index.html:997,999`),
/// but the badge system does not exist (`specs/05`, "Build the badge system").
/// Rather than half-build it here, this leaves the seam to that item, which will
/// run a badge check after these writes land — every badge condition it cares
/// about (Lift Off is `played > 0`, the points badges read the total) is already
/// persisted by the time it does.
///
/// **[markPlayed] is also where a game touches the home flame**, and the trigger
/// question decision 14 left open is settled in that method's doc: opening the
/// app stays an engagement, and starting a game is *another* one. The
/// [_onDayStreakChanged] callback is the streak's half of the same
/// "your snapshot is stale" seam [_onStatsChanged] is for the hub.
class GameActions {
  const GameActions(
    this._store,
    this._onStatsChanged,
    this._onDayStreakChanged, {
    DateTime Function() now = DateTime.now,
    // An initializing formal cannot be private *and* named, and the two call
    // sites read far better as `now:` than as a fourth positional argument.
    // ignore: prefer_initializing_formals
  }) : _now = now;

  final Store _store;

  /// Called after a write that moves a number the Play hub shows. See the class
  /// doc: this is the whole of "points are live".
  final void Function() _onStatsChanged;

  /// Called only when [markPlayed] actually *moved* the consecutive-days-played
  /// streak, so the home flame re-reads it. See [markPlayed].
  final void Function() _onDayStreakChanged;

  /// Today, injectable so a test can play a game "tomorrow" without waiting a
  /// day. Production passes nothing and gets [DateTime.now].
  final DateTime Function() _now;

  /// Count one game played (`markPlayed`, `index.html:999`) **and record the day
  /// as engaged**. Called once when a game starts, so `played` is the number of
  /// games *begun* — which is what the prototype counts (every `start*` calls it
  /// before the first round) and what the Lift Off badge (`played > 0`) reads.
  ///
  /// **This settles decision 14's open question: the launch trigger stays, and a
  /// game begun is an engagement too — "engaged" was *not* tightened to
  /// "finished a game".** Three reasons, in order of weight:
  ///
  /// 1. **Rockimals is radar-first.** Games are one of four tabs; a child who
  ///    comes back every day to watch the animals orbit and meet them has used
  ///    the app exactly as intended. Tying the flame solely to games would show
  ///    that child `🔥 0` forever, which is not "days the child came back".
  /// 2. **There is no single "finished" seam to hang it on.** The three scored
  ///    games end through [GameOverPanel], but Today's Challenge reveals in place
  ///    and never builds one (`index.html:942-947`) — so a finish hook would
  ///    have meant four call sites of two different shapes, to drift. `markPlayed`
  ///    is the one call all four games already make exactly once per run.
  /// 3. It still meets the item's bar, because a run that *finishes* necessarily
  ///    *started*: playing on a new day advances the flame with no relaunch.
  ///
  /// [DayStreak.record] is idempotent per day, so on an ordinary day — where the
  /// launch already recorded it — this writes nothing and fires nothing. It earns
  /// its keep in the one case the launch trigger cannot cover: the app left open
  /// across midnight, where the child plays on a day `bootstrap()` never saw.
  Future<void> markPlayed() async {
    await _store.setPlayed(_store.played + 1);
    final int before = _store.dayStreak;
    final int after = await DayStreak.record(_store, _now());
    // Only on a real move: a same-day replay must not repaint the flame, for the
    // reason `awardPoints` short-circuits a zero award.
    if (after != before) _onDayStreakChanged();
  }

  /// The child's lifetime points total (`points`, `index.html:955`) — read, not
  /// watched, because the one surface that needs it is a [GameOverPanel]
  /// subtitle the game builds once when a run ends.
  int get points => _store.points;

  /// The best streak Power Duel has ever reached (`bestDuel`, `aw_duel`,
  /// `index.html:956`). Read when a game starts, to seed its BEST cell.
  int get bestDuel => _store.bestDuel;

  /// Persist a new Power Duel best (`gSet("aw_duel", …)`,
  /// `index.html:1053`). The caller owns the "is this actually a best?" test, as
  /// the prototype does, because it also has to update what is on screen.
  Future<void> setBestDuel(int streak) =>
      _refreshingWrite(_store.setBestDuel(streak));

  /// The best streak Closer or Farther has ever reached (`bestCloser`,
  /// `aw_closer`, `index.html:956`). Read when the game starts, to seed its BEST
  /// cell.
  int get bestCloser => _store.bestCloser;

  /// Persist a new Closer or Farther best (`gSet("aw_closer", …)`,
  /// `index.html:1079`). As with [setBestDuel] the caller owns the "is this
  /// actually a best?" test, because it also has to update what is on screen.
  Future<void> setBestCloser(int streak) =>
      _refreshingWrite(_store.setBestCloser(streak));

  /// The best Animal Match score out of 8 (`bestSize`, `aw_size`,
  /// `index.html:956`). Read when the game starts, so a run that never beats it
  /// can still report it on the end screen.
  int get bestSize => _store.bestSize;

  /// Persist a new Animal Match best (`gSet("aw_size", …)`,
  /// `index.html:1091`). As with [setBestDuel] the caller owns the "is this
  /// actually a best?" test, because it also has to update what is on screen.
  Future<void> setBestSize(int score) =>
      _refreshingWrite(_store.setBestSize(score));

  /// Count one flawless 8/8 run of Animal Match (`prog.perfect++`,
  /// `index.html:1092`) — the Perfect Match badge's condition (`prog.perfect>0`,
  /// `index.html:983`).
  ///
  /// **Unlike the bests, the increment lives here rather than at the call site**
  /// — it is a read-modify-write with no display half, the same shape as
  /// [markPlayed], and a game that had to fetch the tally only to add one to it
  /// would be handling a number it never shows.
  Future<void> notePerfectRun() => _store.setPerfect(_store.perfect + 1);

  /// Record a run of correct answers against the profile's all-time best
  /// (`noteStreak`, `index.html:998`).
  ///
  /// **Cross-game and distinct from [bestDuel]**: `aw_bstreak` is the longest
  /// run of right answers anywhere (the Profile shows it, and the badge system
  /// will read it), while `aw_duel` and `aw_closer` are one game's best each.
  /// Both streak games happen to feed their own best and this one with the same
  /// number, so the distinction only shows across games: a run of 5 in Power
  /// Duel raises `aw_bstreak` above a `aw_closer` of 2, and neither game's own
  /// card moves.
  ///
  /// A no-op unless the streak beats the record, so a losing round costs no disk
  /// write — the same short-circuit [awardPoints] makes.
  Future<void> noteStreak(int streak) {
    if (streak <= _store.bestStreak) return Future<void>.value();
    return _store.setBestStreak(streak);
  }

  /// Award [n] points and persist the new total (`addPoints`,
  /// `index.html:997`). Points only ever go up: [n] is required non-negative, so
  /// there is no path here that lowers the total (spec 05, "Points never
  /// decrease").
  Future<void> awardPoints(int n) {
    assert(n >= 0, 'points are only ever awarded, never taken away (spec 05)');
    // A zero award is a real call site (a wrong answer scores 0), and it must
    // not cost a disk write for nothing — nor a hub repaint, since the total
    // it shows has not moved.
    if (n <= 0) return Future<void>.value();
    return _refreshingWrite(_store.setPoints(_store.points + n));
  }

  /// Tell the Play hub its snapshot is stale, then hand back [write] unchanged.
  ///
  /// **The argument is already applied when this runs**, which is the point:
  /// Dart evaluates `_store.setBestDuel(streak)` before the call, and that
  /// updates Hive's in-memory keystore synchronously (see the class doc), so the
  /// re-read this triggers sees the new number rather than the old one.
  Future<void> _refreshingWrite(Future<void> write) {
    _onStatsChanged();
    return write;
  }
}

/// What "today" is, for the day-streak write [GameActions.markPlayed] makes.
///
/// Its own provider for one reason: without it, the only way to test that
/// playing on a *new day* moves the flame is to hand-build a [GameActions] with
/// a fake clock — which tests everything except the wiring, and the wiring is
/// where the staleness bug lived. Overriding this instead lets a test drive the
/// real [gameActionsProvider], callbacks and all, on any day it likes.
final Provider<DateTime Function()> gameClockProvider =
    Provider<DateTime Function()>((Ref ref) => DateTime.now, name: 'gameClock');

/// The games' store writes. See [GameActions].
final Provider<GameActions> gameActionsProvider = Provider<GameActions>(
  (Ref ref) => GameActions(
    ref.watch(storeProvider),
    // The whole of "the Play hub's numbers are live": drop its memoised
    // snapshot so the next read of it goes back to the store.
    () => ref.invalidate(gamesHubStatsProvider),
    // And the same trick for the home flame — `dayStreakProvider` memoises its
    // read of the store exactly as the hub's snapshot did.
    () => ref.invalidate(dayStreakProvider),
    now: ref.watch(gameClockProvider),
  ),
  name: 'gameActions',
);

/// A right-or-wrong outcome a game just produced — the port of the prototype's
/// `react(el, ok)` call (`index.html:968`), minus the body.
///
/// **This channel is the *sound* half of `react()`, not the motion half.** It
/// was built expecting both to read it, and the reaction-animations item found
/// that only one can. One value per answer is exactly a sound cue — one tap, one
/// tone — but it cannot name *which* avatar on screen moves, and in two games
/// that is not "all of them": Power Duel hops only the tapped card
/// (`index.html:1052`) and Today's Challenge hops all four on their own separate
/// outcomes while playing a single tone chosen by the round's accuracy
/// (`index.html:937,939`). So `ReactionAvatar` is driven by the answer state
/// each widget already holds, and this channel is left to the sound engine
/// ("Build the sound engine", gated on the persisted sound toggle). Until that
/// lands, publishing a reaction is silent.
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

  /// Whether the answer was right — a happy tone when true, a sad one when
  /// false. The only thing the sound engine needs.
  final bool correct;
}

/// Holds the latest [GameReaction], or null before any answer. Written through
/// [react]; read via `ref.listen` by the sound engine.
class GameReactionNotifier extends Notifier<GameReaction?> {
  @override
  GameReaction? build() => null;

  /// Publish a reaction to [correct]. A new [GameReaction] every call, so a run
  /// of same-sign answers still fires an event each time (see the class doc).
  void react({required bool correct}) => state = GameReaction(correct: correct);
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
          GameButton(label: 'Play again', onTap: onPlayAgain),
          // `#gBack{margin-top:9px}` (`index.html:1028`).
          const SizedBox(height: 9),
          GameButton(
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
/// A clone of the detail screen's `_ActionButton` — the same `.btn` CSS, but
/// stacked full-width here rather than in a row. Public rather than private
/// because it is part of the framework the games share: Today's Challenge
/// reveals in place instead of ending through [GameOverPanel]
/// (`index.html:942-947`) and so builds its own Reveal / Start over / Play again
/// / Done stack out of it. Extracting **one** button across the detail module
/// too remains its own plan item; this is reuse inside `features/games`, not
/// that refactor.
class GameButton extends StatelessWidget {
  const GameButton({
    super.key,
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

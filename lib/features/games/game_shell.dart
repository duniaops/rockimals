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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rockimals/core/audio/sound_cues.dart';
import 'package:rockimals/core/chrome/action_button.dart';
import 'package:rockimals/core/chrome/obar.dart';
import 'package:rockimals/core/chrome/panel.dart';
import 'package:rockimals/core/storage/store.dart';
import 'package:rockimals/core/streak/day_streak.dart';
import 'package:rockimals/core/theme/palette.dart';
import 'package:rockimals/features/data/providers.dart';
import 'package:rockimals/features/games/game_round_timer.dart';
import 'package:rockimals/features/games/games_providers.dart';
import 'package:rockimals/features/profile/profile_providers.dart';
import 'package:rockimals/features/rewards/badge_controller.dart';
import 'package:rockimals/features/rewards/sound_controller.dart';

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
/// **[_onProgressChanged] is `checkBadges()`** (`index.html:997-999`), and it
/// fires after every write that can move a badge condition: the play count (Lift
/// Off), the points total (the five tiers), the best streak (On Fire), and a
/// perfect run (Perfect Match). It is a callback rather than a direct call for
/// the reason the other two are — this class stays a store-writer that knows
/// nothing about who is listening. The ninth badge, Zoo Keeper, is earned by
/// following an animal and never passes through here; `BadgeController` watches
/// the follow set itself.
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
    this._onDayStreakChanged,
    this._onProgressChanged, {
    DateTime Function() now = DateTime.now,
    // An initializing formal cannot be private *and* named, and the two call
    // sites read far better as `now:` than as a fourth positional argument.
    // ignore: prefer_initializing_formals
  }) : _now = now;

  final Store _store;

  /// Called after a write that moves a number some screen shows off the store.
  /// See the class doc: this is the whole of "points are live".
  ///
  /// **One callback for every stats snapshot, not one each.** It now drops both
  /// the Play hub's and the Profile's, because a second callback is the shape
  /// that lets a future write remember one reader and forget the other — the
  /// silent staleness `games_providers.dart` warns about, arrived at from the
  /// other direction. Both snapshots re-read the same store on the same
  /// invalidation, so neither can be a frame behind the other.
  final void Function() _onStatsChanged;

  /// Called only when [markPlayed] actually *moved* the consecutive-days-played
  /// streak, so the home flame re-reads it. See [markPlayed].
  final void Function() _onDayStreakChanged;

  /// Called after a write that can earn a badge — the port of the trailing
  /// `checkBadges()` on the prototype's `addPoints`, `noteStreak`, and
  /// `markPlayed` (`index.html:997-999`). See the class doc.
  ///
  /// **Only after a write that actually landed**, which is why it is not folded
  /// into [_refreshingWrite]: the three game bests go through that helper and
  /// no badge reads them, so checking there would ask nine conditions on every
  /// new personal best for nothing.
  final void Function() _onProgressChanged;

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
    // Lift Off (`played > 0`) — the first badge a child can earn, and the only
    // one that fires before they have answered anything.
    _onProgressChanged();
    // Only on a real move: a same-day replay must not repaint the flame, for the
    // reason `awardPoints` short-circuits a zero award. That guard lives in
    // `DayStreak.recordAndNotify` because all three callers of `record` need it.
    await DayStreak.recordAndNotify(_store, _now(), _onDayStreakChanged);
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
  Future<void> notePerfectRun() {
    final Future<void> write = _store.setPerfect(_store.perfect + 1);
    // Perfect Match, celebrated on the run that earned it. The prototype checks
    // nothing here (`index.html:1092`), so its ⭐ waits for the *next* points
    // award or the Profile — a badge that arrives detached from the 8/8 that won
    // it. Spec 05 asks for the popup on the unlock.
    _onProgressChanged();
    return write;
  }

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
    // Through `_refreshingWrite` as of the Profile item: the 🔥 stat is the
    // first surface to *show* this number, so a new record has to reach it
    // without a relaunch. The short-circuit above still means a losing round
    // costs neither a disk write nor a repaint.
    final Future<void> write = _refreshingWrite(_store.setBestStreak(streak));
    // On Fire (`bestStreak >= 5`) — reached only on a write, so a losing round
    // asks nothing (`noteStreak`, `index.html:998`).
    _onProgressChanged();
    return write;
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
    final Future<void> write = _refreshingWrite(
      _store.setPoints(_store.points + n),
    );
    // The five point tiers. After the write, so the check reads the new total —
    // the same synchronous-keystore guarantee `_refreshingWrite` rests on.
    _onProgressChanged();
    return write;
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

/// The games' store writes. See [GameActions].
final Provider<GameActions> gameActionsProvider = Provider<GameActions>(
  (Ref ref) => GameActions(
    ref.watch(storeProvider),
    // The whole of "the store-backed numbers are live": drop both memoised
    // snapshots so the next read of either goes back to the store. See
    // `_onStatsChanged` on why the Profile shares this callback rather than
    // getting a fifth of its own.
    () {
      ref.invalidate(gamesHubStatsProvider);
      ref.invalidate(profileStatsProvider);
    },
    // And the same trick for the home flame — `dayStreakProvider` memoises its
    // read of the store exactly as the hub's snapshot did.
    () => ref.invalidate(dayStreakProvider),
    // `checkBadges()` (`index.html:997-999`). A `read` of the notifier rather
    // than a `watch` of the provider: this must not rebuild `GameActions` — and
    // therefore hand every game a new one mid-run — each time a badge is earned.
    () => ref.read(badgesProvider.notifier).check(),
    // `dayClockProvider`, not a clock of the games' own: a resume from
    // the background writes the same streak on the same day, and two
    // clocks for one calendar is one of them being wrong.
    now: ref.watch(dayClockProvider),
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
/// **It is also where [gameReactionProvider] finally makes a sound.** One
/// `ref.listen` here covers all four games, because all four render into this
/// shell — the alternative was the same three lines repeated in each of them, to
/// drift. Scoping the listener to the shell also scopes it correctly in time: it
/// is alive exactly while a game is on screen, so a reaction can never be heard
/// after the child has left.
///
/// A `ref.listen` rather than a `ref.watch` because a reaction is an *event*, not
/// a value to render; see [GameReaction] on why a fresh instance per answer is
/// what makes two correct answers in a row two audible cheers.
/// The maximum wait before a revealed answer moves on by itself. The button is
/// the primary path; this is only a gentle escape hatch if a child is called
/// away mid-round.
const Duration kGameFeedbackAutoAdvanceDelay = Duration(seconds: 6);

/// The explanation a game gives after an answer. Games own the facts that made
/// an answer correct; the shell owns the consistent, player-paced presentation.
@immutable
class GameFeedback {
  const GameFeedback({
    required this.correct,
    required this.headline,
    required this.explanation,
  });

  final bool correct;
  final String headline;
  final String explanation;
}

/// Three visible chances make a mistake a teaching moment rather than a dead
/// end. Future games may use fewer than three, but their indicator still comes
/// from this one shared component.
class GameLivesIndicator extends StatelessWidget {
  const GameLivesIndicator({
    required this.lives,
    this.totalLives = 3,
    super.key,
  }) : assert(totalLives > 0),
       assert(lives >= 0 && lives <= totalLives);

  final int lives;
  final int totalLives;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$lives of $totalLives lives remaining',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Text(
                'LIVES',
                style: TextStyle(
                  color: Palette.muted,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                List<String>.generate(
                  totalLives,
                  (int index) => index < lives ? '♥' : '♡',
                ).join(' '),
                style: const TextStyle(
                  color: Palette.accent2,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$lives/$totalLives',
                style: const TextStyle(
                  color: Palette.ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The common game surface with a back button, score bar content, optional
/// lives, and the shared answer feedback flow.
class GameShell extends ConsumerStatefulWidget {
  const GameShell({
    required this.title,
    required this.body,
    this.lives,
    this.feedback,
    this.onNext,
    this.practice = false,
    super.key,
  }) : assert(feedback == null || onNext != null);

  /// The bar title, emoji included (`⚔️ Power Duel`, `index.html:1035`).
  final String title;

  /// The game's current screen — a round or the end panel.
  final Widget body;

  /// Whether this run is the tutorial gate's one unscored practice round.
  ///
  /// The scoring already knew (`DuelGame.practice` and friends skip
  /// `markPlayed`, points, and bests) but the *screen* did not: a practice
  /// round looked identical to real play — lives ticking, score bar up — so a
  /// child had no way to tell nothing was being counted yet. When true the
  /// shell pins [GamePracticeBanner] above the round. Here rather than in each
  /// game, per design rule 8 (`docs/GAMES_V2_SPEC.md`): shared presentation
  /// lives in the shell once.
  final bool practice;

  /// Remaining chances for the current run. Null means this game does not use
  /// lives (or is already showing its end panel).
  final int? lives;

  /// The explanation shown once a child has committed to an answer.
  final GameFeedback? feedback;

  /// Advances after [feedback]. The explicit Next button is primary; the shell
  /// invokes this after [kGameFeedbackAutoAdvanceDelay] as an inactivity
  /// fallback.
  final VoidCallback? onNext;

  @override
  ConsumerState<GameShell> createState() => _GameShellState();
}

class _GameShellState extends ConsumerState<GameShell> {
  Timer? _feedbackTimer;
  late final GameRoundTimerPauseNotifier _roundTimerPause;
  late final ProviderContainer _providerContainer;
  int _pausePublishGeneration = 0;
  bool _advanced = false;

  @override
  void initState() {
    super.initState();
    _providerContainer = ProviderScope.containerOf(context, listen: false);
    _roundTimerPause = ref.read(gameRoundTimerPauseReasonsProvider.notifier);
    _scheduleFeedbackAdvance();
    _syncFeedbackTimerPause();
  }

  @override
  void didUpdateWidget(covariant GameShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.feedback, oldWidget.feedback) ||
        widget.onNext != oldWidget.onNext) {
      _scheduleFeedbackAdvance();
    }
    if (!identical(widget.feedback, oldWidget.feedback)) {
      _syncFeedbackTimerPause();
    }
  }

  @override
  void dispose() {
    _feedbackTimer?.cancel();
    // Invalidate any queued publication before releasing this shell's pause.
    _pausePublishGeneration++;
    // Riverpod rejects provider writes while Flutter is disposing the widget
    // tree, so clear after the frame. The scope may be leaving with the shell;
    // in that case there is no shared state left to clean up.
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      GameRoundTimerPauseNotifier pause;
      try {
        pause = _providerContainer.read(
          gameRoundTimerPauseReasonsProvider.notifier,
        );
      } on StateError {
        // ProviderScope may already have disposed its container with the shell.
        return;
      }
      pause.setPaused(GameRoundTimerPauseReason.feedback, false);
    });
    super.dispose();
  }

  void _syncFeedbackTimerPause() =>
      _setRoundTimerPaused(widget.feedback != null);

  void _setRoundTimerPaused(bool paused) {
    // `initState` and `didUpdateWidget` run while Flutter is updating its
    // element tree. Riverpod deliberately rejects provider writes there, so
    // publish after that frame instead. If feedback changes more than once in a
    // frame, callbacks keep their order and the final value wins.
    final int generation = ++_pausePublishGeneration;
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (!mounted || generation != _pausePublishGeneration) return;
      _roundTimerPause.setPaused(GameRoundTimerPauseReason.feedback, paused);
    });
  }

  void _scheduleFeedbackAdvance() {
    _feedbackTimer?.cancel();
    _advanced = false;
    final VoidCallback? onNext = widget.onNext;
    if (widget.feedback == null || onNext == null) return;
    _feedbackTimer = Timer(kGameFeedbackAutoAdvanceDelay, _advance);
  }

  void _advance() {
    if (_advanced || !mounted) return;
    _advanced = true;
    _feedbackTimer?.cancel();
    widget.onNext?.call();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<GameReaction?>(gameReactionProvider, (
      GameReaction? _,
      GameReaction? next,
    ) {
      if (next == null) {
        return;
      }
      // `ok?playHappy():playSad()` (`index.html:968`). Today's Challenge reaches
      // here too, having already folded its four cards into the round's single
      // `acc >= 60` verdict (`index.html:939`) — one tone per round is what the
      // prototype plays there, not one per card.
      unawaited(
        ref
            .read(soundControllerProvider)
            .play(next.correct ? SoundCue.happy : SoundCue.sad),
      );
    });

    return Scaffold(
      backgroundColor: Palette.pageBackground,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Obar(title: widget.title),
          Expanded(
            child: SingleChildScrollView(
              // `.obody{padding:16px 16px 30px}` (`index.html:95`).
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (widget.practice) const GamePracticeBanner(),
                  if (widget.lives case final int lives)
                    GameLivesIndicator(lives: lives),
                  widget.body,
                  if (widget.feedback
                      case final GameFeedback feedback) ...<Widget>[
                    const SizedBox(height: 12),
                    GameFeedbackPanel(feedback: feedback, onNext: _advance),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The visible marker of an unscored round ([GameShell.practice]): a soft
/// accent-tinted strip above the round saying, in words a six-year-old and a
/// screen reader both get, that this one is just for learning. The emoji is
/// decoration and the sentence carries the meaning, the same rule the radar's
/// CTA and the nav follow ("no essential control may rely on an emoji glyph
/// alone", `docs/GAMES_V2_SPEC.md` item 1).
class GamePracticeBanner extends StatelessWidget {
  const GamePracticeBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Palette.accent.withValues(alpha: 0.12),
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          border: Border.all(color: Palette.accent.withValues(alpha: 0.45)),
        ),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            '🎓 Practice round — just for learning, no points yet!',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Palette.ink,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
          ),
        ),
      ),
    );
  }
}

/// The shell's common feedback presentation. [GameShell] controls its timer and
/// composes this widget so future games cannot drift in copy, panel styling, or
/// Next-button accessibility.
class GameFeedbackPanel extends StatelessWidget {
  const GameFeedbackPanel({
    required this.feedback,
    required this.onNext,
    super.key,
  });

  final GameFeedback feedback;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            feedback.headline,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: feedback.correct ? Palette.good : Palette.accent2,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            feedback.explanation,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Palette.ink, height: 1.35),
          ),
          const SizedBox(height: 14),
          ActionButton(label: 'Next', onTap: onNext),
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

/// The one celebratory end screen every game finishes through (`gameOver`,
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

  /// The spaced celebratory caption above the score.
  final String title;

  /// The result, shown huge (`.big2`) — a streak count, an `n/8`, a total.
  /// A string so both a bare number and `6/8` render the same way.
  final String score;

  /// The muted personal-best and points line under it.
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
          ActionButton(label: 'Play again', onTap: onPlayAgain),
          // `#gBack{margin-top:9px}` (`index.html:1028`).
          const SizedBox(height: 9),
          ActionButton(
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

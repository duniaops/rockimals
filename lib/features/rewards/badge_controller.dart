/// When a badge is earned, and what happens next (`specs/05`, "Animal badges") —
/// the port of the prototype's `checkBadges()`, `badgeQueue`, and `drainBadges()`
/// (`index.html:985-996`).
///
/// **The one place that decides a child has earned something.** Every write that
/// can move a badge condition ends by asking [BadgeController.check], exactly as
/// the prototype's `addPoints`/`noteStreak`/`markPlayed` all end in
/// `checkBadges()` (`index.html:997-999`) — but routed through a single object
/// rather than repeated at each call site, for the reason `sound_controller.dart`
/// gives about its own gate: a rule spelled out four times is a rule the *fifth*
/// call site forgets, silently, and the failure ("that badge never popped") is
/// invisible until a child tells someone.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rockimals/core/audio/sound_cues.dart';
import 'package:rockimals/core/storage/store.dart';
import 'package:rockimals/features/data/providers.dart';
import 'package:rockimals/features/games/game_round_timer.dart';
import 'package:rockimals/features/rewards/badges.dart';
import 'package:rockimals/features/rewards/sound_controller.dart';

/// The beat between one celebration closing and the next opening
/// (`setTimeout(drainBadges,300)`, `index.html:1126`).
///
/// **Not cosmetic.** Two badges can be earned by the same tap — crossing 50
/// points on the answer that also finishes a first game earns Mouse Scout and
/// Lift Off at once — and without a gap the second would replace the first
/// mid-fade, reading as one popup whose emoji glitched rather than as two things
/// won. The pause is what makes "queue multiple unlocks" (`specs/05`) legible.
const Duration kBadgeDrainGap = Duration(milliseconds: 300);

/// What the app knows about badges right now: which are earned, which are
/// waiting to be celebrated, and which is on screen.
@immutable
class BadgeState {
  const BadgeState({
    required this.earned,
    required this.queue,
    required this.celebrating,
  });

  /// A fresh install: nothing earned, nothing to show.
  const BadgeState.empty()
    : earned = const <String>{},
      queue = const <AnimalBadge>[],
      celebrating = null;

  /// The ids of every badge earned, ever (`earnedZ`, `index.html:973`) — the
  /// Profile shelf's lit/dimmed test, and the set persisted to `aw_badges`.
  final Set<String> earned;

  /// Badges won but not yet celebrated (`badgeQueue`, `index.html:985`), in the
  /// order they were earned.
  final List<AnimalBadge> queue;

  /// The badge the popup is showing, or null when nothing is being celebrated.
  ///
  /// **Held apart from [queue] rather than read as its head**, which is the
  /// shape [kBadgeDrainGap] needs: during the beat between two celebrations the
  /// popup is closing (nothing is celebrating) while the next badge is still
  /// waiting (the queue is not empty). A `queue.first` model has no way to say
  /// that, and would snap the second popup open the instant the first closed.
  final AnimalBadge? celebrating;

  /// Whether [id] has been earned — the shelf's lit test (`earnedZ.has(b.id)`,
  /// `index.html:523`).
  bool isEarned(String id) => earned.contains(id);

  /// How many badges are earned, for the Profile's 🏅 stat (`earnedZ.size`,
  /// `index.html:535`).
  int get earnedCount => earned.length;
}

/// Owns the earned ledger, the celebration queue, and the cheer.
///
/// **The earned set is one-way, and that is what makes Zoo Keeper safe.** Its
/// condition reads a set a child can shrink by unfollowing an animal
/// (`watch.size>=3`, `index.html:982`), so a system that recomputed "earned"
/// from the current progress would take the badge away again. Nothing here ever
/// removes an id: [check] only adds. A badge is a record of something that
/// happened, not a description of how things are.
class BadgeController extends Notifier<BadgeState> {
  Timer? _drainTimer;

  /// **This provider must be alive for the whole session, and something has to
  /// keep it that way.** A Riverpod provider is created on its first read, so a
  /// badge system nobody has read yet has no follow listener — a child could
  /// follow three animals before the first read and Zoo Keeper would go
  /// unnoticed until the next game write. `BadgePopupHost` is what holds it
  /// open: it watches this from `MaterialApp.builder`, above the `Navigator`,
  /// so it is built in the first frame and never unmounted while the app runs.
  ///
  /// That is a real structural guarantee rather than a lucky one — the popup has
  /// to live there anyway, for the reason its own library doc gives — but it is
  /// worth stating, because the failure it prevents is a missing celebration
  /// with nothing anywhere reporting it. The badge suite reads this provider in
  /// its setup for exactly this reason, and it found the hazard by not doing so.
  @override
  BadgeState build() {
    // **Follows are the one condition nothing else would report.** Points,
    // plays, streaks, and perfect runs all move through `GameActions`, which
    // calls [check] itself; a follow is toggled from the radar HUD and from the
    // detail screen, and having each of those two call the badge system would
    // put the rule in two more places — and in the wrong direction, with the
    // data and radar layers reaching into rewards. Listening here inverts it:
    // rewards watches the follow set, and neither call site knows badges exist.
    //
    // The prototype simply misses this: nothing in it calls `checkBadges()` on a
    // follow, so Zoo Keeper stays invisible until the child happens to open the
    // Profile (`renderProfile`, `index.html:519`) and then pops with no
    // connection to what earned it. Popping on the third follow is the
    // acceptance criterion (`specs/05`: "Following animals fills My Animals and
    // can unlock Zoo Keeper") rather than a liberty taken.
    ref.listen<Set<String>>(followsProvider, (Set<String>? _, Set<String> _) {
      check();
    });

    // A badge often arrives from the same answer that opens shared feedback.
    // Keep its earned record and queue immediately, but wait to put a popup in
    // front of the explanation. When Next (or its fallback) clears feedback,
    // this is the single place that resumes the queue.
    ref.listen<Set<GameRoundTimerPauseReason>>(
      gameRoundTimerPauseReasonsProvider,
      (
        Set<GameRoundTimerPauseReason>? previous,
        Set<GameRoundTimerPauseReason> next,
      ) {
        if (previous?.contains(GameRoundTimerPauseReason.feedback) == true &&
            !next.contains(GameRoundTimerPauseReason.feedback)) {
          _drain();
        }
      },
    );

    ref.onDispose(() => _drainTimer?.cancel());

    // `ref.read`, not `watch`: a rebuild here would drop a queued celebration on
    // the floor, and the store is a single object handed in at boot that never
    // changes identity — there is nothing to watch for.
    return BadgeState(
      earned: ref.read(storeProvider).badges.toSet(),
      queue: const <AnimalBadge>[],
      celebrating: null,
    );
  }

  /// Award every badge whose condition now holds, and start celebrating
  /// (`checkBadges`, `index.html:986-990`).
  ///
  /// **Nothing calls this at launch, deliberately.** [build] seeds the earned
  /// set from the disk and stops there, so a child who reaches 50 points and
  /// force-quits is not greeted by a popup for something they already saw. The
  /// prototype has the same property by accident (its first `checkBadges` comes
  /// from a game or the Profile); here it is the point of not checking in
  /// [build].
  void check() {
    final BadgeProgress progress = _progress();
    List<AnimalBadge>? won;
    for (final AnimalBadge badge in kBadges) {
      if (!state.isEarned(badge.id) && badge.isEarnedBy(progress)) {
        (won ??= <AnimalBadge>[]).add(badge);
      }
    }
    // The overwhelmingly common case — most answers earn nothing — and it must
    // cost no state change, no disk write, and no repaint of anything watching.
    if (won == null) return;

    final Set<String> earned = <String>{
      ...state.earned,
      for (final AnimalBadge badge in won) badge.id,
    };
    state = BadgeState(
      earned: earned,
      queue: <AnimalBadge>[...state.queue, ...won],
      celebrating: state.celebrating,
    );

    // Persisted the moment it is earned, before it is celebrated
    // (`localStorage.setItem` sits above `drainBadges()`, `index.html:988-989`).
    // The order matters for the one case that is not a happy path: an app killed
    // while the popup is up must still have the badge on the shelf next launch.
    // Un-awaited for the same reason `GameActions` un-awaits its writes — Hive's
    // in-memory keystore is updated synchronously, so the value is readable now
    // and only a disk failure could make this a lie.
    unawaited(ref.read(storeProvider).setBadges(earned));

    _drain();
  }

  /// Close the current celebration and, after [kBadgeDrainGap], open the next
  /// (`$("badgePop").onclick`, `index.html:1126`).
  void dismiss() {
    if (state.celebrating == null) return;
    state = BadgeState(
      earned: state.earned,
      queue: state.queue,
      celebrating: null,
    );
    _setBadgeTimerPaused(false);
    _drainTimer?.cancel();
    // The beat belongs between celebrations, not after the last one. Avoid a
    // needless live timer once the final badge has left the screen.
    if (state.queue.isNotEmpty) {
      _drainTimer = Timer(kBadgeDrainGap, _drain);
    }
  }

  /// Show the next queued badge and cheer (`drainBadges`,
  /// `index.html:991-996`).
  ///
  /// The guard is the prototype's `if(!badgeQueue.length||popup.classList
  /// .contains("show"))return` — nothing happens with an empty queue, and a
  /// celebration already on screen is never interrupted by a later one.
  void _drain() {
    if (state.queue.isEmpty ||
        state.celebrating != null ||
        _feedbackIsVisible) {
      return;
    }
    state = BadgeState(
      earned: state.earned,
      queue: state.queue.sublist(1),
      celebrating: state.queue.first,
    );
    _setBadgeTimerPaused(true);
    // `playCheer()` (`index.html:995`) — the fourth call site the sound gate was
    // built for, and the cue's first real trigger. It plays here rather than in
    // the popup widget so that "a badge is being celebrated" and "the fanfare
    // sounds" are one event: a second badge draining after the gap gets its own
    // cheer without the widget having to notice its content changed.
    unawaited(ref.read(soundControllerProvider).play(SoundCue.cheer));
  }

  /// The five numbers every condition reads, at this instant.
  ///
  /// Read from the store rather than held in [state] because the store is where
  /// they already live and `GameActions` writes them directly; a second copy
  /// here would be a thing to drift. The follow count comes from
  /// `followsProvider` instead, which is the live set the radar's Follow button
  /// flips — reading `Store.follows` would be a frame behind on the tap that
  /// earns Zoo Keeper.
  BadgeProgress _progress() {
    final Store store = ref.read(storeProvider);
    return BadgeProgress(
      points: store.points,
      gamesPlayed: store.played,
      bestStreak: store.bestStreak,
      perfectRuns: store.perfect,
      followCount: ref.read(followsProvider).length,
    );
  }

  bool get _feedbackIsVisible => ref
      .read(gameRoundTimerPauseReasonsProvider)
      .contains(GameRoundTimerPauseReason.feedback);

  void _setBadgeTimerPaused(bool paused) {
    ref
        .read(gameRoundTimerPauseReasonsProvider.notifier)
        .setPaused(GameRoundTimerPauseReason.badge, paused);
  }
}

/// The badge system. See [BadgeController].
final NotifierProvider<BadgeController, BadgeState> badgesProvider =
    NotifierProvider<BadgeController, BadgeState>(
      BadgeController.new,
      name: 'badges',
    );

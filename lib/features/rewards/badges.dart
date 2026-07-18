/// The animal badges (`specs/05`, "Animal badges (the collection meta-game)") —
/// the prototype's `ZBADGES` table (`index.html:974-984`) as data, the progress
/// snapshot its conditions read, and the next-tier derivation the Profile's
/// progress bar needs.
///
/// **Pure, and deliberately so.** Nothing here reads a store, a provider, or a
/// widget: a badge is a name, an emoji, a line of copy, and a question asked of
/// five numbers. `badge_controller.dart` owns *when* the question is asked and
/// what happens when the answer changes; this file owns the question. That split
/// is what lets the whole table be checked by plain `test()`s with no Hive box
/// and no widget tree — which matters because these nine conditions are the
/// meta-game, and a wrong `>=` in one of them is a badge a child can never earn.
library;

import 'package:flutter/foundation.dart';

/// Everything a badge condition may look at, read at one instant.
///
/// **A snapshot passed in, rather than each badge reaching for a store.** The
/// prototype's `ok` closures read four mutable globals and one live `Set`
/// (`index.html:975-983`), which is why its conditions can only be evaluated
/// inside the running app. Bundling them makes every condition a pure function
/// of its argument, so the table can be exercised at any point in its space
/// rather than at whatever point the app happened to be in.
///
/// The five fields are exactly the five the prototype's conditions read — no
/// more, so a badge cannot quietly start depending on something the check does
/// not refresh.
@immutable
class BadgeProgress {
  const BadgeProgress({
    required this.points,
    required this.gamesPlayed,
    required this.bestStreak,
    required this.perfectRuns,
    required this.followCount,
  });

  /// Lifetime points (`points`, `index.html:971`) — the five tier badges.
  final int points;

  /// Games begun, ever (`prog.played`, `index.html:972`) — Lift Off.
  final int gamesPlayed;

  /// The best run of correct answers across every game (`prog.bestStreak`) —
  /// On Fire.
  final int bestStreak;

  /// Flawless 8/8 runs of Animal Match (`prog.perfect`) — Perfect Match.
  final int perfectRuns;

  /// How many animals are followed (`watch.size`, `index.html:982`) — Zoo
  /// Keeper.
  final int followCount;
}

/// One badge: what it looks like, what it says, and when it is earned.
@immutable
class AnimalBadge {
  /// A badge whose condition is anything but a points total.
  ///
  /// `const` so the class keeps the guarantee `@immutable` implies, even though
  /// no call site can take it up: a function literal is not a constant
  /// expression, so every badge below is built at run time.
  const AnimalBadge({
    required this.id,
    required this.emoji,
    required this.title,
    required this.description,
    required bool Function(BadgeProgress progress) earnedWhen,
  }) : pointsGoal = null,
       // An initializing formal cannot be private *and* named, and `earnedWhen:`
       // is what reads at the call site — the same trade `GameActions` makes for
       // its `now:`.
       // ignore: prefer_initializing_formals
       _earnedWhen = earnedWhen;

  /// One of the five point tiers (`index.html:976-980`).
  ///
  /// **The threshold is written once here and everything else is derived from
  /// it**, which is the one thing the plan asked this item to change about the
  /// prototype. There, 50 appears in the badge's `ok` closure
  /// (`index.html:976`) *and* again in `nextBadgeGoal`'s own `tiers` array
  /// (`index.html:514`), along with a second copy of the emoji and the title —
  /// two tables that must agree and nothing that makes them. Here the unlock
  /// test, the shelf's "Earn 50 points" line, and the Profile's next-goal bar
  /// all read [pointsGoal].
  AnimalBadge.points({
    required this.id,
    required this.emoji,
    required this.title,
    required int goal,
  }) : pointsGoal = goal,
       description = 'Earn $goal points',
       _earnedWhen = _pointsAtLeast(goal);

  /// The persisted key (`bd.id`, `index.html:975`). Ids are what
  /// `Store.badges` holds, so **these strings are on children's disks** and
  /// renaming one silently un-earns that badge for everybody who had it.
  final String id;

  /// The badge's face (`bd.e`), shown large and hopping in the popup and small
  /// on the shelf.
  final String emoji;

  /// Its name (`bd.t`) — "Mouse Scout". The popup says "New badge! " + this.
  final String title;

  /// How it is earned, in a child's words (`bd.d`) — "Earn 50 points". Shown
  /// under the title in the popup and on every shelf tile, lit or locked, so a
  /// locked badge always tells you what to do (`specs/05`: "locked dimmed with
  /// their goal").
  final String description;

  /// The points needed, for the five tier badges, and null for the other four.
  ///
  /// Doubles as the marker for "this badge belongs on the Profile's progress
  /// bar" — see [nextBadgeGoal], which is the only reason a *nullable int* is
  /// the right shape rather than a bool beside a number.
  final int? pointsGoal;

  final bool Function(BadgeProgress progress) _earnedWhen;

  /// Whether [progress] has earned this badge (`bd.ok()`, `index.html:987`).
  ///
  /// **Monotonic: every condition below is a `>=` or a `>` on a number that
  /// only ever grows**, so a badge once earned stays earned even before
  /// persistence is considered. That is not an accident of the table — points
  /// never decrease (`specs/05`), bests only rise, and a badge that could
  /// un-earn itself when a child unfollowed an animal would be a punishment for
  /// changing their mind. Zoo Keeper is the one that could: it reads a set that
  /// *can* shrink, and it does not un-earn because the earned set is a
  /// one-way ledger in `BadgeController` (`badge_controller.dart`).
  bool isEarnedBy(BadgeProgress progress) => _earnedWhen(progress);

  /// "🐭 Mouse Scout" — the emoji and the name as one string, which is how the
  /// Profile's next-goal line names a badge (`index.html:514,531`).
  String get label => '$emoji $title';

  static bool Function(BadgeProgress) _pointsAtLeast(int goal) =>
      (BadgeProgress progress) => progress.points >= goal;
}

/// All nine badges, in the prototype's order (`ZBADGES`, `index.html:974-984`).
///
/// **The order is load-bearing twice over**, so it is pinned by a test rather
/// than left as a coincidence of how the list was typed:
///
/// * [nextBadgeGoal] walks it front-to-back and stops at the first unmet tier,
///   which is only the *next* goal if the tiers ascend.
/// * The Profile's shelf renders in this order (`index.html:523`), so it reads
///   as a ladder — the journey a child is on — rather than nine unrelated
///   trophies.
///
/// Not `const` because the two constructors take closures, and a function
/// literal is not a constant expression in Dart. Unmodifiable instead, which
/// buys the same protection at the only point that matters: nothing can push a
/// tenth badge onto the ladder at runtime.
final List<AnimalBadge> kBadges = List<AnimalBadge>.unmodifiable(<AnimalBadge>[
  AnimalBadge(
    id: 'play',
    emoji: '🚀',
    title: 'Lift Off',
    description: 'Play your first game',
    earnedWhen: (BadgeProgress p) => p.gamesPlayed > 0,
  ),
  AnimalBadge.points(id: 'mouse', emoji: '🐭', title: 'Mouse Scout', goal: 50),
  AnimalBadge.points(id: 'fox', emoji: '🦊', title: 'Fox Explorer', goal: 150),
  AnimalBadge.points(id: 'bear', emoji: '🐻', title: 'Bear Ranger', goal: 300),
  AnimalBadge.points(
    id: 'ele',
    emoji: '🐘',
    title: 'Elephant Expert',
    goal: 600,
  ),
  AnimalBadge.points(id: 'whale', emoji: '🐋', title: 'Whale Master', goal: 1000),
  AnimalBadge(
    id: 'fire',
    emoji: '🔥',
    title: 'On Fire',
    description: 'Get 5 correct in a row',
    earnedWhen: (BadgeProgress p) => p.bestStreak >= 5,
  ),
  AnimalBadge(
    id: 'keep',
    emoji: '🐾',
    title: 'Zoo Keeper',
    description: 'Follow 3 space animals',
    earnedWhen: (BadgeProgress p) => p.followCount >= 3,
  ),
  AnimalBadge(
    id: 'star',
    emoji: '⭐',
    title: 'Perfect Match',
    description: 'Score 8/8 in Animal Match',
    earnedWhen: (BadgeProgress p) => p.perfectRuns > 0,
  ),
]);

/// How far a child is from their next point tier — the Profile's progress bar
/// and the line under it (`nextBadgeGoal`, `index.html:513-517`).
@immutable
class BadgeGoal {
  const BadgeGoal({required this.badge, required this.have});

  /// The tier being worked towards. Its [AnimalBadge.pointsGoal] is non-null:
  /// [nextBadgeGoal] only ever builds this from a tier badge.
  final AnimalBadge badge;

  /// Points now (`goal.have`).
  final int have;

  /// Points needed (`goal.need`).
  int get need => badge.pointsGoal!;

  /// How many more to go (`goal.need-goal.have`, `index.html:531`).
  int get remaining => need - have;

  /// The bar's fill, 0…1 (`goal.have/goal.need`, `index.html:522`). Clamped
  /// because a *widget* asked for a width outside its box is a layout error
  /// rather than a rounding quirk — the prototype's `width:${pct}%` merely
  /// overflows a hidden box and shows full.
  double get progress => (have / need).clamp(0.0, 1.0);
}

/// The next unearned point tier, or null once all five are collected
/// (`nextBadgeGoal`, `index.html:513-517`).
///
/// **Derived from [kBadges] rather than from a second table**, which is the
/// change this item makes to the prototype — see [AnimalBadge.points]. The
/// walk stops at the first tier above [points], so it is "the next one" only
/// because [kBadges] lists the tiers in ascending order; that ordering is
/// pinned by a test.
///
/// It reads the points total rather than the earned set on purpose, exactly as
/// the prototype does: a child who somehow has 200 points and an empty shelf
/// should be shown the goal their *score* is next to, not asked to re-earn
/// something behind them.
BadgeGoal? nextBadgeGoal(int points) {
  for (final AnimalBadge badge in kBadges) {
    final int? goal = badge.pointsGoal;
    if (goal != null && points < goal) {
      return BadgeGoal(badge: badge, have: points);
    }
  }
  return null;
}

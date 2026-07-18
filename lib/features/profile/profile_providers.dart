/// The numbers the My Space Zoo tab reads off the store (`specs/05`, "My Space
/// Zoo (Profile tab)") — the Profile's half of the snapshot-plus-invalidation
/// shape `gamesHubStatsProvider` established.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rockimals/core/storage/store.dart';
import 'package:rockimals/features/data/providers.dart';

/// The two persisted numbers the Profile shows: the lifetime points total and
/// the best run of correct answers (`points`, `prog.bestStreak`,
/// `index.html:971-972`).
///
/// **Two fields, not four, and the two that are missing are the point.** The
/// Profile shows four numbers, but only these two are *reads of the store*. The
/// badge count lives in `BadgeState` and the follow count in `FollowsNotifier`,
/// both of which are `Notifier`s that already repaint their listeners the frame
/// they change — folding them in here would mean a snapshot that is live in two
/// of its fields and stale in the other two until something remembered to
/// invalidate it. The screen watches those two providers directly instead, so
/// each number's liveness is visible at the place it is read.
///
/// **A second snapshot beside [GamesHubStats] rather than a widening of it.**
/// The plan called for widening that one; this went the other way, for a reason
/// that only appeared with the Profile in hand. `GamesHubStats` lives in
/// `features/games`, and a Profile that read its points total from there would
/// have the profile feature importing the games feature to learn something games
/// do not own — points are the app's, not the Play hub's. Inverting it matches
/// what `GameActions` already does for `dayStreakProvider` (which lives in
/// `features/data`): the *writer* reaches out to tell each reader its snapshot
/// is stale, and no reader imports a sibling feature.
///
/// **The staleness trap that warning was about is still avoided, because there
/// is still exactly one callback.** `GameActions._onStatsChanged` drops both
/// snapshots, so a future field added to either cannot be live in one screen and
/// stale in the other — the failure mode would have been two callbacks, one of
/// which a new write forgot. Both read the same store on the same invalidation,
/// so they cannot drift from each other either.
@immutable
class ProfileStats {
  const ProfileStats({required this.points, required this.bestStreak});

  /// Lifetime points (`aw_points`) — the hero number and the progress bar's
  /// input.
  final int points;

  /// The longest run of correct answers across every game (`aw_bstreak`) — the
  /// 🔥 stat. Deliberately *not* `Store.dayStreak`, which counts days rather
  /// than answers and belongs to the radar's home flame; the two are one typo
  /// apart and would each look plausible in the other's place.
  final int bestStreak;

  /// Value equality, for the reason [GamesHubStats] gives about its own: a
  /// [Provider] decides whether to notify with `==`, so without this every
  /// invalidation that recomputes the *same* numbers would repaint the whole
  /// badge shelf.
  @override
  bool operator ==(Object other) =>
      other is ProfileStats &&
      other.points == points &&
      other.bestStreak == bestStreak;

  @override
  int get hashCode => Object.hash(points, bestStreak);
}

/// The Profile's read-only numbers. See [ProfileStats].
final Provider<ProfileStats> profileStatsProvider = Provider<ProfileStats>((
  Ref ref,
) {
  final Store store = ref.watch(storeProvider);
  return ProfileStats(points: store.points, bestStreak: store.bestStreak);
}, name: 'profileStats');

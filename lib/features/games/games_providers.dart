import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rockimals/core/storage/store.dart';
import 'package:rockimals/features/data/providers.dart';

/// The numbers the Play hub reads off the store: the lifetime points total and
/// the three per-game bests (`openGames`, `index.html:1002-1006`).
///
/// **One snapshot, not four providers.** The prototype reads all four
/// synchronously at the top of `openGames` (`points`, `bestDuel`, `bestCloser`,
/// `bestSize`); bundling them keeps the store's shape out of the widget while
/// giving a test one value to stand in front of the cards (the
/// `dayStreakProvider` seam, one level up).
///
/// **Live as of the "Wire points" item (`specs/05`), by invalidation rather than
/// by holding state.** This stayed a plain [Provider] — the alternative the
/// original note offered — and [GameActions] invalidates it after every write
/// that moves one of these four numbers. The store remains the single source of
/// truth: there is no second in-memory copy of the total that could drift from
/// the box, which a `Notifier` seeded once at `build()` would have introduced.
///
/// Keeping it a [Provider] also kept `overrideWithValue` working, which six test
/// files use to stand a fixed snapshot in front of the hub —
/// `NotifierProvider` has no such override.
///
/// **These four, and only these four, because the Profile did not widen it.**
/// This note used to say that whichever item first needed `played`,
/// `bestStreak`, or `perfect` on screen owned widening this snapshot *and*
/// [GameActions]' invalidation list together — widening one without the other
/// being the silent-staleness bug this item existed to fix. The Profile was that
/// item, and it took the other road: `ProfileStats` is its own snapshot beside
/// this one (see its doc for why a `features/profile` screen reading its points
/// out of `features/games` was the wrong dependency to create). The trap is
/// still shut, because both snapshots hang off the *same* `_onStatsChanged`
/// callback — there is one thing to remember, not two.
///
/// `played` and `perfect` remain unshown by anything; whoever surfaces one
/// inherits the same choice, and the same rule about the callback.
class GamesHubStats {
  const GamesHubStats({
    required this.points,
    required this.bestDuel,
    required this.bestCloser,
    required this.bestSize,
  });

  /// Lifetime points (`aw_points`, `index.html:971`).
  final int points;

  /// Best Power Duel streak (`aw_duel`, `index.html:956`).
  final int bestDuel;

  /// Best Closer or Farther streak (`aw_closer`).
  final int bestCloser;

  /// Best Animal Match score out of 8 (`aw_size`).
  final int bestSize;

  /// Value equality, so an invalidation that recomputes the *same* four numbers
  /// does not repaint the hub — [Provider] decides whether to notify with `==`,
  /// and without this every recompute is a fresh identity and therefore a fresh
  /// rebuild.
  ///
  /// **No write reaches that case today**, since [GameActions] only invalidates
  /// after a number actually moved. It is here because this is a snapshot value
  /// held as provider state, and a value that compares by identity is the sort
  /// of thing the next item widens the invalidation list into a bug. Pinned by
  /// its own test rather than left as an unchecked claim.
  @override
  bool operator ==(Object other) =>
      other is GamesHubStats &&
      other.points == points &&
      other.bestDuel == bestDuel &&
      other.bestCloser == bestCloser &&
      other.bestSize == bestSize;

  @override
  int get hashCode => Object.hash(points, bestDuel, bestCloser, bestSize);
}

/// The Play hub's read-only numbers. See [GamesHubStats].
final Provider<GamesHubStats> gamesHubStatsProvider = Provider<GamesHubStats>((
  Ref ref,
) {
  final Store store = ref.watch(storeProvider);
  return GamesHubStats(
    points: store.points,
    bestDuel: store.bestDuel,
    bestCloser: store.bestCloser,
    bestSize: store.bestSize,
  );
}, name: 'gamesHubStats');

// The sound toggle used to be declared here, because the Play hub's 🔊/🔇
// button was once the only surface that could flip it. It now lives in
// `features/settings/sound.dart` beside the app's other persisted settings —
// three features read it and none of them is `games`. Import it from there.

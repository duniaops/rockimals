import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rockimals/core/storage/store.dart';
import 'package:rockimals/features/data/providers.dart';

/// The numbers the Play hub reads off the store when it opens: the lifetime
/// points total and the three per-game bests (`openGames`,
/// `index.html:1002-1006`).
///
/// **One snapshot, not four providers, and read once rather than watched.** The
/// prototype reads all four synchronously at the top of `openGames`
/// (`points`, `bestDuel`, `bestCloser`, `bestSize`) and never updates them while
/// the hub is on screen — a game that changes a best does so on its own overlay,
/// and `gameOver` → `refreshTabs` re-renders the hub only once it is returned to.
/// So the hub's numbers are a point-in-time read, and bundling them keeps the
/// store's shape out of the widget while giving a test one value to stand in
/// front of the cards (the `dayStreakProvider` seam, one level up).
///
/// **These are a plain read, deliberately not reactive yet.** Nothing writes
/// points or a best today — the four games and the "Wire points" item
/// (`specs/05`) are still ahead — so a plain [Provider] off [storeProvider] is
/// the whole need, exactly as [dayStreakProvider] is until a game writes the
/// streak live. When those items land, whoever makes points accumulate owns
/// lifting this to a `Notifier` (or invalidating it on write) so a best earned
/// in a game shows on the card without a relaunch; the hub reads it the same way
/// either way.
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

/// Whether game sound is on, live — the persisted global toggle the Play hub's
/// 🔊/🔇 button flips (`soundOn`, `index.html:959`, `gSet("aw_sound")`).
///
/// **A `Notifier`, for the same reason [FollowsNotifier] is one: this one
/// changes mid-session and must repaint the same frame.** Tapping the button has
/// to flip the icon at once, so the value cannot be a plain read the way
/// [gamesHubStatsProvider] is — it seeds from the store, holds the live value in
/// [state], and writes every change straight back so it survives a restart
/// (specs 05 and 08 both require the toggle to hold).
///
/// Defaults to **on**: a game that starts silent reads as broken ([Store.soundOn]
/// owns that default, and the note there on why the prototype's own persistence
/// was *not* ported — its `||d` coalesce loses a stored "off" on every reload).
///
/// **Where the *sound* is not, yet.** The prototype plays a cheerful tone when
/// the toggle goes on (`if(soundOn)playHappy()`); the synth that makes that tone
/// is the sound-engine item (`specs/05`). This notifier owns the on/off truth
/// and its persistence; task 05 reads [state] to decide whether a cue sounds and
/// adds the confirmation blip when the toggle is switched on.
class SoundOnNotifier extends Notifier<bool> {
  @override
  bool build() => ref.watch(storeProvider).soundOn;

  /// Flip the toggle and persist the new value (`soundOn=!soundOn;
  /// gSet("aw_sound",…)`, `index.html:1020`).
  Future<void> toggle() {
    final bool next = !state;
    state = next;
    return ref.read(storeProvider).setSoundOn(next);
  }
}

/// The live sound toggle. See [SoundOnNotifier].
final NotifierProvider<SoundOnNotifier, bool> soundOnProvider =
    NotifierProvider<SoundOnNotifier, bool>(
      SoundOnNotifier.new,
      name: 'soundOn',
    );

/// Shared pause state for a game's round timer.
///
/// No game has a round timer yet, but a timer belongs to the round body while
/// its interruptions belong to the shell and its overlays. Keeping those
/// reasons here means a future timed game can simply watch
/// [gameRoundTimerPausedProvider] instead of trying to coordinate feedback and
/// badge popups itself.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// An interruption that should pause a round timer without ending its round.
enum GameRoundTimerPauseReason { feedback, badge }

/// Tracks the current independent reasons a round timer must stay paused.
class GameRoundTimerPauseNotifier
    extends Notifier<Set<GameRoundTimerPauseReason>> {
  @override
  Set<GameRoundTimerPauseReason> build() => const <GameRoundTimerPauseReason>{};

  /// Adds or removes one pause [reason] without disturbing the others.
  void setPaused(GameRoundTimerPauseReason reason, bool paused) {
    if (state.contains(reason) == paused) return;
    if (paused) {
      state = <GameRoundTimerPauseReason>{...state, reason};
    } else {
      state = <GameRoundTimerPauseReason>{...state}..remove(reason);
    }
  }
}

/// The shell and global celebration layer publish their active interruptions
/// here. Timed round bodies will watch [gameRoundTimerPausedProvider].
final NotifierProvider<
  GameRoundTimerPauseNotifier,
  Set<GameRoundTimerPauseReason>
>
gameRoundTimerPauseReasonsProvider =
    NotifierProvider<
      GameRoundTimerPauseNotifier,
      Set<GameRoundTimerPauseReason>
    >(GameRoundTimerPauseNotifier.new, name: 'gameRoundTimerPauseReasons');

/// Whether a future round timer should currently be paused.
final Provider<bool> gameRoundTimerPausedProvider = Provider<bool>((Ref ref) {
  return ref.watch(gameRoundTimerPauseReasonsProvider).isNotEmpty;
}, name: 'gameRoundTimerPaused');

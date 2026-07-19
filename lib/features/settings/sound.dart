/// **🔊 Sound** — the persisted global audio toggle
/// (`specs/05`, `specs/08-settings-about.md:45-46`, `index.html:959`).
///
/// **It lives here, and not with the Play hub, because three features read it
/// and none of them is `games`.** It was declared in
/// `features/games/games_providers.dart` for as long as the hub's 🔊/🔇 button
/// was the only surface that could flip it. Spec 08 added a second flip point in
/// Settings, and `features/rewards/sound_controller.dart` gates every cue in the
/// app on it — so two features were reaching into a third for a value that is
/// not about games at all. One persisted setting, owned end to end by one
/// module, is the shape `calm_motion.dart` and `little_kids_mode.dart` already
/// have; this is the third.
///
/// **What that buys beyond tidiness:** the confirmation blip. The prototype
/// plays a cheerful tone when the toggle goes *on* (`if(soundOn)playHappy()`,
/// `index.html:1020`) — proof to a child that the speaker works. With the
/// notifier in `features/games` that rule had to be duplicated at each button,
/// because moving it into [SoundOnNotifier.toggle] would have made
/// `features/games` and `features/rewards` import each other. From here there is
/// no cycle to create, so the rule can live in one place.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rockimals/core/storage/store.dart';
import 'package:rockimals/features/data/providers.dart';

/// Whether game sound is on, live — the persisted global toggle the Play hub's
/// 🔊/🔇 button and the Settings screen's 🔊 Sound row both flip
/// (`soundOn`, `index.html:959`, `gSet("aw_sound")`).
///
/// **A `Notifier`, because this one changes mid-session and must repaint the
/// same frame.** Tapping the button has to flip the icon at once — the child is
/// looking straight at it — so it seeds from the store, holds the live value in
/// [state], and writes every change straight back so it survives a restart
/// (specs 05 and 08 both require the toggle to hold). Two surfaces show it and
/// neither owns it, which is what stops them disagreeing.
///
/// Defaults to **on**: a game that starts silent reads as broken ([Store.soundOn]
/// owns that default, and the note there on why the prototype's own persistence
/// was *not* ported — its `||d` coalesce loses a stored "off" on every reload).
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

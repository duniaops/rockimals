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
/// `features/games` and `features/rewards` import each other. From here it lives
/// in one place, so both the Play hub's 🔊/🔇 button and the Settings row
/// inherit it and neither can drift.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rockimals/core/audio/sound_cues.dart';
import 'package:rockimals/core/audio/sound_engine.dart';
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

  /// Flip the toggle, persist the new value, and — on the way *on* only —
  /// answer with the happy jingle (`soundOn=!soundOn; gSet("aw_sound",…);
  /// if(soundOn)playHappy()`, `index.html:1020`).
  ///
  /// **The blip belongs here rather than at each button** because there are two
  /// buttons: the Play hub's 🔊/🔇 and the Settings screen's 🔊 Sound row. A
  /// child turning sound back on from Settings needs the same proof the speaker
  /// works that the hub gives, and a rule written twice is a rule that will
  /// eventually be written once. Turning sound *off* is silent — the prototype's
  /// behaviour and the only coherent one, since a cue confirming silence
  /// contradicts itself.
  ///
  /// **Why this reads [soundEngineProvider] directly, when
  /// `sound_engine.dart` says to go through `SoundController`.** The gate exists
  /// so no cue can be played that ignores this toggle; it decides by reading
  /// *this notifier*. Here the answer is settled one statement above — the cue
  /// fires precisely because the flag was just set to `true` — so the gate would
  /// re-enter the notifier it is called from to re-read a value we wrote
  /// ourselves. The layering cost is the real objection: `SoundController` lives
  /// in `features/rewards` and imports this library, so calling it from here
  /// would make settings and rewards import each other — the exact cross-feature
  /// knot moving the toggle into this module untied. `sound_test.dart` grep-pins
  /// that this is the *only* library outside the gate that touches the engine,
  /// so the invariant is now enforced rather than merely documented.
  ///
  /// The cue is deliberately **not** awaited: the returned future is the
  /// persistence write and nothing else, so a slow or wedged audio route cannot
  /// stall a caller that awaits the flip. Same handling `GameShell` gives its
  /// answer cues.
  Future<void> toggle() {
    final bool next = !state;
    state = next;
    if (next) {
      unawaited(ref.read(soundEngineProvider).play(SoundCue.happy));
    }
    return ref.read(storeProvider).setSoundOn(next);
  }
}

/// The live sound toggle. See [SoundOnNotifier].
final NotifierProvider<SoundOnNotifier, bool> soundOnProvider =
    NotifierProvider<SoundOnNotifier, bool>(
      SoundOnNotifier.new,
      name: 'soundOn',
    );

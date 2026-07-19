/// The gate between "something happened" and "the app makes a noise"
/// (`specs/05`, "Build the sound engine") — the port of the `if(!soundOn)return`
/// that opens all three of the prototype's `play*` functions
/// (`index.html:965-967`).
///
/// **Why the gate is one object rather than a check at each call site.** The
/// prototype repeats `if(!soundOn)return` three times and gets away with it
/// because there are only ever three functions. The rule it enforces — "the sound
/// toggle mutes all audio" (`specs/05`), a child's setting the app must not
/// override — is exactly the kind that breaks silently and late, when a *fourth*
/// call site is added and forgets. The badge cheer is that fourth call site, and
/// it lands in the next item. Routing every cue through here means a new sound
/// cannot be added that ignores the toggle.
///
/// **It lives in `features/rewards/` and not `core/audio/` for a layering
/// reason.** The synthesiser and the player know nothing about Rockimals and
/// import nothing from `features/`; this object has to read the sound flag,
/// which is a persisted setting and lives in `features/settings/sound.dart`.
/// Putting the one feature-aware piece here keeps `core/audio/` a
/// self-contained, reusable unit — and puts the gate beside `reaction.dart`, the
/// motion half of the same `react()` call it completes.
///
/// **Why it does not instead live beside the flag in `features/settings/` — a
/// question that is now settled rather than open.** It was raised when
/// `SoundOnNotifier.toggle`'s confirmation blip needed a cue from *inside*
/// `features/settings` and could not use this gate (settings and rewards would
/// have had to import each other), and took a documented exception straight to
/// `soundEngineProvider` instead. Moving the gate beside the flag is the obvious
/// reading of that, and it is wrong twice over:
///
/// - **It would not have removed the exception that raised it.** The blip fires
///   precisely *because* the flag was just set to `true`, so this gate's
///   predicate is provably true at that call site — in any home the gate could
///   have. The exception is intrinsic to the caller, not an artifact of the
///   layering, so relocating buys nothing for the one case that motivated it.
/// - **It would invert what `features/settings/` is.** That module is a leaf:
///   six features import it and it imports nothing but `features/data`. It owns
///   flags. Handing it the app's audio playback would make every feature that
///   wants a noise depend on settings *for playback* — a service hub, not a
///   settings module. A gate that consumes one flag one-way is exactly the shape
///   `reaction.dart` already has against `calm_motion.dart`.
///
/// The trigger to reopen is a **second** settings-side cue whose predicate is
/// not already decided at the call site — at that point the exception has become
/// a rule, and `sound_test.dart`'s allowlist is the wrong place to hold the
/// line. Until then `sound_controller_test.dart` pins this file's location, so
/// the move fails loudly instead of quietly.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rockimals/core/audio/sound_cues.dart';
import 'package:rockimals/core/audio/sound_engine.dart';
import 'package:rockimals/features/settings/sound.dart';

/// Plays a [SoundCue] if — and only if — the persisted sound toggle is on.
///
/// **Reactions still animate when it is off**, which is the acceptance criterion
/// this exists to meet. This object gates *audio* only; the hop and the wobble
/// are driven by `ReactionAvatar` from each game's own answer state, on a path
/// that never reaches here.
class SoundController {
  const SoundController(this._engine, this._isOn);

  final SoundEngine _engine;

  /// Read at play time, never captured — a child can flip the toggle between one
  /// answer and the next, and the very next cue has to obey the new value.
  final bool Function() _isOn;

  /// Play [cue], unless sound is off.
  Future<void> play(SoundCue cue) async {
    if (!_isOn()) {
      return;
    }
    await _engine.play(cue);
  }
}

/// The one object anything that wants to make a noise should use.
///
/// Reads [soundOnProvider] through a callback rather than watching it: watching
/// would rebuild every holder of a controller each time the toggle flips, and the
/// value is only ever wanted at the instant a cue plays.
final Provider<SoundController> soundControllerProvider =
    Provider<SoundController>(
      (Ref ref) => SoundController(
        ref.watch(soundEngineProvider),
        () => ref.read(soundOnProvider),
      ),
      name: 'soundController',
    );

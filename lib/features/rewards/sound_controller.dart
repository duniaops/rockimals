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
/// import nothing from `features/`; this object has to read the sound flag, which
/// currently lives with the Play hub's providers. Putting the one feature-aware
/// piece here keeps `core/audio/` a self-contained, reusable unit — and puts the
/// gate beside `reaction.dart`, the motion half of the same `react()` call it
/// completes.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rockimals/core/audio/sound_cues.dart';
import 'package:rockimals/core/audio/sound_engine.dart';
import 'package:rockimals/features/games/games_providers.dart';

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

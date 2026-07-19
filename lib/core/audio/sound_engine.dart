/// Playback for the synthesised cues (`specs/05`, "Build the sound engine") —
/// the port of the prototype's `actx()`/`AudioContext` half of `beep()`
/// (`index.html:960-964`), and the one place the persisted sound toggle decides
/// whether anything is heard.
///
/// **The split with `tone_synth.dart` is the point of this file.** Everything
/// that decides what a cue *sounds like* is arithmetic over there, testable to
/// the sample on the host VM. Everything here is "hand these bytes to a speaker",
/// which no machine in this project can verify — there is no Xcode and no Android
/// SDK (the human-gated plan item). Keeping the untestable part this thin is
/// deliberate: [SoundEngine] is an interface with one method, so the routing that
/// *can* be checked — which cue fires on which event, and that the toggle
/// silences it — is checked against a fake, and only the final byte handoff rests
/// on a device nobody has yet run this on.
library;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rockimals/core/audio/sound_cues.dart';
import 'package:rockimals/core/audio/tone_synth.dart';

/// Something that can make a [SoundCue] audible.
///
/// An interface with a single method so the suite can substitute a recorder and
/// assert cue-by-cue what the app tried to play — see the library doc.
abstract class SoundEngine {
  /// Play [cue] now, cutting off whatever was still sounding.
  ///
  /// Implementations must not throw: see [ToneSoundEngine.play] for why a failed
  /// sound is never allowed to become a failed game.
  Future<void> play(SoundCue cue);

  /// Release the platform player. Called when the owning provider is disposed.
  Future<void> dispose();
}

/// The real engine: renders each cue to WAV bytes once and plays it through the
/// platform's media player.
class ToneSoundEngine implements SoundEngine {
  /// Created on first [play], not here — see [_player].
  ///
  /// **The player is not injectable, and that is the layering working.** A test
  /// that wants to assert what the app played substitutes the whole
  /// [SoundEngine], not a fake `AudioPlayer` inside this one; there is nothing
  /// left in this class worth testing around a stub player, which is the point of
  /// keeping it this thin.
  AudioPlayer? _player;

  /// Rendered cues, kept after their first play.
  ///
  /// **Lazy and cached, in that order.** Rendering all three up front would spend
  /// the work on a child who opens the app to watch the radar and never plays a
  /// game; rendering on *every* play would redo about 24,000 samples of `pow()`
  /// on the tap that most needs to feel instant. Three cues is at most ~130kB
  /// held for the session, which is less than a single small image.
  final Map<SoundCue, Uint8List> _rendered = <SoundCue, Uint8List>{};

  @override
  Future<void> play(SoundCue cue) async {
    final Uint8List bytes = _rendered.putIfAbsent(
      cue,
      () => encodeWav(notesFor(cue)),
    );
    try {
      final AudioPlayer player = _player ??= AudioPlayer();
      // `stop` first so a fast run of answers re-triggers from the top rather
      // than being ignored while the previous cue is still ringing — the
      // prototype gets this free, since every WebAudio `beep` builds its own
      // oscillator and the old one simply keeps playing out.
      await player.stop();
      await player.play(BytesSource(bytes));
    } catch (error, stack) {
      // **A sound that will not play must never take the game down with it.**
      // Audio is the one subsystem here that depends on hardware and on a
      // platform plugin: a device with no audio route, a player the OS declines
      // to hand over mid-call, or a host test VM with no plugin registered at
      // all will all throw from these two lines. Every one of them should end
      // as a silent tap, because the answer was still graded, the points were
      // still awarded, and the avatar still hopped — sound is the decoration on
      // top. Swallowed loudly enough to debug (`FlutterError.reportError` prints
      // in debug and is collectable in release) and never rethrown.
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'rockimals sound',
          context: ErrorDescription('playing the $cue cue'),
        ),
      );
    }
  }

  @override
  Future<void> dispose() async {
    final AudioPlayer? player = _player;
    _player = null;
    _rendered.clear();
    if (player == null) {
      return;
    }
    try {
      await player.dispose();
    } catch (_) {
      // Tearing down a player that never successfully started is not a failure
      // worth reporting, and this runs during provider disposal.
    }
  }
}

/// The app's [SoundEngine]. Overridden with a fake in tests.
final Provider<SoundEngine> soundEngineProvider = Provider<SoundEngine>((
  Ref ref,
) {
  final ToneSoundEngine engine = ToneSoundEngine();
  ref.onDispose(engine.dispose);
  return engine;
}, name: 'soundEngine');

/// **The toggle gate is deliberately not here** — it is `SoundController`
/// (`lib/features/rewards/sound_controller.dart`). This library stays free of any
/// `features/` import so `core/` never depends on a feature, and the sound
/// on/off flag is a persisted setting (`lib/features/settings/sound.dart`). The
/// practical consequence: nothing should call [soundEngineProvider] directly; go
/// through the controller, which is the single place the toggle is honoured.
///
/// **There is exactly one sanctioned exception, and it is enforced rather than
/// trusted**: `SoundOnNotifier.toggle` plays the confirmation blip that answers
/// "sound on" straight through this provider, because it has just set the flag
/// the gate would ask about and routing through the gate would knot
/// `features/settings` and `features/rewards` together. `sound_test.dart` greps
/// `lib/` for reads of [soundEngineProvider] and fails on any third library, so
/// a new direct caller cannot appear unnoticed.

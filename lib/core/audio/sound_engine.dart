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
///
/// **What the handoff is wrapped in is testable even though the handoff is not**,
/// and [ToneSoundEngine.handOffToPlatform] is the seam that says so: a player can
/// fail by throwing *or* by never answering, and both have to end as a silent tap
/// rather than a stuck game. The second is not reachable on a host VM by accident
/// — it is the state a missing binding produces, and it hangs the caller instead
/// of failing it — so it is produced deliberately in the suite.
library;

import 'dart:async';

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

/// How long [ToneSoundEngine.play] waits for the platform player before it stops
/// holding its caller and reports the cue as lost.
///
/// **This number is not the device-latency judgement it looks like**, which is
/// what let it be picked without a device to measure on. It does not cancel
/// anything: `Future.timeout` abandons the *wait*, not the playback, so a player
/// that was merely slow still plays its cue, and [ToneSoundEngine] still notices
/// it answered (the in-flight guard clears on the real completion, however late).
/// All the bound decides is how long a caller is held and when a hung player is
/// worth a line in the log. Two seconds is far above any plausible time to *start*
/// a 300ms jingle and far below a child noticing the app is thinking.
const Duration kPlatformCallTimeout = Duration(seconds: 2);

/// The real engine: renders each cue to WAV bytes once and plays it through the
/// platform's media player.
class ToneSoundEngine implements SoundEngine {
  /// Created on first [play], not here — see [handOffToPlatform].
  ///
  /// **The player is not injectable, and that is the layering working.** A test
  /// that wants to assert what the app played substitutes the whole
  /// [SoundEngine], not a fake `AudioPlayer` inside this one. What *is* worth
  /// testing in this class is the guarding around the handoff rather than the
  /// handoff itself, and [handOffToPlatform] is the seam that makes exactly that
  /// reachable without a stub player.
  AudioPlayer? _player;

  /// The platform call that has been made and has not come back yet, or `null`.
  ///
  /// **This is the whole fix for cues piling up.** `GameShell` fires each cue
  /// through `unawaited(...)`, so before this existed a player that never
  /// answered leaked one suspended call per answer for the life of the screen.
  /// Holding the in-flight call here and dropping any cue that arrives while it
  /// is set caps that at one, forever — a wedged player costs a single stuck
  /// frame instead of a slow drip.
  ///
  /// **Cleared on the real completion, not on the timeout**, which is what keeps
  /// this from becoming a permanent mute. If the platform was only slow and
  /// answers after the bound, the next cue is handed off normally; if it truly
  /// never answers, no second call is ever started. Neither case needed a guess
  /// about which one a device would produce.
  Future<void>? _handOff;

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
    // `audioplayers`' web platform handoff can stay pending even though the
    // browser has no native player to initialise. That turned every game cue
    // into a two-second timeout report. Web keeps the persisted sound setting
    // and its visible toggle, but does not attempt a native-only handoff.
    //
    // Keep this before synthesis too: rendering an inaudible WAV on every tap
    // is needless work, and this leaves iOS/Android behaviour exactly below.
    if (kIsWeb) {
      return;
    }

    final Uint8List bytes = _rendered.putIfAbsent(
      cue,
      () => encodeWav(notesFor(cue)),
    );

    if (_handOff != null) {
      // The previous cue's platform call has not come back. Drop this one
      // rather than queue behind it — see [_handOff]. On a working player the
      // pair below resolves in milliseconds and answers are seconds apart, so
      // this branch is reached only when something is already wrong.
      return;
    }

    final Future<void> handOff = _handOffAndReport(cue, bytes);
    _handOff = handOff;
    unawaited(
      handOff.whenComplete(() {
        _handOff = null;
      }),
    );

    try {
      await handOff.timeout(kPlatformCallTimeout);
    } on TimeoutException catch (error, stack) {
      // **The caller is released; the call is not cancelled.** Letting `play`
      // hang forever is how a hung player reached `GameShell`'s `unawaited`
      // futures in the first place, so the wait is bounded even though the
      // playback it is waiting on cannot be.
      _report(cue, error, stack);
    }
  }

  /// The platform handoff with its failures already swallowed and reported, so
  /// that both the awaited path and the guard-clearing chain in [play] observe
  /// an error-free future and no failure goes unhandled on one of them.
  Future<void> _handOffAndReport(SoundCue cue, Uint8List bytes) async {
    try {
      await handOffToPlatform(bytes);
    } catch (error, stack) {
      _report(cue, error, stack);
    }
  }

  /// Hand [bytes] to the platform player and complete when it says it started.
  ///
  /// **Overridable purely so the guarding in [play] is testable.** No machine in
  /// this project can drive a real `AudioPlayer` (no Xcode, no Android SDK — the
  /// human-gated plan item), and a host VM cannot even reach the failure this
  /// method models: without a binding `AudioPlayer`'s internal creation future
  /// simply never completes. Subclassing this one method lets the suite produce
  /// "never answers" on demand and check that a hung player is bounded, dropped,
  /// and recovered from — none of which is about the two lines below.
  @protected
  Future<void> handOffToPlatform(Uint8List bytes) async {
    final AudioPlayer player = _player ??= AudioPlayer();
    // `stop` first so a fast run of answers re-triggers from the top rather
    // than being ignored while the previous cue is still ringing — the
    // prototype gets this free, since every WebAudio `beep` builds its own
    // oscillator and the old one simply keeps playing out.
    await player.stop();
    await player.play(BytesSource(bytes));
  }

  /// **A sound that will not play must never take the game down with it.**
  ///
  /// Audio is the one subsystem here that depends on hardware and on a platform
  /// plugin: a device with no audio route, a player the OS declines to hand over
  /// mid-call, a host test VM with no plugin registered at all, or one that takes
  /// the handoff and never answers. Every one of them should end as a silent tap,
  /// because the answer was still graded, the points were still awarded, and the
  /// avatar still hopped — sound is the decoration on top. Swallowed loudly
  /// enough to debug (`FlutterError.reportError` prints in debug and is
  /// collectable in release) and never rethrown.
  void _report(SoundCue cue, Object error, StackTrace stack) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'rockimals sound',
        context: ErrorDescription('playing the $cue cue'),
      ),
    );
  }

  @override
  Future<void> dispose() async {
    final AudioPlayer? player = _player;
    _player = null;
    _handOff = null;
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

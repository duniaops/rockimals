/// A [SoundEngine] that records instead of playing, plus the provider overrides
/// every widget test needs once a game can make a noise.
///
/// **Why this is shared rather than a private fake per file.** Wiring the sound
/// engine into [GameShell] put a new provider read on the path of *every* answer
/// tap, so the four game suites and the hub suite all had to stand something in
/// front of it at once. A per-file `_FakeEngine` would have been the same twenty
/// lines copied five times, and the next screen that plays a cue — the badge
/// popup — would have made it six.
///
/// Standing a fake here is not only about avoiding the plugin. It is the only way
/// the acceptance criterion "the sound toggle mutes all audio" can be *checked*:
/// a real engine on a host VM is silent whether or not the gate works, so the
/// test would pass on a completely broken gate. Recording what the app asked to
/// play makes the difference observable.
library;

import 'package:rockimals/core/audio/sound_cues.dart';
import 'package:rockimals/core/audio/sound_engine.dart';
import 'package:rockimals/features/settings/sound.dart';

/// Captures the cues it is asked to play, in order.
class RecordingSoundEngine implements SoundEngine {
  /// Every cue that reached the engine — i.e. that got past the toggle gate.
  final List<SoundCue> played = <SoundCue>[];

  bool disposed = false;

  @override
  Future<void> play(SoundCue cue) async => played.add(cue);

  @override
  Future<void> dispose() async => disposed = true;
}

/// A sound toggle held at [_on] without touching the store.
class StubSoundOn extends SoundOnNotifier {
  StubSoundOn(this._on);

  final bool _on;

  @override
  bool build() => _on;

  @override
  Future<void> toggle() async {
    // Deliberately inert: a test that wants the real flip-and-persist behaviour
    // uses the real notifier over a temp-directory store, as the hub suite does.
  }
}

// **There is no `silentSoundOverrides()` helper returning the pair of overrides
// a caller needs, and the reason is riverpod's API, not taste.** `ProviderScope`
// declares `final List<Override> overrides`, but `Override` itself is not in
// riverpod 3.3.2's export list (`riverpod.dart` `show`s ~26 names and that is not
// one of them). A function returning the list therefore cannot spell its own
// return type, and a `List<Object>` will not spread into a `List<Override>`. So
// call sites write the two lines themselves:
//
//     soundEngineProvider.overrideWithValue(engine),
//     soundOnProvider.overrideWith(() => StubSoundOn(true)),
//
// The fakes above are still shared, which is the part that was worth sharing.

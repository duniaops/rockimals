/// The toggle gate (`specs/05`, "Build the sound engine": *"toggling sound off
/// silences all audio while reactions still animate"*).
///
/// This is the acceptance criterion stated as a unit test. It reads a recording
/// engine rather than a real one on purpose — see `recording_sound_engine.dart`
/// for why a silent host VM cannot tell a working gate from a broken one.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/core/audio/sound_cues.dart';
import 'package:rockimals/core/audio/sound_engine.dart';
import 'package:rockimals/features/rewards/sound_controller.dart';
import 'package:rockimals/features/settings/sound.dart';

import '../../support/recording_sound_engine.dart';

void main() {
  group('the sound toggle gates every cue', () {
    test('with sound on, a cue reaches the engine', () async {
      final RecordingSoundEngine engine = RecordingSoundEngine();
      final SoundController controller = SoundController(engine, () => true);

      await controller.play(SoundCue.happy);

      expect(engine.played, <SoundCue>[SoundCue.happy]);
    });

    test('with sound off, nothing reaches the engine', () async {
      final RecordingSoundEngine engine = RecordingSoundEngine();
      final SoundController controller = SoundController(engine, () => false);

      for (final SoundCue cue in SoundCue.values) {
        await controller.play(cue);
      }

      expect(engine.played, isEmpty, reason: 'the toggle must mute all audio');
    });

    test(
      'every cue in the enum is gated, not just the two games use',
      () async {
        // The gate exists so that a *future* sound cannot bypass it — the badge
        // cheer is the next one to land. Iterating the enum means a new cue is
        // covered the day it is added rather than the day someone remembers.
        final RecordingSoundEngine engine = RecordingSoundEngine();
        final SoundController off = SoundController(engine, () => false);
        final SoundController on = SoundController(engine, () => true);

        for (final SoundCue cue in SoundCue.values) {
          await off.play(cue);
        }
        expect(engine.played, isEmpty);

        for (final SoundCue cue in SoundCue.values) {
          await on.play(cue);
        }
        expect(engine.played, SoundCue.values);
      },
    );

    test('the flag is read per cue, so a mid-session flip takes effect', () async {
      // The child taps the speaker button between two answers. The next cue must
      // obey the new value — a controller that captured the flag at construction
      // would keep playing until the screen was rebuilt.
      final RecordingSoundEngine engine = RecordingSoundEngine();
      bool on = true;
      final SoundController controller = SoundController(engine, () => on);

      await controller.play(SoundCue.happy);
      on = false;
      await controller.play(SoundCue.sad);
      on = true;
      await controller.play(SoundCue.cheer);

      expect(engine.played, <SoundCue>[SoundCue.happy, SoundCue.cheer]);
    });
  });

  group('the wired-up controller', () {
    test('reads the real sound toggle through the provider graph', () async {
      final RecordingSoundEngine engine = RecordingSoundEngine();
      final ProviderContainer container = ProviderContainer(
        overrides: [
          soundEngineProvider.overrideWithValue(engine),
          soundOnProvider.overrideWith(() => StubSoundOn(false)),
        ],
      );
      addTearDown(container.dispose);

      await container.read(soundControllerProvider).play(SoundCue.happy);

      expect(engine.played, isEmpty);
    });

    test('plays once the toggle provider says on', () async {
      final RecordingSoundEngine engine = RecordingSoundEngine();
      final ProviderContainer container = ProviderContainer(
        overrides: [
          soundEngineProvider.overrideWithValue(engine),
          soundOnProvider.overrideWith(() => StubSoundOn(true)),
        ],
      );
      addTearDown(container.dispose);

      await container.read(soundControllerProvider).play(SoundCue.cheer);

      expect(engine.played, <SoundCue>[SoundCue.cheer]);
    });
  });

  group('the real engine', () {
    test('never throws when there is no audio plugin to talk to', () async {
      // A host VM has no registered `audioplayers` plugin, so this exercises the
      // exact failure path a device with no audio route would take. It must end
      // as a silent tap: the answer was still graded and the avatar still
      // hopped, and sound is the decoration on top of that. A throw here would
      // surface as a crash mid-game.
      //
      // **The binding is required, and what happens without it is worth
      // recording.** With no `TestWidgetsFlutterBinding`, there is no platform
      // channel machinery at all and `AudioPlayer`'s internal `_create` never
      // completes — this test hangs to its 30s timeout rather than failing. With
      // the binding, an unregistered plugin throws `MissingPluginException`,
      // which is the case a real device hits.
      TestWidgetsFlutterBinding.ensureInitialized();

      // The reported error is expected and consumed, not a test failure.
      final List<FlutterErrorDetails> reported = <FlutterErrorDetails>[];
      final FlutterExceptionHandler? previous = FlutterError.onError;
      FlutterError.onError = reported.add;
      addTearDown(() => FlutterError.onError = previous);

      final ToneSoundEngine engine = ToneSoundEngine();
      await expectLater(engine.play(SoundCue.happy), completes);
      await expectLater(engine.dispose(), completes);

      expect(
        reported,
        isNotEmpty,
        reason: 'a swallowed failure should still be reported for debugging',
      );
    });

    test('disposing one that never played is harmless', () async {
      await expectLater(ToneSoundEngine().dispose(), completes);
    });
  });

  group('the gate stays in features/rewards', () {
    test('no library outside this feature declares it', () {
      // The tripwire for a decision that was otherwise only a comment, and
      // comments do not fail. `SoundOnNotifier.toggle`'s confirmation blip needed
      // a cue from inside `features/settings` and could not use this gate, which
      // made "move the gate beside the flag" look like the obvious fix. It is
      // not, for two reasons recorded in full in `sound_controller.dart`: it
      // would not have removed that exception (the blip's predicate is decided
      // one statement above it, in any home the gate could have), and it would
      // hand `features/settings` — a leaf that six features import and that
      // imports nothing but `features/data` — responsibility for the app's audio
      // playback.
      //
      // The mirror of `sound_test.dart`'s guard on the *toggle's* location, and
      // it exists for the same reason: the argument is about where a thing lives,
      // so nothing but a check on where it lives can hold it.
      final List<String> offenders = <String>[];
      for (final FileSystemEntity entity in Directory(
        'lib',
      ).listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        if (entity.path.endsWith('features/rewards/sound_controller.dart')) {
          continue;
        }
        final String source = entity.readAsStringSync();
        if (source.contains('class SoundController') ||
            source.contains('soundControllerProvider =')) {
          offenders.add(entity.path);
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'these files declare the sound gate outside features/rewards — see '
            'the library doc in sound_controller.dart before moving it',
      );
    });
  });
}

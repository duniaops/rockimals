import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/core/audio/sound_cues.dart';
import 'package:rockimals/core/audio/sound_engine.dart';
import 'package:rockimals/features/data/providers.dart';
import 'package:rockimals/features/settings/sound.dart';

import '../../support/memory_store.dart';
import '../../support/recording_sound_engine.dart';

/// The 🔊 Sound toggle's behaviour, and — the reason this file exists at all —
/// the seam that behaviour now sits behind.
///
/// The notifier itself was already covered from both of its screens
/// (`games_hub_test.dart` drives the Play hub's button, `settings_screen_test.dart`
/// the Settings row, and both assert the store afterwards). What had no test was
/// the *location*: the toggle moved out of `features/games` precisely so that
/// three features would stop reaching into a fourth for a value that is not
/// about games, and nothing stopped the next agent declaring it back where it
/// was. The last group is that guard.
void main() {
  group('SoundOnNotifier', () {
    test('starts from the store, defaulting to on', () {
      // A game that starts silent reads as broken, which is why `Store.soundOn`
      // defaults true; asserted here as well because this notifier is what every
      // cue in the app actually asks.
      final ProviderContainer container = _container(MemoryStore());

      expect(container.read(soundOnProvider), isTrue);
    });

    test('starts from the store when the child turned it off', () {
      final ProviderContainer container = _container(
        MemoryStore(soundOn: false),
      );

      expect(container.read(soundOnProvider), isFalse);
    });

    test('toggle flips the live value and persists it', () async {
      // Both halves matter and they fail differently: a flip that does not
      // persist loses the child's choice at the next launch, and a write that
      // does not flip leaves the icon lying about the state until a rebuild.
      final MemoryStore store = MemoryStore();
      final ProviderContainer container = _container(store);

      await container.read(soundOnProvider.notifier).toggle();

      expect(container.read(soundOnProvider), isFalse);
      expect(store.soundOn, isFalse);
    });

    test('the state moves before the write completes', () async {
      // The optimistic flip `ReducedMotionNotifier` and `LittleKidsModeNotifier`
      // both make: the child is looking straight at the speaker icon, so it
      // settles on the frame of the tap rather than a disk round-trip later.
      // The assertion sits *between* the call and the await, which is the only
      // place the difference between the two orderings is observable.
      final ProviderContainer container = _container(MemoryStore());

      final Future<void> pending = container
          .read(soundOnProvider.notifier)
          .toggle();
      expect(container.read(soundOnProvider), isFalse);

      await pending;
    });

    test('toggling twice returns to the starting value', () async {
      final MemoryStore store = MemoryStore();
      final ProviderContainer container = _container(store);

      await container.read(soundOnProvider.notifier).toggle();
      await container.read(soundOnProvider.notifier).toggle();

      expect(container.read(soundOnProvider), isTrue);
      expect(store.soundOn, isTrue);
    });
  });

  group('the confirmation blip', () {
    test('turning sound on answers with the happy jingle', () async {
      // `if(soundOn)playHappy()` (`index.html:1020`). An emoji swapping from 🔇
      // to 🔊, or a switch sliding across, proves nothing about the speaker — a
      // child whose device is muted at the OS level needs to hear the difference
      // between "the app is off" and "the phone is off".
      final RecordingSoundEngine engine = RecordingSoundEngine();
      final ProviderContainer container = _container(
        MemoryStore(soundOn: false),
        engine: engine,
      );

      await container.read(soundOnProvider.notifier).toggle();

      expect(container.read(soundOnProvider), isTrue);
      expect(engine.played, <SoundCue>[SoundCue.happy]);
    });

    test('turning sound off is silent — it does not sign off', () async {
      // The prototype only plays on the way on, and that is the only coherent
      // reading: a cue confirming that sound is off contradicts itself.
      final RecordingSoundEngine engine = RecordingSoundEngine();
      final ProviderContainer container = _container(
        MemoryStore(),
        engine: engine,
      );

      await container.read(soundOnProvider.notifier).toggle();

      expect(container.read(soundOnProvider), isFalse);
      expect(engine.played, isEmpty);
    });

    test('the cue does not gate the persistence write', () async {
      // `toggle()` fires the cue unawaited on purpose, so the future it returns
      // is the store write and nothing else. Pinned because the failure mode is
      // silent and nasty: an awaited cue against a wedged audio route would hang
      // every caller of the toggle, and the open plan item about a hung player
      // says that route is real. An engine that never answers must not stop the
      // child's choice reaching disk.
      final MemoryStore store = MemoryStore(soundOn: false);
      final ProviderContainer container = _container(
        store,
        engine: _NeverAnsweringEngine(),
      );

      await container
          .read(soundOnProvider.notifier)
          .toggle()
          .timeout(const Duration(seconds: 5));

      expect(store.soundOn, isTrue);
    });
  });

  group('the settings feature owns the toggle', () {
    test('no library outside features/settings declares its state', () {
      // The regression this file exists to stop. `soundOnProvider` lived in
      // `features/games/games_providers.dart` while the Play hub was its only
      // flip point; by the time Settings and the sound gate both read it, two
      // features were importing a third for a setting that is not about games.
      // Reading it from anywhere is fine and expected — *declaring* it outside
      // this feature is what puts the seam back.
      final List<String> offenders = <String>[];
      for (final FileSystemEntity entity in Directory(
        'lib',
      ).listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        if (entity.path.endsWith('features/settings/sound.dart')) continue;
        final String source = entity.readAsStringSync();
        if (source.contains('class SoundOnNotifier') ||
            source.contains('soundOnProvider =')) {
          offenders.add(entity.path);
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'these files declare the sound toggle outside the settings feature '
            '— the cross-feature dependency moving it here removed',
      );
    });

    test('only the gate and the toggle itself reach the engine', () {
      // `sound_engine.dart` has always *said* "nothing should call
      // `soundEngineProvider` directly; go through `SoundController`" — the rule
      // that stops a fifth cue being added that ignores the child's setting. It
      // was a comment, and comments do not fail.
      //
      // The confirmation blip is the first sanctioned exception (it has just
      // written the flag the gate would ask about, and routing through the gate
      // would make settings and rewards import each other), so this is the
      // moment to make the rule enforceable instead of widening it on trust.
      // Any third library that reads the engine fails here, and whoever adds it
      // has to argue the case in this list rather than in a comment nobody runs.
      const List<String> allowed = <String>[
        // The declaration and its own doc comment.
        'core/audio/sound_engine.dart',
        // The gate every other cue in the app goes through.
        'features/rewards/sound_controller.dart',
        // The confirmation blip — see `SoundOnNotifier.toggle`.
        'features/settings/sound.dart',
      ];

      final List<String> offenders = <String>[];
      for (final FileSystemEntity entity in Directory(
        'lib',
      ).listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        if (allowed.any((String ok) => entity.path.endsWith(ok))) continue;
        if (entity.readAsStringSync().contains('soundEngineProvider')) {
          offenders.add(entity.path);
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'these files reach the sound engine without passing the toggle '
            'gate — route the cue through `SoundController` instead',
      );
    });
  });
}

/// A [SoundEngine] whose `play` never completes — the wedged audio route the
/// open "bound a hung audio call" plan item describes, which `audioplayers`
/// produces for real when no binding has registered the plugin.
class _NeverAnsweringEngine implements SoundEngine {
  @override
  Future<void> play(SoundCue cue) => Completer<void>().future;

  @override
  Future<void> dispose() async {}
}

/// Shaped like `little_kids_mode_test.dart`'s helper, with one addition the
/// confirmation blip forced: the sound **engine** is faked too.
///
/// It has to be. `toggle()` reaches the engine on the way on, so a container
/// with only the store in front of it would build a real `ToneSoundEngine` and
/// hand bytes to the `audioplayers` plugin — which on a host VM with no binding
/// either throws (reported through `FlutterError`, failing the test) or never
/// answers at all. Recording instead is also the only way to *observe* the blip:
/// a real engine here is silent whether the rule works or not.
ProviderContainer _container(MemoryStore store, {SoundEngine? engine}) {
  final ProviderContainer container = ProviderContainer(
    overrides: [
      storeProvider.overrideWithValue(store),
      soundEngineProvider.overrideWithValue(engine ?? RecordingSoundEngine()),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

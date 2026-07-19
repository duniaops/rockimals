import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/features/data/providers.dart';
import 'package:rockimals/features/settings/sound.dart';

import '../../support/memory_store.dart';

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
  });
}

/// Shaped like `little_kids_mode_test.dart`'s helper, and for the same reason:
/// the store is the only thing this notifier reaches past, so it is the only
/// thing that needs standing in front of.
ProviderContainer _container(MemoryStore store) {
  final ProviderContainer container = ProviderContainer(
    overrides: [storeProvider.overrideWithValue(store)],
  );
  addTearDown(container.dispose);
  return container;
}

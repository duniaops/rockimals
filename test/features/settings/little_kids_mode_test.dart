/// 🧸 Little Kids mode's two halves: the persisted choice, and the v1.1
/// extension point it is wired to (`specs/08-settings-about.md:51-53`,
/// `specs/06-title-polish-safety.md:26-27`).
///
/// **The load-bearing test in this file is the one that asserts nothing
/// happens.** v1 ships the switch and the storage and none of the behaviour, so
/// "the default (off) path is unchanged" is the item's actual deliverable — and
/// a claim like that decays silently. Written down as a property it becomes the
/// thing that fails on the day a v1.1 agent implements read-aloud and forgets to
/// come back here, which is exactly when someone should be made to look.
///
/// The *surface* — that the row exists, says the right words, is big enough, and
/// reaches the store — is `settings_screen_test.dart`'s question and is not
/// repeated here. This file owns the wiring behind it.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/core/storage/store.dart';
import 'package:rockimals/features/data/providers.dart';
import 'package:rockimals/features/settings/little_kids_mode.dart';

import '../../support/memory_store.dart';

void main() {
  group('the persisted choice', () {
    test('is off on a fresh install', () {
      // [Store.littleKidsMode]'s own default, and a plain bool rather than
      // Calm motion's tri-state: there is no OS signal to defer to, so "never
      // chosen" and "off" are the same answer.
      final ProviderContainer container = _container(MemoryStore());

      expect(container.read(littleKidsModeProvider), isFalse);
    });

    test('seeds from what the store already holds', () {
      final ProviderContainer container = _container(
        MemoryStore(littleKidsMode: true),
      );

      expect(container.read(littleKidsModeProvider), isTrue);
    });

    test('choose() moves the state and writes through, both ways', () async {
      // Both directions, because a toggle that can only write `true` strands a
      // grown-up with a setting they cannot undo. That the store then survives
      // a reopen is `store_test.dart`'s question, asked there against a real
      // Hive box — a [MemoryStore] could not answer it honestly.
      final Store store = MemoryStore();
      final ProviderContainer container = _container(store);
      expect(container.read(littleKidsModeProvider), isFalse);

      await container.read(littleKidsModeProvider.notifier).choose(true);
      expect(store.littleKidsMode, isTrue);
      expect(container.read(littleKidsModeProvider), isTrue);

      await container.read(littleKidsModeProvider.notifier).choose(false);
      expect(store.littleKidsMode, isFalse);
      expect(container.read(littleKidsModeProvider), isFalse);
    });

    test('the state moves before the write completes', () async {
      // The optimistic flip [ReducedMotionNotifier.choose] and
      // [SoundOnNotifier.toggle] both make: the switch settles on the frame of
      // the tap rather than a disk round-trip later. Asserted by reading the
      // state *without* awaiting — a notifier that only published after its
      // write would show the old value here and leave the switch lagging.
      final ProviderContainer container = _container(MemoryStore());

      final Future<void> pending = container
          .read(littleKidsModeProvider.notifier)
          .choose(true);
      expect(container.read(littleKidsModeProvider), isTrue);

      await pending;
    });
  });

  group('the v1 extension point', () {
    test('answers the standard experience with the toggle off', () {
      final LittleKidsMode mode = _container(
        MemoryStore(),
      ).read(littleKidsExperienceProvider);

      expect(mode.readsAloud, isFalse);
      expect(mode.controlScale, 1);
      expect(mode.simplestGamesOnly, isFalse);
    });

    test('answers exactly the same with the toggle ON — the v1 no-op', () {
      // **This is the item's deliverable, stated as a property.** Spec 08
      // allows the v1 body to be a no-op (`:51-53`); this is what that costs
      // and what it promises. Every affordance is compared against the
      // toggle-off answer rather than against a hardcoded constant, so a v1.1
      // implementation that changes *one* of the three fails here and has to
      // come back and say so deliberately.
      final ProviderContainer off = _container(MemoryStore());
      final ProviderContainer on = _container(
        MemoryStore(littleKidsMode: true),
      );

      final LittleKidsMode standard = off.read(littleKidsExperienceProvider);
      final LittleKidsMode enabled = on.read(littleKidsExperienceProvider);

      expect(enabled.readsAloud, standard.readsAloud);
      expect(enabled.controlScale, standard.controlScale);
      expect(enabled.simplestGamesOnly, standard.simplestGamesOnly);
    });

    test('is a real wire from the toggle, not a constant wearing a provider', () {
      // The test above is only worth anything if the experience actually
      // *receives* the child's choice — a provider that ignored
      // [littleKidsModeProvider] entirely would pass it while proving nothing.
      // [StandardExperience.enabled] is the carried-but-unread value that makes
      // the no-op visible in code, so this asserts the wire and the two
      // together are the whole claim.
      final ProviderContainer container = _container(
        MemoryStore(littleKidsMode: true),
      );

      expect(
        container.read(littleKidsExperienceProvider),
        isA<StandardExperience>().having(
          (StandardExperience e) => e.enabled,
          'enabled',
          isTrue,
        ),
      );
    });

    test('re-resolves when the choice changes', () async {
      // The seam has to be live, not read once at launch: a v1.1 body must
      // start answering differently the moment the switch is flipped, without
      // a restart — the bar `specs/08-settings-about.md:75` sets for the
      // toggle beside it.
      final ProviderContainer container = _container(MemoryStore());
      expect(
        (container.read(littleKidsExperienceProvider) as StandardExperience)
            .enabled,
        isFalse,
      );

      await container.read(littleKidsModeProvider.notifier).choose(true);

      expect(
        (container.read(littleKidsExperienceProvider) as StandardExperience)
            .enabled,
        isTrue,
      );
    });
  });
}

/// A container over [store] and nothing else — neither provider under test
/// reaches past persistence, so nothing else needs standing in front of.
ProviderContainer _container(Store store) {
  final ProviderContainer container = ProviderContainer(
    overrides: [storeProvider.overrideWithValue(store)],
  );
  addTearDown(container.dispose);
  return container;
}

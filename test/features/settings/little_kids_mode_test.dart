/// 🧸 Little Kids mode's two halves: the persisted choice, and the extension
/// point it is wired to (`specs/08-settings-about.md:51-53`,
/// `specs/06-title-polish-safety.md:26-27`).
///
/// **The load-bearing test in this file is still the one about the affordances
/// that have *not* shipped.** v1 shipped none of the behaviour, so this file
/// asserted that turning the switch on changed nothing — deliberately, so that
/// it would fail on the day someone implemented an affordance and forgot to come
/// back. It did exactly that. What replaces it is the same idea one affordance
/// smaller: `simplestGamesOnly` now flips, and `readsAloud`/`controlScale` are
/// pinned to their off answers so that *they* are the next thing to fail loudly.
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

  group('the extension point', () {
    test('answers the standard experience with the toggle off', () {
      final LittleKidsMode mode = _container(
        MemoryStore(),
      ).read(littleKidsExperienceProvider);

      expect(mode.readsAloud, isFalse);
      expect(mode.controlScale, 1);
      expect(mode.simplestGamesOnly, isFalse);
    });

    test('the toggle ON changes the games, and only the games', () {
      // **The successor to v1's "nothing happens", and it is written the same
      // way and for the same reason.** Each affordance is compared against its
      // own toggle-*off* answer rather than a hardcoded constant, so the two
      // that have not shipped stay pinned to the standard experience and the day
      // one of them starts answering differently is the day this fails and
      // someone is made to look. `simplestGamesOnly` is the one that has shipped
      // and is asserted to differ — a body that quietly stopped honouring it
      // would otherwise pass a test named for the opposite.
      final ProviderContainer off = _container(MemoryStore());
      final ProviderContainer on = _container(
        MemoryStore(littleKidsMode: true),
      );

      final LittleKidsMode standard = off.read(littleKidsExperienceProvider);
      final LittleKidsMode enabled = on.read(littleKidsExperienceProvider);

      expect(enabled.simplestGamesOnly, isTrue);
      expect(
        enabled.simplestGamesOnly,
        isNot(standard.simplestGamesOnly),
        reason: 'the affordance this item shipped',
      );

      expect(
        enabled.readsAloud,
        standard.readsAloud,
        reason: 'not shipped — TTS is a plugin this project has not taken on',
      );
      expect(
        enabled.controlScale,
        standard.controlScale,
        reason: 'not shipped — the multiplier needs a real screen to choose',
      );
    });

    test('is a real wire from the toggle, not a constant wearing a provider', () {
      // v1 proved this with a carried-but-unread `enabled` field, because both
      // branches were the same class and there was nothing else to look at. The
      // branch itself is the evidence now: a provider that ignored
      // [littleKidsModeProvider] could not produce two different types.
      expect(
        _container(MemoryStore()).read(littleKidsExperienceProvider),
        isA<StandardExperience>(),
      );
      expect(
        _container(
          MemoryStore(littleKidsMode: true),
        ).read(littleKidsExperienceProvider),
        isA<LittleKidsExperience>(),
      );
    });

    test('re-resolves when the choice changes', () async {
      // The seam has to be live, not read once at launch: the Play hub must
      // narrow the moment the switch is flipped, without a restart — the bar
      // `specs/08-settings-about.md:75` sets for the toggle beside it, and now a
      // promise with a visible consequence rather than a latent one.
      final ProviderContainer container = _container(MemoryStore());
      expect(
        container.read(littleKidsExperienceProvider).simplestGamesOnly,
        isFalse,
      );

      await container.read(littleKidsModeProvider.notifier).choose(true);

      expect(
        container.read(littleKidsExperienceProvider).simplestGamesOnly,
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

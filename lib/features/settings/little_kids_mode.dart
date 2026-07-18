/// **🧸 Little Kids mode** — the persisted toggle and the v1.1 extension point
/// behind it (`specs/08-settings-about.md:51-53`,
/// `specs/06-title-polish-safety.md:26-27`, plan decision 7).
///
/// Spec 06 asks for read-aloud names and prompts via TTS, bigger controls, and
/// only the simplest two games — and then allows the whole thing to be stubbed:
/// *"implement or leave a clean extension point for v1.1"* (`:27`). This file is
/// that clean extension point, and spec 08 is why it exists as a *reachable*
/// one rather than as a note: *"the Little Kids mode stub needs an extension
/// point that is reachable, or it is untestable"* (`:30-31`).
///
/// **So v1 ships the switch and the storage, and none of the behaviour.** That
/// is the item's scope, and it is stated here rather than left to be discovered
/// because a toggle that does nothing is otherwise indistinguishable from a
/// toggle that is broken. The Settings row says as much to the grown-up flipping
/// it — see the copy in `settings_screen.dart`.
///
/// **Two names, and the split is the whole design.** [littleKidsModeProvider] is
/// the child's *choice*: a bool, persisted, and what the [Switch] on the Settings
/// screen shows. [littleKidsExperienceProvider] is what the choice *means*: a
/// [LittleKidsMode] holding one answer per affordance. Everything that will
/// eventually behave differently asks the second and never the first, which is
/// what stops v1.1 from becoming a hunt for `if (littleKidsMode)` scattered
/// across three features — exactly the shape `calm_motion.dart` avoided for the
/// same reason, and `AnimalSystem` before it.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rockimals/core/storage/store.dart';
import 'package:rockimals/features/data/providers.dart';

/// The child's own 🧸 Little Kids mode choice.
///
/// **A plain bool, unlike [ReducedMotionNotifier]'s tri-state**, and
/// [Store.littleKidsMode] owns the reason: there is no OS signal to defer to
/// here, so "never chosen" and "off" genuinely are the same answer and a third
/// state would only be a value nothing could ever resolve.
///
/// Shaped like [SoundOnNotifier]: seeded from the store, holding the live value,
/// writing every change straight back. The switch must flip on the frame of the
/// tap — the grown-up is looking straight at it — and hold across a restart
/// (`specs/08-settings-about.md:73`).
class LittleKidsModeNotifier extends Notifier<bool> {
  @override
  bool build() => ref.watch(storeProvider).littleKidsMode;

  /// Record the choice and persist it.
  ///
  /// Takes a concrete bool rather than flipping, because the row hands one over
  /// and because this notifier has no "unset" to fall back to — see the class
  /// doc. `state` moves before the write for the same reason
  /// [ReducedMotionNotifier.choose] does it: the switch settles on the frame of
  /// the tap rather than a disk round-trip later.
  Future<void> choose(bool value) {
    state = value;
    return ref.read(storeProvider).setLittleKidsMode(value);
  }
}

/// The live 🧸 Little Kids mode choice. See [LittleKidsModeNotifier].
final NotifierProvider<LittleKidsModeNotifier, bool> littleKidsModeProvider =
    NotifierProvider<LittleKidsModeNotifier, bool>(
      LittleKidsModeNotifier.new,
      name: 'littleKidsMode',
    );

/// What Little Kids mode *means* to the rest of the app — one question per
/// affordance `specs/06-title-polish-safety.md:26` names.
///
/// **The three members are the spec's own list, not an invented API**:
/// read-aloud names and prompts, bigger controls, the simplest two games. They
/// are questions rather than a bool so that a v1.1 implementation can answer
/// each one differently — read-aloud may ship before the game restriction does —
/// without every caller learning that.
///
/// **It deliberately does not expose the toggle itself.** A `bool get enabled`
/// here would invite exactly the `if (mode.enabled)` branches this interface
/// exists to prevent: the point is that a feature asks *what to do*, never *what
/// the child chose*. [littleKidsExperienceProvider] is the only place the two
/// meet.
///
/// **Nothing implements this but [StandardExperience], and nothing calls it at
/// all.** That is not an oversight — it is what "leave a clean extension point"
/// means, and the alternative (no seam, then three features each inventing one)
/// is the cost this is paying to avoid. The surfaces that will take it, when
/// they do: the detail screen and the games' prompts for [readsAloud], the
/// shared row and button widgets for [controlScale], and the Play hub's card
/// list for [simplestGamesOnly].
abstract interface class LittleKidsMode {
  /// Whether names and prompts are read aloud (TTS).
  bool get readsAloud;

  /// How much larger controls are drawn — `1` is the standard size, so this is
  /// a multiplier a widget can apply unconditionally rather than a flag it has
  /// to branch on.
  double get controlScale;

  /// Whether the Play hub offers only the two simplest games.
  bool get simplestGamesOnly;
}

/// The v1 body of the extension point: **a documented no-op**.
///
/// Every answer is the standard-experience answer, and it is the same answer
/// whether [enabled] is true or false. Turning the switch on in v1 changes
/// nothing a child can see; it records a preference the app is not yet able to
/// honour. `little_kids_mode_test.dart` pins that as a property rather than
/// leaving it as a claim in this comment, because the day it stops being true is
/// the day v1.1 lands and the test should be the thing that notices.
///
/// **[enabled] is carried and not read, and that is the no-op stated in code.**
/// It is what makes [littleKidsExperienceProvider] a real wire from the toggle
/// rather than a constant wearing a provider — the difference matters to the
/// test above, which would otherwise be asserting that a provider ignores an
/// input it never received.
class StandardExperience implements LittleKidsMode {
  const StandardExperience({required this.enabled});

  /// The child's persisted choice. A v1.1 implementation is constructed from
  /// this; the v1 one has nothing to do with it.
  final bool enabled;

  @override
  bool get readsAloud => false;

  @override
  double get controlScale => 1;

  @override
  bool get simplestGamesOnly => false;
}

/// The resolved Little Kids experience — **the one line v1.1 changes.**
///
/// A v1.1 agent writes a second [LittleKidsMode] implementation and returns it
/// from here when `enabled`; every caller downstream is already asking the right
/// question. Nothing else in this file, and nothing on the Settings screen, has
/// to move.
final Provider<LittleKidsMode> littleKidsExperienceProvider =
    Provider<LittleKidsMode>(
      (Ref ref) =>
          StandardExperience(enabled: ref.watch(littleKidsModeProvider)),
      name: 'littleKidsExperience',
    );

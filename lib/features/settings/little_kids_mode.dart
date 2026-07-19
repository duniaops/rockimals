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
/// **The first of the three affordances now ships: [LittleKidsMode.simplestGamesOnly].**
/// v1 shipped the switch and the storage and none of the behaviour, and said so
/// on the Settings row ("coming soon") because a toggle that does nothing is
/// otherwise indistinguishable from a toggle that is broken. The Play hub now
/// honours the choice, so those words are gone and the row describes what the
/// switch does today. [LittleKidsMode.readsAloud] and
/// [LittleKidsMode.controlScale] still answer the standard answer —
/// [LittleKidsExperience] states per member what each is waiting on.
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
/// **The seam has its first caller, and it took the shape this interface was
/// built for.** `games_hub.dart` asks [simplestGamesOnly] and nothing else — it
/// never learns whether the child turned the switch on, which is the whole point
/// of keeping the choice and its meaning in two providers. The surfaces still
/// waiting: the detail screen and the games' prompts for [readsAloud], and the
/// shared row and button widgets for [controlScale].
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

/// Every answer the app gives when 🧸 Little Kids mode is **off** — the
/// experience nothing about this feature changes.
///
/// **It is no longer "the no-op body".** [littleKidsExperienceProvider] answers
/// with [LittleKidsExperience] instead when the switch is on, so this class is
/// one half of a real branch rather than the only answer there was.
///
/// **`enabled` is gone, and losing it *is* the branch landing.** v1 carried the
/// child's choice here unread, for one reason: it let a test prove the provider
/// was a live wire and not a constant wearing a provider. The branch proves that
/// now — the two classes give different answers, so a provider that ignored the
/// toggle would be visible immediately — and a field nothing reads is the dead
/// state plan decision 1 says not to keep.
class StandardExperience implements LittleKidsMode {
  const StandardExperience();

  @override
  bool get readsAloud => false;

  @override
  double get controlScale => 1;

  @override
  bool get simplestGamesOnly => false;
}

/// Every answer the app gives when 🧸 Little Kids mode is **on**.
///
/// **Only [simplestGamesOnly] differs from [StandardExperience] today, and that
/// is the interface working as designed.** The three affordances are separate
/// questions precisely so they can ship on separate days; this is the first of
/// those days. The other two answer the standard answer and each says below what
/// it is waiting on — an implementation that quietly invented a different answer
/// would be worse than one that admits it has not shipped, because the Settings
/// row's copy is written from what this class actually does.
class LittleKidsExperience implements LittleKidsMode {
  const LittleKidsExperience();

  /// Still standard. Read-aloud needs a TTS engine — a platform plugin this
  /// project has not taken on, and one whose only honest verification is a
  /// device (the HUMAN-GATED toolchain item). Answering `true` with no voice
  /// behind it would send every caller down a branch that stays silent, which
  /// reads to a child as the app ignoring them.
  @override
  bool get readsAloud => false;

  /// Still standard. "Bigger controls" is a *number*, and choosing it needs a
  /// real screen to look at: every tap target in the app is already asserted
  /// ≥48dp, so the gain here is real but the multiplier is not something a
  /// widget test can tell us is right.
  @override
  double get controlScale => 1;

  /// **The one that ships.** The Play hub offers Power Duel and Closer or
  /// Farther only; `games_hub.dart` holds which two and, more usefully, the rule
  /// that picked them.
  @override
  bool get simplestGamesOnly => true;
}

/// The resolved Little Kids experience — the one place the child's *choice* and
/// what it *means* meet, and the only place they ever should.
///
/// The second affordance to ship changes [LittleKidsExperience] and nothing
/// here: callers already ask the right question, and this branch already routes
/// them to the right answer.
final Provider<LittleKidsMode> littleKidsExperienceProvider =
    Provider<LittleKidsMode>(
      (Ref ref) => ref.watch(littleKidsModeProvider)
          ? const LittleKidsExperience()
          : const StandardExperience(),
      name: 'littleKidsExperience',
    );

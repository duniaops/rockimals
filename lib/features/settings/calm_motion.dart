/// **🐢 Calm motion** — the reduced-motion setting (`specs/08-settings-about.md:47-50`,
/// `specs/06-title-polish-safety.md:25`, plan decision 7).
///
/// One module owns the whole setting: the persisted choice, the rule that
/// resolves it against the OS, and the two factors that say what "calmer" means
/// to the things that move. That is the same shape `AnimalSystem` has and for
/// the same reason — the alternative is a `bool` read in three features that
/// each invent their own idea of how much slower is slow enough.
///
/// **The phrase "reduced motion" names the key and nothing a child sees.** It is
/// the `MediaQuery` flag's name and the store field's name, so it is unavoidable
/// in code; `CLAUDE.md`'s gentle-tone rule and spec 08 both put "🐢 Calm motion"
/// on the screen. No string in this file that reaches a widget says otherwise.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rockimals/core/storage/store.dart';
import 'package:rockimals/features/data/providers.dart';

/// How much of its normal speed the radar's drift keeps when Calm motion is on.
///
/// Spec 08 allows "drifts slowly **or** holds still" (`:74`). Slowly wins: a
/// radar frozen at 0 is indistinguishable from the pause button already on the
/// screen, and from a bug. At a fifth speed an animal still visibly travels —
/// the sky is alive, it just stopped hurrying — and a child who turned this on
/// because the movement bothered them is not left wondering whether the app
/// broke.
const double kCalmDriftScale = 0.2;

/// How much of its normal length a reaction keeps when Calm motion is on
/// ("reactions shorten", `specs/08-settings-about.md:75`).
///
/// Half, not a fifth: this is a *duration*, not a speed, so the same factor that
/// calms the radar would here stretch the hop to over four seconds — the exact
/// opposite of shortening it. The motion keeps its full shape and gets out of
/// the way twice as fast, which is what "shorten" asks for and what keeps a
/// right answer still feeling like a celebration.
const double kCalmReactionScale = 0.5;

/// The child's own Calm motion choice, or null if they have never made one.
///
/// **Null is a real third state, not a missing bool** — see [Store.reducedMotion],
/// which explains why the box keeps it. This notifier is the live half of that
/// same tri-state: it holds exactly what is stored and resolves nothing. The
/// resolving is [calmMotionOf]'s job, because it needs a [BuildContext] to ask
/// the OS and a provider has none.
class ReducedMotionNotifier extends Notifier<bool?> {
  @override
  bool? build() => ref.watch(storeProvider).reducedMotion;

  /// Record the child's choice and persist it.
  ///
  /// Takes a concrete bool and never a null: once they have touched the switch
  /// the answer is theirs, and there is no gesture in the app that means "go
  /// back to asking the OS". Setting `state` before the write is the optimistic
  /// flip [SoundOnNotifier] makes — the switch and the radar both settle on the
  /// frame of the tap rather than a disk round-trip later.
  Future<void> choose(bool value) {
    state = value;
    return ref.read(storeProvider).setReducedMotion(value);
  }
}

/// The live Calm motion choice. See [ReducedMotionNotifier].
final NotifierProvider<ReducedMotionNotifier, bool?> reducedMotionProvider =
    NotifierProvider<ReducedMotionNotifier, bool?>(
      ReducedMotionNotifier.new,
      name: 'reducedMotion',
    );

/// Whether Calm motion is in force right now: the child's choice if they have
/// made one, and the OS accessibility flag if they have not
/// (`specs/08-settings-about.md:48-49`).
///
/// **A function of both a `ref` and a `context`, which is why it is not simply a
/// `Provider<bool>`.** The OS half lives in `MediaQuery`, and a provider cannot
/// reach an [InheritedWidget]. The alternative — mirroring
/// `MediaQuery.disableAnimations` into a provider from some widget near the root
/// — would add a second copy of a value the framework already publishes, and a
/// window where the two disagree. Reading both at the point of use has neither
/// problem, and because both halves are ordinary dependencies of the calling
/// widget's `build`, a change to *either* rebuilds it. That is the whole of "no
/// restart required" (`specs/08-settings-about.md:75`).
///
/// **Call this from `build` or `didChangeDependencies`, never `initState`** —
/// the `MediaQuery` lookup registers a dependency and asserts if the element is
/// not ready for one yet.
///
/// **`maybe…Of`, so a missing `MediaQuery` reads as "the OS is not asking" and
/// not as a crash.** Every real route sits under one — `WidgetsApp` inserts it —
/// so the null branch is unreachable in the app and exists for widgets mounted
/// bare in a test. Falling back to `false` is the safe direction: the worst it
/// can do is animate normally, whereas asserting would take a child's whole
/// screen down over an accessibility flag.
bool calmMotionOf(BuildContext context, WidgetRef ref) =>
    ref.watch(reducedMotionProvider) ??
    (MediaQuery.maybeDisableAnimationsOf(context) ?? false);

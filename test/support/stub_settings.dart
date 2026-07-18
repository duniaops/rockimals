/// Settings notifiers held at a fixed value, without a store.
///
/// The counterpart to `StubSoundOn` in `recording_sound_engine.dart`, and it
/// exists for the same reason: a persisted setting reads `storeProvider`, which
/// throws until it is overridden, so **every** widget that resolves one drags a
/// store into any test that mounts it. `ReactionAvatar` became such a widget
/// when 🐢 Calm motion started setting the hop's duration — which is how a
/// change to Settings reached four game suites that have nothing to do with it.
///
/// Shared rather than copied per suite because it is now wanted from both the
/// radar's suite and the games', and a stub that drifts between two copies is a
/// test that passes for the wrong reason in one of them.
library;

import 'package:rockimals/features/settings/calm_motion.dart';

/// A 🐢 Calm motion choice held at [_chosen] without touching the store.
///
/// **Null is the interesting value**, not a placeholder for "off": it is the
/// fresh-install state, the one the resolver answers by asking the OS. A stub
/// that collapsed it to `false` would make it impossible to test the OS-flag
/// default at all.
class StubCalmMotion extends ReducedMotionNotifier {
  StubCalmMotion([this._chosen]);

  final bool? _chosen;

  @override
  bool? build() => _chosen;

  @override
  Future<void> choose(bool value) async {
    // The live half only: the state moves so a mounted screen reacts, and the
    // write is dropped because there is no box under this. A suite that wants
    // the real persist-and-reload uses the real notifier over a temp-directory
    // store, as the store and settings suites do.
    state = value;
  }
}

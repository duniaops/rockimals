import 'package:flutter/widgets.dart';

/// Runs [onResume] each time the app comes back to the foreground, and renders
/// [child] unchanged.
///
/// **The gap this closes.** Everything Rockimals recomputes "when the app
/// starts" — today's date, and one day the sky — is computed exactly once per
/// *process*, not once per time a child looks at the phone. A phone that is
/// locked with the radar open and unlocked the next morning never runs that
/// code again: the process is still alive, so there is no cold launch to hang
/// it on. This is the hook for the other case.
///
/// **Deliberately about nothing in particular.** It knows [AppLifecycleState]
/// and a callback; it does not know about streaks, feeds, or providers, and it
/// lives in `core/` on that basis. A second resume-time concern is a second
/// line in the caller's `onResume`, not a second observer racing this one — see
/// `RockimalsApp` (`lib/main.dart`), which composes them.
///
/// **Only `resumed`.** The other three states are the way *out* of the
/// foreground (`inactive` → `hidden` → `paused`) and firing on any of them
/// would run the work as the child puts the phone down rather than as they pick
/// it up. Note also that registering an observer does not replay the current
/// state, so a cold launch — which is already `resumed` — does not call
/// [onResume] on mount; the launch path is the caller's to cover separately,
/// and does.
class AppResumeHost extends StatefulWidget {
  const AppResumeHost({required this.onResume, required this.child, super.key});

  /// Called on every foreground return. Read at call time rather than captured,
  /// so a rebuilt closure is the one that runs.
  final VoidCallback onResume;

  final Widget child;

  @override
  State<AppResumeHost> createState() => _AppResumeHostState();
}

class _AppResumeHostState extends State<AppResumeHost>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    // Not optional: the binding holds observers for the life of the process, so
    // one left registered keeps this `State` — and everything its callback
    // closes over — alive past the tree it belonged to, and fires it against a
    // disposed scope on the next resume.
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) widget.onResume();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/core/lifecycle/app_resume_host.dart';

/// The one hook Rockimals has for "the child came back to the app without
/// relaunching it" — the case a locked phone produces, which no cold-launch code
/// ever runs for.
///
/// Everything here is about *when* it fires, because that is the whole of what
/// this widget decides. What the callback then does belongs to its caller
/// (`lib/main.dart`, and `record_engagement_test.dart` for the streak it moves).
void main() {
  /// Puts the app through a full trip to the background and back, one state at
  /// a time.
  ///
  /// Stepped rather than jumped straight to `resumed`: Flutter delivers these
  /// as a walk through the neighbouring states in order, and the binding
  /// asserts as much, so a test that skipped to the end would be driving a
  /// transition a device never produces.
  Future<void> backgroundAndReturn(WidgetTester tester) async {
    for (final AppLifecycleState state in <AppLifecycleState>[
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
      await tester.pump();
    }
  }

  Future<int Function()> mount(WidgetTester tester) async {
    int calls = 0;
    await tester.pumpWidget(
      AppResumeHost(onResume: () => calls++, child: const SizedBox.shrink()),
    );
    return () => calls;
  }

  testWidgets('coming back to the foreground runs the callback', (
    tester,
  ) async {
    final int Function() calls = await mount(tester);

    await backgroundAndReturn(tester);

    expect(calls(), 1);
  });

  testWidgets('mounting does not, though the app is already resumed', (
    tester,
  ) async {
    // A cold launch is *already* in `resumed` when this mounts, and registering
    // an observer does not replay the current state. Pinned because the
    // alternative reading is tempting and wrong: if this fired on mount, the
    // caller's launch-time work would run twice per cold launch, and the second
    // caller to be added here would be written assuming it does.
    final int Function() calls = await mount(tester);

    await tester.pump();

    expect(calls(), 0);
  });

  testWidgets('and putting the phone down does not', (tester) async {
    // The three states on the way out. Firing on any of them would run the work
    // as the child leaves rather than as they return — for the day streak, that
    // is a write against the day they are *finishing*, which is the day already
    // recorded.
    final int Function() calls = await mount(tester);

    for (final AppLifecycleState state in <AppLifecycleState>[
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
      await tester.pump();
    }

    expect(calls(), 0);
  });

  testWidgets('every return counts, not just the first', (tester) async {
    final int Function() calls = await mount(tester);

    await backgroundAndReturn(tester);
    await backgroundAndReturn(tester);

    expect(calls(), 2);
  });

  testWidgets('and it stops once the widget is gone', (tester) async {
    // The binding holds its observers for the life of the *process*, so an
    // observer that outlives its tree keeps firing — against a `State` that is
    // disposed and, in the app's case, a provider scope that no longer exists.
    // This is the leak `dispose` exists to prevent, asserted rather than
    // trusted.
    final int Function() calls = await mount(tester);
    await tester.pumpWidget(const SizedBox.shrink());

    await backgroundAndReturn(tester);

    expect(calls(), 0);
  });

  testWidgets('the child is rendered untouched', (tester) async {
    // It is a host, not a wrapper that decorates anything: whatever it is given
    // is what is on screen.
    await tester.pumpWidget(
      AppResumeHost(
        onResume: () {},
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: Text('under the host'),
        ),
      ),
    );

    expect(find.text('under the host'), findsOneWidget);
  });
}

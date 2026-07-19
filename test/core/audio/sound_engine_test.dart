/// What [ToneSoundEngine] does when the platform player never answers.
///
/// **Why this is a suite of its own rather than more cases next to the throwing
/// player.** A player that *throws* is one line to provoke — a host VM has no
/// `audioplayers` plugin registered, so `MissingPluginException` arrives for
/// free, and `sound_controller_test.dart` covers it there. A player that accepts
/// the handoff and never comes back cannot be provoked that way: it is what a
/// *missing* binding produces, and the symptom is that the test hangs to its
/// timeout instead of failing, which is precisely the bug under test. So it is
/// produced deliberately, by overriding the one seam the engine exposes.
///
/// The failure this pins is not a crash. `GameShell` fires every cue through
/// `unawaited(...)`, so a hung player used to cost one suspended call per answer
/// for the life of the screen — no freeze, no crash, a slow drip that nothing
/// would ever have reported.
///
/// **These are `testWidgets` and not `test` for the clock, not for the widgets.**
/// The bound being checked is [kPlatformCallTimeout], two real seconds; a
/// `testWidgets` body runs inside `FakeAsync`, so `tester.pump(...)` advances it
/// instantly and the suite stays fast while still exercising the real constant
/// rather than a shortened one injected for the test.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/core/audio/sound_cues.dart';
import 'package:rockimals/core/audio/sound_engine.dart';

/// A [ToneSoundEngine] whose platform handoff completes only when the test says
/// so — the "the OS took the call and never called back" case.
class _StallingEngine extends ToneSoundEngine {
  /// One completer per handoff, in order, so a test can answer them
  /// individually and assert how many were ever started.
  final List<Completer<void>> handOffs = <Completer<void>>[];

  @override
  Future<void> handOffToPlatform(Uint8List bytes) {
    final Completer<void> completer = Completer<void>();
    handOffs.add(completer);
    return completer.future;
  }
}

/// A [ToneSoundEngine] whose handoff completes immediately — the healthy player,
/// present so the guarding can be shown to cost nothing when nothing is wrong.
class _PromptEngine extends ToneSoundEngine {
  int handOffs = 0;

  @override
  Future<void> handOffToPlatform(Uint8List bytes) async => handOffs++;
}

void main() {
  /// Collects the errors the engine reports rather than letting them fail the
  /// test — a swallowed-and-reported cue is the expected outcome here, not a
  /// surprise.
  List<FlutterErrorDetails> captureReports() {
    final List<FlutterErrorDetails> reported = <FlutterErrorDetails>[];
    final FlutterExceptionHandler? previous = FlutterError.onError;
    FlutterError.onError = reported.add;
    addTearDown(() => FlutterError.onError = previous);
    return reported;
  }

  group('a platform player that never answers', () {
    testWidgets('does not hold the caller for ever', (
      WidgetTester tester,
    ) async {
      final List<FlutterErrorDetails> reported = captureReports();
      final _StallingEngine engine = _StallingEngine();

      bool completed = false;
      unawaited(engine.play(SoundCue.happy).then((_) => completed = true));

      await tester.pump();
      expect(
        completed,
        isFalse,
        reason: 'the cue was handed off, so `play` should still be waiting',
      );

      await tester.pump(kPlatformCallTimeout);

      expect(
        completed,
        isTrue,
        reason:
            'before this bound existed, this future stayed pending for the life '
            'of the screen — one per answer tap',
      );
      expect(
        reported.single.exception,
        isA<TimeoutException>(),
        reason: 'a dropped cue should still be debuggable',
      );
      expect(reported.single.library, 'rockimals sound');
    });

    testWidgets('takes only one call, however many cues arrive', (
      WidgetTester tester,
    ) async {
      captureReports();
      final _StallingEngine engine = _StallingEngine();

      // A child answering question after question while the player is wedged.
      for (int i = 0; i < 5; i++) {
        unawaited(engine.play(SoundCue.values[i % SoundCue.values.length]));
        await tester.pump(kPlatformCallTimeout * 2);
      }

      expect(
        engine.handOffs,
        hasLength(1),
        reason:
            'the in-flight guard clears on the real completion, not on the '
            'timeout, so a player that never answers is asked exactly once',
      );
    });

    testWidgets('is used again once it finally answers', (
      WidgetTester tester,
    ) async {
      captureReports();
      final _StallingEngine engine = _StallingEngine();

      unawaited(engine.play(SoundCue.happy));
      await tester.pump(kPlatformCallTimeout);

      // Slow, not dead: the platform comes back after the bound had passed.
      engine.handOffs.single.complete();
      await tester.pump();

      // `unawaited` + `pump`, not `await`: the second cue stalls too, and its
      // bound is on the fake clock, so awaiting it here would wait for a timer
      // that only `pump` can advance.
      unawaited(engine.play(SoundCue.sad));
      await tester.pump();

      expect(
        engine.handOffs,
        hasLength(2),
        reason:
            'a bound that muted the app permanently would be a worse bug than '
            'the leak it replaced',
      );

      // The second cue is stalling too; let its bound fire so the test does not
      // end with a pending timer.
      await tester.pump(kPlatformCallTimeout);
    });
  });

  group('a healthy platform player', () {
    testWidgets('plays every cue and reports nothing', (
      WidgetTester tester,
    ) async {
      final List<FlutterErrorDetails> reported = captureReports();
      final _PromptEngine engine = _PromptEngine();

      for (final SoundCue cue in SoundCue.values) {
        await engine.play(cue);
      }

      expect(engine.handOffs, SoundCue.values.length);
      expect(reported, isEmpty);
    });
  });
}

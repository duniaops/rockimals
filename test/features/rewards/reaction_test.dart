import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/features/rewards/reaction.dart';

/// The reaction animations (`specs/05`, "Reactions (juice)") — the port of the
/// prototype's `hop` and `wob` keyframes (`index.html:237-240`).
///
/// **The suite is split in two on purpose.** The keyframe group asserts the
/// *shape* of the motion against the CSS, value by value, which is arithmetic
/// and needs no engine; the widget group asserts the *wiring* — that a reaction
/// starts, settles, and can be played again — which is the half a pumped frame
/// is actually good at. Trying to read exact keyframe values back out of a
/// pumped transform matrix would have tested the fake clock's rounding as much
/// as the animation.
void main() {
  group('the hop keyframes', () {
    // `0%{translateY(0)} 22%{translateY(-24px)} 45%{translateY(0)}
    //  55%{translateY(-9px)} 78%{translateY(0)} 100%{…}` (`index.html:237`).
    test('lifts 24px, drops, lifts 9px, and lands', () {
      expect(kHopLift.transform(0), closeTo(0, _tol));
      expect(kHopLift.transform(0.22), closeTo(-24, _tol));
      expect(kHopLift.transform(0.45), closeTo(0, _tol));
      expect(kHopLift.transform(0.55), closeTo(-9, _tol));
      expect(kHopLift.transform(0.78), closeTo(0, _tol));
      expect(kHopLift.transform(1), closeTo(0, _tol));
    });

    test('is airborne between the keyframes, not teleporting between them', () {
      // Halfway up the first segment the avatar is somewhere above the ground
      // and below the peak — the assertion that the easing is actually
      // interpolating rather than stepping.
      final double midRise = kHopLift.transform(0.11);
      expect(midRise, lessThan(0));
      expect(midRise, greaterThan(-24));
    });

    /// **The spin reverses, and it is meant to.** CSS pads a keyframe's shorter
    /// transform list with the identity, so the `22%` and `55%` stops — which
    /// name `translateY` alone — mean `rotate(0deg)`. See [kHopTurns]'s doc for
    /// why this is ported rather than corrected. This test exists to make that
    /// deliberate: a future agent who "fixes" the spin to a monotonic 0→360
    /// fails here and is sent to read the reasoning.
    test(
      'spins to a half turn, winds back to zero, then spins a full turn',
      () {
        expect(kHopTurns.transform(0), closeTo(0, _tol));
        expect(kHopTurns.transform(0.22), closeTo(0, _tol));
        expect(kHopTurns.transform(0.45), closeTo(0.5, _tol));
        expect(kHopTurns.transform(0.55), closeTo(0, _tol));
        expect(kHopTurns.transform(0.78), closeTo(1, _tol));
        expect(kHopTurns.transform(1), closeTo(1, _tol));
      },
    );

    test('ends where it started, so the avatar is upright and level again', () {
      // A full turn is visually the resting pose, which is why the hop can be
      // followed straight by another one.
      expect(kHopTurns.transform(1) % 1, closeTo(0, _tol));
      expect(kHopLift.transform(1), closeTo(0, _tol));
    });
  });

  group('the wobble keyframes', () {
    // `0%,100%{rotate(0)} 20%{rotate(-13deg) translateY(3px)}
    //  40%{rotate(11deg) translateY(3px)} 60%{rotate(-8deg)} 80%{rotate(6deg)}`
    // (`index.html:239`).
    test('swings -13°, 11°, -8°, 6° and settles level', () {
      expect(kWobbleTurns.transform(0) * 360, closeTo(0, _tol));
      expect(kWobbleTurns.transform(0.2) * 360, closeTo(-13, _tol));
      expect(kWobbleTurns.transform(0.4) * 360, closeTo(11, _tol));
      expect(kWobbleTurns.transform(0.6) * 360, closeTo(-8, _tol));
      expect(kWobbleTurns.transform(0.8) * 360, closeTo(6, _tol));
      expect(kWobbleTurns.transform(1) * 360, closeTo(0, _tol));
    });

    test('decays — each swing is smaller than the one before it', () {
      // The reason a wrong answer does not read as a telling-off
      // (`CLAUDE.md:70`): the shake is running out of energy from the first
      // beat, so it ends as a shrug rather than a shudder.
      final List<double> swings = <double>[
        kWobbleTurns.transform(0.2).abs(),
        kWobbleTurns.transform(0.4).abs(),
        kWobbleTurns.transform(0.6).abs(),
        kWobbleTurns.transform(0.8).abs(),
      ];
      for (int i = 1; i < swings.length; i++) {
        expect(swings[i], lessThan(swings[i - 1]));
      }
    });

    test('sags 3px through the first two swings, then straightens', () {
      expect(kWobbleLift.transform(0), closeTo(0, _tol));
      expect(kWobbleLift.transform(0.2), closeTo(3, _tol));
      expect(kWobbleLift.transform(0.4), closeTo(3, _tol));
      expect(kWobbleLift.transform(0.6), closeTo(0, _tol));
      expect(kWobbleLift.transform(0.8), closeTo(0, _tol));
      expect(kWobbleLift.transform(1), closeTo(0, _tol));
    });

    test('never leaves the ground — a wobble is not a hop', () {
      // The one property that keeps the two motions distinguishable to a child
      // glancing at the screen: sad only ever moves *down*.
      for (double t = 0; t <= 1; t += 0.05) {
        expect(kWobbleLift.transform(t), greaterThanOrEqualTo(-_tol));
      }
    });
  });

  group('reactionFor', () {
    test('maps an answer to a motion, and an open question to none', () {
      expect(reactionFor(true), Reaction.happy);
      expect(reactionFor(false), Reaction.sad);
      expect(reactionFor(null), isNull);
    });
  });

  group('ReactionAvatar', () {
    testWidgets('sits perfectly still while the question is open', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_harness(null));

      // No reaction means no [Transform] at all, not an identity one — an open
      // round costs the avatar nothing.
      expect(
        find.descendant(
          of: find.byType(ReactionAvatar),
          matching: find.byType(Transform),
        ),
        findsNothing,
      );
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('a correct answer lifts the avatar off its resting place and '
        'puts it back', (WidgetTester tester) async {
      await tester.pumpWidget(_harness(null));
      final Offset rest = tester.getCenter(_avatar);

      await tester.pumpWidget(_harness(Reaction.happy));
      // Sampled across the whole hop rather than at one instant: the point is
      // that it *travels*, and a single probe would pin this test to the fake
      // clock's step size.
      double highest = 0;
      for (int frame = 0; frame < 34; frame++) {
        await tester.pump(const Duration(milliseconds: 25));
        highest = <double>[
          highest,
          rest.dy - tester.getCenter(_avatar).dy,
        ].reduce((double a, double b) => a > b ? a : b);
      }
      // The keyframe peak is 24px; anything near it proves the lift ran.
      expect(highest, greaterThan(20));

      await tester.pumpAndSettle();
      expect(tester.getCenter(_avatar).dy, closeTo(rest.dy, 0.01));
    });

    testWidgets('a wrong answer tilts the avatar both ways and settles level', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_harness(null));
      final Offset restTopLeft = tester.getTopLeft(_avatar);

      await tester.pumpWidget(_harness(Reaction.sad));
      // A rotation about the centre leaves the centre alone, so the corner is
      // the probe: it swings one way and then the other.
      double leftmost = 0;
      double rightmost = 0;
      for (int frame = 0; frame < 26; frame++) {
        await tester.pump(const Duration(milliseconds: 25));
        final double dx = tester.getTopLeft(_avatar).dx - restTopLeft.dx;
        if (dx < leftmost) leftmost = dx;
        if (dx > rightmost) rightmost = dx;
      }
      expect(leftmost, lessThan(-1), reason: 'the wobble swings one way');
      expect(rightmost, greaterThan(1), reason: 'and then back the other');

      await tester.pumpAndSettle();
      expect(tester.getTopLeft(_avatar).dx, closeTo(restTopLeft.dx, 0.01));
      expect(tester.getTopLeft(_avatar).dy, closeTo(restTopLeft.dy, 0.01));
    });

    testWidgets('the two motions run for their own lengths — 850ms and 650ms '
        '(index.html:238,240)', (WidgetTester tester) async {
      // The crisp version of "the durations are different": at 650ms the sad
      // one is over and the happy one is not.
      await tester.pumpWidget(_harness(null));
      await tester.pumpWidget(_harness(Reaction.sad));
      // The tick that *ends* an animation is the first one to land at or past
      // the duration, and the frame that starts the ticker is elapsed-zero — so
      // a run is only observably finished a frame beyond its nominal length.
      // Hence the extra millisecond on every probe here; without it this test
      // measures the fake clock's frame boundary rather than the durations.
      await tester.pump(kSadDuration + _aFrame);
      expect(tester.hasRunningAnimations, isFalse);

      await tester.pumpWidget(_harness(null));
      await tester.pumpWidget(_harness(Reaction.happy));
      await tester.pump(kSadDuration + _aFrame);
      expect(
        tester.hasRunningAnimations,
        isTrue,
        reason: 'the hop is 200ms longer than the wobble',
      );
      await tester.pump(kHappyDuration - kSadDuration);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('two correct answers in a row both hop, because the round '
        'resets to null in between', (WidgetTester tester) async {
      // The port of `el.classList.remove(…); void el.offsetWidth;`
      // (`index.html:968`). Every game clears its answer state when it deals
      // the next round; this is the test that says why that matters.
      await tester.pumpWidget(_harness(null));
      await tester.pumpWidget(_harness(Reaction.happy));
      await tester.pumpAndSettle();

      await tester.pumpWidget(_harness(null));
      await tester.pumpWidget(_harness(Reaction.happy));
      await tester.pump(const Duration(milliseconds: 150));
      expect(tester.hasRunningAnimations, isTrue);
    });

    testWidgets('a rebuild that does not change the answer does not replay the '
        'motion', (WidgetTester tester) async {
      // A sibling calling setState mid-reveal — the banner appearing, a score
      // ticking — must not restart the hop from the top.
      await tester.pumpWidget(_harness(null));
      await tester.pumpWidget(_harness(Reaction.happy));
      await tester.pump(kHappyDuration - const Duration(milliseconds: 50));

      await tester.pumpWidget(_harness(Reaction.happy));
      await tester.pump(const Duration(milliseconds: 60));
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('clearing the reaction stops the motion and leaves the avatar '
        'straight', (WidgetTester tester) async {
      await tester.pumpWidget(_harness(null));
      final Offset rest = tester.getCenter(_avatar);

      await tester.pumpWidget(_harness(Reaction.happy));
      await tester.pump(const Duration(milliseconds: 180));
      expect(tester.getCenter(_avatar).dy, lessThan(rest.dy - 20));

      // A round cut short — the child taps back, or the next round is dealt
      // early. The avatar must not be left mid-air.
      await tester.pumpWidget(_harness(null));
      await tester.pump();
      expect(tester.hasRunningAnimations, isFalse);
      expect(tester.getCenter(_avatar), rest);
    });

    testWidgets('an avatar mounted already carrying a reaction plays it', (
      WidgetTester tester,
    ) async {
      // Unreachable from the four games as they stand, but "a non-null reaction
      // animates" should not quietly depend on whether the element happened to
      // be reused across a rebuild.
      await tester.pumpWidget(_harness(Reaction.happy));
      await tester.pump(const Duration(milliseconds: 150));
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pumpAndSettle();
    });
  });
}

/// How far a keyframe assertion may miss by.
///
/// Not floating-point paranoia: [TweenSequence] derives each segment's boundary
/// as `cumulativeWeight / totalWeight`, and e.g. `60/100` is not bit-identical
/// to the literal `0.6` this suite probes with. So a probe at a boundary can
/// land a hair *inside* the previous segment, where [Curves.ease] has reached
/// 0.999999 rather than 1 — an error of a few millionths of a pixel or a degree,
/// which no eye and no frame can tell from exact.
const double _tol = 1e-4;

/// A nudge past a duration boundary, so a probe lands on the frame that ends
/// the animation rather than the one just short of it.
const Duration _aFrame = Duration(milliseconds: 1);

final Finder _avatar = find.byKey(const Key('avatar'));

/// One avatar, centred, with a fixed size so its resting position is a stable
/// thing to measure motion against.
Widget _harness(Reaction? reaction) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: Center(
      child: ReactionAvatar(
        reaction: reaction,
        child: const SizedBox(key: Key('avatar'), width: 40, height: 40),
      ),
    ),
  );
}

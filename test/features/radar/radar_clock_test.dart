import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/features/radar/radar_clock.dart';

/// The radar's frame step — `index.html:730`, which is one line of the prototype
/// and the reason the whole screen stays calm.
///
/// These assertions were `RadarOrbits.advance`'s until the planet backdrop
/// became the second thing to spend the same step; they moved here with the
/// behaviour rather than being rewritten, so the clamp is still covered by the
/// tests that were written for it.
void main() {
  group('FrameClock.step', () {
    test('measures the gap between frames, in seconds', () {
      final FrameClock clock = FrameClock();

      // A `Ticker` reports elapsed time from its own start, so a 16ms frame is
      // the gap between two of its values and not either value itself.
      expect(
        clock.step(const Duration(milliseconds: 16)),
        closeTo(0.016, 1e-9),
      );
      expect(
        clock.step(const Duration(milliseconds: 32)),
        closeTo(0.016, 1e-9),
      );
      expect(
        clock.step(const Duration(milliseconds: 48)),
        closeTo(0.016, 1e-9),
      );
    });

    test('takes the first frame from zero rather than from an unset clock', () {
      // The first callback arrives at ~0, so the first step must be ~0 — not a
      // jump from whatever the clock read before the radar existed.
      expect(
        FrameClock().step(const Duration(milliseconds: 16)),
        closeTo(0.016, 1e-9),
      );
    });

    test('refuses to let a slow frame teleport the sky', () {
      // The clamp (`index.html:730`) and the reason it exists. A frame gap of
      // ten seconds — backgrounded, or a tab that was not being drawn — must
      // move the radar by 50ms, not by ten seconds. Otherwise coming back to it
      // snaps every animal to a new angle and flings the planets across the
      // field in one frame, which is the jolt the screen exists not to give.
      expect(FrameClock().step(const Duration(seconds: 10)), 0.05);
    });

    test('keeps its place through a clamped frame instead of catching up', () {
      // What the clamp costs, pinned: the sky falls *behind* rather than paying
      // the debt back on the next frame. A radar that made up the missing 9.95s
      // afterwards would give exactly the jolt the clamp is there to prevent —
      // just one frame later.
      final FrameClock clock = FrameClock();
      expect(clock.step(const Duration(seconds: 10)), 0.05);
      expect(
        clock.step(const Duration(seconds: 10, milliseconds: 16)),
        closeTo(0.016, 1e-9),
        reason: 'the frame after a long gap is an ordinary frame',
      );
    });

    test('ticks even on a frame nothing moves on', () {
      // `Radar.last = ts` sits *outside* `if(Radar.playing)`
      // (`index.html:730-731`), so the clock keeps its place while the sky is
      // held still. The play/pause item relies on this: a minute paused must not
      // buy a clamped 50ms lurch on the frame the child presses play.
      final FrameClock clock = FrameClock();
      clock.step(const Duration(seconds: 1));

      // Sixty seconds of frames the caller ignored the step of.
      for (int i = 1; i <= 3600; i++) {
        clock.step(Duration(seconds: 1, milliseconds: i * 16));
      }

      expect(
        clock.step(const Duration(seconds: 1, milliseconds: 3600 * 16 + 16)),
        closeTo(0.016, 1e-9),
      );
    });
  });
}

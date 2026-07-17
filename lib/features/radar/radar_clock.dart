import 'dart:math' as math;

/// How far the radar moves on this frame, in seconds — `const dt =
/// Math.min(0.05, (ts - Radar.last)/1000); Radar.last = ts;`
/// (`index.html:730`).
///
/// **One step per frame, spent on everything that moves.** The prototype takes
/// it once at the top of `radarLoop` and hands the same number to the animals,
/// to the Moon, and to the planet backdrop's drift (`index.html:731-735`). This
/// is that line, given its own home for the reason the field's labels were given
/// one: "when was the last frame" is a fact about the *frame*, not about any of
/// the three things that spend it, and two subsystems each keeping their own
/// copy of it would be two answers to one question.
///
/// **The clamp is the whole reason this exists.** `min(0.05, …)` means a frame
/// that took longer than 50ms — the app was backgrounded, the phone was busy —
/// moves the radar by 50ms and no more. Without it, returning to the radar after
/// a minute away teleports every animal to a new angle and flings the planets
/// across the field in a single frame, which is exactly the jolt
/// `specs/02-live-radar.md:28` asks this screen never to give. The sky simply
/// falls behind instead, which nobody can tell, because there is nothing to be
/// behind: these orbits are decorative, not a prediction of where the rock
/// really is.
///
/// **It ticks whether or not anything moves**, and that is deliberate rather
/// than incidental: the prototype updates `Radar.last` *outside* its
/// `if(Radar.playing)` guard (`index.html:730-731`). So a sky that has been held
/// still by the play/pause item for a minute starts again on an ordinary 16ms
/// step, instead of lurching through a clamped 50ms one on the frame the child
/// presses play. That item should keep calling [step] and ignore what it says.
class FrameClock {
  /// The last [step]'s timestamp, so a step can be taken from a clock that only
  /// reports elapsed time. `Radar.last` (`index.html:730`).
  ///
  /// Starting at zero is what makes the first frame's step ~0 rather than a jump
  /// from whatever a wall clock happened to read: a `Ticker` reports time from
  /// its own start, so the first callback arrives at ~0.
  Duration _last = Duration.zero;

  /// The step to the frame at [elapsed], in seconds, clamped to [_maxFrame].
  double step(Duration elapsed) {
    final double dt = math.min(
      _maxFrame,
      (elapsed - _last).inMicroseconds / Duration.microsecondsPerSecond,
    );
    _last = elapsed;
    return dt;
  }

  /// `min(0.05, …)` (`index.html:730`) — the longest step the radar will take.
  static const double _maxFrame = 0.05;
}

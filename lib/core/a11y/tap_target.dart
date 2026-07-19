import 'package:flutter/widgets.dart';
import 'package:rockimals/core/a11y/control_scale.dart';

/// The minimum size of anything a child is asked to hit, in logical pixels.
///
/// 48dp is Material's `kMinInteractiveDimension` and the number
/// `specs/08-settings-about.md:82` states outright ("Every tap target is
/// ≥48dp"); Apple's HIG asks for 44pt, so meeting 48 meets both. It matters
/// more here than in most apps: `specs/06-title-polish-safety.md:21` asks for
/// "large, well-spaced tap targets everywhere" precisely because the hands
/// using Rockimals are five-year-old hands, which are both smaller and less
/// accurate than the adult thumb these guidelines were measured against.
///
/// This is deliberately **not** `kMinInteractiveDimension`, even though the
/// values agree today. That constant is Material's private business and could
/// move with a Flutter upgrade; this one is a product commitment the specs
/// name, and `test/a11y/tap_target_audit_test.dart` enforces it app-wide.
const double kMinTapTarget = 48;

/// Grows the region that responds to a touch without changing a single painted
/// pixel.
///
/// **The problem this solves, and why it is not "just make the button bigger".**
/// Most of this app's chrome is a direct port of the prototype's CSS, and the
/// prototype's numbers are small: the `.back` pill is ~30dp tall
/// (`index.html:93`), the radar's zoom buttons are 38×38 (`index.html:177`),
/// the Sky sort chips are ~30dp. Padding them out to 48 would meet the
/// guideline by redrawing the design — a back pill heavier than the title
/// beside it, zoom buttons that crowd the radar they sit on. So the [InkWell]
/// goes *outside* the painted thing and is stretched to [kMinTapTarget]
/// instead. This is the same trick Material's own [IconButton] plays around a
/// 24dp glyph, and `settings_screen.dart`'s back pill was the first place in
/// this app to use it; [TapTarget] is that trick with a name, so the other
/// twelve sites do not each re-derive it.
///
/// Wrap the **painted** widget and put the gesture handler outside:
///
/// ```dart
/// InkWell(
///   onTap: onTap,
///   child: const TapTarget(child: _BackPill()),
/// )
/// ```
///
/// Order matters. Inside-out — `TapTarget(child: InkWell(...))` — the ink still
/// only covers the pill and nothing has changed, which is a mistake that looks
/// correct in a diff and is why the example above is spelled out.
class TapTarget extends StatelessWidget {
  const TapTarget({super.key, required this.child, this.expandWidth = false});

  final Widget child;

  /// Whether the target must also reach [kMinTapTarget] **horizontally**.
  ///
  /// Off by default because most targets here are wide and short — a back pill
  /// or a sort chip is already past 48 across and only needs height, and
  /// forcing width would leave dead space beside it that swallows taps meant
  /// for whatever sits alongside. Turn it on for the square ones (the radar's
  /// zoom buttons, `index.html:177`), where the shortfall is on both axes.
  final bool expandWidth;

  @override
  Widget build(BuildContext context) {
    // **🧸 Little Kids mode raises the floor, it does not replace it**
    // (`ControlScale`, `features/settings/little_kids_mode.dart`). The
    // multiplier is 1 for everyone else, so this line is a no-op on the standard
    // experience and `kMinTapTarget` remains the number the audit enforces.
    // Multiplying the *minimum* rather than the painted child is what makes this
    // affordance nearly free here: every one of the thirteen sites that already
    // wrap themselves in a [TapTarget] gets a bigger region to hit without
    // knowing this setting exists, and none of them get redrawn.
    final double minimum = kMinTapTarget * ControlScale.of(context);

    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: minimum,
        minWidth: expandWidth ? minimum : 0,
      ),
      // **Both factors stay 1 on every path, including `expandWidth`.** A
      // [Center] with a null factor fills the space it is given rather than
      // hugging its child, so `widthFactor: expandWidth ? null : 1` — which
      // reads like "grow when asked to" — made the radar's 38dp zoom buttons
      // *790dp* wide, a full-width invisible band that swallowed drags meant
      // for the sky behind it. Shrink-wrapping to the child and letting
      // [ConstrainedBox]'s `minWidth` raise the floor is what actually gives
      // `max(childWidth, kMinTapTarget)`.
      child: Center(widthFactor: 1, heightFactor: 1, child: child),
    );
  }
}

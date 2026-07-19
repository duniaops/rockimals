import 'package:flutter/material.dart';
import 'package:rockimals/core/theme/palette.dart';

/// The prototype's `.panel` card surface (`index.html:105`): card fill, a 16px
/// radius, a hairline `--line` border, and 14px of padding on every side.
///
/// **This is the surface only — no heading, no column, no alignment.** The three
/// detail panels want a stretch [Column] with an optional uppercase `h4` above
/// it; the About block wants a start-aligned one and no heading at all. Baking
/// either shape in here would make one of its two callers fight it, so the
/// widget stops at the four CSS properties that are genuinely the same on both
/// screens. `features/detail/detail_panel.dart` is the heading-plus-column
/// layer, built on this.
///
/// **Why this lives in `core/chrome/` rather than in either feature.** The
/// detail feature extracted its three copies first and stopped at the feature
/// boundary, deliberately: a Settings screen importing `features/detail` for a
/// surface that is not about detail is the wrong seam, the same one `Obar` was
/// moved here to avoid. `core/theme/` was the first guess, but it holds *tokens*
/// ([Palette]); `core/chrome/` holds the shared widgets built from them, which
/// is what a `.panel` is.
///
/// **Keep the constructor `const`.** `about_block.dart` is const the whole way
/// down on purpose — every line on it is a compile-time string, so the panel is
/// built once and rebuilt never — and that property is quietly lost the moment
/// this constructor stops being const. It is an improvement on what was there:
/// the About block previously used a [Container], which has no const
/// constructor, so the surface itself rebuilt on every parent build.
///
/// Near-misses that are **not** this widget, so a future reader does not fold
/// them in: `.tile` and `.stat` (radius 14, padding 12), `.acard` (radius 16 but
/// padding 12), the games' `.dcard`/`.chcard` (radius 16, but asymmetric padding
/// and a border colour that changes with the answer), and the radar's `.chip`
/// (radius 16, but `5px 10px` padding and a fill that follows its toggle). Each
/// of those shares a *number* with `.panel` by coincidence of the prototype, not
/// because it is the same surface — which is why they read their own literals
/// and not the tokens below.
///
/// **That list is load-bearing, not commentary.**
/// `test/core/chrome/panel_surface_guard_test.dart` parses `lib/` and fails
/// when any widget outside this file paints all four values at once, and every
/// near-miss above is pinned there as a fixture that must keep passing. Adding
/// a near-miss here without adding it there leaves the guard free to start
/// firing on it; adding one there without adding it here leaves the next reader
/// re-deriving why it is not a copy.
///
/// The one genuine fourth copy was the non-featured branch of
/// `games_hub.dart`'s `.gcard`. It cannot *be* a [Panel] — it is tappable, so it
/// paints through [Material]/[Ink]/[InkWell], and its `featured` sibling branch
/// swaps the fill for a gradient and the border for the accent. It reads
/// [kPanelSurface] instead.
/// `.panel`'s `border-radius:16px` (`index.html:105`).
///
/// Split out from [kPanelSurface] because a tappable panel needs the radius
/// twice over — once in the decoration it paints, and again on the [InkWell]
/// that has to clip its splash to the same corners. Two literals that must agree
/// is exactly the drift worth naming.
const BorderRadius kPanelRadius = BorderRadius.all(Radius.circular(16));

/// `.panel`'s `padding:14px` (`index.html:105`).
const EdgeInsets kPanelPadding = EdgeInsets.all(14);

/// `.panel`'s fill, border, and corners as one decoration (`index.html:105`).
///
/// [Panel] paints it through a [DecoratedBox]; `games_hub.dart`'s non-featured
/// `.gcard` paints the same object through an [Ink] so it can take a splash.
/// Sharing the decoration rather than the four values is what makes those two
/// surfaces the same fact rather than two facts that currently agree — and it is
/// the only form both callers can take, since [Material]'s own `shape`/`color`
/// pair cannot be handed a [BoxDecoration].
const BoxDecoration kPanelSurface = BoxDecoration(
  color: Palette.card,
  borderRadius: kPanelRadius,
  border: Border.fromBorderSide(BorderSide(color: Palette.line)),
);

class Panel extends StatelessWidget {
  const Panel({super.key, required this.child});

  /// The panel's contents, laid out by the caller. Placed straight inside the
  /// padding, so whatever alignment or constraints the child brings are the
  /// ones it gets.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: kPanelSurface,
      child: Padding(padding: kPanelPadding, child: child),
    );
  }
}

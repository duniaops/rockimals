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
/// padding 12), and the games' `.dcard`/`.chcard` (radius 16, but asymmetric
/// padding and a border colour that changes with the answer). The one real
/// fourth copy is the non-featured branch of `games_hub.dart`'s `.gcard`, which
/// paints all four values identically but through [Material]/[InkWell] because
/// it is tappable and has a gradient sibling branch; it has its own plan item.
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child});

  /// The panel's contents, laid out by the caller. Placed straight inside the
  /// padding, so whatever alignment or constraints the child brings are the
  /// ones it gets.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      // `.panel` — `background:var(--card);border:1px solid var(--line);
      // border-radius:16px;padding:14px` (`index.html:105`).
      decoration: const BoxDecoration(
        color: Palette.card,
        borderRadius: BorderRadius.all(Radius.circular(16)),
        border: Border.fromBorderSide(BorderSide(color: Palette.line)),
      ),
      child: Padding(padding: const EdgeInsets.all(14), child: child),
    );
  }
}

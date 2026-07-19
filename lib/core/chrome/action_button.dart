import 'package:flutter/material.dart';
import 'package:rockimals/core/a11y/tap_target.dart';
import 'package:rockimals/core/theme/palette.dart';

/// The app's one `.btn` (`index.html:51-56`) — a full-width button, filled with
/// the `accent2`→`accent` vertical gradient on dark [Palette.onAccent] text, or
/// [ghost]: transparent on [Palette.ink] behind a [Palette.line] border.
///
/// **It owns the button, not the layout.** The two callers arrange these
/// differently and always did: the detail screen sets two side by side in a flex
/// row (`index.html:604`), the game framework stacks them full-width
/// (`index.html:1027-1029`). Both copies were byte-identical inside that
/// difference, so what is shared here is the painted button and each caller
/// still wraps it in its own [Expanded] or [SizedBox].
///
/// **Why `core/chrome/` and not a feature.** Same answer, and the same reason,
/// as the [Obar] beside it: the detail screen and the games are finished, tested
/// modules, and either one importing the other for a button is the wrong seam in
/// both directions. The clone survived two rounds of reuse before this — the
/// game framework copied it, then Today's Challenge made the games' copy public
/// as `GameButton` rather than write a third — which is what left exactly two to
/// fold.
///
/// **The filled variant carries the `.btn` halo; the ghost drops it**
/// (`.btn.ghost{box-shadow:none}`, `index.html:56`). The halo is cheap on both
/// callers for the reason it is on the home Play CTA (`_PlayCta` in
/// `radar_view.dart`): these sit on static screens, not the radar's per-frame
/// canvas, so `box-shadow:0 8px 22px rgba(232,87,31,.32)` rasterises once.
class ActionButton extends StatelessWidget {
  const ActionButton({
    super.key,
    required this.label,
    required this.onTap,
    this.semanticLabel,
    this.ghost = false,
  });

  /// The visible text, glyphs and all.
  final String label;

  /// What a screen reader says instead of [label], for the labels that lead with
  /// a decorative emoji ("⭐ Follow" → "Follow"). Null where the two are the
  /// same, which is every button the games raise.
  final String? semanticLabel;

  final VoidCallback onTap;

  final bool ghost;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      // Route tests across the detail screen and all four games tap these by
      // semantics label — there is no Material button here for a `find.byType`
      // to catch — so the label is load-bearing, not decoration.
      label: semanticLabel ?? label,
      child: DecoratedBox(
        decoration: BoxDecoration(
          // `background:linear-gradient(180deg,var(--accent2),var(--accent))`
          // (`index.html:52`), dropped for the ghost's transparent fill.
          gradient: ghost
              ? null
              : const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[Palette.accent2, Palette.accent],
                ),
          // `border-radius:14px` (`index.html:52`).
          borderRadius: const BorderRadius.all(Radius.circular(14)),
          // `.btn.ghost{border:1px solid var(--line)}` (`index.html:56`).
          border: ghost ? Border.all(color: Palette.line) : null,
          boxShadow: ghost
              ? null
              : <BoxShadow>[
                  // `0 8px 22px rgba(232,87,31,.32)` — `--accent` at .32 (0x52).
                  BoxShadow(
                    color: Palette.accent.withValues(alpha: 0.32),
                    offset: const Offset(0, 8),
                    blurRadius: 22,
                  ),
                ],
        ),
        // A transparency [Material] so the ink has something to splash on. The
        // games' end screen and the detail body are both bare [Column]s under no
        // [Scaffold]; carrying it here is what lets them share one widget.
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: const BorderRadius.all(Radius.circular(14)),
            onTap: onTap,
            // 43dp painted, 5 short of [kMinTapTarget]. Unlike the `‹ Back`
            // pill, this button's fill is the whole shape a child aims at, so
            // there is nothing to keep small: the [TapTarget] sits inside the
            // ink and grows the button itself. 5dp is invisible on a full-width
            // bar.
            child: TapTarget(
              child: Padding(
                // `padding:14px` (`index.html:52`).
                padding: const EdgeInsets.all(14),
                child: ExcludeSemantics(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      // `.btn{color:#1a0d05}`; `.btn.ghost{color:var(--ink)}`
                      // (`index.html:51`, `56`).
                      color: ghost ? Palette.ink : Palette.onAccent,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                      height: 1,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

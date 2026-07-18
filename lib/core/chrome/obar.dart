import 'package:flutter/material.dart';
import 'package:rockimals/core/a11y/tap_target.dart';
import 'package:rockimals/core/theme/palette.dart';

/// The overlay back-bar (`.obar`, `index.html:92-94`): a card-pill back button
/// and a plain title over a bottom rule.
///
/// Every pushed route in the app wears this — the animal detail screen, the Play
/// hub, the game framework's [GameShell], and Settings. None of them uses a
/// Material [AppBar], because the prototype's flat bar is the app's own chrome
/// and an [AppBar] would make those four the only Material-shaped screens here.
///
/// **Why this lives in `core/chrome/` and not in a feature.** It was copied four
/// times before it was extracted, and each copy's comment gave the same reason
/// for waiting: the extraction spans finished, tested modules, so folding it
/// into whichever screen happened to be under construction would have buried a
/// cross-feature move in an unrelated diff. Once it did land, no feature could
/// own it — a Settings screen importing `features/detail` for its back-bar is
/// the wrong seam in the other direction. `core/chrome/` is that neutral home,
/// beside [TapTarget] in `core/a11y/` and [Palette] in `core/theme/`, and it is
/// the answer the two sibling plan items (the shared `.panel` shell and the
/// full-width `.btn`) should reuse rather than settle a second, different way.
///
/// **The four copies were not identical when this was written**, and the
/// difference is the reason the accessibility work had to come first. Settings'
/// back pill was the only one that met the 48dp floor; the other three painted
/// the same ~30dp pill with the ink stopping at its edge. The a11y audit
/// generalised Settings' trick into [TapTarget] and gave it to all four, which
/// is what turned this extraction into a straight rename instead of a change of
/// behaviour on three screens.
class Obar extends StatelessWidget {
  const Obar({super.key, required this.title});

  /// The `.otitle` text — the animal's name, `Play`, the game's name, or
  /// `Settings`. Ellipsised on one line; long names are expected.
  final String title;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        // `border-bottom:1px solid var(--line2)` (`index.html:92`).
        border: Border(bottom: BorderSide(color: Palette.line2)),
      ),
      child: Padding(
        // `.obar{padding:36px 14px 10px}` (`index.html:92`) — the 36px top
        // clears the status bar the prototype sits under; on device the real
        // inset is added to it so it clears the notch too.
        padding: EdgeInsets.fromLTRB(
          14,
          36 + MediaQuery.of(context).padding.top,
          14,
          10,
        ),
        child: Row(
          children: <Widget>[
            const _BackButton(),
            // `gap:12px` (`index.html:92`).
            const SizedBox(width: 12),
            // `.otitle{font-weight:800;font-size:16px}` on one ellipsised line
            // (`index.html:94`).
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Palette.ink,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The `‹ Back` pill (`.obar .back`, `index.html:93`) — pops whatever pushed
/// this route. The prototype's `data-close` handler is a plain
/// [Navigator.maybePop].
///
/// The tap target is [kMinTapTarget] tall while the painted pill stays the
/// prototype's ~30dp: the pill's 8px of vertical padding around 14px text cannot
/// reach 48 without making it visibly heavier than the 16px title beside it, so
/// the [InkWell] sits *outside* the pill and [TapTarget] stretches the region a
/// thumb has to find without touching a painted pixel.
class _BackButton extends StatelessWidget {
  const _BackButton();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      // Route tests across the radar, the Play hub, and the games tap this by
      // label — these screens carry no Material [BackButton] for
      // `tester.pageBack()` to find, so the label is load-bearing, not
      // decoration.
      label: 'Back',
      // A transparency [Material] so the ink has something to splash on. Three
      // of the four callers are bare [Column]s under no [Scaffold]; Settings
      // does sit under one, where this is simply a no-op. Carrying it here is
      // what lets all four share one widget.
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: const BorderRadius.all(Radius.circular(11)),
          onTap: () => Navigator.of(context).maybePop(),
          // No `expandWidth`: the pill is already wider than 48, and a width
          // floor would only leave dead space beside it.
          child: const TapTarget(child: _BackPill()),
        ),
      ),
    );
  }
}

/// The painted pill itself, split out so [_BackButton] can wrap it in a bigger
/// tap target without the ink and the border disagreeing about their bounds.
class _BackPill extends StatelessWidget {
  const _BackPill();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      // `.back{background:var(--card);border:1px solid var(--line);
      // border-radius:11px}` (`index.html:93`).
      decoration: BoxDecoration(
        color: Palette.card,
        borderRadius: BorderRadius.all(Radius.circular(11)),
        border: Border.fromBorderSide(BorderSide(color: Palette.line)),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        // The glyph and the word are one label on the [Semantics] above; a
        // screen reader reading "‹ Back" out of the text as well would announce
        // the button twice.
        child: ExcludeSemantics(
          child: Text(
            '‹ Back',
            style: TextStyle(
              color: Palette.ink,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}

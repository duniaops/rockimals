import 'package:flutter/material.dart';
import 'package:rockimals/core/chrome/panel.dart';
import 'package:rockimals/core/theme/palette.dart';

/// The detail screen's `.panel` shell (`index.html:105-106`) — the card surface
/// every block on the animal detail screen sits in, with the optional uppercase
/// `h4` heading above its contents.
///
/// **The surface itself is [Panel], in `core/chrome/`.** It moved there once
/// `about_block.dart` turned out to paint the same four CSS properties: a
/// Settings screen importing `features/detail` for a card that is not about
/// detail is the wrong seam. What stayed here is the part that is specific to
/// this feature — the `h4` and the stretch [Column] its three callers share.
///
/// Extracted once the size and distance comparisons were carrying a
/// byte-identical private `_PanelHeader` each, and a third shell clone stood in
/// `grown_up_facts.dart` — the same extraction [FlybyBadge] got as soon as the
/// detail became its second caller. All three `.panel`s in this feature now read
/// their surface from one place, so a change to the card's radius or the
/// heading's letter-spacing cannot land on two of the three.
///
/// **Why `children` and not a single `child`.** Both comparison panels put a
/// stack of blocks straight into the `.panel`'s stretch [Column], and the
/// size panel relies on that stretch to give its centred [Row] the full content
/// width. Wrapping those blocks in a nested [Column] to fit a one-`child` API
/// would quietly change both the cross-axis alignment and the height
/// constraints; splicing the list into the same [Column] keeps the frame the
/// callers already had.
class DetailPanel extends StatelessWidget {
  const DetailPanel({super.key, this.heading, required this.children});

  /// The `.panel h4` text in **natural case** — [DetailPanel] uppercases the
  /// glyphs itself and keeps this string for the screen reader. Null for a panel
  /// the prototype gives no heading (the grown-up facts card).
  final String? heading;

  /// The panel's contents, spliced directly into its stretch [Column].
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final String? heading = this.heading;

    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (heading != null) ...<Widget>[
            _PanelHeading(text: heading),
            // `.panel h4{margin-bottom:10px}` (`index.html:106`).
            const SizedBox(height: 10),
          ],
          ...children,
        ],
      ),
    );
  }
}

/// The uppercase muted panel title (`.panel h4`, `index.html:106`).
///
/// Same `text-transform:uppercase` treatment the stat tiles use: the glyphs show
/// caps, but the [Semantics] label stays natural case so a screen reader says
/// "How big is it? — car-sized", not the spelled-out letters.
class _PanelHeading extends StatelessWidget {
  const _PanelHeading({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      label: text,
      child: ExcludeSemantics(
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
            color: Palette.muted,
            fontSize: 13,
            letterSpacing: 0.5,
            fontWeight: FontWeight.w700,
            height: 1.2,
          ),
        ),
      ),
    );
  }
}

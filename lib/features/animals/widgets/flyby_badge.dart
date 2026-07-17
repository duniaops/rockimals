import 'package:flutter/material.dart';
import 'package:rockimals/core/animals/animal_system.dart';
import 'package:rockimals/core/theme/palette.dart';

/// The flyby badge (`.badge`, `index.html:71-74`) — a small pill that is amber
/// for a close flyby and green for a rock just passing.
///
/// **Shared because two surfaces now draw the identical pill.** It began private
/// to [AnimalCard] (`animal_card.dart`), and the animal detail screen
/// (`index.html:573`) renders the same `.badge.close`/`.badge.safe` pill,
/// centred under the avatar. That is the second caller this codebase waits for
/// before hoisting a helper (the `usingDemoKey` / `isCloseFlyby` rule), so the
/// pill and its four colours move here rather than being copied.
///
/// Sizes to its own text (a [Container] takes its intrinsic width in a
/// start-aligned column, and [Center] wraps it on the detail screen), so it
/// never stretches to fill its parent the way a filled row would.
///
/// Speaks its meaning once, without the decorative 👋 (which a screen reader
/// would otherwise sound out as "waving hand"): the visible label carries the
/// glyph, the [Semantics] label is the plain [spokenFlyby] words. Inside
/// [AnimalCard] the whole card is one merged semantics node, so the card wraps
/// this in an [ExcludeSemantics] and this node is dropped there; standing alone
/// on the detail screen it speaks for itself.
class FlybyBadge extends StatelessWidget {
  const FlybyBadge({super.key, required this.tag});

  final FlybyTag tag;

  @override
  Widget build(BuildContext context) {
    final bool close = tag == FlybyTag.closeFlyby;
    return Semantics(
      label: spokenFlyby(tag),
      child: Container(
        // `.badge` — `padding:3px 8px;border-radius:12px` (`index.html:71`).
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: close ? _closeBadgeFill : _safeBadgeFill,
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          border: Border.all(color: close ? _closeBadgeBorder : _safeBadgeBorder),
        ),
        child: ExcludeSemantics(
          child: Text(
            // `👋 close flyby` / `just passing` (`index.html:445-447`) — the same
            // copy the AnimalSystem's [FlybyTag] owns, so the badge and the home
            // strip's flyby count agree on the words.
            tag.label,
            style: TextStyle(
              color: close ? _closeBadgeInk : _safeBadgeInk,
              // `.badge` — `font-size:10px;font-weight:800;letter-spacing:.3px`
              // (`index.html:71`).
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}

/// The badge copy for a screen reader — the visible label minus its leading 👋,
/// which would otherwise be sounded out as "waving hand". `just passing` has no
/// glyph and passes through unchanged.
///
/// Public so [AnimalCard] can fold it into its own merged card label without
/// re-deriving the rule.
String spokenFlyby(FlybyTag tag) =>
    tag == FlybyTag.closeFlyby ? 'close flyby' : tag.label;

/// `.badge.close` — amber over the base orange `#E88C1F` (`index.html:74`). Note
/// this is *not* `--accent` (`#E8571F`): the badge uses a distinct amber, so it
/// stays a local literal rather than reaching for [Palette.accent].
final Color _closeBadgeFill = const Color(0xFFE88C1F).withValues(alpha: 0.15);
final Color _closeBadgeBorder = const Color(0xFFE88C1F).withValues(alpha: 0.4);

/// `.badge.close` text — `#ffcf9a` (`index.html:74`).
const Color _closeBadgeInk = Color(0xFFFFCF9A);

/// `.badge.safe` — green over `--good` `#31c48d` (`index.html:73`), which is
/// [Palette.good].
final Color _safeBadgeFill = Palette.good.withValues(alpha: 0.12);
final Color _safeBadgeBorder = Palette.good.withValues(alpha: 0.35);

/// `.badge.safe` text — `#8ef0c6` (`index.html:73`).
const Color _safeBadgeInk = Color(0xFF8EF0C6);

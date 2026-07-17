import 'package:flutter/material.dart';
import 'package:rockimals/core/animals/animal_system.dart';
import 'package:rockimals/core/theme/palette.dart';
import 'package:rockimals/data/models/asteroid.dart';

/// The reusable animal row card — a port of the prototype's `acardEl`
/// (`index.html:461-469`), the `.acard` every list of animals is built from.
///
/// **The one shared list-item widget** (`CLAUDE.md` feature-first / shared code):
/// the prototype hands the same `acardEl` to the Sky list and the My Animals
/// list (`index.html:491`, `504`), so this lives in `features/animals/widgets`
/// rather than under either tab. The Sky tab (`specs/07`) and My Animals
/// (`specs/05`) both reuse it; My Animals adds an approach-date line beneath the
/// meta the same way the prototype appends to `.info` (`index.html:505-507`),
/// which is why the card takes an optional [footer] rather than baking that line
/// in.
///
/// **Distinct from the radar's slide-up HUD card** (`_SelectedAnimalCard` in
/// `radar_view.dart`). That one is a single selection floating over a live
/// field, with Meet/Follow buttons and a five-field stat line; this is a quiet
/// row in a scrolling list, with the prototype's shorter three-field meta and a
/// whole-card tap. They render the same animal through the same AnimalSystem
/// formatters but are not the same surface, so they are not the same widget.
class AnimalCard extends StatelessWidget {
  const AnimalCard({
    super.key,
    required this.asteroid,
    required this.onTap,
    this.footer,
  });

  final Asteroid asteroid;

  /// Tapping the card (`el.onclick = () => openDetail(a)`, `index.html:467`).
  /// The caller owns where it goes — the Sky and My Animals tabs both open the
  /// detail screen, but the card does not reach for a route itself.
  final VoidCallback onTap;

  /// An optional extra line beneath the meta, for My Animals' approach-date
  /// caption (`index.html:505-507`). Null on the Sky tab, which uses the bare
  /// card. Kept out of the card's own body so the shared widget carries only
  /// what every list of animals shows.
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final Critter c = critter(asteroid);
    final FlybyTag tag = flybyTag(asteroid);

    // `${sizeLabel(a.diaMax)} · ${distLabel(a.missLunar)} · ${a.velKps.toFixed(0)}
    // km/s` (`index.html:465`). Every field reads through the AnimalSystem's
    // single-source formatters, so a list row cannot phrase a size, distance, or
    // speed differently from the HUD card, the detail screen, or the games. Note
    // the speed is a whole number here (`toFixed(0)`) — the HUD's is one decimal
    // (`index.html:722`); the two surfaces round differently on purpose, so this
    // is `.round()`, not `toStringAsFixed(1)`.
    final String meta = '${sizeLabel(asteroid.diaMax)}'
        ' · ${distLabel(asteroid.missLunar)}'
        ' · ${asteroid.velKps.round()} km/s';

    return Semantics(
      button: true,
      // Spoken as one clean sentence: the glyphs (the avatar emoji, the badge's
      // 👋) are decoration a screen reader should not sound out, so the whole
      // visual is excluded below and the meaning is said in words — the pattern
      // the nav, the chips, and the home strip all follow. `_spokenFlyby` drops
      // the badge emoji; the rest of the meta reads aloud fine.
      label: '${c.name}, $meta, ${_spokenFlyby(tag)}',
      child: ExcludeSemantics(
        child: Material(
          // `.acard` — `background:var(--card)`, `border:1px var(--line)`,
          // `border-radius:16px` (`index.html:65`).
          color: Palette.card,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
            side: BorderSide(color: Palette.line),
          ),
          child: InkWell(
            borderRadius: const BorderRadius.all(Radius.circular(16)),
            onTap: onTap,
            child: Padding(
              // `padding:12px` (`index.html:65`).
              padding: const EdgeInsets.all(12),
              child: Row(
                // `align-items:center` (`index.html:65`) — the avatar sits
                // centred against the info column however tall it grows.
                children: <Widget>[
                  _AnimalAvatar(emoji: c.animal.emoji),
                  // `gap:12px` (`index.html:65`).
                  const SizedBox(width: 12),
                  // `.info{flex:1;min-width:0}` (`index.html:68`) — takes the
                  // rest of the row and lets the name ellipsise rather than
                  // pushing the card wider.
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        // `.nm` — `font-weight:700;font-size:14px` with
                        // `text-overflow:ellipsis` on one line (`index.html:69`).
                        Text(
                          c.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Palette.ink,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            height: 1.2,
                          ),
                        ),
                        // `.meta{margin-top:2px}` (`index.html:70`).
                        const SizedBox(height: 2),
                        Text(
                          meta,
                          style: const TextStyle(
                            color: Palette.muted,
                            fontSize: 12,
                            height: 1.2,
                          ),
                        ),
                        // The badge sits `margin-top:6px` below the meta
                        // (`index.html:466`).
                        const SizedBox(height: 6),
                        _FlybyBadge(tag: tag),
                        ?footer,
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The circular animal avatar (`.acard .mini.avatar`, `index.html:67`, `226-227`)
/// — a 44px navy orb with the emoji centred in it. The `.avatar` rule overrides
/// the generic grey `.mini` rock gradient with the flat navy disc animals wear
/// everywhere (`index.html:226`).
///
/// Local to this file rather than a shared widget: the detail screen and the
/// challenge cards draw the same avatar at 56/52px (`index.html:215`, `133`),
/// but those are their own items and the sizes differ, so a shared `Avatar`
/// abstraction has exactly one consumer today. This plan's standard is that a
/// helper waits for a second caller (the `usingDemoKey` / `isCloseFlyby` rule).
class _AnimalAvatar extends StatelessWidget {
  const _AnimalAvatar({required this.emoji});

  final String emoji;

  @override
  Widget build(BuildContext context) {
    return Container(
      // `width:44px;height:44px` (`index.html:67`).
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        // `radial-gradient(circle at 50% 42%, #24406e, #14284a)` (`index.html:
        // 226`) — `#24406e` is `--line`; `#14284a` is a one-off darker navy, so
        // it stays a local literal.
        gradient: RadialGradient(
          center: Alignment(0, -0.16),
          radius: 0.9,
          colors: <Color>[Palette.line, Color(0xFF14284A)],
        ),
        border: Border.fromBorderSide(BorderSide(color: Palette.line)),
      ),
      child: ExcludeSemantics(
        // `.acard .mini.avatar{font-size:24px}` (`index.html:227`).
        child: Text(emoji, style: const TextStyle(fontSize: 24, height: 1)),
      ),
    );
  }
}

/// The flyby badge (`.badge`, `index.html:71-74`) — a small pill that is amber
/// for a close flyby and green for a rock just passing.
///
/// Sizes to its own text (a [Container] in a start-aligned [Column] takes its
/// intrinsic width), so it never stretches to the card's edge the way a filled
/// row would.
class _FlybyBadge extends StatelessWidget {
  const _FlybyBadge({required this.tag});

  final FlybyTag tag;

  @override
  Widget build(BuildContext context) {
    final bool close = tag == FlybyTag.closeFlyby;
    return Container(
      // `.badge` — `padding:3px 8px;border-radius:12px` (`index.html:71`).
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: close ? _closeBadgeFill : _safeBadgeFill,
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        border: Border.all(color: close ? _closeBadgeBorder : _safeBadgeBorder),
      ),
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
    );
  }
}

/// The badge copy for a screen reader — the visible label minus its leading 👋,
/// which would otherwise be sounded out as "waving hand". `just passing` has no
/// glyph and passes through unchanged.
String _spokenFlyby(FlybyTag tag) =>
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

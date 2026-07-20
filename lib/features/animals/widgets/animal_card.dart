import 'package:flutter/material.dart';
import 'package:rockimals/core/a11y/control_scale.dart';
import 'package:rockimals/core/animals/animal_system.dart';
import 'package:rockimals/core/theme/palette.dart';
import 'package:rockimals/data/models/asteroid.dart';
import 'package:rockimals/features/animals/widgets/flyby_badge.dart';

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
    this.footerLabel,
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

  /// What [footer] *means*, in words, appended to the card's spoken label.
  ///
  /// **Without this a footer is silent, and silently so.** The card says its
  /// whole meaning through one [Semantics.label] and hides the visual behind
  /// [ExcludeSemantics] (so the avatar emoji and the badge's 👋 are not sounded
  /// out) — and [footer] is inside that visual. So My Animals' "⏳ approach
  /// 2026-07-17" would render for a child who can see it and not exist at all
  /// for one using a screen reader, which is the failure mode that looks like
  /// nothing in a screenshot.
  ///
  /// A second parameter rather than a `String footerText` the card styles
  /// itself: the caption's accent colour and weight belong to My Animals, not
  /// to every list of animals (see [footer]). Null when [footer] is null.
  final String? footerLabel;

  @override
  Widget build(BuildContext context) {
    final Critter c = critter(asteroid);
    final FlybyTag tag = flybyTag(asteroid);
    final double scale = ControlScale.of(context);

    // `${sizeLabel(a.diaMax)} · ${distLabel(a.missLunar)} · ${a.velKps.toFixed(0)}
    // km/s` (`index.html:465`). Every field reads through the AnimalSystem's
    // single-source formatters, so a list row cannot phrase a size, distance, or
    // speed differently from the radar HUD, detail screen, or games.
    final String meta =
        '${sizeLabel(asteroid.diaMax)}'
        ' · ${distLabel(asteroid.missLunar)}'
        ' · ${speedLabel(asteroid.velKps)}';

    return Semantics(
      button: true,
      // Spoken as one clean sentence: the glyphs (the avatar emoji, the badge's
      // 👋) are decoration a screen reader should not sound out, so the whole
      // visual is excluded below and the meaning is said in words — the pattern
      // the nav, the chips, and the home strip all follow. `_spokenFlyby` drops
      // the badge emoji; the rest of the meta reads aloud fine.
      label:
          '${c.name}, $meta, ${spokenFlyby(tag)}'
          '${footerLabel == null ? '' : ', $footerLabel'}',
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
              // `padding:12px` (`index.html:65`), times 🧸 Little Kids mode's
              // multiplier — 1 for everyone else, so this is the prototype's
              // number on the standard experience.
              //
              // **This card is the shared *row* the affordance names**, and it
              // is here for a different reason from the buttons: its [InkWell]
              // already covers the whole card, so it was never near the 48dp
              // floor and gains nothing from a bigger hit region. What a small
              // child gains is a bigger, less crowded thing to look at and land
              // on in a scrolling list, which is padding and the avatar.
              padding: EdgeInsets.all(12 * scale),
              child: Row(
                // `align-items:center` (`index.html:65`) — the avatar sits
                // centred against the info column however tall it grows.
                children: <Widget>[
                  _AnimalAvatar(emoji: c.animal.emoji),
                  // `gap:12px` (`index.html:65`).
                  SizedBox(width: 12 * scale),
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
                        FlybyBadge(tag: tag),
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
    // `width:44px;height:44px` (`index.html:67`), times 🧸 Little Kids mode's
    // multiplier.
    //
    // **The orb grows and the emoji inside it does not**, which is
    // [ControlScale]'s "geometry, not type" rule and happens to cut the right
    // way twice: the glyph is a [Text] and so already grows with the OS font
    // setting, and at 1.5× text a 24dp emoji is a tight fit in a 44dp orb
    // today. Scaling the orb alone gives it room rather than taking more.
    final double side = 44 * ControlScale.of(context);

    return Container(
      width: side,
      height: side,
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

// The flyby badge moved to its own file, `FlybyBadge`
// (`features/animals/widgets/flyby_badge.dart`), when the detail screen became
// its second consumer.

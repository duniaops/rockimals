import 'package:flutter/material.dart';
import 'package:rockimals/core/animals/animal_system.dart';
import 'package:rockimals/core/theme/palette.dart';
import 'package:rockimals/data/models/asteroid.dart';
import 'package:rockimals/features/animals/widgets/flyby_badge.dart';

/// The animal detail screen — a port of the prototype's `openDetail`
/// (`index.html:554-619`), the screen a child lands on from **Meet** on the
/// radar HUD or from a tap on a Sky / My Animals card.
///
/// **This item builds the header and the stat tiles only** (the "Build the
/// detail screen header and stat tiles" plan item): the big avatar, the
/// `"{Name} the {Species}"` header title, the `"a {Species}-sized space rock"`
/// line, the flyby badge, and the four kid stat tiles. The size-comparison
/// module, the distance-comparison track, the Follow / Show-on-radar actions,
/// and the parent-gated grown-up facts panel are each their own later item, so
/// the body below stops after the tiles with room left for them under it.
///
/// Every number reads through the AnimalSystem's own formatters — [sizeLabel],
/// [distLabel], [powerStars] — so the detail screen cannot phrase a size,
/// distance or power differently from the animal card, the radar HUD, or the
/// games. The one field with a formatter all its own is "How wide": it is the
/// model's **only** `diaMin` consumer, shown as the range `{round(diaMin)}–
/// {round(diaMax)} m` (decision 11, `index.html:575`), not a single number.
class DetailScreen extends StatelessWidget {
  const DetailScreen({super.key, required this.asteroid});

  final Asteroid asteroid;

  @override
  Widget build(BuildContext context) {
    final Critter c = critter(asteroid);

    return Scaffold(
      backgroundColor: Palette.pageBackground,
      // `.obar` + `.obody` (`index.html:311-313`): a flat back-bar over a
      // scrolling body, not a Material [AppBar] — the prototype's overlay chrome
      // is a card-pill back button and a plain title, with no elevation or
      // centred arrow.
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _Obar(title: c.name),
          Expanded(
            child: SingleChildScrollView(
              // `.obody{padding:16px 16px 30px}` (`index.html:95`).
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  // `.drock avatar` (`index.html:571`) — the big navy disc.
                  Center(child: _DetailAvatar(emoji: c.animal.emoji)),
                  // `a <b>{Species}</b>-sized space rock` (`index.html:572`).
                  const SizedBox(height: 8),
                  _SpeciesLine(species: c.animal.species),
                  // The flyby badge, centred (`index.html:573`).
                  const SizedBox(height: 4),
                  Center(child: FlybyBadge(tag: flybyTag(asteroid))),
                  // `.tiles` (`index.html:574-579`) — `margin:12px 0`.
                  const SizedBox(height: 12),
                  _StatTiles(asteroid: asteroid),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The overlay's top bar (`.obar`, `index.html:92-94`, `312`) — a `‹ Back`
/// card-pill and the animal's `"{Name} the {Species}"` title, over a bottom
/// rule.
///
/// Built inline rather than shared: it is the second overlay chrome the app will
/// grow (the games and challenge overlays wear the same `.obar`), but those are
/// later items and not yet written, so this waits for its own second caller the
/// way the rest of this codebase does.
class _Obar extends StatelessWidget {
  const _Obar({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        // `border-bottom:1px solid var(--line2)` (`index.html:92`).
        border: Border(bottom: BorderSide(color: Palette.line2)),
      ),
      child: Padding(
        // `.obar{padding:36px 14px 10px}` (`index.html:92`) — the 36px top clears
        // the status bar the prototype sits under; on device the real inset is
        // added below so it clears the notch too.
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

/// The `‹ Back` pill (`.obar .back`, `index.html:93`) — closes the detail,
/// popping back to whatever pushed it (the radar HUD, or a Sky / My Animals
/// card). The prototype's `data-close` handler is a plain
/// [Navigator.pop].
class _BackButton extends StatelessWidget {
  const _BackButton();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Back',
      child: Material(
        // `.back` — `background:var(--card);border:1px solid var(--line)`.
        color: Palette.card,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(11)),
          side: BorderSide(color: Palette.line),
        ),
        child: InkWell(
          borderRadius: const BorderRadius.all(Radius.circular(11)),
          onTap: () => Navigator.of(context).maybePop(),
          child: const Padding(
            // `padding:8px 12px` (`index.html:93`).
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
        ),
      ),
    );
  }
}

/// The big detail avatar (`.drock.avatar`, `index.html:99`, `226`, `230`) — a
/// 130px navy disc with the species emoji at 72px.
///
/// The base `.drock` is a grey rock, but the `.avatar` class overrides its
/// background to the flat navy gradient `!important` (`index.html:226`) — animals
/// wear navy everywhere — so this draws the navy disc, the same gradient the
/// card's 44px avatar uses, only bigger. The craters the grey rock carries in its
/// `::after` are painted over by the navy fill and are not ported (the card's
/// avatar drops them for the same reason).
class _DetailAvatar extends StatelessWidget {
  const _DetailAvatar({required this.emoji});

  final String emoji;

  @override
  Widget build(BuildContext context) {
    return Container(
      // `.drock{width:130px;height:130px}` (`index.html:99`).
      width: 130,
      height: 130,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        // `radial-gradient(circle at 50% 42%, #24406e, #14284a)` (`index.html:
        // 226`) — `#24406e` is `--line`; `#14284a` is a one-off darker navy. The
        // same disc the card avatar draws (`animal_card.dart`).
        gradient: RadialGradient(
          center: Alignment(0, -0.16),
          radius: 0.9,
          colors: <Color>[Palette.line, Color(0xFF14284A)],
        ),
        border: Border.fromBorderSide(BorderSide(color: Palette.line)),
      ),
      child: ExcludeSemantics(
        // `.drock.avatar{font-size:72px}` (`index.html:230`).
        child: Text(emoji, style: const TextStyle(fontSize: 72, height: 1)),
      ),
    );
  }
}

/// The `"a {Species}-sized space rock"` line (`index.html:572`) — centred, muted,
/// with the species word picked out in white.
///
/// A [Text.rich] so the species keeps its `color:#fff` bold against the muted
/// sentence around it, exactly as the prototype bolds `<b>${c.species}</b>`.
class _SpeciesLine extends StatelessWidget {
  const _SpeciesLine({required this.species});

  final String species;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: <InlineSpan>[
          const TextSpan(text: 'a '),
          TextSpan(
            text: species,
            // `<b style="color:#fff">` (`index.html:572`).
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          const TextSpan(text: '-sized space rock'),
        ],
      ),
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: Palette.muted,
        // `font-size:12.5px` (`index.html:572`).
        fontSize: 12.5,
        height: 1.3,
      ),
    );
  }
}

/// The four kid stat tiles (`.tiles`, `index.html:574-579`) — a 2×2 grid of
/// How wide / How fast / How close / Power ⭐.
class _StatTiles extends StatelessWidget {
  const _StatTiles({required this.asteroid});

  final Asteroid asteroid;

  @override
  Widget build(BuildContext context) {
    // `How wide` is the range, not a scalar (decision 11, `index.html:575`): the
    // model's only `diaMin` read. `How fast` keeps one decimal (`toFixed(1)`,
    // `index.html:576`) — the detail screen's precision, distinct from the card
    // meta's whole-number speed. `How close` and `Power ⭐` read straight through
    // the AnimalSystem.
    final List<_Tile> tiles = <_Tile>[
      _Tile(
        label: 'How wide',
        value: '${asteroid.diaMin.round()}–${asteroid.diaMax.round()} m',
      ),
      _Tile(
        label: 'How fast',
        value: '${asteroid.velKps.toStringAsFixed(1)} km/s',
      ),
      _Tile(label: 'How close', value: distLabel(asteroid.missLunar)),
      _Tile(
        label: 'Power ⭐',
        value: '${powerStars(asteroid)}',
        // `.v` is overridden to `var(--accent2)` on this one tile
        // (`index.html:578`).
        valueColor: Palette.accent2,
      ),
    ];

    // `.tiles{display:grid;grid-template-columns:1fr 1fr;gap:9px}`
    // (`index.html:101`). Two rows of two, glued by 9px gaps. A [Row] pair rather
    // than a scrolling [GridView] so the tiles keep their intrinsic height and
    // the whole screen scrolls as one. Each row is wrapped in [IntrinsicHeight]
    // so its two tiles match heights the way CSS grid's default `align-items:
    // stretch` does — cheap here on a static screen, and robust if a value ever
    // wraps to two lines.
    return Column(
      children: <Widget>[
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(child: tiles[0]),
              const SizedBox(width: 9),
              Expanded(child: tiles[1]),
            ],
          ),
        ),
        const SizedBox(height: 9),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(child: tiles[2]),
              const SizedBox(width: 9),
              Expanded(child: tiles[3]),
            ],
          ),
        ),
      ],
    );
  }
}

/// One stat tile (`.tile`, `index.html:102-104`) — an uppercase muted key over a
/// big white value, on a card surface.
class _Tile extends StatelessWidget {
  const _Tile({
    required this.label,
    required this.value,
    this.valueColor = Colors.white,
  });

  final String label;
  final String value;

  /// `.tile .v{color:#fff}` for three tiles; the Power tile overrides it to
  /// [Palette.accent2] (`index.html:578`).
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    // Spoken as one phrase in its natural case — "How wide, 50–100 m" — with the
    // uppercased key and the raw value excluded below. `text-transform:uppercase`
    // is a CSS *display* transform: the prototype's DOM text stays "How wide", so
    // a faithful port shows caps but has the reader say the words, not letters.
    return Semantics(
      container: true,
      label: '$label, $value',
      child: ExcludeSemantics(
        child: Container(
          // `.tile` — `background:var(--card);border:1px solid var(--line);
          // border-radius:14px;padding:12px` (`index.html:102`).
          padding: const EdgeInsets.all(12),
          decoration: const BoxDecoration(
            color: Palette.card,
            borderRadius: BorderRadius.all(Radius.circular(14)),
            border: Border.fromBorderSide(BorderSide(color: Palette.line)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // `.tile .k` — `color:var(--muted);font-size:11px;
              // letter-spacing:.4px;text-transform:uppercase` (`index.html:103`).
              Text(
                label.toUpperCase(),
                style: const TextStyle(
                  color: Palette.muted,
                  fontSize: 11,
                  letterSpacing: 0.4,
                  height: 1.2,
                ),
              ),
              // `.tile .v` — `font-size:17px;font-weight:800;margin-top:3px`
              // (`index.html:104`).
              const SizedBox(height: 3),
              Text(
                value,
                style: TextStyle(
                  color: valueColor,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

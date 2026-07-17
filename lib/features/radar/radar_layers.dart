import 'package:flutter/foundation.dart';

/// One of the radar's five toggle chips (`index.html:668-672`).
///
/// **The label lives on the chip, exactly as the prototype's `defs` array
/// carries it** (`index.html:670`) — so the chip row can map over
/// [RadarLayer.values] the way `radarChips()` maps over `defs`, and the order
/// here is the order they appear. The one rename is the first: the prototype's
/// `⚠ Hazards` becomes **👋 Close flybys** (plan decision 2, matching the fix
/// `specs/07-sky-tab.md:31-34` already made) — the radar must never be the
/// surface that leaks NASA's word for it (`CLAUDE.md:64`).
enum RadarLayer {
  /// Show *only* the animals that are waving, rather than the whole sky
  /// (`showHaz`, `index.html:625`). Off by default, so the chip is the one that
  /// starts unlit.
  closeFlybys('👋 Close flybys'),

  /// The decorative Sun and six planets behind the field (`showPlanets`).
  planets('Planets'),

  /// The animals' names, the planets' names, and the Sun's (`showLabels`) —
  /// one chip over three layers (`index.html:755`, `806`, `864`).
  labels('Labels'),

  /// The dashed Moon-distance rings (`showRings`).
  rings('Rings'),

  /// The Moon on its own ring (`showMoon`).
  moon('Moon');

  const RadarLayer(this.label);

  /// What the chip says. Ported from the `defs` table (`index.html:670`).
  final String label;
}

/// Which of the radar's five layers are on — `Radar.showHaz` / `showLabels` /
/// `showRings` / `showMoon` / `showPlanets` (`index.html:625`), gathered into
/// one immutable value the view holds and the painter reads.
///
/// **Gathered rather than five loose fields for two reasons.** The painter takes
/// one parameter instead of five, so [RadarPainter.shouldRepaint] compares one
/// value; and the toggle is [toggle], one place that owns "flip this chip",
/// which the chip row and any future caller share rather than each rewriting the
/// same five-way switch.
///
/// **`playing` is deliberately not here.** It is not a layer: it changes whether
/// the sky *moves*, not what is drawn, so it lives on the view's `Ticker` (a
/// paused frame still paints, and its planets still bob — `index.html:730-734`).
/// Folding it in would make it look like something the painter reads, which it
/// is not.
@immutable
class RadarLayers {
  /// The prototype's opening state (`index.html:625`): Close-flybys **off**,
  /// everything else **on**.
  const RadarLayers({
    this.closeFlybysOnly = false,
    this.planets = true,
    this.labels = true,
    this.rings = true,
    this.moon = true,
  });

  /// `showHaz` (`index.html:625`), read through the tag rather than the raw flag
  /// (plan decision 2). When on, the field shows only the animals that are
  /// waving.
  final bool closeFlybysOnly;

  /// `showPlanets` — the Sun and the six planets behind the field.
  final bool planets;

  /// `showLabels` — the animals', the planets', and the Sun's names.
  final bool labels;

  /// `showRings` — the dashed Moon-distance rings.
  final bool rings;

  /// `showMoon` — the Moon riding the 1× ring.
  final bool moon;

  /// Whether [layer]'s chip is lit (`Radar[RFLAG[k]]`, `index.html:671`).
  bool isOn(RadarLayer layer) => switch (layer) {
    RadarLayer.closeFlybys => closeFlybysOnly,
    RadarLayer.planets => planets,
    RadarLayer.labels => labels,
    RadarLayer.rings => rings,
    RadarLayer.moon => moon,
  };

  /// The layers with [layer] flipped — `Radar[k] = !Radar[k]`
  /// (`index.html:672`).
  RadarLayers toggle(RadarLayer layer) => switch (layer) {
    RadarLayer.closeFlybys => _copy(closeFlybysOnly: !closeFlybysOnly),
    RadarLayer.planets => _copy(planets: !planets),
    RadarLayer.labels => _copy(labels: !labels),
    RadarLayer.rings => _copy(rings: !rings),
    RadarLayer.moon => _copy(moon: !moon),
  };

  RadarLayers _copy({
    bool? closeFlybysOnly,
    bool? planets,
    bool? labels,
    bool? rings,
    bool? moon,
  }) => RadarLayers(
    closeFlybysOnly: closeFlybysOnly ?? this.closeFlybysOnly,
    planets: planets ?? this.planets,
    labels: labels ?? this.labels,
    rings: rings ?? this.rings,
    moon: moon ?? this.moon,
  );

  @override
  bool operator ==(Object other) =>
      other is RadarLayers &&
      other.closeFlybysOnly == closeFlybysOnly &&
      other.planets == planets &&
      other.labels == labels &&
      other.rings == rings &&
      other.moon == moon;

  @override
  int get hashCode =>
      Object.hash(closeFlybysOnly, planets, labels, rings, moon);
}

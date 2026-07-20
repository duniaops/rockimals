import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:rockimals/core/animals/animal_system.dart';
import 'package:rockimals/core/theme/palette.dart';
import 'package:rockimals/data/models/asteroid.dart';
import 'package:rockimals/features/detail/detail_panel.dart';

/// The detail screen's **distance-comparison track** (`index.html:564-566,
/// 590-602`) — the "How close does it pass?" panel that lays Earth, the Moon, and
/// this asteroid out along one horizontal track so a child can *see* the flyby
/// against the one distance every kid already knows: how far the Moon is.
///
/// Like the size comparison next to it, this lives in the detail feature rather
/// than the AnimalSystem: `CLAUDE.md:78` scopes that module to the ladder,
/// naming, `power()`, `flybyTag()`, and the Moon-distance *formatters*
/// ([distLabel] / [moonCompare], which this panel reads back), not to the
/// on-screen geometry of one screen's track.

/// The three track positions for a given `missLunar`, as fractions of the track
/// width in `[0, 1]` (`index.html:565-566`).
///
/// Pulled out of the widget as a plain value so the geometry is unit-testable
/// without pumping a frame — the same split `radar_geometry.dart` makes. The one
/// property that matters, and the reason the prototype writes it this way: the
/// asteroid marker **never leaves the track**. The view spans
/// `max(1.25, missLunar)` Moon-distances, so a hair-close 0.07-LD pebble still
/// lands a little way in from Earth (the `1.25` floor stops it pinning to the
/// left edge), and a distant 50-LD rock is clamped to the far end by the
/// `min(1, …)` rather than shooting off the right.
@immutable
class DistanceTrack {
  const DistanceTrack._(this.moonFraction, this.asteroidFraction);

  /// Port of `span=max(1.25,a.missLunar); moonPct=1/span; astPct=min(1,l/span)`
  /// (`index.html:565-566`), kept as fractions rather than percentages.
  factory DistanceTrack.forMissLunar(double missLunar) {
    final double span = math.max(1.25, missLunar);
    return DistanceTrack._(1 / span, math.min(1.0, missLunar / span));
  }

  /// Earth is pinned at the track's left edge (`.earth{left:0}`, the literal
  /// `style="left:0"`, `index.html:120,595`) for every asteroid.
  static const double earthFraction = 0;

  /// The Moon's fixed marker, `1/span` of the way along (`index.html:566`). At
  /// the `1.25`-LD floor it sits at 0.8; a far view pushes it toward Earth.
  final double moonFraction;

  /// This asteroid's marker, clamped into `[0, 1]` so it stays on-track
  /// (`index.html:566`). Equals [moonFraction] at exactly 1 LD — the asteroid is
  /// then passing at the Moon's own distance, so the two dots coincide.
  final double asteroidFraction;
}

/// `.track` background `#16294a` (`index.html:118`) — a one-off navy, local to
/// this widget the way the ring strokes stay local to `radar_painter.dart`; the
/// prototype names it nowhere.
const Color _trackFill = Color(0xFF16294A);

/// `.moon` fill `#cfd6de` (`index.html:121`) — the grey Moon dot.
const Color _moonFill = Color(0xFFCFD6DE);

/// `.track{height:10px;border-radius:8px}` (`index.html:118`).
const double _trackHeight = 10;
const double _trackRadius = 8;

/// `.track{margin:… 6px …}` (`index.html:118`) — the 6px the track is inset from
/// the panel's content box on each side; Earth (fraction 0) sits at this inset.
const double _trackInset = 6;

/// Where the track's top edge sits inside the fixed-height region below. The top
/// tick lives 20px above it (`.tick.top{top:-20px}`) and the bottom ticks 16px
/// below (`.tick{top:16px}`), so 22 leaves room for the ☄️ label above and the
/// track floats the markers' shadows clear of the header.
const double _trackTop = 22;

/// Total height reserved for the track region — the top ☄️ tick (from y≈2), the
/// 10px track at y=22, and the Earth/Moon ticks at y=38 with room for their text.
const double _regionHeight = 54;

/// How much horizontal room the "🌙 Moon" tick needs between its centre and the
/// "Earth" tick's centre before the two 10px labels stop colliding — half of
/// each label's rendered width plus a small gap.
///
/// **Not in the prototype, and deliberately so.** The prototype draws both
/// ticks unconditionally (`index.html:595,597`), which garbles them into one
/// unreadable smear for any distant rock: at 177× Moon the Moon marker sits
/// `1/177` of the way along the track — a couple of pixels from Earth. When
/// they collide, the Moon's *label* is dropped (the grey dot stays, exactly as
/// the prototype places it): the panel header already announces the distance
/// in Moon terms, so no information is lost, and "Earth" stays readable.
const double _moonTickClearance = 44;

/// The "How close does it pass?" panel (`.panel` + `.distwrap` + `.track`,
/// `index.html:590-602`).
class DistanceComparison extends StatelessWidget {
  const DistanceComparison({super.key, required this.asteroid});

  final Asteroid asteroid;

  @override
  Widget build(BuildContext context) {
    final DistanceTrack track = DistanceTrack.forMissLunar(asteroid.missLunar);
    // The ☄️ tick's copy is the same Moon-relative label the "How close" stat
    // tile shows (`distLabel`, `index.html:599`); the header uses the longer
    // `moonCompare` phrasing (`index.html:591`). Both read through the
    // AnimalSystem so the track cannot phrase a distance differently from the
    // tile above it.
    final String astLabel = distLabel(asteroid.missLunar);

    return DetailPanel(
      // `<h4>How close does it pass? — ${moonCompare(a.missLunar)}</h4>`
      // (`index.html:591`). Announces its own natural-case label, as the
      // size panel's header does.
      heading: 'How close does it pass? — ${moonCompare(asteroid.missLunar)}',
      children: <Widget>[_Track(positions: track, astLabel: astLabel)],
    );
  }
}

/// The track itself (`.distwrap` > `.track`, `index.html:592-601`) — Earth, the
/// Moon, and the asteroid as absolutely-positioned dots with ticks above and
/// below, ported as a [Stack] over a [LayoutBuilder] so the fractional positions
/// resolve against the real pixel width.
class _Track extends StatelessWidget {
  const _Track({required this.positions, required this.astLabel});

  final DistanceTrack positions;
  final String astLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      // The dots and their tiny emoji ticks are decorative; a reader hears the
      // one fact that matters — where the asteroid falls between Earth and the
      // Moon — without spelling out 🌙/☄️. The header above carries the rest.
      label:
          'On a track from Earth to the Moon, this asteroid passes at '
          '$astLabel.',
      child: ExcludeSemantics(child: _buildTrack()),
    );
  }

  Widget _buildTrack() {
    return SizedBox(
      height: _regionHeight,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          // The track spans the panel content box minus its 6px side margins;
          // fractions map onto that inner width, so fraction 0 is the track's
          // left edge and fraction 1 its right.
          final double trackWidth = constraints.maxWidth - _trackInset * 2;
          double centerX(double fraction) =>
              _trackInset + fraction * trackWidth;

          // Whether the "🌙 Moon" tick has room to render clear of "Earth" —
          // see [_moonTickClearance] for why it may not.
          final bool moonTickFits =
              centerX(positions.moonFraction) -
                  centerX(DistanceTrack.earthFraction) >=
              _moonTickClearance;

          return Stack(
            // The browser does not clip: the top ☄️ tick sits above the track and
            // an edge label can overflow into the panel padding, exactly as the
            // prototype's un-clipped `.track` children do (`index.html:118` has no
            // `overflow`). `Clip.none` keeps that — and keeps the astm glow.
            clipBehavior: Clip.none,
            children: <Widget>[
              // `.track` — the bar, inset 6px each side, rounded, over var(--line).
              const Positioned(
                left: _trackInset,
                right: _trackInset,
                top: _trackTop,
                height: _trackHeight,
                child: DecoratedBox(
                  key: ValueKey<String>('dist-track'),
                  decoration: BoxDecoration(
                    color: _trackFill,
                    borderRadius: BorderRadius.all(
                      Radius.circular(_trackRadius),
                    ),
                    border: Border.fromBorderSide(
                      BorderSide(color: Palette.line),
                    ),
                  ),
                ),
              ),

              // `.earth` — a 16px blue disc at left:0 (`index.html:120,594`).
              _dot(
                keyValue: 'dist-earth',
                size: 16,
                centerX: centerX(DistanceTrack.earthFraction),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  // `radial-gradient(circle at 35% 30%,#7ec8ff,#1c6fb0)`.
                  gradient: RadialGradient(
                    center: Alignment(-0.3, -0.4),
                    radius: 0.9,
                    colors: <Color>[Color(0xFF7EC8FF), Color(0xFF1C6FB0)],
                  ),
                ),
              ),
              // `.tick` "Earth" below the track (`index.html:595`).
              _tick(
                centerX: centerX(DistanceTrack.earthFraction),
                top: _trackTop + 16,
                text: 'Earth',
                color: Palette.muted,
              ),

              // `.moon` — an 11px grey disc at moonPct (`index.html:121,596`).
              _dot(
                keyValue: 'dist-moon',
                size: 11,
                centerX: centerX(positions.moonFraction),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: _moonFill,
                ),
              ),
              // `.tick` "🌙 Moon" below the track (`index.html:597`) — only
              // when it fits clear of "Earth"; see [_moonTickClearance].
              if (moonTickFits)
                _tick(
                  centerX: centerX(positions.moonFraction),
                  top: _trackTop + 16,
                  text: '🌙 Moon',
                  color: Palette.muted,
                ),

              // `.astm` — a 12px accent disc with a glow at astPct
              // (`index.html:122,598`).
              _dot(
                keyValue: 'dist-asteroid',
                size: 12,
                centerX: centerX(positions.asteroidFraction),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Palette.accent,
                  // `box-shadow:0 0 10px var(--accent)`.
                  boxShadow: <BoxShadow>[
                    BoxShadow(color: Palette.accent, blurRadius: 10),
                  ],
                ),
              ),
              // `.tick.top` "☄️ {distLabel}" *above* the track, tinted accent2
              // (`index.html:599`).
              _tick(
                centerX: centerX(positions.asteroidFraction),
                top: _trackTop - 20,
                text: '☄️ $astLabel',
                color: Palette.accent2,
              ),
            ],
          );
        },
      ),
    );
  }

  /// One marker dot (`.earth`/`.moon`/`.astm`, `index.html:119`) — `position:
  /// absolute;top:50%;transform:translate(-50%,-50%)`, i.e. centred on
  /// (`centerX`, the track's vertical middle).
  Widget _dot({
    required String keyValue,
    required double size,
    required double centerX,
    required BoxDecoration decoration,
  }) {
    const double trackMidY = _trackTop + _trackHeight / 2;
    return Positioned(
      left: centerX - size / 2,
      top: trackMidY - size / 2,
      width: size,
      height: size,
      child: DecoratedBox(
        key: ValueKey<String>(keyValue),
        decoration: decoration,
      ),
    );
  }

  /// One tick label (`.tick`, `index.html:123-124`) — `transform:translateX(-50%)`
  /// centres its variable width on `centerX`, which [FractionalTranslation] does
  /// by shifting the laid-out text left by half its own width.
  Widget _tick({
    required double centerX,
    required double top,
    required String text,
    required Color color,
  }) {
    return Positioned(
      left: centerX,
      top: top,
      child: FractionalTranslation(
        translation: const Offset(-0.5, 0),
        child: Text(
          text,
          maxLines: 1,
          // `white-space:nowrap` (`index.html:123`).
          softWrap: false,
          overflow: TextOverflow.visible,
          style: TextStyle(
            color: color,
            // `.tick{font-size:10px}` (`index.html:123`).
            fontSize: 10,
            height: 1.2,
          ),
        ),
      ),
    );
  }
}

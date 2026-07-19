/// Text on the radar's canvas, laid out once and kept.
///
/// **Laying text out is by a distance the most expensive thing the radar does
/// per frame**, and almost none of its strings ever change: six ring labels,
/// "Earth", "Moon", and the planets' names are fixed for the life of the app.
/// Measuring them sixty times a second would be the single biggest cost on the
/// screen, spent on an answer that was the same the last fifty-nine times
/// (`CLAUDE.md:80`).
///
/// **Shared rather than per-painter**, because the radar is drawn by more than
/// one file — the field itself (`radar_painter.dart`) and the decorative planet
/// backdrop (`planet_painters.dart`) — and both paint 9px labels onto the same
/// canvas every frame. A second cache would be the same drift `Palette` was
/// written to end, and would silently halve this one's hit rate.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

/// How many labels this process has laid out.
///
/// Exists so the cache below can be held to its claim. "Laid out once" is the
/// single biggest per-frame cost on this screen (`CLAUDE.md:80`) and it is
/// invisible from the outside: a radar that re-measured all sixty of its
/// animals every frame would look exactly like one that did not, until it was
/// on a child's actual phone.
@visibleForTesting
int debugLabelLayouts = 0;

class RadarLabel {
  factory RadarLabel(
    String text, {
    required double fontSize,
    required Color colour,
    String? family,
    FontWeight? weight,
  }) {
    debugLabelLayouts++;
    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: text,
        // A null family is the port of `-apple-system, sans-serif`
        // (`index.html:824`), i.e. whatever the phone's own font is. The emoji
        // asks for `serif` outright (`index.html:861`) and is the only caller
        // that passes one.
        style: TextStyle(
          fontSize: fontSize,
          color: colour,
          fontFamily: family,
          fontWeight: weight,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    return RadarLabel._(
      painter,
      painter.computeDistanceToActualBaseline(TextBaseline.alphabetic),
    );
  }

  const RadarLabel._(this._painter, this._baseline);

  final TextPainter _painter;
  final double _baseline;

  /// Draws with [x] through the text's centre and [y] on its alphabetic
  /// baseline — canvas's `textAlign="center"` and its default `textBaseline`,
  /// which is what every `fillText` on this canvas is positioned by.
  void paint(Canvas canvas, double x, double y) =>
      _painter.paint(canvas, Offset(x - _painter.width / 2, y - _baseline));

  /// Draws with [at] through the text's centre in *both* axes — canvas's
  /// `textBaseline="middle"`, which `radarDraw` switches to for the animal
  /// emoji alone and switches back straight after (`index.html:861-863`). It is
  /// the difference between an animal sitting in its token and an animal
  /// standing on it.
  void paintCentred(Canvas canvas, Offset at) => _painter.paint(
    canvas,
    at.translate(-_painter.width / 2, -_painter.height / 2),
  );
}

/// The radar's text, laid out once each and kept for the life of the app.
///
/// **Bounded by the data, not by the frame count**, which is what makes a
/// process-lifetime cache safe here: the keys are the six ring labels, "Earth",
/// "Moon", the six planets and the Sun, one entry per (species, size) pair on
/// the field, and one per name shown — a few dozen in total, all of them
/// reachable again on the very next frame. Records are structurally equal in
/// Dart, so the key is just the style.
final Map<
  ({
    String text,
    double size,
    Color colour,
    String? family,
    FontWeight? weight,
  }),
  RadarLabel
>
_labels =
    <
      ({
        String text,
        double size,
        Color colour,
        String? family,
        FontWeight? weight,
      }),
      RadarLabel
    >{};

RadarLabel radarLabel(
  String text, {
  required double size,
  required Color colour,
  String? family,
  FontWeight? weight,
}) => _labels.putIfAbsent(
  (text: text, size: size, colour: colour, family: family, weight: weight),
  () => RadarLabel(
    text,
    fontSize: size,
    colour: colour,
    family: family,
    weight: weight,
  ),
);

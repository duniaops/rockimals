import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:rockimals/core/animals/animal_system.dart';
import 'package:rockimals/core/theme/palette.dart';
import 'package:rockimals/data/models/asteroid.dart';
import 'package:rockimals/features/detail/detail_panel.dart';

/// The detail screen's **size-comparison module** (`index.html:542-590`) — the
/// "How big is it?" panel that stands the asteroid next to a familiar object
/// (a bus, the Eiffel Tower, …) scaled to real diameter, with an
/// "≈ N× the {object}" line underneath.
///
/// `REFS` and `bestRef` are ported here, in the detail feature, rather than into
/// the AnimalSystem: `CLAUDE.md:78` scopes that module to the size→species
/// ladder, naming, `power()`, `flybyTag()`, and the Moon-distance formatters, and
/// the prototype itself keeps this table in its `DETAIL` block
/// (`index.html:542`), separate from `ANIMALS`. The comparison is a presentation
/// concern of this one screen.

/// One familiar reference object (`REFS` entry, `index.html:543-548`) — a title,
/// its real size in metres, and an emoji.
@immutable
class SizeRef {
  const SizeRef(this.title, this.meters, this.emoji);

  final String title;
  final double meters;
  final String emoji;
}

/// The 8-entry `REFS` table in its **literal source order** (`index.html:543-548`).
///
/// The order is data, not tidiness: Football pitch (105 m) precedes Statue of
/// Liberty (93 m), out of ascending order, and [bestRef] is last-match-wins
/// (decision 8), so this ordering is what makes `bestRef(100)` answer Statue of
/// Liberty. Sorting the list ascending would silently change that answer. Do not
/// reorder it.
const List<SizeRef> kSizeRefs = <SizeRef>[
  SizeRef('Human', 1.8, '🧍'),
  SizeRef('Bus', 12, '🚌'),
  SizeRef('Blue whale', 30, '🐋'),
  SizeRef('Football pitch', 105, '🏟️'),
  SizeRef('Statue of Liberty', 93, '🗽'),
  SizeRef('Eiffel Tower', 330, '🗼'),
  SizeRef('Empire State', 443, '🏙️'),
  SizeRef('Burj Khalifa', 830, '🏗️'),
];

/// Pick the reference within an order of magnitude, preferring the largest that
/// is still smaller-or-similar (`bestRef`, `index.html:550-552`).
///
/// **Last-match-wins, NOT max-by** (decision 8). The prototype iterates [kSizeRefs]
/// in array order keeping the *last* ref whose size is `<= meters * 1.6`, and the
/// table is deliberately not sorted ascending — so at `meters == 100` both
/// Football pitch (105) and Statue of Liberty (93) qualify and the later one,
/// Statue of Liberty, wins. Defaults to Human (the first entry) for anything too
/// small to reach even the second rung.
SizeRef bestRef(double meters) {
  SizeRef pick = kSizeRefs.first;
  for (final SizeRef ref in kSizeRefs) {
    if (ref.meters <= meters * 1.6) {
      pick = ref;
    }
  }
  return pick;
}

/// Render a reference object's size in metres the way the prototype's `${ref.m}`
/// does — an integer with no trailing `.0` (`12 m`), but keeping Human's one
/// decimal (`1.8 m`). `double.toString()` alone would print `12.0`.
String _refMeters(double meters) =>
    meters == meters.roundToDouble() ? meters.round().toString() : '$meters';

/// The two shapes' one-off greys, local to this widget exactly as the ring
/// strokes stay local to `radar_painter.dart` — the prototype names them nowhere
/// (`index.html:111-112`), so they do not belong in [Palette].
const Color _astLight = Color(0xFFD3DAE2);
const Color _astDark = Color(0xFF7C848D);
const Color _refLight = Color(0xFFCFD6DE);
const Color _refDark = Color(0xFF6A7078);

/// The "How big is it?" panel (`.panel` + `.cmp`, `index.html:581-590`).
class SizeComparison extends StatelessWidget {
  const SizeComparison({super.key, required this.asteroid});

  final Asteroid asteroid;

  @override
  Widget build(BuildContext context) {
    final SizeRef ref = bestRef(asteroid.diaMax);

    // Bar geometry (`index.html:558-560`): both shapes scale against the larger
    // of the two real sizes, with per-shape floors so the tiny one never
    // vanishes. `astW` is the asteroid disc's diameter; the ref is a `refW×refH`
    // rectangle.
    final double maxDim = math.max(asteroid.diaMax, ref.meters);
    final double astW = math.max(
      26.0,
      (asteroid.diaMax / maxDim * 120).roundToDouble(),
    );
    final double refW = math.max(
      14.0,
      (ref.meters / maxDim * 80).roundToDouble(),
    );
    final double refH = math.max(
      20.0,
      (ref.meters / maxDim * 110).roundToDouble(),
    );

    // "≈ N× the {object}" (`index.html:588`): one decimal below 10×, none at or
    // above it, and the object name lower-cased into the sentence.
    final double ratio = asteroid.diaMax / ref.meters;
    final String ratioStr = ratio.toStringAsFixed(ratio < 10 ? 1 : 0);

    return DetailPanel(
      // `<h4>How big is it? — ${sizeLabel(a.diaMax)}</h4>` (`index.html:583`).
      heading: 'How big is it? — ${sizeLabel(asteroid.diaMax)}',
      children: <Widget>[
        // `.cmp{align-items:flex-end;justify-content:center;gap:20px;
        // min-height:120px}` (`index.html:109`) — the two columns share a
        // bottom edge, so the bigger shape rises higher.
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 120),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              // The asteroid: a grey disc (`.cmp .ast .shape`,
              // `index.html:112`).
              _ComparisonObject(
                shape: Container(
                  width: astW,
                  height: astW,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      center: Alignment(-0.3, -0.4),
                      radius: 0.9,
                      colors: <Color>[_astLight, _astDark],
                    ),
                  ),
                ),
                boldCaption: '${asteroid.diaMax.round()} m',
                subCaption: 'this asteroid',
              ),
              const SizedBox(width: 20),
              // The reference: a grey slab (`.cmp .shape`, `index.html:111`).
              _ComparisonObject(
                shape: Container(
                  width: refW,
                  height: refH,
                  decoration: const BoxDecoration(
                    borderRadius: BorderRadius.all(Radius.circular(6)),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[_refLight, _refDark],
                    ),
                  ),
                ),
                boldCaption: '${ref.emoji} ${ref.title}',
                subCaption: '${_refMeters(ref.meters)} m',
              ),
            ],
          ),
        ),
        // The ratio line — `margin-top:8px`, muted, centred (`index.html:588`).
        const SizedBox(height: 8),
        Text(
          '≈ $ratioStr× the ${ref.title.toLowerCase()}',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Palette.muted,
            fontSize: 12,
            height: 1.3,
          ),
        ),
      ],
    );
  }
}

/// One `.obj` column (`index.html:110`) — a shape over a two-line caption, the
/// pair bottom-aligned with its sibling by the parent [Row].
class _ComparisonObject extends StatelessWidget {
  const _ComparisonObject({
    required this.shape,
    required this.boldCaption,
    required this.subCaption,
  });

  final Widget shape;

  /// `.cap b{color:#fff;display:block;font-size:12px}` (`index.html:114`) — the
  /// asteroid's size, or the reference's emoji + name.
  final String boldCaption;

  /// The trailing `.cap` text (`index.html:113`) — muted, 11px.
  final String subCaption;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        shape,
        // `.cmp .obj{gap:6px}` (`index.html:110`).
        const SizedBox(height: 6),
        ConstrainedBox(
          // `.cmp .cap{max-width:90px;text-align:center}` (`index.html:113`).
          constraints: const BoxConstraints(maxWidth: 90),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                boldCaption,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
              ),
              Text(
                subCaption,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Palette.muted,
                  fontSize: 11,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

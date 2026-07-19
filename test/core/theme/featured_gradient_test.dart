import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/core/theme/featured_gradient.dart';

/// **Read out of `index.html` rather than typed twice**, for the reason
/// `palette_test.dart` states at length: a pair of hand-copied hex values is
/// exactly the kind of thing that goes wrong by one nibble and surfaces weeks
/// later as "why is that card a slightly different blue?". `index.html` is the
/// authoritative spec (`CLAUDE.md:44`) and ships beside this test, so parsing it
/// costs nothing and cannot go stale.
///
/// This constant exists because the same two stops were written out four times
/// across three features. The interesting failure is therefore not just "the
/// constant is wrong" but "someone wrote the literal again", so the last group
/// greps `lib/` for the hex values and fails if a fifth copy appears.
void main() {
  final String prototype = File('index.html').readAsStringSync();
  final List<List<Color>> declared = _featuredGradients(prototype);

  group('kFeaturedGradient — parity with the prototype', () {
    test('the prototype declares this gradient five times', () {
      // `.hero` (:45), `.lvlcard` (:145), `.gfeat` (:210), `.badgePop .bcard`
      // (:249), `.ptsCard` (:262). The count is asserted, not just the value,
      // because it is the whole argument for hoisting: five restatements is the
      // prototype saying "shared" without a variable to say it with. A
      // prototype that grew a sixth — or dropped to one — should make someone
      // re-read this file rather than sail past.
      expect(declared, hasLength(5));
    });

    test('all five declare the same two stops', () {
      // If the prototype ever varies one of them, `kFeaturedGradient` is the
      // wrong abstraction and this is where that shows up — before four call
      // sites have quietly been made identical that were not meant to be.
      // Compared as strings because `List` has identity equality, so a `Set` of
      // the lists themselves would hold five entries however equal they are.
      final Set<String> distinct = declared
          .map((List<Color> stops) => stops.join(','))
          .toSet();
      expect(distinct, hasLength(1));
    });

    test('the constant carries those stops in that order', () {
      expect(kFeaturedGradient.colors, declared.first);
    });

    test('runs topLeft → bottomRight, approximating CSS 150°', () {
      // CSS `150deg` points down and slightly right. Flutter has no degree
      // form, so all four original copies independently approximated it this
      // way; pinned here so sharing them cannot silently change it.
      expect(kFeaturedGradient.begin, Alignment.topLeft);
      expect(kFeaturedGradient.end, Alignment.bottomRight);
    });
  });

  group('kFeaturedGradient — the only copy in the app', () {
    test('no Dart file outside this token restates the hex values', () {
      final List<String> offenders = <String>[];
      for (final FileSystemEntity entity
          in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        if (entity.path.endsWith('core/theme/featured_gradient.dart')) continue;
        final String source = entity.readAsStringSync();
        if (source.contains('0xFF17325C') || source.contains('0xFF0E2244')) {
          offenders.add(entity.path);
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'these files write out the featured gradient again instead of '
            'reading kFeaturedGradient — the duplication this constant exists '
            'to end',
      );
    });
  });
}

/// Every `linear-gradient(150deg,#rrggbb,#rrggbb)` in the prototype's CSS, as
/// its two parsed stops.
List<List<Color>> _featuredGradients(String prototype) {
  final RegExp pattern = RegExp(
    r'linear-gradient\(150deg,\s*#([0-9a-fA-F]{6}),\s*#([0-9a-fA-F]{6})\)',
  );

  return pattern
      .allMatches(prototype)
      .map(
        (RegExpMatch m) => <Color>[
          Color(int.parse('FF${m.group(1)!}', radix: 16)),
          Color(int.parse('FF${m.group(2)!}', radix: 16)),
        ],
      )
      .toList();
}

import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/core/theme/palette.dart';

/// **This suite reads `index.html` and compares against it, rather than holding
/// values someone typed twice.**
///
/// A palette is a table of hand-copied hex digits, which is precisely where a
/// careful read fails silently: nothing throws, a colour is just quietly wrong
/// by one nibble, and it surfaces as "why is the nav a slightly different
/// orange?" weeks later. The FALLBACK item hit this exact shape and answered it
/// by verifying mechanically instead of by eye; this is the same answer, made
/// permanent. `index.html` is the authoritative spec (`CLAUDE.md:44`) and is
/// committed alongside this test, so parsing it costs nothing and can never go
/// stale.
///
/// The payoff is that these tests fail for the *right* reason in both
/// directions: a typo in `Palette` fails, and so does a prototype that grows a
/// twelfth variable, or that starts using one of the two dead ones.
void main() {
  final String prototype = File('index.html').readAsStringSync();
  final Map<String, Color> declared = _rootVariables(prototype);

  group('Palette — parity with the prototype', () {
    // The nine live variables. `--navy` and `--card2` are deliberately absent —
    // see the dead-variable group below, which is what earns their absence.
    const Map<String, Color> ported = <String, Color>{
      'accent': Palette.accent,
      'accent2': Palette.accent2,
      'good': Palette.good,
      'bad': Palette.bad,
      'ink': Palette.ink,
      'muted': Palette.muted,
      'card': Palette.card,
      'line': Palette.line,
      'line2': Palette.line2,
    };

    ported.forEach((String name, Color ours) {
      test('--$name matches the prototype digit for digit', () {
        expect(
          declared[name],
          isNotNull,
          reason: '--$name is not declared in the prototype :root block',
        );
        expect(ours, declared[name]);
      });
    });

    test('the :root block declares exactly the eleven we know about', () {
      // Set equality, not a subset: a prototype that gains a variable should
      // fail here rather than be silently unported. The two dead ones are
      // listed because they *are* declared — being unported is a decision this
      // suite records, not an oversight it should hide.
      expect(
        declared.keys.toSet(),
        <String>{...ported.keys, 'navy', 'card2'},
      );
    });
  });

  group('the two dead variables are still dead', () {
    // The plan's decision 1 — "do not port the prototype's dead state" — is why
    // `--navy` and `--card2` have no home in `Palette`. That decision rests on a
    // fact about the prototype, so the fact is asserted rather than trusted: if
    // some future edit to `index.html` starts using either, this fails and says
    // to port it.
    for (final (String name, String hex) in <(String, String)>[
      ('navy', '0B1F3A'),
      ('card2', '0f2242'),
    ]) {
      test('--$name is declared and then never referenced', () {
        expect(
          declared[name],
          isNotNull,
          reason: 'expected --$name to still be declared',
        );
        expect(
          prototype.contains('var(--$name)'),
          isFalse,
          reason: '--$name is now used; port it into Palette',
        );
        // Nor by its raw hex, which is how `--card` is used in five places
        // despite being a variable — so a `var()` search alone would not settle
        // it. Exactly one occurrence: the declaration itself.
        expect(
          RegExp(hex, caseSensitive: false).allMatches(prototype).length,
          1,
          reason: '$hex appears outside its declaration; port it into Palette',
        );
      });
    }
  });

  group('the colours the prototype never named', () {
    test('pageBackground is the page background', () {
      // Three uses (`body`, `.overlay`, `.loading`), each restating the literal
      // by hand — which is what makes it a palette entry despite never being a
      // variable.
      expect(
        RegExp('background:#070f1f').allMatches(prototype).length,
        3,
        reason: 'the page background moved; Palette.pageBackground is stale',
      );
      expect(Palette.pageBackground, const Color(0xFF070F1F));
    });

    test('onAccent is what the prototype puts on the orange', () {
      // `.rchip.on`, `.rplay`, and the primary buttons — the answer Material's
      // `onPrimary` would otherwise compute for itself. See `main.dart`.
      expect(
        RegExp('#1a0d05', caseSensitive: false).allMatches(prototype).length,
        5,
        reason: 'the text-on-accent colour moved; Palette.onAccent is stale',
      );
      expect(Palette.onAccent, const Color(0xFF1A0D05));
    });
  });

  group('deriving an alpha off muted', () {
    // `radar_painter.dart` now writes its two label colours as
    // `Palette.muted.withValues(alpha: …)` instead of restating muted's
    // channels — which is the whole point of the palette existing, and is also
    // an unverified claim about `withValues` that **nothing else in the suite
    // touches**. The radar's tests never probe a label (text is antialiased and
    // a pixel probe on a glyph would be fragile), so without this group the
    // derivation could be wrong in either channel or alpha and every test would
    // still be green.

    test('muted really is the rgba() the radar hard-codes', () {
      // The premise: `rgba(147,168,202,…)` at `index.html:830` and `:875` is
      // `--muted` in disguise. If muted's channels are not 147/168/202, the
      // radar's labels are a different colour that merely looks like it, and
      // deriving them off muted would be a silent re-colour.
      expect((Palette.muted.r * 255).round(), 147);
      expect((Palette.muted.g * 255).round(), 168);
      expect((Palette.muted.b * 255).round(), 202);
      expect(prototype.contains('rgba(147,168,202,.55)'), isTrue);
      expect(prototype.contains('rgba(147,168,202,.85)'), isTrue);
    });

    test('deriving reproduces restating, exactly', () {
      // Not "close enough": these are the values `radar_painter.dart` shipped
      // before this refactor, so anything but equality is a behaviour change
      // smuggled in under a cleanup.
      expect(
        Palette.muted.withValues(alpha: 0.55),
        const Color.fromRGBO(147, 168, 202, 0.55),
      );
      expect(
        Palette.muted.withValues(alpha: 0.85),
        const Color.fromRGBO(147, 168, 202, 0.85),
      );
    });
  });
}

/// The prototype's `:root{…}` custom properties, as Flutter colours.
///
/// Deliberately strict: it matches only six-digit hex, which is every value the
/// block holds today. A prototype that switched one to `rgb()` or a keyword
/// would drop out of this map and fail the set-equality test above rather than
/// pass by being invisible.
Map<String, Color> _rootVariables(String prototype) {
  final RegExpMatch? root = RegExp(r':root\{([^}]*)\}').firstMatch(prototype);
  // A throw, not an `expect`: this runs while `main` is still building the
  // suite, where `expect` has no test to fail and reports an
  // `OutsideTestException` instead of the thing that is actually wrong.
  if (root == null) {
    throw StateError('no :root block in index.html — has the prototype moved?');
  }

  final Map<String, Color> vars = <String, Color>{};
  final RegExp decl = RegExp(r'--([a-z0-9]+)\s*:\s*#([0-9a-fA-F]{6})');
  for (final RegExpMatch m in decl.allMatches(root.group(1)!)) {
    vars[m.group(1)!] = Color(0xFF000000 | int.parse(m.group(2)!, radix: 16));
  }
  return vars;
}

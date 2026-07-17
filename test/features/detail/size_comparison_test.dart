import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/core/animals/animal_system.dart';
import 'package:rockimals/data/fallback_asteroids.dart';
import 'package:rockimals/data/models/asteroid.dart';
import 'package:rockimals/features/detail/size_comparison.dart';

/// The detail screen's size-comparison module (`REFS` / `bestRef` / the "How big
/// is it?" panel, `index.html:542-590`).
///
/// The `bestRef` group is the guardrail decision 8 exists for: the `REFS` table
/// is ported in its literal, non-ascending source order and the pick is
/// last-match-wins, so `bestRef(100)` **must** answer Statue of Liberty. Either
/// re-sorting the array or reimplementing the loop as a max-by would flip that
/// answer, and the `100 m` assertion is what catches it. The widget group then
/// mounts the panel and reads that its shapes, captions and "≈ N×" line render
/// the prototype's values for a giant and a tiny animal.
void main() {
  group('bestRef — last-match-wins over the literal source order (decision 8)',
      () {
    test('too small to reach the second rung → Human (the default)', () {
      // 1 * 1.6 = 1.6, below Human's own 1.8, so nothing qualifies and the pick
      // stays the first entry.
      expect(bestRef(1).title, 'Human');
    });

    test('20 m → Blue whale', () {
      // 20 * 1.6 = 32: Human, Bus, Blue whale (30) qualify; Football pitch (105)
      // does not. Blue whale is the last qualifier.
      expect(bestRef(20).title, 'Blue whale');
    });

    test('100 m → Statue of Liberty, NOT Football pitch (the decision-8 pin)',
        () {
      // 100 * 1.6 = 160: both Football pitch (105) and Statue of Liberty (93)
      // qualify. The table lists Football pitch *first*, so last-match-wins
      // returns Statue of Liberty. A max-by, or a re-sorted array, would return
      // Football pitch — this assertion is the tripwire for that helpful "fix".
      expect(bestRef(100).title, 'Statue of Liberty');
    });

    test('500 m → Empire State', () {
      // 500 * 1.6 = 800: everything through Empire State (443) qualifies; Burj
      // Khalifa (830) does not.
      expect(bestRef(500).title, 'Empire State');
    });

    test('3000 m → Burj Khalifa (the largest)', () {
      // 3000 * 1.6 = 4800: every rung qualifies, so the last one wins.
      expect(bestRef(3000).title, 'Burj Khalifa');
    });

    test('the table is in its literal, non-ascending source order', () {
      // The load-bearing fact: Football pitch (105) precedes Statue of Liberty
      // (93). If a future edit sorts this ascending, the 100 m test above fails,
      // but this pins the *cause* directly.
      expect(kSizeRefs.map((SizeRef r) => r.title).toList(), <String>[
        'Human',
        'Bus',
        'Blue whale',
        'Football pitch',
        'Statue of Liberty',
        'Eiffel Tower',
        'Empire State',
        'Burj Khalifa',
      ]);
    });
  });

  group('SizeComparison panel', () {
    // 433 Eros — 16 800 m, the giant of the sample sky. bestRef(16800) is Burj
    // Khalifa (830 m); the ratio 16800/830 ≈ 20.2 is ≥ 10, so it renders with no
    // decimals.
    final Asteroid whale =
        kFallbackAsteroids.firstWhere((Asteroid a) => a.name == '433 Eros');

    // 2020 SW — 9 m, tiny. bestRef(9): 9 * 1.6 = 14.4, so Bus (12) is the last
    // qualifier. The ratio 9/12 = 0.75 is < 10, so it renders one decimal (0.8),
    // exercising the other branch of the "≈ N×" formatter.
    final Asteroid tiny =
        kFallbackAsteroids.firstWhere((Asteroid a) => a.name == '2020 SW');

    Future<void> pump(WidgetTester tester, Asteroid rock) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(width: 360, child: SizeComparison(asteroid: rock)),
            ),
          ),
        ),
      );
    }

    testWidgets('a giant renders Burj Khalifa and a whole-number ratio',
        (tester) async {
      await pump(tester, whale);

      // The panel header reads through the AnimalSystem's own size label, shown
      // uppercase (`text-transform`) exactly as the stat-tile keys are.
      expect(
        find.text('How big is it? — ${sizeLabel(whale.diaMax)}'.toUpperCase()),
        findsOneWidget,
      );

      // The asteroid column: its rounded diameter and the fixed caption.
      expect(find.text('${whale.diaMax.round()} m'), findsOneWidget); // 16800 m
      expect(find.text('this asteroid'), findsOneWidget);

      // The reference column: bestRef(16800) is Burj Khalifa at 830 m.
      expect(find.text('🏗️ Burj Khalifa'), findsOneWidget);
      expect(find.text('830 m'), findsOneWidget);

      // ratio ≈ 20.2, ≥ 10 → no decimals, and the object name lower-cased.
      expect(find.text('≈ 20× the burj khalifa'), findsOneWidget);
    });

    testWidgets('a tiny animal renders the Bus and a one-decimal ratio',
        (tester) async {
      await pump(tester, tiny);

      expect(find.text('9 m'), findsOneWidget); // round(diaMax)
      expect(find.text('this asteroid'), findsOneWidget);

      // bestRef(9) is the Bus at 12 m — an integer with no trailing ".0".
      expect(find.text('🚌 Bus'), findsOneWidget);
      expect(find.text('12 m'), findsOneWidget);

      // ratio 0.75 < 10 → one decimal, rounding to 0.8.
      expect(find.text('≈ 0.8× the bus'), findsOneWidget);
    });

    testWidgets('the header speaks its natural-case label, not the caps',
        (tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await pump(tester, whale);

      // Display shows caps; the reader hears the words (matching the stat tiles).
      expect(
        find.bySemanticsLabel('How big is it? — ${sizeLabel(whale.diaMax)}'),
        findsOneWidget,
      );

      handle.dispose();
    });
  });
}

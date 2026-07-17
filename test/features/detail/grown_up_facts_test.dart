import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/core/animals/animal_system.dart';
import 'package:rockimals/data/fallback_asteroids.dart';
import 'package:rockimals/data/models/asteroid.dart';
import 'package:rockimals/features/data/providers.dart';
import 'package:rockimals/features/detail/detail_screen.dart';
import 'package:rockimals/features/detail/grown_up_facts.dart';

/// The grown-up facts panel (`index.html:608-612`) and its parent gate — the
/// only place the real designation and the external NASA/JPL link appear, and
/// the one outbound tap in the app, gated behind a simple arithmetic prompt.
///
/// Two things this item is on the hook for that the prototype never was:
///  * the designation is shown *verbatim* (plan's numbered-asteroid decision),
///  * the link is *gated* (`CLAUDE.md:25`, spec 06) — the prototype opened it on
///    a bare tap, so the gate is a new behaviour with no prototype parity to
///    lean on, and is pinned here on its own terms.
///
/// The launcher is injected as a spy so the gate flow runs without a real
/// platform channel; a fixed [ParentGateChallenge] makes the arithmetic known.
void main() {
  final Asteroid eros =
      kFallbackAsteroids.firstWhere((Asteroid a) => a.name == '433 Eros');
  final Asteroid rabbit =
      kFallbackAsteroids.firstWhere((Asteroid a) => a.name == '2020 SW');

  // A gate whose answer we know: 3 + 4 = 7.
  const ParentGateChallenge fixed = ParentGateChallenge(3, 4);

  Future<List<Uri>> pumpPanel(
    WidgetTester tester,
    Asteroid rock,
  ) async {
    final List<Uri> launched = <Uri>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GrownUpFacts(
            asteroid: rock,
            challenge: fixed,
            launcher: (Uri url) async {
              launched.add(url);
              return true;
            },
          ),
        ),
      ),
    );
    return launched;
  }

  group('the panel', () {
    testWidgets('shows the intro, the designation verbatim, and the link', (
      tester,
    ) async {
      await pumpPanel(tester, eros);

      expect(
        find.text('🔭 Grown-up fact — its real space name is'),
        findsOneWidget,
      );
      // The real NASA designation, exactly as the model holds it — not the
      // friendly "{First} the {Species}".
      expect(find.text('433 Eros'), findsOneWidget);
      expect(find.text('Look it up on NASA/JPL ↗'), findsOneWidget);
    });

    testWidgets('renders the designation, not the animal name', (tester) async {
      // The panel is the one place the raw designation surfaces; the animal name
      // ("{First} the Rabbit") must NOT — that is the friendly name shown
      // everywhere else, and mixing them here would leak jargon or hide the
      // real name a grown-up came for.
      await pumpPanel(tester, rabbit);
      final Critter c = critter(rabbit);

      expect(find.text('2020 SW'), findsOneWidget);
      expect(find.text(c.name), findsNothing); // e.g. "Milo the Rabbit"
    });
  });

  group('the parent gate', () {
    testWidgets('a tap on the link raises the arithmetic gate', (tester) async {
      final List<Uri> launched = await pumpPanel(tester, eros);

      // No dialog, and nothing launched, before the tap.
      expect(find.text('Ask a grown-up 🔭'), findsNothing);
      expect(launched, isEmpty);

      await tester.tap(find.text('Look it up on NASA/JPL ↗'));
      await tester.pumpAndSettle();

      expect(find.text('Ask a grown-up 🔭'), findsOneWidget);
      expect(find.text('What is 3 + 4?'), findsOneWidget);
      // The gate stands between the tap and the browser: still nothing launched.
      expect(launched, isEmpty);
    });

    testWidgets('a correct answer opens the JPL link and closes the gate', (
      tester,
    ) async {
      final List<Uri> launched = await pumpPanel(tester, eros);

      await tester.tap(find.text('Look it up on NASA/JPL ↗'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '7');
      await tester.tap(find.text('Open ↗'));
      await tester.pumpAndSettle();

      // Opened exactly the model's JPL URL, and the gate is gone.
      expect(launched, <Uri>[Uri.parse(eros.jpl)]);
      expect(find.text('What is 3 + 4?'), findsNothing);
    });

    testWidgets('a wrong answer neither launches nor closes, and is gentle', (
      tester,
    ) async {
      final List<Uri> launched = await pumpPanel(tester, eros);

      await tester.tap(find.text('Look it up on NASA/JPL ↗'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '9');
      await tester.tap(find.text('Open ↗'));
      await tester.pumpAndSettle();

      // The browser never opened; the gate stays up so a grown-up can retry.
      expect(launched, isEmpty);
      expect(find.text('What is 3 + 4?'), findsOneWidget);
      // Encouraging, never a scold (`CLAUDE.md:63`).
      expect(find.text('Not quite — ask a grown-up to help!'), findsOneWidget);
    });

    testWidgets('Cancel dismisses the gate without launching', (tester) async {
      final List<Uri> launched = await pumpPanel(tester, eros);

      await tester.tap(find.text('Look it up on NASA/JPL ↗'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('What is 3 + 4?'), findsNothing);
      expect(launched, isEmpty);
    });
  });

  group('ParentGateChallenge', () {
    test('accepts only the exact sum, trimming whitespace', () {
      const ParentGateChallenge c = ParentGateChallenge(3, 4);
      expect(c.answer, 7);
      expect(c.prompt, 'What is 3 + 4?');
      expect(c.accepts('7'), isTrue);
      expect(c.accepts('  7 '), isTrue);
      expect(c.accepts('8'), isFalse);
      expect(c.accepts(''), isFalse);
      expect(c.accepts('seven'), isFalse); // never throws on garbage
    });

    test('random draws both addends from 2..9 so the sum is non-trivial', () {
      final Random seeded = Random(42);
      for (int i = 0; i < 200; i++) {
        final ParentGateChallenge c = ParentGateChallenge.random(seeded);
        expect(c.a, inInclusiveRange(2, 9));
        expect(c.b, inInclusiveRange(2, 9));
      }
    });
  });

  testWidgets(
    'inside the detail screen the designation appears exactly once, gated',
    (tester) async {
      // The Done-when's "the designation appears nowhere else": pump the whole
      // detail screen and confirm "433 Eros" renders once (the grown-up panel),
      // while the header title shows the friendly animal name instead. Not
      // tapping the link here, so the screen's default real launcher is never
      // invoked.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            followsProvider.overrideWith(_MemFollows.new),
          ],
          child: MaterialApp(home: DetailScreen(asteroid: eros)),
        ),
      );

      final Critter c = critter(eros);
      expect(find.text('433 Eros'), findsOneWidget);
      expect(find.text(c.name), findsOneWidget); // "{First} the Whale"
      expect(c.name, isNot('433 Eros'));
    },
  );
}

/// A follow set held in memory — the widget tester's fake clock hangs on a real
/// `Box.put`, so the detail-screen mount (which reads [followsProvider]) is kept
/// off Hive, the pattern `detail_screen_test.dart` established.
class _MemFollows extends FollowsNotifier {
  @override
  Set<String> build() => <String>{};

  @override
  Future<void> toggle(String designation) async {}
}

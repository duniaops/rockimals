import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/core/animals/animal_system.dart';
import 'package:rockimals/data/fallback_asteroids.dart';
import 'package:rockimals/data/models/asteroid.dart';
import 'package:rockimals/features/animals/widgets/animal_card.dart';

/// The shared animal row card (`acardEl`, `index.html:461-469`) — the `.acard`
/// the Sky and My Animals lists are built from.
///
/// The card is a plain [StatelessWidget] over an [Asteroid], so it is mounted
/// directly here rather than driven through a screen: the whole point of the
/// widget is that it renders one animal's row, so the honest test is to hand it
/// one and read the row. Field expectations are computed through the
/// AnimalSystem's own formatters, which pins the card's *wiring* — which field
/// feeds which formatter, and the order and glue between them — while leaving the
/// maths to `animal_system_test`. One literal meta line is asserted too, as a
/// human-readable record of what a real record renders.
void main() {
  // 2011 EW — 302 m (Elephant), 12.4 Moons, 11.2 km/s, hazardous. A close flyby
  // (the `hazardous` flag), and its speed rounds to a whole number that differs
  // from the raw value, so it catches a card that formats speed like the HUD's
  // one-decimal line instead of the list's whole number.
  final Asteroid closeRock =
      kFallbackAsteroids.firstWhere((Asteroid a) => a.name == '2011 EW');

  // 2015 TB145 — 640 m (Elephant), 1.3 Moons, 35 km/s, not hazardous and outside
  // the Moon: the "just passing" case, for the green badge.
  final Asteroid passingRock =
      kFallbackAsteroids.firstWhere((Asteroid a) => a.name == '2015 TB145');

  Future<void> mount(WidgetTester tester, Asteroid rock,
      {VoidCallback? onTap, Widget? footer}) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              child: AnimalCard(
                asteroid: rock,
                onTap: onTap ?? () {},
                footer: footer,
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('renders the avatar, name, meta and flyby badge of an animal', (
    WidgetTester tester,
  ) async {
    await mount(tester, closeRock);

    final Critter c = critter(closeRock);

    // The avatar emoji, the "{First} the {Species}" name, and the badge.
    expect(find.text(c.animal.emoji), findsOneWidget); // 🐘 Elephant
    expect(find.text(c.name), findsOneWidget);
    expect(find.text(flybyTag(closeRock).label), findsOneWidget); // 👋 close flyby

    // The three-field meta, computed through the formatters (so this pins order,
    // glue, and which field feeds which function) and pinned once as a literal.
    final String expectedMeta = '${sizeLabel(closeRock.diaMax)}'
        ' · ${distLabel(closeRock.missLunar)}'
        ' · ${closeRock.velKps.round()} km/s';
    expect(expectedMeta, 'stadium-sized · 12× Moon · 11 km/s');
    expect(find.text(expectedMeta), findsOneWidget);
  });

  testWidgets('shows the "just passing" badge for a distant, unflagged rock', (
    WidgetTester tester,
  ) async {
    await mount(tester, passingRock);

    expect(flybyTag(passingRock), FlybyTag.justPassing);
    expect(find.text('just passing'), findsOneWidget);
    expect(find.text('👋 close flyby'), findsNothing);
  });

  testWidgets('a tap invokes the callback', (WidgetTester tester) async {
    int taps = 0;
    await mount(tester, closeRock, onTap: () => taps++);

    await tester.tap(find.byType(AnimalCard));
    expect(taps, 1);
  });

  testWidgets('renders an optional footer beneath the card body', (
    WidgetTester tester,
  ) async {
    const String caption = '⏳ approach 2026-07-16';
    await mount(tester, closeRock, footer: const Text(caption));

    // The footer is present, and the rest of the card still renders around it.
    expect(find.text(caption), findsOneWidget);
    expect(find.text(critter(closeRock).name), findsOneWidget);
  });

  testWidgets('speaks a screen reader label without the decorative glyphs', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await mount(tester, closeRock);

    final Critter c = critter(closeRock);
    // One clean button label: the name and stats in words, the badge without its
    // 👋 glyph, and no bare avatar emoji sounded out.
    expect(
      find.bySemanticsLabel(
        '${c.name}, stadium-sized · 12× Moon · 11 km/s, close flyby',
      ),
      findsOneWidget,
    );

    handle.dispose();
  });
}

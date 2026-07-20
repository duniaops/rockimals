import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/core/a11y/control_scale.dart';
import 'package:rockimals/core/animals/animal_system.dart';
import 'package:rockimals/data/fallback_asteroids.dart';
import 'package:rockimals/data/models/asteroid.dart';
import 'package:rockimals/features/animals/widgets/animal_card.dart';
import 'package:rockimals/features/animals/widgets/flyby_badge.dart';

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
  // from the raw value, so it exercises the shared kid-facing speed formatter.
  final Asteroid closeRock = kFallbackAsteroids.firstWhere(
    (Asteroid a) => a.name == '2011 EW',
  );

  // 2015 TB145 — 640 m (Elephant), 1.3 Moons, 35 km/s, not hazardous and outside
  // the Moon: the "just passing" case, for the green badge.
  final Asteroid passingRock = kFallbackAsteroids.firstWhere(
    (Asteroid a) => a.name == '2015 TB145',
  );

  Future<void> mount(
    WidgetTester tester,
    Asteroid rock, {
    VoidCallback? onTap,
    Widget? footer,
    String? footerLabel,
    double controlScale = 1,
  }) {
    return tester.pumpWidget(
      ControlScale(
        scale: controlScale,
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 360,
                child: AnimalCard(
                  asteroid: rock,
                  onTap: onTap ?? () {},
                  footer: footer,
                  footerLabel: footerLabel,
                ),
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
    expect(
      find.text(flybyTag(closeRock).label),
      findsOneWidget,
    ); // 👋 close flyby

    // The three-field meta, computed through the formatters (so this pins order,
    // glue, and which field feeds which function) and pinned once as a literal.
    final String expectedMeta =
        '${sizeLabel(closeRock.diaMax)}'
        ' · ${distLabel(closeRock.missLunar)}'
        ' · ${speedLabel(closeRock.velKps)}';
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

  testWidgets('appends the footer to what a screen reader is told', (
    WidgetTester tester,
  ) async {
    // The card says its whole meaning through one label and hides the visual —
    // including the footer — behind [ExcludeSemantics], so a caption added
    // there is *silent* unless the card is told what it means. That is the
    // failure mode a screenshot cannot show: My Animals' approach date would
    // render for a child who can see it and not exist for one using a screen
    // reader.
    final SemanticsHandle handle = tester.ensureSemantics();
    const String caption = '⏳ approach 2026-07-16';
    await mount(
      tester,
      closeRock,
      footer: const Text(caption),
      footerLabel: caption,
    );

    final String label = tester.getSemantics(find.byType(AnimalCard)).label;
    expect(label, contains(caption));
    // Appended, not substituted — the name and meta are still spoken first.
    expect(label, startsWith(critter(closeRock).name));

    handle.dispose();
  });

  testWidgets('says nothing extra when there is no footer', (
    WidgetTester tester,
  ) async {
    // The Sky tab's bare card. A null [AnimalCard.footerLabel] must leave the
    // label exactly as it was rather than trailing a stray comma or the word
    // "null" — the shape a naive interpolation produces.
    final SemanticsHandle handle = tester.ensureSemantics();
    await mount(tester, closeRock);

    final String label = tester.getSemantics(find.byType(AnimalCard)).label;
    expect(label, endsWith(spokenFlyby(flybyTag(closeRock))));

    handle.dispose();
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

  group('🧸 Little Kids mode draws the row bigger', () {
    // **The card is the shared *row* the bigger-controls affordance names**, and
    // it is here for a different reason from the buttons: its [InkWell] already
    // covers the whole card, so it was never near the 48dp floor and gains
    // nothing from a bigger hit region. What it gains is a bigger, less crowded
    // thing to look at and land on in a list — padding and the avatar orb.
    //
    // These are written as *inequalities against the same card at scale 1*
    // rather than against measured pixel values, so they keep asking the right
    // question if the prototype's 12dp padding or 44dp orb are ever re-ported.

    testWidgets('the row grows taller', (WidgetTester tester) async {
      await mount(tester, closeRock);
      final double standard = tester.getSize(find.byType(AnimalCard)).height;

      await mount(tester, closeRock, controlScale: 2);

      expect(
        tester.getSize(find.byType(AnimalCard)).height,
        greaterThan(standard),
      );
    });

    testWidgets('the avatar orb grows with it', (WidgetTester tester) async {
      // Asserted separately from the row height because they scale through
      // different code — the row through its [Padding], the orb through its own
      // [Container] — so a change that dropped one would otherwise hide behind
      // the other still growing.
      Finder orb() => find.ancestor(
        of: find.text(critter(closeRock).animal.emoji),
        matching: find.byType(Container),
      );

      await mount(tester, closeRock);
      final Size standard = tester.getSize(orb().first);

      await mount(tester, closeRock, controlScale: 2);

      expect(
        tester.getSize(orb().first),
        Size(standard.width * 2, standard.height * 2),
      );
    });

    testWidgets('and the name is left to the OS text setting', (
      WidgetTester tester,
    ) async {
      // [ControlScale]'s orthogonality rule at this call site: type size belongs
      // to `MediaQuery.textScaler`, so a card that multiplied `fontSize` here
      // would compound the two settings for the family most likely to have both
      // turned up.
      // **Height, not the whole [Size].** The name is a single ellipsised line,
      // so its height is font-driven and its *width* is not: bigger padding and
      // a bigger orb leave the `Expanded` less room, which narrows the text box
      // without touching the type. Asserting the full size failed on that, which
      // would have been a real-looking regression report for correct behaviour.
      double nameHeight() =>
          tester.getSize(find.text(critter(closeRock).name)).height;

      await mount(tester, closeRock);
      final double standard = nameHeight();

      await mount(tester, closeRock, controlScale: 2);

      expect(nameHeight(), standard);
    });
  });
}

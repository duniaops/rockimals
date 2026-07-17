import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/core/animals/animal_system.dart';
import 'package:rockimals/core/theme/palette.dart';
import 'package:rockimals/data/fallback_asteroids.dart';
import 'package:rockimals/data/models/asteroid.dart';
import 'package:rockimals/features/detail/detail_screen.dart';

/// The animal detail screen header and stat tiles (`openDetail`,
/// `index.html:554-619`) — the screen **Meet** on the radar HUD opens.
///
/// This item builds only the header (big avatar, `"{Name} the {Species}"`, the
/// species line, the flyby badge) and the four kid stat tiles; the comparisons,
/// the actions, and the grown-up facts are later items. So the tests drive three
/// animals of clearly different sizes through the screen and read what renders —
/// the Done-when's "opening three animals of different sizes shows the right
/// avatar, species, and stats". Field expectations run through the AnimalSystem's
/// own formatters (as `animal_card_test` does), pinning the screen's *wiring* —
/// which field feeds which tile — while the maths stays in `animal_system_test`;
/// a few literals are pinned as a human-readable record of a real render.
void main() {
  // Three sizes, three species, both badges, and How wide as a range each time:
  //  * 2020 SW — 9 m Rabbit, 0.07 Moons: tiny and a close flyby (`< 1`).
  //  * 2018 LF16 — 213 m Bear, 40 Moons: mid-sized and just passing.
  //  * 433 Eros — 16 800 m Whale, 52 Moons: the giant of the sample sky.
  final Asteroid rabbit =
      kFallbackAsteroids.firstWhere((Asteroid a) => a.name == '2020 SW');
  final Asteroid bear =
      kFallbackAsteroids.firstWhere((Asteroid a) => a.name == '2018 LF16');
  final Asteroid whale =
      kFallbackAsteroids.firstWhere((Asteroid a) => a.name == '433 Eros');

  Future<void> pump(WidgetTester tester, Asteroid rock) {
    return tester.pumpWidget(
      MaterialApp(home: DetailScreen(asteroid: rock)),
    );
  }

  testWidgets('shows the avatar, name, species line, badge and tiles', (
    tester,
  ) async {
    await pump(tester, rabbit);
    final Critter c = critter(rabbit);

    // Header: the big avatar emoji (only the avatar shows it — the title is the
    // name without the glyph) and the "{Name} the {Species}" title.
    expect(c.animal.emoji, '🐰');
    expect(find.text(c.animal.emoji), findsOneWidget);
    expect(find.text(c.name), findsOneWidget); // "{first} the Rabbit"

    // "a Rabbit-sized space rock" — a rich line with the species picked out, so
    // it is matched through the RichText's plain text.
    expect(
      find.textContaining('a ${c.animal.species}-sized space rock',
          findRichText: true),
      findsOneWidget,
    );

    // The flyby badge (0.07 Moons → a close flyby).
    expect(flybyTag(rabbit), FlybyTag.closeFlyby);
    expect(find.text('👋 close flyby'), findsOneWidget);

    // The four tiles — keys (displayed uppercase, `text-transform`) and values.
    expect(find.text('HOW WIDE'), findsOneWidget);
    expect(find.text('HOW FAST'), findsOneWidget);
    expect(find.text('HOW CLOSE'), findsOneWidget);
    expect(find.text('POWER ⭐'), findsOneWidget);
    expect(find.text('4–9 m'), findsOneWidget); // diaMin–diaMax, decision 11
    expect(find.text('8.1 km/s'), findsOneWidget); // toFixed(1)
    expect(find.text('7% to Moon'), findsOneWidget); // distLabel(0.07)
    expect(find.text('${powerStars(rabbit)}'), findsOneWidget);
  });

  testWidgets('a mid-sized, just-passing animal renders its own stats', (
    tester,
  ) async {
    await pump(tester, bear);
    final Critter c = critter(bear);

    expect(c.animal.emoji, '🐻');
    expect(find.text(c.animal.emoji), findsOneWidget);
    expect(
      find.textContaining('a Bear-sized space rock', findRichText: true),
      findsOneWidget,
    );

    // 40 Moons, unflagged → just passing (the green badge).
    expect(flybyTag(bear), FlybyTag.justPassing);
    expect(find.text('just passing'), findsOneWidget);
    expect(find.text('👋 close flyby'), findsNothing);

    expect(find.text('95–213 m'), findsOneWidget);
    expect(find.text('14.0 km/s'), findsOneWidget);
    expect(find.text('40× Moon'), findsOneWidget); // distLabel(40)
  });

  testWidgets('the giant Whale renders its full diameter range', (tester) async {
    await pump(tester, whale);
    final Critter c = critter(whale);

    expect(c.animal.emoji, '🐋');
    expect(find.text(c.animal.emoji), findsOneWidget);
    expect(
      find.textContaining('a Whale-sized space rock', findRichText: true),
      findsOneWidget,
    );

    // How wide is a range, not a scalar — the one place `diaMin` is read
    // (decision 11). 8600–16800, not "16800 m".
    expect(find.text('8600–16800 m'), findsOneWidget);
    expect(find.text('5.6 km/s'), findsOneWidget);
    expect(find.text('52× Moon'), findsOneWidget);
  });

  testWidgets('the Power tile is tinted accent2, the others are white', (
    tester,
  ) async {
    await pump(tester, rabbit);

    final Text power = tester.widget<Text>(find.text('${powerStars(rabbit)}'));
    expect(power.style?.color, Palette.accent2);

    // A non-power value stays white (`.tile .v{color:#fff}`).
    final Text wide = tester.widget<Text>(find.text('4–9 m'));
    expect(wide.style?.color, Colors.white);
  });

  testWidgets('the tiles speak their natural-case label and value', (
    tester,
  ) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await pump(tester, rabbit);

    // `text-transform:uppercase` is display-only: the reader hears "How wide",
    // not "H-O-W", and the value with it — one phrase per tile.
    expect(find.bySemanticsLabel('How wide, 4–9 m'), findsOneWidget);
    expect(find.bySemanticsLabel('How close, 7% to Moon'), findsOneWidget);

    handle.dispose();
  });

  testWidgets('the ‹ Back pill pops the detail route', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => DetailScreen(asteroid: rabbit),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(DetailScreen), findsOneWidget);

    await tester.tap(find.text('‹ Back'));
    await tester.pumpAndSettle();
    expect(find.byType(DetailScreen), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });
}

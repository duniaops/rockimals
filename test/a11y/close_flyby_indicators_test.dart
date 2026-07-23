import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/core/animals/animal_system.dart';
import 'package:rockimals/data/models/asteroid.dart';
import 'package:rockimals/data/models/asteroid_feed.dart';
import 'package:rockimals/features/animals/widgets/animal_card.dart';
import 'package:rockimals/features/animals/widgets/flyby_badge.dart';
import 'package:rockimals/features/data/providers.dart';
import 'package:rockimals/features/detail/detail_screen.dart';
import 'package:rockimals/features/settings/little_kids_mode.dart';
import 'package:rockimals/features/shell/app_shell.dart';

import '../support/memory_store.dart';
import '../support/stub_settings.dart';

/// **Close-flyby state is never carried by colour alone** —
/// `specs/06-title-polish-safety.md:23` ("Never rely on colour alone — pair the
/// close-flyby colour with icon + text") and its acceptance criterion at `:44`.
///
/// The guardrail exists twice over here. Once for the roughly 1-in-12 boys who
/// will not reliably separate the amber "close flyby" pill from the green "just
/// passing" one — the badge's two fills are a warm amber and a green, which is
/// the exact axis red-green colour blindness collapses. And once for every child
/// who simply has not been told what amber *means*: a colour is only an
/// indicator to someone who has already learnt the legend, and there is no
/// legend in this app.
///
/// **The shape of the assertion is "strip the colour, can you still tell?"** So
/// each test reads the *text* on a close-flyby surface and on a just-passing one
/// and requires them to differ, rather than checking a glyph is present
/// somewhere on screen — which a surface could satisfy while still encoding the
/// actual state in a fill nobody can see.
void main() {
  group('the badge says which state it is in, in words and a glyph', () {
    testWidgets('a close flyby carries the wave and the words', (tester) async {
      await tester.pumpWidget(
        _wrap(const FlybyBadge(tag: FlybyTag.closeFlyby)),
      );

      expect(find.textContaining(kCloseFlybyGlyph), findsOneWidget);
      expect(find.textContaining('close flyby'), findsOneWidget);
    });

    testWidgets('and a rock just passing says so, differently', (tester) async {
      // The half that matters: two states that read the same in greyscale are
      // not two states. `just passing` shares no word with `close flyby`, so a
      // child who cannot see the fill still gets the answer.
      await tester.pumpWidget(
        _wrap(const FlybyBadge(tag: FlybyTag.justPassing)),
      );

      expect(find.textContaining('just passing'), findsOneWidget);
      expect(find.textContaining(kCloseFlybyGlyph), findsNothing);
      expect(find.textContaining('close flyby'), findsNothing);
    });

    testWidgets('the two states share no visible text', (tester) async {
      await tester.pumpWidget(
        _wrap(const FlybyBadge(tag: FlybyTag.closeFlyby)),
      );
      final String close = _visibleText(tester);

      await tester.pumpWidget(
        _wrap(const FlybyBadge(tag: FlybyTag.justPassing)),
      );
      final String passing = _visibleText(tester);

      expect(close, isNot(passing));
      expect(close, isNot(isEmpty));
      expect(passing, isNot(isEmpty));
    });
  });

  testWidgets('an animal card marks a close flyby in text', (tester) async {
    await tester.pumpWidget(_wrap(AnimalCard(asteroid: _close, onTap: () {})));
    final String close = _visibleText(tester);

    await tester.pumpWidget(_wrap(AnimalCard(asteroid: _far, onTap: () {})));
    final String passing = _visibleText(tester);

    expect(close, contains(kCloseFlybyGlyph));
    expect(close, contains('close flyby'));
    expect(passing, isNot(contains('close flyby')));
  });

  testWidgets('the detail screen marks a close flyby in text', (tester) async {
    await tester.pumpWidget(_app(const DetailScreen(asteroid: _close)));
    await tester.pump(const Duration(milliseconds: 100));

    expect(_visibleText(tester), contains('close flyby'));
    expect(_visibleText(tester), contains(kCloseFlybyGlyph));
  });

  testWidgets('the radar home strip counts close flybys in words', (
    tester,
  ) async {
    // The one aggregate indicator, and the one that tints a *border* red
    // (`_homeChipWarnBorder`) — so it is exactly the shape this guardrail is
    // about: the colour is the decoration, and the count is the message.
    await tester.pumpWidget(_app(const AppShell()));
    await tester.pump(const Duration(milliseconds: 100));

    final String shown = _visibleText(tester);
    expect(shown, contains(kCloseFlybyGlyph));
    expect(shown.toLowerCase(), contains('close flyb'));
  });

  test('the glyph has one home, so every surface can be found', () {
    // `kCloseFlybyGlyph` is what makes "which surfaces mark a close flyby" a
    // grep rather than a memory, and `FlybyTag`'s own label is built from it —
    // so a change to the icon reaches the badge, the card, the detail screen and
    // the radar's token together, or fails loudly here.
    expect(FlybyTag.closeFlyby.label, startsWith(kCloseFlybyGlyph));
    expect(FlybyTag.justPassing.label, isNot(contains(kCloseFlybyGlyph)));
  });
}

/// Every string actually painted in the current tree, concatenated.
///
/// Read off the render tree rather than by collecting [Text] widgets, so it sees
/// what is on the glass — including text a widget builds internally — and
/// includes nothing that is merely mounted offstage.
String _visibleText(WidgetTester tester) {
  final StringBuffer found = StringBuffer();
  void visit(RenderObject node) {
    if (node is RenderParagraph) found.write('${node.text.toPlainText()}\n');
    node.visitChildren(visit);
  }

  visit(tester.binding.renderViews.first);
  return found.toString();
}

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

Widget _app(Widget home) => ProviderScope(
  overrides: [
    // 🧸 Little Kids mode, which the radar's Play CTA resolves for its
    // game count — stubbed off like every store-backed read beside it.
    littleKidsModeProvider.overrideWith(StubLittleKids.new),
    asteroidFeedProvider.overrideWith((Ref ref) => AsteroidFeed.fallback()),
    dayStreakProvider.overrideWithValue(0),
    storeProvider.overrideWithValue(MemoryStore()),
  ],
  child: MaterialApp(home: home),
);

/// Inside the Moon's distance, so [flybyTag] calls it a close flyby on distance
/// alone — without leaning on NASA's `hazardous` flag, which the other half of
/// the rule covers.
const Asteroid _close = Asteroid(
  name: '2004 BL86',
  diaMin: 250,
  diaMax: 560,
  velKps: 15.6,
  missKm: 300000,
  missLunar: 0.4,
  hazardous: false,
  mag: 19.1,
  jpl: 'https://ssd.jpl.nasa.gov/tools/sbdb_lookup.html',
  date: '2026-07-18',
);

const Asteroid _far = Asteroid(
  name: '2011 EW',
  diaMin: 40,
  diaMax: 90,
  velKps: 8.2,
  missKm: 9000000,
  missLunar: 23.4,
  hazardous: false,
  mag: 22.4,
  jpl: 'https://ssd.jpl.nasa.gov/tools/sbdb_lookup.html',
  date: '2026-07-18',
);

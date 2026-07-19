import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/core/a11y/control_scale.dart';
import 'package:rockimals/core/a11y/tap_target.dart';
import 'package:rockimals/core/audio/sound_engine.dart';
import 'package:rockimals/data/models/asteroid.dart';
import 'package:rockimals/data/models/asteroid_feed.dart';
import 'package:rockimals/features/data/providers.dart';
import 'package:rockimals/features/games/challenge_game.dart';
import 'package:rockimals/features/radar/radar_geometry.dart';
import 'package:rockimals/features/radar/radar_painter.dart';
import 'package:rockimals/features/shell/app_shell.dart';

import '../support/memory_store.dart';
import '../support/recording_sound_engine.dart';

/// **Three layouts that only fit because nobody had measured them on a phone.**
///
/// Both tap-target audits used to mount on the test binding's default 800×600 —
/// a landscape desktop window no child holds — and both now mount at 390×800.
/// That change alone turned eleven arms red, on three unrelated overflows, none
/// of which was a tap-target violation: at a phone's width the audits found
/// zero targets under 48dp, and three [RenderFlex]es that could not fit their
/// contents at 1.5× text.
///
/// The audits catch all three today, because an overflow throws and a throw
/// fails the mount. But what they assert is only *"nothing threw"*, which does
/// not survive a refactor: a future change could satisfy them by clipping, by
/// ellipsising, or by shrinking the text — each of which "fixes" the overflow
/// by taking away the thing the larger text setting was turned on to provide.
/// This file pins the three properties by name, so the next person changing any
/// of them is told which promise they broke rather than that a screen threw.
///
/// **Why 1.0× *and* 1.5× on every one of them.** The 1.0× arm is not
/// ceremony — it is the assertion that the fix is invisible at the default text
/// size. All three defects were fixed by letting a box grow, and a box that
/// grows when it did not need to would be a visual regression against the
/// prototype on every phone in the world. So each test says both halves:
/// unchanged at 1.0×, and bigger rather than broken at 1.5×.
///
/// The numbers below are the layout the test font produces at exactly 390×800.
/// They are asserted as relationships wherever a relationship is the real
/// claim, and exactly only where the exact number *is* the claim — the nav
/// bar's 70dp is the prototype's, and drifting off it would be the regression.
void main() {
  group("a phone's width, at both text sizes", () {
    testWidgets('the nav bar keeps its 70dp and grows rather than clipping', (
      tester,
    ) async {
      // The bar was a fixed `SizedBox(height: 70)` — `index.html:12`'s height,
      // correct in a 390×844 frame at the browser's default font. At 390dp a
      // tab gets 97.5dp, which is narrow enough for a 1.5× label to wrap to two
      // lines, and the fixed box then overflowed by 9px on every tab in every
      // state of the app. At 800dp a tab gets 200dp, the label stays on one
      // line, and that is the whole reason this never failed.
      await _pump(tester, const AppShell(), scale: 1);
      for (final String tab in _tabs) {
        expect(
          _navButton(tester, tab).height,
          70,
          reason:
              'at the default text size the nav bar must still be exactly the '
              "prototype's 70dp — the fix is a floor, not a new height",
        );
      }

      await _pump(tester, const AppShell(), scale: 1.5);
      for (final String tab in _tabs) {
        expect(
          _navButton(tester, tab).height,
          greaterThan(70),
          reason:
              'at 1.5× text the label wraps, so the bar has to grow with it; '
              'if this is back at 70 the label is being clipped or truncated',
        );
      }
    });

    testWidgets('every nav button still fills the bar it grew', (tester) async {
      // The reason the bar is an [IntrinsicHeight] with `stretch` rather than
      // four buttons each sizing to their own glyphs. Letting the buttons
      // shrink-wrap would fix the overflow just as well and quietly cut the
      // hittable region from the bar's height to the text's — a tap-target
      // regression hiding inside a tap-target fix, and one the ≥48dp audit
      // would not catch because ~51dp of glyphs still clears 48.
      for (final double scale in <double>[1.0, 1.5]) {
        await _pump(tester, const AppShell(), scale: scale);
        final Iterable<double> heights = _tabs.map(
          (String tab) => _navButton(tester, tab).height,
        );
        expect(
          heights.toSet(),
          hasLength(1),
          reason:
              'all four nav buttons must be the same height as each other and '
              'as the bar, at $scale× text — found $heights',
        );
      }
    });

    testWidgets("the radar HUD's two actions wrap instead of overflowing", (
      tester,
    ) async {
      // `.ra` is `display:flex;gap:8px` (`index.html:183`) with nothing to
      // shrink the buttons, and it was ported as a [Row]. At 1.5× the two
      // labels want 428dp of the card's 342, and where CSS spills quietly a
      // [Row] throws.
      await _pump(tester, const AppShell(), scale: 1);
      await _selectAnimal(tester);
      final double oneRun = _hudActions(tester).height;
      expect(
        oneRun,
        kMinTapTarget,
        reason:
            'at the default text size both pills fit side by side, so the '
            'wrap must lay out in a single run exactly as the Row did — one '
            "button's height and no more",
      );

      await _pump(tester, const AppShell(), scale: 1.5);
      await _selectAnimal(tester);
      expect(
        _hudActions(tester).height,
        greaterThan(oneRun),
        reason:
            'at 1.5× text the pills no longer fit on one line, so Follow must '
            'drop to a second run — the alternative that also stops the '
            'overflow is ellipsising "✓ Following", which is exactly the word '
            'the button exists to say',
      );
    });

    testWidgets("a challenge card's height follows its contents, not its width", (
      tester,
    ) async {
      // `.ch-grid` is `grid-template-columns:1fr 1fr;gap:10px` with no
      // `aspect-ratio` and no `grid-auto-rows` (`index.html:130`), so a browser
      // sizes each row to its tallest card. The port pinned the height to the
      // *width* with `childAspectRatio: 0.82`, a number with no source in the
      // prototype — and since width does not move when the system font does,
      // the contents grew out of the box at 1.5× text.
      await _pump(tester, const ChallengeGame(), scale: 1, feed: _flatSky);
      final Size small = _challengeCard(tester);

      await _pump(tester, const ChallengeGame(), scale: 1.5, feed: _flatSky);
      final Size large = _challengeCard(tester);

      expect(
        large.width,
        small.width,
        reason: 'text scale must not change how wide the two columns are',
      );
      expect(
        large.height,
        greaterThan(small.height),
        reason:
            'the row has to get taller when its text does; if these are equal '
            'the height is pinned to the width again and the cards are '
            'overflowing or clipping at large text sizes',
      );
    });
  });
}

const List<String> _tabs = <String>['Radar', 'Sky', 'Watchlist', 'Profile'];

/// Exactly four rocks that all render the **same stat line**, so a challenge
/// card is the same height whichever way the deal falls.
///
/// This is the answer to `_dealCards`' unseeded `shuffle`. The card's height is
/// set by its stat text — `sizeLabel`, `distLabel` and the rounded speed — and
/// the two pumps this test compares are two separate deals, so with the bundled
/// sky it would be measuring a 1.0× card against a *different* 1.5× card and
/// racing on how many lines each one's numbers happened to wrap to. Handing the
/// game four rocks with identical size, distance and speed removes the variable
/// rather than seeding around it; the names still differ (so these are four
/// distinct cards), and the name is `maxLines: 1` and ellipsised, so it cannot
/// change a height either way.
///
/// Four is also the whole round (`_roundSize`), so the pool is dealt entire and
/// no rock can be left out.
final AsteroidFeed _flatSky = () {
  final List<Asteroid> rocks = <Asteroid>[
    for (final String name in <String>[
      '2024 AA1',
      '2024 BB2',
      '2024 CC3',
      '2024 DD4',
    ])
      Asteroid(
        name: name,
        diaMin: 90,
        diaMax: 130,
        velKps: 15.6,
        missKm: 1200000,
        missLunar: 3.1,
        hazardous: false,
        mag: 19.1,
        jpl: 'https://ssd.jpl.nasa.gov/tools/sbdb_lookup.html',
        date: '2026-07-18',
      ),
  ];
  return AsteroidFeed(
    asteroids: rocks,
    todayList: rocks,
    feedRange: 'sample data',
    provenance: FeedProvenance.sample,
  );
}();

/// The hittable region of one nav tab — the [InkWell], which is stretched to
/// the bar's full inner height and so measures the bar as well as the button.
Size _navButton(WidgetTester tester, String tab) => tester.getSize(
  find.ancestor(of: find.text(tab), matching: find.byType(InkWell)).first,
);

/// The HUD card's action row. Found through the Meet button rather than by
/// index, because the radar screen builds more than one [Wrap].
Size _hudActions(WidgetTester tester) => tester.getSize(
  find
      .ancestor(of: find.textContaining('Meet '), matching: find.byType(Wrap))
      .first,
);

/// One challenge card, found through the stat line every card renders rather
/// than through the widget the grid happens to be built out of.
///
/// Deliberately not `find.byType(IntrinsicHeight)`, which was the first draft:
/// naming the mechanism makes the test pass or fail on *how* the grid is
/// written, so reinstating the old fixed-ratio `GridView` failed it with
/// "index out of range" instead of with the claim it is here to make. Measuring
/// the card itself means any grid that sizes its rows to their contents passes,
/// and any grid that pins them to the width fails on the height comparison.
Size _challengeCard(WidgetTester tester) => tester.getSize(
  find
      .ancestor(
        of: find.textContaining('km/s').first,
        matching: find.byType(InkWell),
      )
      .first,
);

/// Taps the first animal on the live radar and lets its card finish sliding up.
///
/// Driven through the painter's own geometry, the way
/// `tap_target_audit_test.dart` does it, because the HUD card only exists once
/// a real tap has selected something.
Future<void> _selectAnimal(WidgetTester tester) async {
  final Finder canvas = find.byWidgetPredicate(
    (Widget w) => w is CustomPaint && w.painter is RadarPainter,
  );
  final RadarPainter painter =
      tester.widget<CustomPaint>(canvas).painter! as RadarPainter;

  await tester.tapAt(
    painter.orbits.positionOf(
      painter.orbits.orbits.first,
      geometry: RadarGeometry(
        size: tester.getSize(canvas),
        maxLd: painter.maxLd,
      ),
      zoom: painter.zoom,
      viewRot: painter.viewRot,
    ),
  );
  await tester.pump(); // build the card at t = 0
  await tester.pump(const Duration(milliseconds: 250)); // finish the slide

  expect(
    find.textContaining('Meet '),
    findsOneWidget,
    reason: 'the HUD card did not open, so nothing was measured',
  );
}

/// Mounts [home] on a **phone**, with the feed, streak, store and audio all
/// stood in front of.
///
/// 390×800 is the size the rest of the suite uses for a phone
/// (`one_off_controls_test.dart:179`), and is the point of this file: every
/// assertion here passes on the 800×600 default, which is how all three defects
/// reached `main` with a green audit.
Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  required double scale,
  AsteroidFeed? feed,
}) async {
  tester.view
    ..physicalSize = const Size(390, 800)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // Resolved, not pending: `AppShell` reads `requireValue`, so a feed
        // still loading would throw on the first build.
        asteroidFeedProvider.overrideWith(
          (Ref ref) => feed ?? AsteroidFeed.fallback(),
        ),
        dayStreakProvider.overrideWithValue(0),
        storeProvider.overrideWithValue(MemoryStore()),
        soundEngineProvider.overrideWithValue(RecordingSoundEngine()),
      ],
      child: MaterialApp(
        builder: (BuildContext context, Widget? child) => ControlScale(
          // Held at 1 so the text scaler is the only variable: 🧸 Little Kids
          // mode's multiplier is `tap_target_audit_test.dart`'s question.
          scale: 1,
          child: MediaQuery.withClampedTextScaling(
            minScaleFactor: scale,
            maxScaleFactor: scale,
            child: child!,
          ),
        ),
        home: home,
      ),
    ),
  );
  // Pumped rather than settled: the radar's ticker never stops, so a settle
  // would time out.
  await tester.pump(const Duration(milliseconds: 100));
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/core/theme/palette.dart';
import 'package:rockimals/data/models/asteroid.dart';
import 'package:rockimals/data/models/asteroid_feed.dart';
import 'package:rockimals/features/data/providers.dart';
import 'package:rockimals/features/radar/radar_view.dart';
import 'package:rockimals/features/settings/calm_motion.dart';
import 'package:rockimals/features/settings/little_kids_mode.dart';

import '../../support/stub_settings.dart';

/// The home overlay: the wordmark, the streak flame, and the `todayList`-based
/// stat strip laid over the radar. `radar_view_test.dart` owns the field and
/// the chips underneath it; this suite owns what the overlay says about the
/// loaded sky.
void main() {
  testWidgets('shows the ROCKIMALS wordmark, not the prototype\'s brand', (
    tester,
  ) async {
    // Plan decision 5: the wordmark is ROCKIMALS. `ASTEROID WATCH` was the
    // prototype's, and it must not survive the port.
    await _mount(tester, _sky(<double>[3]));

    expect(find.text('ROCKIMALS'), findsOneWidget);
    expect(find.textContaining('ASTEROID WATCH'), findsNothing);
  });

  testWidgets('the flame shows the persisted day streak', (tester) async {
    await _mount(tester, _sky(<double>[3]), streak: 7);
    expect(find.text('🔥 7'), findsOneWidget);
  });

  group('the visiting chip', () {
    testWidgets('says "today" for a live window ending today', (tester) async {
      await _mount(tester, _sky(<double>[3, 5]));
      expect(find.textContaining('2 visiting today'), findsOneWidget);
    });

    testWidgets('says "recently" for an earlier cached window', (tester) async {
      // The case a single bool could not name (plan decision on the strip copy):
      // real NASA rocks from a day or two ago must not claim "today".
      await _mount(
        tester,
        _sky(<double>[3, 5, 8], provenance: FeedProvenance.earlier),
      );
      expect(find.textContaining('3 visiting recently'), findsOneWidget);
      expect(find.textContaining('visiting today'), findsNothing);
    });

    testWidgets('says "(sample)" for the bundled sample sky', (tester) async {
      await _mount(tester, AsteroidFeed.fallback());
      // The fallback seeds seven in `todayList` (plan decision 10).
      expect(find.textContaining('7 visiting (sample)'), findsOneWidget);
    });
  });

  testWidgets('the closest chip reads the nearest approach in todayList', (
    tester,
  ) async {
    // `[...todayList].sort(...)[0]` (`index.html:452`) — 0.5 is the nearest, and
    // `distLabel(0.5)` is "50% to Moon".
    await _mount(tester, _sky(<double>[3, 0.5, 12]));
    expect(find.textContaining('closest 50% to Moon'), findsOneWidget);
  });

  group('the close-flyby chip', () {
    testWidgets('counts flybys and pluralises, with the warn treatment', (
      tester,
    ) async {
      // One rock at 0.5 Moon-distances is a close flyby (`< 1`); the other two
      // are just passing. So the count is 1, singular, and warned.
      await _mount(tester, _sky(<double>[0.5, 3, 12]));

      expect(find.textContaining('1 close flyby'), findsOneWidget);
      expect(_flybyChipBorder(tester), Palette.bad.withValues(alpha: 0.4));
    });

    testWidgets('pluralises when there is more than one', (tester) async {
      await _mount(tester, _sky(<double>[0.5, 0.9, 12]));
      expect(find.textContaining('2 close flybys'), findsOneWidget);
    });

    testWidgets('drops the warn treatment when there are none', (tester) async {
      // All three are past a Moon-distance and none hazardous, so zero flybys —
      // the plain `--line` border, not the soft-red warn one.
      await _mount(tester, _sky(<double>[3, 5, 12]));

      expect(find.textContaining('0 close flybys'), findsOneWidget);
      expect(_flybyChipBorder(tester), Palette.line);
    });
  });

  testWidgets('the hint says "tap an animal", never "tap a rock"', (
    tester,
  ) async {
    // Softened from the prototype's `index.html:287` — the rocks are animals.
    await _mount(tester, _sky(<double>[3]));

    expect(find.textContaining('tap an animal'), findsOneWidget);
    expect(find.textContaining('tap a rock'), findsNothing);
  });
}

/// The border colour of the close-flyby strip chip — the warn tell. Walks up
/// from the chip's `Text.rich` (whose plain text alone carries the lowercase
/// "close flyb", unlike the capitalised toggle chip) to its enclosing container.
Color _flybyChipBorder(WidgetTester tester) {
  final Finder chipText = find.byWidgetPredicate(
    (Widget w) => w is RichText && w.text.toPlainText().contains('close flyb'),
  );
  final Container chip = tester.widget<Container>(
    find.ancestor(of: chipText, matching: find.byType(Container)).first,
  );
  final BoxDecoration decoration = chip.decoration! as BoxDecoration;
  return (decoration.border! as Border).top.color;
}

Future<void> _mount(
  WidgetTester tester,
  AsteroidFeed feed, {
  int streak = 0,
}) async {
  tester.view
    ..physicalSize = const Size(390, 700)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // 🧸 Little Kids mode, which the radar's Play CTA resolves for its
        // game count — stubbed off like every store-backed read beside it.
        littleKidsModeProvider.overrideWith(StubLittleKids.new),
        asteroidFeedProvider.overrideWith((Ref ref) => feed),
        dayStreakProvider.overrideWithValue(streak),
        // The radar field resolves 🐢 Calm motion each build, and the real
        // notifier reads the store. Held at "never chose", which resolves
        // against a `MediaQuery` that is not asking — so the sky drifts at full
        // speed here exactly as it did before the setting existed.
        reducedMotionProvider.overrideWith(StubCalmMotion.new),
      ],
      child: const MaterialApp(home: RadarView()),
    ),
  );
  await tester.pump();
}

/// A live sky whose `asteroids` and `todayList` are the same rocks — the strip
/// reads `todayList`, so that is what these tests set.
AsteroidFeed _sky(
  List<double> missLunar, {
  FeedProvenance provenance = FeedProvenance.today,
}) {
  final List<Asteroid> rocks = _rocks(missLunar);
  return AsteroidFeed(
    asteroids: rocks,
    todayList: rocks,
    feedRange: '2026-07-15 → 2026-07-17',
    provenance: provenance,
  );
}

/// Only `missLunar` and `hazardous` reach the strip's counts; the rest is
/// plausible filler.
List<Asteroid> _rocks(List<double> missLunar) => <Asteroid>[
  for (final double ld in missLunar)
    Asteroid(
      name: '2026 LD$ld',
      diaMax: 100,
      diaMin: 50,
      hazardous: false,
      missLunar: ld,
      missKm: ld * 384400,
      velKps: 12,
      mag: 22,
      jpl: 'https://ssd.jpl.nasa.gov/tools/sbdb_lookup.html',
      date: '2026-07-17',
    ),
];

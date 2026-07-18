import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/core/animals/animal_system.dart';
import 'package:rockimals/data/models/asteroid.dart';
import 'package:rockimals/data/models/asteroid_feed.dart';
import 'package:rockimals/features/data/providers.dart';
import 'package:rockimals/features/detail/detail_screen.dart';
import 'package:rockimals/features/radar/radar_geometry.dart';
import 'package:rockimals/features/radar/radar_painter.dart';
import 'package:rockimals/features/radar/radar_view.dart';
import 'package:rockimals/features/settings/calm_motion.dart';

import '../../support/stub_settings.dart';

/// The selected-animal HUD card — the panel that slides up when a child taps an
/// animal (`radarSelect`, `index.html:715-726`).
///
/// **Driven through the real radar, over an in-memory follow set.** The card is
/// private, so the only honest way to test "tapping any animal opens the card"
/// is to tap an animal on the actual field and read what appears — which makes
/// the tap, the selection, and the render all the code a child hits. Follow is
/// overridden with an in-memory notifier here rather than a real Hive box for a
/// concrete reason: a `Box.put` triggered inside the widget tester never settles
/// under its fake clock and hangs the test. So this suite owns the *wiring* — the
/// button reaches the shared provider and the label tracks its state — and
/// `providers_test.dart` owns that a toggle actually reaches the store the app
/// reopens from, against a real box in plain async where the write completes.
void main() {
  testWidgets('a tap opens the card with the name, badge, stats and Meet', (
    tester,
  ) async {
    await _mount(tester);

    // No animal tapped yet: no card, and the hint is showing.
    expect(find.text(_name), findsNothing);
    expect(find.textContaining('tap an animal'), findsOneWidget);

    await _tapAnimal(tester);

    // The card names the animal, badges its flyby, and carries the five-field
    // stat line — read through the AnimalSystem's own formatters so this pins
    // the card's *formatting* (order, glue, which function) and not the maths
    // that animal_system_test owns. For 2026 AB (100 m, 2.0 Moons, 12 km/s)
    // that line reads: "plane-sized · 100 m wide · comes 2.0× Moon · zooms
    // 12.0 km/s · power ⭐ 83".
    expect(find.text(_name), findsOneWidget);
    expect(find.text(flybyTag(_rock).label), findsOneWidget); // "just passing"
    expect(find.text(_statLine), findsOneWidget);
    expect(find.text('Meet ${critter(_rock).first}'), findsOneWidget);
    expect(find.text('⭐ Follow'), findsOneWidget);

    // The card takes the hint's strip, so the hint steps aside while it is up
    // (`index.html:719`).
    expect(find.textContaining('tap an animal'), findsNothing);
  });

  testWidgets('Follow toggles the button through the shared provider', (
    tester,
  ) async {
    await _mount(tester);
    await _tapAnimal(tester);
    expect(find.text('⭐ Follow'), findsOneWidget);

    // Tapping Follow flips the label — the card read the shared set, wrote
    // through `followsProvider.notifier`, and rebuilt on the new state.
    await tester.tap(find.text('⭐ Follow'));
    await tester.pump();
    expect(find.text('✓ Following'), findsOneWidget);
    expect(find.text('⭐ Follow'), findsNothing);

    // And it is a toggle: a second tap unfollows.
    await tester.tap(find.text('✓ Following'));
    await tester.pump();
    expect(find.text('⭐ Follow'), findsOneWidget);
  });

  testWidgets('the card opens on the animal\'s current follow state', (
    tester,
  ) async {
    // A follow made anywhere is the same follow the card shows: seeded from the
    // set, the card opens on "✓ Following" for an animal already in the
    // watchlist. This is what lets task 03's detail screen and the My Animals
    // tab agree with the card without any of them owning the truth.
    await _mount(tester, followed: <String>{_rock.name});
    await _tapAnimal(tester);

    expect(find.text('✓ Following'), findsOneWidget);
    expect(find.text('⭐ Follow'), findsNothing);
  });

  testWidgets('Meet opens the detail screen for that animal', (tester) async {
    await _mount(tester);
    await _tapAnimal(tester);

    await tester.tap(find.text('Meet ${critter(_rock).first}'));
    await tester.pump(); // start the route transition
    await tester.pump(const Duration(milliseconds: 400)); // and finish it

    // The real detail screen (`DetailScreen`, task 03) for the tapped animal.
    // "How wide" and its `diaMin–diaMax` range are unique to the detail — the
    // card underneath (kept in the tree by the maintained route) never shows
    // them — so they confirm the child landed on the detail, not still the card.
    // 2026 AB is 50–100 m.
    expect(find.byType(DetailScreen), findsOneWidget);
    expect(
      find.text('${_rock.diaMin.round()}–${_rock.diaMax.round()} m'),
      findsOneWidget,
    );
  });

  testWidgets('a tap on empty space closes the card and brings the hint back', (
    tester,
  ) async {
    await _mount(tester);
    await _tapAnimal(tester);
    expect(find.text(_name), findsOneWidget, reason: 'the premise');

    // Earth's own centre: the inner floor means no animal can sit here, so this
    // deselects (`index.html:712`).
    final Size size = tester.getSize(_radarCanvas());
    await tester.tapAt(Offset(size.width / 2, size.height * 0.46));
    await tester.pump();

    expect(find.text(_name), findsNothing);
    expect(find.textContaining('tap an animal'), findsOneWidget);
  });
}

/// The one animal in the test sky. `2026 AB` at 100 m is a Tiger (plane-sized),
/// passing at 2.0 Moons — real, whole numbers so the stat line reads cleanly and
/// the "just passing" badge (not a close flyby, which is `< 1`) is exercised.
const Asteroid _rock = Asteroid(
  name: '2026 AB',
  diaMax: 100,
  diaMin: 50,
  hazardous: false,
  missLunar: 2,
  missKm: 768800, // 2 Moons
  velKps: 12,
  mag: 22,
  jpl: 'https://ssd.jpl.nasa.gov/tools/sbdb_lookup.html',
  date: '2026-07-17',
);

/// The card's name line: "🐯 {first} the Tiger", sourced from [critter] rather
/// than spelled out so the hashed first name cannot drift out of sync with it.
String get _name => '${critter(_rock).animal.emoji} ${critter(_rock).name}';

/// The five-field meta line, built the way the card builds it (`index.html:722`)
/// so this asserts the card's own ordering and glue, not a re-typed copy of the
/// numbers.
String get _statLine =>
    '${sizeLabel(_rock.diaMax)} · ${_rock.diaMax.round()} m wide'
    ' · comes ${distLabel(_rock.missLunar)}'
    ' · zooms ${_rock.velKps.toStringAsFixed(1)} km/s'
    ' · power ⭐ ${powerStars(_rock)}';

/// A follow set held in memory, [followed] to start with. Overrides [toggle] so
/// the button's write never touches Hive — a real `Box.put` inside the widget
/// tester hangs its fake clock (that path is providers_test.dart's).
class _MemFollows extends FollowsNotifier {
  _MemFollows(this._seed);

  final Set<String> _seed;

  @override
  Set<String> build() => <String>{..._seed};

  @override
  Future<void> toggle(String designation) async {
    final Set<String> next = <String>{...state};
    if (next.contains(designation)) {
      next.remove(designation);
    } else {
      next.add(designation);
    }
    state = next;
  }
}

/// Mounts the radar over a single-rock sky, with the follow set seeded to
/// [followed] and the day-streak flame standing at a fixed number — both
/// overridden in memory so this suite never opens a Hive box.
Future<void> _mount(
  WidgetTester tester, {
  Set<String> followed = const <String>{},
}) async {
  tester.view
    ..physicalSize = const Size(390, 700)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final AsteroidFeed feed = AsteroidFeed(
    asteroids: <Asteroid>[_rock],
    todayList: <Asteroid>[_rock],
    feedRange: '2026-07-15 → 2026-07-17',
    provenance: FeedProvenance.today,
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        asteroidFeedProvider.overrideWith((Ref ref) => feed),
        dayStreakProvider.overrideWithValue(0),
        followsProvider.overrideWith(() => _MemFollows(followed)),
        // The radar field resolves 🐢 Calm motion each build, and the real
        // notifier reads the store. Held at "never chose", which resolves
        // against a `MediaQuery` that is not asking — so the sky drifts at full
        // speed here exactly as it did before the setting existed.
        reducedMotionProvider.overrideWith(StubCalmMotion.new),
      ],
      child: const MaterialApp(home: RadarView()),
    ),
  );
  // The feed override resolves a frame later; the radar builds behind the
  // loading gate, so `requireValue` would throw before this.
  await tester.pump();
}

/// Taps the sole animal and lets its slide-up finish, so the card's buttons sit
/// where a finger would find them.
Future<void> _tapAnimal(WidgetTester tester) async {
  final RadarPainter painter = _painter(tester);
  final Size size = tester.getSize(_radarCanvas());
  final Offset at = painter.orbits.positionOf(
    painter.orbits.orbits.single,
    geometry: RadarGeometry(size: size, maxLd: painter.maxLd),
    zoom: painter.zoom,
    viewRot: painter.viewRot,
  );
  await tester.tapAt(at);
  await tester.pump(); // build the card
  await tester.pump(const Duration(milliseconds: 250)); // finish the 200ms slide
}

/// The radar's own canvas — named by its painter, since a `Material`'s ink is a
/// `CustomPaint` too (the note in `radar_view_test.dart`).
Finder _radarCanvas() => find.byWidgetPredicate(
  (Widget w) => w is CustomPaint && w.painter is RadarPainter,
);

RadarPainter _painter(WidgetTester tester) =>
    tester.widget<CustomPaint>(_radarCanvas()).painter! as RadarPainter;

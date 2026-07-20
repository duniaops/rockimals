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
    // 12 km/s · power ⭐ 83".
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

  /// 🐢 Calm motion's half of this card. The radar field's drift is pinned in
  /// `radar_view_test.dart`; this is the other motion on the same screen.
  group('🐢 Calm motion', () {
    testWidgets('halves the slide-up rather than removing it', (tester) async {
      // **A duration, so it shortens rather than slowing** ([kCalmReactionScale],
      // not [kCalmDriftScale]) — the fifth that calms the drift would here
      // *stretch* a 200ms slide to a full second, which is the opposite of what
      // the setting was asked for.
      //
      // **And shortened rather than removed**, which is the half worth arguing.
      // This slide is what tells a child their tap landed on *this* animal; a
      // card that simply appeared, fully formed, would be indistinguishable
      // from one that had been sitting there. Eight pixels over a tenth of a
      // second keeps that answer while barely being movement at all.
      //
      // The measurement is *when it lands*, not how far along it is at some
      // sampled instant: `Curves.ease` is steep early, so a mid-slide sample of
      // a halved 200ms and a full 200ms differ by less than intuition suggests
      // and a sloppy tolerance would pass for either. "Finished at 100ms, still
      // going at 100ms" cannot.
      final Duration halved = kHudSlide * kCalmReactionScale;

      await _mount(tester, calmMotion: true);
      expect(
        await _slideProgressAt(tester, halved * 0.5),
        inExclusiveRange(0, 1),
        reason: 'a calm card is genuinely mid-slide, not snapped to its end',
      );

      await _remount(tester, calmMotion: true);
      expect(
        await _slideProgressAt(tester, halved),
        closeTo(1, 1e-6),
        reason: 'and has landed by half of the prototype’s 200ms',
      );

      // The same two samples against the unchanged card, which is what makes
      // the pair above mean anything: at 100ms it is still on its way, and only
      // at the full 200ms is it home.
      await _remount(tester);
      expect(await _slideProgressAt(tester, halved), lessThan(1));

      await _remount(tester);
      expect(await _slideProgressAt(tester, kHudSlide), closeTo(1, 1e-6));
    });
  });
}

/// Tears the radar down and mounts it again, so the next tap plays a *fresh*
/// slide.
///
/// **Not optional, and the reason is a trap worth stating.** Calling [_mount]
/// twice does not remount anything: the root widgets are the same types in the
/// same positions, so Flutter *updates* the tree rather than rebuilding it, the
/// field keeps its `_selected`, and the card is already sitting at full opacity
/// when the second tap arrives. A comparison written that way reads 1.0 for the
/// second arm no matter what the code does — it passes for any implementation,
/// including one that ignores the setting entirely.
Future<void> _remount(WidgetTester tester, {bool? calmMotion}) async {
  await tester.pumpWidget(const SizedBox());
  await _mount(tester, calmMotion: calmMotion);
}

/// How far through its slide-up the card is [elapsed] after the animal is
/// tapped, as the 0→1 the card's builder drives.
///
/// Read off the [Opacity] the card's own builder installs rather than off the
/// [Transform], because the transform's 8 pixels are shared with nothing while
/// the opacity is the same `t` — and the tree above the card carries transforms
/// of its own that a `find.byType(Transform).first` would have to dodge.
Future<double> _slideProgressAt(WidgetTester tester, Duration elapsed) async {
  final RadarPainter painter = _painter(tester);
  final Size size = tester.getSize(_radarCanvas());
  await tester.tapAt(
    painter.orbits.positionOf(
      painter.orbits.orbits.single,
      geometry: RadarGeometry(size: size, maxLd: painter.maxLd),
      zoom: painter.zoom,
      viewRot: painter.viewRot,
    ),
  );
  await tester.pump(); // build the card at t = 0
  await tester.pump(elapsed);

  return tester
      .widget<Opacity>(
        find
            .ancestor(of: find.text(_name), matching: find.byType(Opacity))
            .first,
      )
      .opacity;
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
    ' · zooms ${speedLabel(_rock.velKps)}'
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
  bool? calmMotion,
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
        // The radar field and this card both resolve 🐢 Calm motion each build,
        // and the real notifier reads the store. Defaulted to "never chose",
        // which resolves against a `MediaQuery` that is not asking — so the sky
        // drifts and the card slides at full speed here exactly as they did
        // before the setting existed.
        reducedMotionProvider.overrideWith(() => StubCalmMotion(calmMotion)),
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
  await tester.pump(
    const Duration(milliseconds: 250),
  ); // finish the 200ms slide
}

/// The radar's own canvas — named by its painter, since a `Material`'s ink is a
/// `CustomPaint` too (the note in `radar_view_test.dart`).
Finder _radarCanvas() => find.byWidgetPredicate(
  (Widget w) => w is CustomPaint && w.painter is RadarPainter,
);

RadarPainter _painter(WidgetTester tester) =>
    tester.widget<CustomPaint>(_radarCanvas()).painter! as RadarPainter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/core/animals/animal_system.dart';
import 'package:rockimals/data/models/asteroid.dart';
import 'package:rockimals/data/models/asteroid_feed.dart';
import 'package:rockimals/features/data/providers.dart';
import 'package:rockimals/features/detail/detail_screen.dart';
import 'package:rockimals/features/radar/radar_focus.dart';
import 'package:rockimals/features/radar/radar_geometry.dart';
import 'package:rockimals/features/radar/radar_painter.dart';
import 'package:rockimals/features/radar/radar_view.dart';
import 'package:rockimals/features/shell/app_shell.dart';

/// Show on radar (`openRadarFocus`, `index.html:657`; `specs/03-meet-animal.md:
/// 23`) — the one action that reaches across three widgets that do not know
/// about each other. The detail screen publishes a [RadarFocus] request; the
/// shell brings the Radar tab forward and the radar selects the animal and
/// re-centres the field. These pin the three halves — the event, the tab switch,
/// and the selection-plus-reset — plus the real button driving all of it end to
/// end.
void main() {
  group('the focus request', () {
    test('re-fires for the same animal, so a repeat Show on radar lands', () {
      // The plan's "additionally resets zoom and rotation" only helps if a
      // second Show-on-radar for the *same* animal is a real event: a child can
      // re-centre a field they spun away again. A bare `Asteroid?` would make the
      // second `focus` `identical` to the first and publish nothing;
      // [RadarFocus]'s per-call identity is what keeps it an event.
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      int fires = 0;
      container.listen<RadarFocus?>(
        radarFocusProvider,
        (RadarFocus? previous, RadarFocus? next) => fires++,
      );

      container.read(radarFocusProvider.notifier).focus(_rock);
      container.read(radarFocusProvider.notifier).focus(_rock);

      expect(fires, 2);
      expect(container.read(radarFocusProvider)?.asteroid.name, _rock.name);
    });
  });

  testWidgets('the radar selects the animal and resets a spun, zoomed view', (
    tester,
  ) async {
    // The radar's half, in isolation. The field is dragged round and pinched in
    // first, so the reset ([_focusOnRadar]) has something to undo — the
    // prototype's `radarSelect` leaves the view alone, and the plan adds the
    // reset because a spun-and-zoomed field can leave the selection off screen.
    final ProviderContainer container = _container();
    addTearDown(container.dispose);
    await _mountRadar(tester, container);

    await tester.dragFrom(
      _centre(tester) + const Offset(120, 0),
      const Offset(-120, 120),
    );
    await _pinch(tester, from: 100, to: 200);
    await tester.pump();
    expect(_painter(tester).viewRot, isNot(0), reason: 'the premise: spun');
    expect(_painter(tester).zoom, isNot(1), reason: 'the premise: zoomed');
    expect(_painter(tester).selected, isNull, reason: 'the premise: none picked');

    container.read(radarFocusProvider.notifier).focus(_rock);
    await tester.pump();

    // Selected, and the field back to the sky the child opened the app to.
    expect(_painter(tester).selected?.name, _rock.name);
    expect(_painter(tester).zoom, 1);
    expect(_painter(tester).viewRot, 0);
  });

  testWidgets('a focus request from another tab brings the Radar tab forward', (
    tester,
  ) async {
    // The shell's half (`switchTab("today")`, `index.html:657`). A child can
    // reach the detail from the Sky or My Animals tab, so Show on radar has to
    // switch tabs, not only select — driven here from off the Radar tab.
    final ProviderContainer container = _container();
    addTearDown(container.dispose);
    await _mountShell(tester, container);

    await tester.tap(find.text('Sky'));
    await tester.pump();
    expect(find.byType(RadarView), findsNothing, reason: 'left the radar');

    container.read(radarFocusProvider.notifier).focus(_rock);
    await tester.pump();

    // Back on the radar, with the animal selected — the shell switched tabs and
    // the radar (mounted and listening from behind the Sky tab) had already
    // picked it.
    expect(find.byType(RadarView), findsOneWidget);
    expect(_painter(tester).selected?.name, _rock.name);
  });

  testWidgets('Show on radar, tapped for real, returns to the radar selected', (
    tester,
  ) async {
    // The whole path a child takes: tap an animal, Meet it, then Show on radar.
    // The detail button publishes the request and pops; the child lands back on
    // the radar with that animal selected. The isolated tests above own the tab
    // switch and the reset; this owns that the real button wires them together.
    final ProviderContainer container = _container();
    addTearDown(container.dispose);
    await _mountShell(tester, container);

    // Select the animal and open its detail through Meet.
    await tester.tapAt(_animalAt(tester));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250)); // the card's slide
    await tester.tap(find.text('Meet ${critter(_rock).first}'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400)); // the push transition
    expect(find.byType(DetailScreen), findsOneWidget, reason: 'on the detail');

    // The action row is at the foot of the scrolling detail body — scroll it up
    // before tapping.
    await tester.ensureVisible(find.text('🛰️ Show on radar'));
    await tester.tap(find.text('🛰️ Show on radar'));
    // The radar's ticker never stops scheduling frames, so `pumpAndSettle` would
    // time out; pump the pop transition by hand.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    // Back on the radar with the animal selected — the detail is gone.
    expect(find.byType(DetailScreen), findsNothing);
    expect(find.byType(RadarView), findsOneWidget);
    expect(_painter(tester).selected?.name, _rock.name);
  });
}

/// One rock, close enough to sit mid-field and clear of the zoom column on the
/// right (`radar_view_test.dart`'s reasoning) — tappable at rest.
const Asteroid _rock = Asteroid(
  name: '2026 AB',
  diaMax: 100,
  diaMin: 50,
  hazardous: false,
  missLunar: 3,
  missKm: 1153200,
  velKps: 12,
  mag: 22,
  jpl: 'https://ssd.jpl.nasa.gov/tools/sbdb_lookup.html',
  date: '2026-07-17',
);

final AsteroidFeed _sky = AsteroidFeed(
  asteroids: <Asteroid>[_rock],
  todayList: <Asteroid>[_rock],
  feedRange: '2026-07-15 → 2026-07-17',
  provenance: FeedProvenance.today,
);

/// A container with the sky resolved and the store-backed providers stood in
/// front of in memory, so nothing here opens a Hive box or a repository — the
/// same overrides the radar and shell suites use.
ProviderContainer _container() {
  final ProviderContainer container = ProviderContainer(
    overrides: [
      asteroidFeedProvider.overrideWith((Ref ref) => _sky),
      dayStreakProvider.overrideWithValue(0),
      followsProvider.overrideWith(_NoFollows.new),
    ],
  );
  return container;
}

/// The radar alone, over [container] — enough for the radar's own reaction to a
/// focus request.
Future<void> _mountRadar(WidgetTester tester, ProviderContainer container) async {
  tester.view
    ..physicalSize = const Size(390, 700)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: RadarView()),
    ),
  );
  // The feed override resolves a frame later; the radar builds behind the
  // loading gate, so `requireValue` would throw before this.
  await tester.pump();
}

/// The whole shell over [container] — the frame the tab switch and the Meet →
/// detail → Show-on-radar flow need.
Future<void> _mountShell(WidgetTester tester, ProviderContainer container) async {
  tester.view
    ..physicalSize = const Size(390, 700)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: AppShell()),
    ),
  );
  await tester.pump();
}

/// A follow set that stays empty and never touches the store — the HUD card and
/// the detail both read it, but these tests never tap Follow.
class _NoFollows extends FollowsNotifier {
  @override
  Set<String> build() => <String>{};
}

/// The radar's own canvas — named by its painter, since a `Material`'s ink is a
/// `CustomPaint` too (`radar_view_test.dart`'s note).
Finder _radarCanvas() => find.byWidgetPredicate(
  (Widget w) => w is CustomPaint && w.painter is RadarPainter,
);

/// What the radar is currently drawing — its selection and view transform.
RadarPainter _painter(WidgetTester tester) =>
    tester.widget<CustomPaint>(_radarCanvas()).painter! as RadarPainter;

/// Earth, and the centre of the field.
Offset _centre(WidgetTester tester) {
  final Size size = tester.getSize(_radarCanvas());
  return Offset(size.width / 2, size.height * 0.46);
}

/// Where the sole animal currently is, asked of the same [RadarOrbits] the
/// painter draws so a test taps the animal a child would see.
Offset _animalAt(WidgetTester tester) {
  final RadarPainter painter = _painter(tester);
  final Size size = tester.getSize(_radarCanvas());
  return painter.orbits.positionOf(
    painter.orbits.orbits.single,
    geometry: RadarGeometry(size: size, maxLd: painter.maxLd),
    zoom: painter.zoom,
    viewRot: painter.viewRot,
  );
}

/// Two fingers, [from] apart, spread to [to] apart up the middle of the field —
/// clear of the zoom column on the right (`radar_view_test.dart`'s reasoning).
Future<void> _pinch(
  WidgetTester tester, {
  required double from,
  required double to,
}) async {
  final Size size = tester.getSize(_radarCanvas());
  final Offset centre = Offset(size.width / 2, size.height * 0.62);
  final TestGesture top = await tester.startGesture(centre - Offset(0, from / 2));
  final TestGesture bottom = await tester.startGesture(centre + Offset(0, from / 2));

  await top.moveTo(centre - Offset(0, to / 2));
  await bottom.moveTo(centre + Offset(0, to / 2));
  await top.up();
  await bottom.up();
  await tester.pump();
}

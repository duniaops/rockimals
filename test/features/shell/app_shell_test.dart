import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/data/models/asteroid.dart';
import 'package:rockimals/data/models/asteroid_feed.dart';
import 'package:rockimals/features/data/providers.dart';
import 'package:rockimals/features/radar/radar_painter.dart';
import 'package:rockimals/features/radar/radar_view.dart';
import 'package:rockimals/features/settings/little_kids_mode.dart';
import 'package:rockimals/features/shell/app_shell.dart';
import 'package:rockimals/features/watchlist/watchlist_screen.dart';

import '../../support/memory_store.dart';
import '../../support/stub_settings.dart';

/// The frame the whole app is seen through, so what these pin is the three
/// things a child would notice immediately if they broke: the app opens on the
/// radar, every tab is reachable, and the one you are on is the one that looks
/// selected. Plus the invisible fourth — that leaving a tab does not throw it
/// away.
///
/// **The two halves are asserted with deliberately different finders, and the
/// difference is the whole point.** An [IndexedStack] keeps every tab mounted
/// and paints only the selected one, so "displayed" and "alive" are genuinely
/// different questions here. Flutter's default finders answer the first:
/// `_IndexedStackElement.debugVisitOnstageChildren` visits only the child at
/// `index`, so a hidden tab's body is invisible to `find.text` exactly as it is
/// to a child. `skipOffstage: false` answers the second by looking at the
/// mounted tree regardless of what is painted. Asserting state preservation
/// therefore *requires* that flag — the first draft of this file used a default
/// finder and read as though the shell were destroying tabs.
void main() {
  group('AppShell', () {
    testWidgets('opens on the Radar tab', (tester) async {
      // The prototype's first nav button carries `class="on"`
      // (`index.html:303`) and `specs/02-live-radar.md:4` calls the radar the
      // home tab: it is the thing a child opens Rockimals to see. Both halves
      // are asserted — the body that is shown and the label that looks
      // selected — because a shell that displayed the radar while highlighting
      // Profile would pass either one alone.
      await tester.pumpWidget(_app());

      expect(_bodyOf('Radar'), findsOneWidget);
      expect(_bodyOf('Sky'), findsNothing);
      expect(_labelColour(tester, 'Radar'), _selected);
      expect(_labelColour(tester, 'Sky'), _idle);
    });

    testWidgets('switches to any of the four tabs when its button is tapped', (
      tester,
    ) async {
      await tester.pumpWidget(_app());

      // Every tab, not a sample: this is the whole of the item's behaviour, and
      // there are only four. [_navLabel] scopes the finder to the bottom button
      // because the My Animals nav label deliberately matches its screen title.
      for (final String label in <String>[
        'Sky',
        'My Animals',
        'Profile',
        'Radar',
      ]) {
        await tester.tap(_navLabel(label));
        await tester.pump();

        expect(_bodyOf(label), findsOneWidget, reason: 'tapped $label');
        expect(_labelColour(tester, label), _selected, reason: 'tapped $label');
      }
    });

    testWidgets('shows one tab at a time', (tester) async {
      // The prototype hides every view but the selected one
      // (`index.html:1130`), and the failure this guards is an IndexedStack
      // swapped for a Column or a Stack that paints all four at once — which
      // the test above would not notice, since each of its assertions is
      // satisfied by a body simply being on screen.
      await tester.pumpWidget(_app());

      await tester.tap(_navLabel('My Animals'));
      await tester.pump();

      expect(_bodyOf('My Animals'), findsOneWidget);
      for (final String other in <String>['Radar', 'Sky', 'Profile']) {
        expect(_bodyOf(other), findsNothing, reason: other);
      }
    });

    testWidgets('highlights only the selected tab', (tester) async {
      // The prototype's `switchTab` toggles `on` off every button before
      // setting it (`index.html:1131`), so the failure this guards is a nav
      // that adds highlights without removing them and ends up with four
      // orange labels.
      await tester.pumpWidget(_app());

      await tester.tap(find.text('Profile'));
      await tester.pump();

      expect(_labelColour(tester, 'Profile'), _selected);
      for (final String other in <String>['Radar', 'Sky', 'My Animals']) {
        expect(_labelColour(tester, other), _idle, reason: other);
      }
    });

    testWidgets('keeps a tab alive after switching away from it', (
      tester,
    ) async {
      // The item's "keeping each tab's state alive" clause, and the reason the
      // shell is an IndexedStack rather than a body rebuilt per tap. A child
      // who scrolls the Sky, checks their points, and comes back should find
      // the Sky where they left it — a rebuilt body silently rewinds it, which
      // looks like nothing at all until the tab in question has scroll position
      // or a half-finished game in it.
      //
      // The Radar tab is the probe because it is the only tab whose body is not
      // a stub. It was the debug list when this was written and is now the
      // radar, exactly as this comment then asked for — the property being
      // pinned is the shell's, not any one screen's.
      //
      // It also matters more here than it did there. The radar seeds every
      // animal's orbit once, at mount (`RadarOrbits.seed`), so a shell that
      // rebuilt the tab would restart the sky from its phase-0 seeds on every
      // return to it — the whole field snapping back to where it was at launch.
      await tester.pumpWidget(_app());
      expect(find.byType(RadarView), findsOneWidget);

      await tester.tap(find.text('Sky'));
      await tester.pump();

      // Gone from the screen...
      expect(find.byType(RadarView), findsNothing);
      // ...but not from the tree. Both lines are needed: the first alone passes
      // for a shell that destroys the tab, and the second alone passes for one
      // that never hid it.
      expect(find.byType(RadarView, skipOffstage: false), findsOneWidget);
    });

    testWidgets('labels the four tabs with the kid-friendly follow language', (
      tester,
    ) async {
      // Games v2 Item 1 supersedes the prototype's "Watchlist" label so the
      // tab and its screen use the same child-facing name.
      await tester.pumpWidget(_app());

      for (final String label in <String>[
        'Radar',
        'Sky',
        'My Animals',
        'Profile',
      ]) {
        expect(_navLabel(label), findsOneWidget, reason: label);
      }
      expect(find.text('Watchlist'), findsNothing);
      for (final String emoji in <String>['🛰️', '🌌', '⭐', '👤']) {
        expect(find.text(emoji), findsOneWidget, reason: emoji);
      }
    });

    testWidgets('freezes the radar off-tab and resumes it on return', (
      tester,
    ) async {
      // The "pause the render loop off-tab" item (`specs/02-live-radar.md:29`,
      // `index.html:729`). An [IndexedStack] keeps the radar mounted and its
      // ticker firing from behind another tab, so without the per-tab
      // [TickerMode] the sky would keep drawing sixty frames a second while a
      // child reads their profile. The Done-when is "zero radar frames while
      // another tab is shown, and motion resumes on return"; this reads that off
      // the paint output, the same signal `radar_view_test.dart`'s "keeps
      // drawing" test uses — Earth's glow breathes and the one animal orbits, so
      // a running loop changes the circles it draws frame to frame and a stopped
      // one draws the identical frame forever.
      await tester.pumpWidget(_app());
      await tester.pump(); // the feed override resolves; the first radar frame

      // On-tab the loop runs, so the painted circles move.
      final List<double> onA = _radarCircles(tester);
      await tester.pump(const Duration(milliseconds: 471));
      final List<double> onB = _radarCircles(tester);
      expect(onB, isNot(onA), reason: 'the radar animates while it is shown');

      // Leave the radar for the Sky tab.
      await tester.tap(find.text('Sky'));
      await tester.pump(); // switch tabs
      await tester.pump(const Duration(seconds: 1)); // drain the nav tap ripple

      // Off-tab: the ticker is muted, so a pump draws no new frame — the sky is
      // exactly where it was left.
      final List<double> offA = _radarCircles(tester);
      await tester.pump(const Duration(milliseconds: 471));
      final List<double> offB = _radarCircles(tester);
      expect(offB, offA, reason: 'a hidden radar draws no new frames');

      // ...and independently, nothing is asking for the next frame. This is the
      // "zero frames" half stated a second way: a live radar reschedules a frame
      // callback every tick, so a false here means the loop has genuinely
      // stopped, not merely that this particular pump happened to match.
      expect(
        tester.binding.hasScheduledFrame,
        isFalse,
        reason: 'the muted radar requests no frames off-tab',
      );

      // Come back to the radar.
      await tester.tap(find.text('Radar'));
      await tester.pump();

      // Motion resumes. The [FrameClock] clamp turns the long off-tab gap into
      // one ordinary step rather than a lurch, but that it moves at all is the
      // assertion here.
      final List<double> backA = _radarCircles(tester);
      await tester.pump(const Duration(milliseconds: 471));
      final List<double> backB = _radarCircles(tester);
      expect(backB, isNot(backA), reason: 'motion resumes when shown again');
    });

    testWidgets('marks each tab as a selectable button for a screen reader', (
      tester,
    ) async {
      // The nav shows selection by label colour alone (`index.html:87`) — no
      // pill, no underline — so with nothing else it is invisible to anyone not
      // seeing the colour. `specs/06-title-polish-safety.md:43` has an
      // accessibility pass of its own; this is only the part that would be
      // awkward to retrofit once four tabs of content sit on top.
      //
      // No `hasEnabledState`: a tab is never disabled, and claiming the state
      // exists would have a screen reader announce every tab as "enabled" for
      // no reason. `matchesSemantics` is exhaustive, so the absence is asserted
      // rather than merely unmentioned.
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(_app());

      expect(
        tester.getSemantics(find.text('Radar')),
        matchesSemantics(
          label: 'Radar',
          isButton: true,
          isSelected: true,
          hasTapAction: true,
          hasFocusAction: true,
          hasSelectedState: true,
          isFocusable: true,
        ),
      );
      // The emoji is decoration and must not be announced: without the
      // exclusion this reads "satellite Radar".
      expect(tester.getSemantics(find.text('Sky')).label, 'Sky');

      handle.dispose();
    });
  });
}

/// `--accent2` / `--muted` (`index.html:9-10`) — restated here rather than
/// imported, because they are private to the shell and a test that read the
/// same constant the widget reads would pass for any value at all.
const Color _selected = Color(0xFFFF7A45);
const Color _idle = Color(0xFF93A8CA);

/// A probe for each tab's *body*, keyed by its nav label — something only that
/// tab puts on screen. **Every row now points at a real screen**: the Radar row
/// was repointed when the radar displaced the debug list, the Sky row when the
/// Sky tab landed, the My Animals row when that screen did, and this last one when
/// My Space Zoo replaced the final "… is coming soon" stub. Note each probe is a
/// tab's distinctive body widget or title.
Finder _bodyOf(String label) => switch (label) {
  'Radar' => find.byType(RadarView),
  'Sky' => find.text('The Sky'),
  'My Animals' => find.byType(WatchlistScreen),
  'Profile' => find.text('My Space Zoo'),
  _ => throw ArgumentError.value(label, 'label', 'not a tab'),
};

Finder _navLabel(String label) => find.descendant(
  of: find.ancestor(of: find.text(label), matching: find.byType(InkWell)),
  matching: find.text(label),
);

Color? _labelColour(WidgetTester tester, String label) =>
    tester.widget<Text>(_navLabel(label)).style?.color;

/// The radii of every circle the radar's canvas draws this frame — Earth, its
/// breathing glow, the animals, and the planet backdrop's spheres.
///
/// **Read with `skipOffstage: false` on purpose: the interesting frames are the
/// ones where the radar is *not* the visible tab.** An [IndexedStack] keeps the
/// hidden radar mounted and sized, and the `paints` matcher drives its `paint`
/// directly rather than waiting for it to be on screen, so this reads the same
/// output whether the tab is shown or hidden — which is exactly what lets the
/// test compare a running loop against a paused one. The whole list is captured
/// (returning `false` keeps the scan going, as `radar_view_test.dart`'s ring
/// collector does) so an unchanged frame is unchanged in full, not just in the
/// one circle a matcher happened to name.
List<double> _radarCircles(WidgetTester tester) {
  final RenderBox canvas = tester.renderObject<RenderBox>(
    find.byWidgetPredicate(
      (Widget w) => w is CustomPaint && w.painter is RadarPainter,
      skipOffstage: false,
    ),
  );
  final List<double> radii = <double>[];
  final Matcher collector =
      (paints..something((Symbol method, List<dynamic> arguments) {
            if (method == #drawCircle) radii.add(arguments[1] as double);
            return false;
          }))
          as Matcher;
  collector.matches(canvas, <dynamic, dynamic>{});
  return radii;
}

/// The shell with a sky already in hand. Without an override the Radar tab
/// builds a live Dio and starts a real request as a side effect of asking which
/// tab is selected, and leaves the repository's ten-second ceiling pending at
/// teardown.
///
/// **The sky is resolved rather than a never-completing future, and the change
/// is forced rather than cosmetic.** This helper used to hold the feed in
/// flight, which was free when the Radar tab was the debug list — that screen
/// renders a spinner from `.when`. [RadarView] instead reads `requireValue`,
/// which throws on an [AsyncLoading], and it is entitled to: the loading gate
/// builds the shell only once there is a sky, so "the shell exists" and "the
/// feed resolved" are the same fact in the app. A pending future here would
/// therefore test a state the app cannot be in, and would fail for a reason
/// that says nothing about the nav.
Widget _app() {
  return ProviderScope(
    // The override list is left to inference: Riverpod 3 does not export the
    // `Override` type, so there is no name to annotate it with.
    overrides: [
      // 🧸 Little Kids mode, which the radar's Play CTA resolves for its
      // game count — stubbed off like every store-backed read beside it.
      littleKidsModeProvider.overrideWith(StubLittleKids.new),
      asteroidFeedProvider.overrideWith((Ref ref) => _sky),
      // The radar tab's home overlay reads the day streak; a value in front of
      // it keeps the shell suite off a Hive box, as the feed override keeps it
      // off a repository.
      dayStreakProvider.overrideWithValue(0),
      // The Watchlist tab reads the follow set, which is seeded from the store.
      // An in-memory one keeps this suite off a Hive box for the same reason —
      // what the follow set *contains* is `watchlist_screen_test.dart`'s
      // question, not the nav's.
      storeProvider.overrideWithValue(MemoryStore()),
    ],
    child: const MaterialApp(home: AppShell()),
  );
}

/// One rock, because nothing here reads the sky — it exists so the Radar tab
/// has something to build against. `radar_view_test.dart` owns what the radar
/// does with a feed; this file only needs the tab not to be empty.
final AsteroidFeed _sky = AsteroidFeed(
  asteroids: <Asteroid>[_rock],
  todayList: <Asteroid>[_rock],
  feedRange: '2026-07-15 → 2026-07-17',
  provenance: FeedProvenance.today,
);

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

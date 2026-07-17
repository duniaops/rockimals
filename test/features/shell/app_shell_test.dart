import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/data/models/asteroid_feed.dart';
import 'package:rockimals/features/data/providers.dart';
import 'package:rockimals/features/debug/debug_animal_list_screen.dart';
import 'package:rockimals/features/shell/app_shell.dart';

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
      // there are only four. The nav labels are unique strings in the tree —
      // the stubs read "Sky is coming soon", never a bare "Sky" — so these
      // finders hit the buttons and not the bodies.
      for (final String label in <String>[
        'Sky',
        'Watchlist',
        'Profile',
        'Radar',
      ]) {
        await tester.tap(find.text(label));
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

      await tester.tap(find.text('Watchlist'));
      await tester.pump();

      expect(_bodyOf('Watchlist'), findsOneWidget);
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
      for (final String other in <String>['Radar', 'Sky', 'Watchlist']) {
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
      // a stub. When the radar displaces the debug screen, this should switch
      // to the radar's widget rather than be deleted — the property is the
      // shell's, not that screen's.
      await tester.pumpWidget(_app());
      expect(find.byType(DebugAnimalListScreen), findsOneWidget);

      await tester.tap(find.text('Sky'));
      await tester.pump();

      // Gone from the screen...
      expect(find.byType(DebugAnimalListScreen), findsNothing);
      // ...but not from the tree. Both lines are needed: the first alone passes
      // for a shell that destroys the tab, and the second alone passes for one
      // that never hid it.
      expect(
        find.byType(DebugAnimalListScreen, skipOffstage: false),
        findsOneWidget,
      );
    });

    testWidgets('labels the four tabs the way the prototype does', (
      tester,
    ) async {
      // `index.html:303-306`, verbatim and in order. "Watchlist" is deliberate
      // and is the one label worth a test of its own: `CLAUDE.md:64` rewrites
      // "track" → "follow", so the tempting "fix" here is to rename the tab —
      // but `specs/08-settings-about.md:41` names it Watchlist in the only
      // place a spec names the nav at all.
      await tester.pumpWidget(_app());

      for (final String label in <String>[
        'Radar',
        'Sky',
        'Watchlist',
        'Profile',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      for (final String emoji in <String>['🛰️', '🌌', '⭐', '👤']) {
        expect(find.text(emoji), findsOneWidget, reason: emoji);
      }
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
/// tab puts on screen. Every one of these is transitional: the debug screen and
/// all three stubs are deleted by the tasks that own their tabs, and each should
/// be repointed at the real screen rather than dropped.
Finder _bodyOf(String label) => switch (label) {
  'Radar' => find.byType(DebugAnimalListScreen),
  'Sky' => find.text('Sky is coming soon'),
  'Watchlist' => find.text('My Animals is coming soon'),
  'Profile' => find.text('My Space Zoo is coming soon'),
  _ => throw ArgumentError.value(label, 'label', 'not a tab'),
};

Color? _labelColour(WidgetTester tester, String label) =>
    tester.widget<Text>(find.text(label)).style?.color;

/// The shell with the sky held back. The Radar tab watches the feed, so without
/// the override this builds a live Dio and starts a real request as a side
/// effect of asking which tab is selected — and leaves the repository's
/// ten-second ceiling pending at teardown. A never-completing future also holds
/// that tab on its spinner, which is the state a cold launch is in anyway.
Widget _app() {
  return ProviderScope(
    // The override list is left to inference: Riverpod 3 does not export the
    // `Override` type, so there is no name to annotate it with.
    overrides: [
      asteroidFeedProvider.overrideWith(
        (Ref ref) => Completer<AsteroidFeed>().future,
      ),
    ],
    child: const MaterialApp(home: AppShell()),
  );
}

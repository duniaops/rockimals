/// The Settings entry point and its screen (`specs/08-settings-about.md:39-43`,
/// and the acceptance criterion at `:72`: *"Settings opens from the Profile tab
/// and backs out cleanly"*).
///
/// **What is worth pinning here is smaller than it looks, and it is not the
/// pixels.** The screen's body is empty in this commit by design — the toggles
/// and the About block are their own items — so there is nothing to assert about
/// its contents that would not have to be deleted by the next item. What *does*
/// outlive this commit is the shape: Settings is reachable from exactly one
/// place, it is a **route** rather than a tab, it comes back, and both of the
/// two things a thumb has to hit are big enough. Each of those is a decision a
/// later change could quietly undo.
///
/// **The "route, not a tab" half is asserted through the Navigator rather than
/// by counting nav buttons** — `app_shell_test.dart:136` already pins the nav at
/// exactly four labels, and a second copy of that assertion here would fail in
/// two places for one cause. What this file adds is the other side of the same
/// rule: that opening Settings *pushes*, which is what makes a fifth tab
/// unnecessary in the first place.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/core/audio/sound_engine.dart';
import 'package:rockimals/core/storage/store.dart';
import 'package:rockimals/features/data/providers.dart';
import 'package:rockimals/features/profile/my_space_zoo_screen.dart';
import 'package:rockimals/features/rewards/badge_controller.dart';
import 'package:rockimals/features/settings/settings_screen.dart';

import '../../support/memory_store.dart';
import '../../support/recording_sound_engine.dart';

void main() {
  group('the Profile tab entry point', () {
    testWidgets('carries a ⚙️ Settings row', (tester) async {
      // Scrolled to first, in this test and every one below it: the row is the
      // last thing on a tab taller than any phone, so a default finder — which
      // sees only what a sliver has actually laid out — looks straight past it.
      // That it needs scrolling to is the design, not an inconvenience.
      await tester.pumpWidget(_app());
      await tester.scrollUntilVisible(find.text('Settings'), 200);

      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('⚙️'), findsOneWidget);
    });

    testWidgets('puts the row below the badge shelf, not above it', (
      tester,
    ) async {
      // Position, not mere presence. "At the bottom of the Profile tab"
      // (`specs/08-settings-about.md:40`) is the whole reason this row is
      // unobtrusive: a child scrolling for their badges stops at the shelf and
      // never reaches it. A row that drifted up next to the points hero would
      // still pass every other test in this file.
      await tester.pumpWidget(_app());
      await tester.scrollUntilVisible(find.text('Settings'), 200);

      expect(
        tester.getTopLeft(find.text('Settings')).dy,
        greaterThan(tester.getBottomLeft(find.text('Perfect Match')).dy),
      );
    });

    testWidgets('announces itself as a button, without the emoji or chevron', (
      tester,
    ) async {
      // The row paints three glyphs and means one thing. Read as authored a
      // screen reader would say "gear", "Settings", "greater-than" — so the
      // decoration is excluded and the label set once, the trade `AnimalCard`
      // and the stat tiles both make.
      await tester.pumpWidget(_app());
      await tester.scrollUntilVisible(find.text('Settings'), 200);

      expect(find.bySemanticsLabel('Settings'), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Settings')),
        isSemantics(label: 'Settings', isButton: true),
      );
    });
  });

  group('opening and leaving Settings', () {
    testWidgets('tapping the row pushes a screen titled Settings', (
      tester,
    ) async {
      await tester.pumpWidget(_app());
      await tester.scrollUntilVisible(find.text('Settings'), 200);
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      expect(find.byType(SettingsScreen), findsOneWidget);
      // The title, and the proof it is a *route*: the Profile tab it was opened
      // from is still mounted underneath rather than replaced.
      expect(find.text('Settings'), findsOneWidget);
      expect(find.byType(MySpaceZooScreen, skipOffstage: false), findsOneWidget);
    });

    testWidgets('the ‹ Back pill returns to the Profile', (tester) async {
      await tester.pumpWidget(_app());
      await tester.scrollUntilVisible(find.text('Settings'), 200);
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('‹ Back'));
      await tester.pumpAndSettle();

      expect(find.byType(SettingsScreen), findsNothing);
      // Back on the tab it was opened from, with its own content on screen —
      // "backs out cleanly" (`specs/08-settings-about.md:72`) means landing
      // where you started, not merely that the route is gone.
      expect(find.text('My Space Zoo'), findsOneWidget);
    });

    testWidgets('the system back gesture also returns to the Profile', (
      tester,
    ) async {
      // Android's back button is the way most children will leave this screen,
      // and it goes through a different path than the pill: the pill calls
      // `maybePop` itself, this asks the route to pop. A screen that trapped it
      // would be the dead end `specs/08-settings-about.md:69` forbids.
      await tester.pumpWidget(_app());
      await tester.scrollUntilVisible(find.text('Settings'), 200);
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      await _systemBack(tester);
      await tester.pumpAndSettle();

      expect(find.byType(SettingsScreen), findsNothing);
      expect(find.text('My Space Zoo'), findsOneWidget);
    });
  });

  group('tap targets', () {
    // `specs/08-settings-about.md:82` — *"Every tap target is ≥48dp"*. Both are
    // measured off the rendered box rather than read back from the constant
    // that sets them, so padding changed elsewhere in the row fails here.

    testWidgets('the Settings row is at least 48dp tall', (tester) async {
      await tester.pumpWidget(_app());
      await tester.scrollUntilVisible(find.text('Settings'), 200);

      expect(
        tester.getSize(_tappableAround(find.text('Settings'))).height,
        greaterThanOrEqualTo(48),
      );
    });

    testWidgets('the back pill has a 48dp target around its smaller pill', (
      tester,
    ) async {
      await tester.pumpWidget(_app());
      await tester.scrollUntilVisible(find.text('Settings'), 200);
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      final Size target = tester.getSize(_tappableAround(find.text('‹ Back')));
      final Size pill = tester.getSize(find.text('‹ Back'));

      expect(target.height, greaterThanOrEqualTo(48));
      // The visual must *not* have grown to meet it — the pill stays the
      // prototype's `.back` (`index.html:93`), and the target is the invisible
      // expansion around it. Asserting only the 48 would pass a pill inflated
      // to twice the height of the title beside it.
      expect(pill.height, lessThan(48));
    });

    testWidgets('the row keeps its 48 when the text is scaled up', (
      tester,
    ) async {
      // A minimum that only holds at 1× is not a minimum. Large text grows the
      // row past 48 rather than shrinking it, so this is really asking that the
      // constraint is a floor and not a fixed height.
      await tester.pumpWidget(_app(textScale: 1.5));
      await tester.scrollUntilVisible(find.text('Settings'), 200);

      expect(
        tester.getSize(_tappableAround(find.text('Settings'))).height,
        greaterThanOrEqualTo(48),
      );
    });
  });

  group('the screen itself', () {
    testWidgets('is a route over the app, so it has no bottom nav of its own', (
      tester,
    ) async {
      // The counterpart to `app_shell_test.dart`'s four-label assertion: the
      // nav stays at four *because* Settings is pushed over it, and a screen
      // that grew its own nav would be the first step back towards a fifth tab.
      await tester.pumpWidget(_app());
      await tester.scrollUntilVisible(find.text('Settings'), 200);
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      expect(
        tester.widget<Scaffold>(
          find.descendant(
            of: find.byType(SettingsScreen),
            matching: find.byType(Scaffold),
          ),
        ).bottomNavigationBar,
        isNull,
      );
    });
  });
}

/// Android's system back, delivered the way the platform delivers it — the
/// `popRoute` message on `flutter/navigation`. `flutter_test` has no helper for
/// this, and driving `Navigator.pop` directly would test the [Navigator] rather
/// than the screen's willingness to be left.
Future<void> _systemBack(WidgetTester tester) async {
  final ByteData message = const JSONMethodCodec().encodeMethodCall(
    const MethodCall('popRoute'),
  );
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/navigation',
    message,
    (ByteData? _) {},
  );
}

/// The [InkWell] that actually takes the tap around [inner] — the box whose
/// size a thumb has to hit, which is not the text's own box.
Finder _tappableAround(Finder inner) =>
    find.ancestor(of: inner, matching: find.byType(InkWell)).first;

/// The Profile tab under a real [Navigator], because every assertion here is
/// about pushing off it. The store and the sound engine are faked for the
/// reason `my_space_zoo_screen_test.dart` states: this screen reads the store in
/// its first frame, and a badge earned mid-test would otherwise reach the real
/// engine.
Widget _app({double textScale = 1}) {
  final Store store = MemoryStore(points: 142, bestStreak: 7);
  final ProviderContainer container = ProviderContainer(
    overrides: [
      storeProvider.overrideWithValue(store),
      soundEngineProvider.overrideWithValue(RecordingSoundEngine()),
    ],
  );
  addTearDown(container.dispose);
  container.read(badgesProvider);

  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: const Scaffold(body: MySpaceZooScreen()),
      ),
    ),
  );
}

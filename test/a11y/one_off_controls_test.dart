import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/core/a11y/control_scale.dart';
import 'package:rockimals/core/a11y/tap_target.dart';
import 'package:rockimals/core/audio/sound_engine.dart';
import 'package:rockimals/data/models/asteroid_feed.dart';
import 'package:rockimals/features/data/providers.dart';
import 'package:rockimals/features/games/games_hub.dart';
import 'package:rockimals/features/profile/my_space_zoo_screen.dart';
import 'package:rockimals/features/settings/little_kids_mode.dart';
import 'package:rockimals/features/settings/settings_screen.dart';
import 'package:rockimals/features/shell/app_shell.dart';

import '../support/memory_store.dart';
import '../support/recording_sound_engine.dart';
import '../support/stub_settings.dart';

/// **The five screen-local controls that do not go through [TapTarget], and the
/// decision about whether 🧸 Little Kids mode should grow them.**
///
/// The affordance shipped against the three *shared* widgets the extension point
/// named — `TapTarget`, `ActionButton`, `AnimalCard` — and deliberately stopped
/// there, leaving five private, screen-local controls undecided: the bottom
/// nav's `_NavButton`, `settings_screen.dart`'s `_ToggleRow`,
/// `my_space_zoo_screen.dart`'s `_SettingsRow`, `games_hub.dart`'s
/// `_GameCardTile`, and `radar_view.dart`'s `_HudButton`.
///
/// **Why this file exists at all rather than five source comments.** The
/// decision is "these four stay as they are", and a comment saying so cannot
/// fail — which is the same objection the sound-gate item was settled on. A
/// future agent sweeping `ControlScale` through the app, or retuning a padding
/// by eye, should get a red test and a reason, not silence. So each control is
/// pinned to the *property its note claims*, not to a pixel count that font
/// metrics would make brittle.
///
/// **The fifth one is not here, because it was not a decision.** `_HudButton`
/// turned out to measure 31dp — below the 48dp floor outright, and invisible to
/// `tap_target_audit_test.dart` because that walk never selected an animal. It
/// was a bug rather than an exception, so it was fixed (it wraps [TapTarget] now
/// and scales with the rest) and the audit grew a selected-animal arm. That arm,
/// not this file, is its guard.
void main() {
  group('the multiplier is a no-op for these three, and measurably so', () {
    // **The shared claim being pinned:** each of these is already taller than
    // `kMinTapTarget * kLittleKidsControlScale` (60dp) from its own content or
    // chrome, so applying `ControlScale` could not raise a floor that never
    // binds. That makes "we chose not to scale it" cost nothing, and it is the
    // half of the argument a test can actually hold. Asserted as an inequality
    // against the floor rather than an exact height, so a label or a font metric
    // moving does not fail a claim it has not falsified.
    const double littleKidsFloor = kMinTapTarget * kLittleKidsControlScale;

    testWidgets('the bottom nav tab clears the floor from the bar', (
      tester,
    ) async {
      final Size standard = await _measure(
        tester,
        const AppShell(),
        find.text('Sky'),
      );
      final Size littleKids = await _measure(
        tester,
        const AppShell(),
        find.text('Sky'),
        controlScale: kLittleKidsControlScale,
      );

      expect(
        standard.height,
        greaterThanOrEqualTo(littleKidsFloor),
        reason: 'the 70dp bar is what makes not scaling the nav free',
      );
      expect(
        littleKids,
        standard,
        reason: '🧸 mode must not reflow a bar the whole app sits above',
      );
    });

    testWidgets('a settings toggle row clears the floor from its content', (
      tester,
    ) async {
      final Size standard = await _measure(
        tester,
        const SettingsScreen(),
        find.textContaining('Calm'),
      );
      final Size littleKids = await _measure(
        tester,
        const SettingsScreen(),
        find.textContaining('Calm'),
        controlScale: kLittleKidsControlScale,
      );

      expect(standard.height, greaterThanOrEqualTo(littleKidsFloor));
      expect(littleKids, standard);
    });

    testWidgets('a game card clears the floor several times over', (
      tester,
    ) async {
      final Size standard = await _measure(
        tester,
        const GamesHub(),
        find.text('Power Duel'),
      );
      final Size littleKids = await _measure(
        tester,
        const GamesHub(),
        find.text('Power Duel'),
        controlScale: kLittleKidsControlScale,
      );

      expect(standard.height, greaterThanOrEqualTo(littleKidsFloor));
      expect(littleKids, standard);
    });
  });

  testWidgets('the Settings row sits at the floor, and stays there in 🧸 mode', (
    tester,
  ) async {
    // **The one real decision of the five, so the one assertion that pins a
    // number.** Unlike the three above, this row's floor genuinely binds — it
    // measures exactly `kMinTapTarget` — so scaling it *would* change what
    // renders, to 60dp. The choice is to leave it: this is the app's only door
    // into the grown-up screen, placed at the foot of Profile precisely so a
    // child hunting badges never lands on it, and widening that door by a
    // quarter in the mode built for four-year-olds works against its own
    // placement.
    //
    // Both halves are asserted because each fails a different mistake: the
    // equality catches the row drifting off the commitment
    // (`specs/08-settings-about.md:82`), and the invariance catches a future
    // `ControlScale` sweep quietly taking it to 60 without reading any of this.
    final Finder row = find.text('Settings');

    final Size standard = await _measure(
      tester,
      const MySpaceZooScreen(),
      row,
      scrollTo: true,
    );
    final Size littleKids = await _measure(
      tester,
      const MySpaceZooScreen(),
      row,
      scrollTo: true,
      controlScale: kLittleKidsControlScale,
    );

    expect(
      standard.height,
      kMinTapTarget,
      reason: 'the grown-up door meets the 48dp commitment exactly',
    );
    expect(
      littleKids.height,
      kMinTapTarget,
      reason: '🧸 mode deliberately does not widen the way out to Settings',
    );
  });
}

/// Mounts [home] and returns the size of the [InkWell] that [target] sits in —
/// the hittable region, which is the thing every claim here is about.
///
/// [ControlScale] is injected at the [MaterialApp] builder rather than left to
/// `littleKidsExperienceProvider`, matching `tap_target_audit_test.dart`: these
/// screens are mounted directly rather than under `RockimalsApp`, and the real
/// wiring is `app_test.dart`'s question.
Future<Size> _measure(
  WidgetTester tester,
  Widget home,
  Finder target, {
  double controlScale = 1,
  bool scrollTo = false,
}) async {
  tester.view
    ..physicalSize = const Size(390, 800)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // 🧸 Little Kids mode, which the radar's Play CTA resolves for its
        // game count — stubbed off like every store-backed read beside it.
        littleKidsModeProvider.overrideWith(StubLittleKids.new),
        asteroidFeedProvider.overrideWith((Ref ref) => AsteroidFeed.fallback()),
        dayStreakProvider.overrideWithValue(0),
        storeProvider.overrideWithValue(MemoryStore()),
        soundEngineProvider.overrideWithValue(RecordingSoundEngine()),
      ],
      child: MaterialApp(
        builder: (BuildContext context, Widget? child) =>
            ControlScale(scale: controlScale, child: child!),
        home: home,
      ),
    ),
  );
  // Pumped rather than settled: the radar's ticker under [AppShell] never
  // stops, so `pumpAndSettle` would time out.
  await tester.pump(const Duration(milliseconds: 100));

  if (scrollTo) {
    await tester.scrollUntilVisible(target, 200);
    await tester.pump();
  }

  expect(target, findsOneWidget, reason: 'nothing was measured');
  return tester.getSize(
    find.ancestor(of: target, matching: find.byType(InkWell)).first,
  );
}

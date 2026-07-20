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
import 'package:rockimals/core/audio/sound_cues.dart';
import 'package:rockimals/core/audio/sound_engine.dart';
import 'package:rockimals/core/storage/store.dart';
import 'package:rockimals/features/data/providers.dart';
import 'package:rockimals/features/games/games_hub.dart';
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
      expect(
        find.byType(MySpaceZooScreen, skipOffstage: false),
        findsOneWidget,
      );
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

  group('the replayable game guide', () {
    testWidgets('opens from Settings and records that the guide was shown', (
      tester,
    ) async {
      late Store store;
      await _openSettings(tester, onStore: (Store value) => store = value);
      await tester.scrollUntilVisible(
        find.text('Play the game guide again'),
        200,
      );

      await tester.tap(find.text('Play the game guide again'));
      await tester.pumpAndSettle();
      expect(find.text('Welcome to Play!'), findsOneWidget);

      await tester.tap(find.text('Skip tutorial'));
      await tester.pump();
      expect(store.gameTutorialProgress, contains('guide'));
      expect(find.byType(SettingsScreen), findsOneWidget);
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
        tester
            .widget<Scaffold>(
              find.descendant(
                of: find.byType(SettingsScreen),
                matching: find.byType(Scaffold),
              ),
            )
            .bottomNavigationBar,
        isNull,
      );
    });
  });

  /// The 🐢 Calm motion toggle (`specs/08-settings-about.md:47-50`). What the
  /// setting *does* is pinned where it does it — `radar_view_test.dart` for the
  /// drift, `reaction_test.dart` for the hop — and what it survives is pinned in
  /// `store_test.dart` against a real reopened box. This group owns the surface:
  /// the row exists, it says the right words, it is big enough, it shows the
  /// right state, and a tap reaches the store.
  group('the 🐢 Calm motion toggle', () {
    testWidgets('is on the Settings screen, labelled for a child', (
      tester,
    ) async {
      await _openSettings(tester);

      expect(find.text('Calm motion'), findsOneWidget);
      expect(find.text('🐢'), findsOneWidget);
      expect(_switchFor('Calm motion'), findsOneWidget);
    });

    testWidgets('never says "reduced motion" anywhere on the screen', (
      tester,
    ) async {
      // `specs/08-settings-about.md:47-48` and `CLAUDE.md`'s gentle-tone rule.
      // The phrase names the key and the OS flag and belongs in neither the
      // label nor the hint. Asserted by sweeping every string the screen
      // renders, so it also catches the About block's copy when that lands.
      await _openSettings(tester);

      final Iterable<String> copy = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byType(SettingsScreen),
              matching: find.byType(Text),
            ),
          )
          .map((Text t) => (t.data ?? '').toLowerCase());

      expect(
        copy,
        isNotEmpty,
        reason: 'the sweep must have something to sweep',
      );
      for (final String line in copy) {
        expect(line, isNot(contains('reduced motion')));
        expect(line, isNot(contains('reduce motion')));
      }
    });

    testWidgets('is off on a fresh install with no OS flag set', (
      tester,
    ) async {
      await _openSettings(tester);

      expect(tester.widget<Switch>(_switchFor('Calm motion')).value, isFalse);
    });

    testWidgets('shows on when the OS asks for it and the child never chose', (
      tester,
    ) async {
      // `specs/08-settings-about.md:76` — the first-run default *is* the OS
      // flag, and the switch has to show that rather than quietly disagreeing
      // with the radar behind it.
      await _openSettings(tester, osDisablesAnimations: true);

      expect(tester.widget<Switch>(_switchFor('Calm motion')).value, isTrue);
    });

    testWidgets('shows the child\'s "off" even while the OS flag is on', (
      tester,
    ) async {
      // `:77`, and the reason [Store.reducedMotion] keeps a third state: a
      // stored `false` is a decision, not an absence, and it outranks the OS.
      await _openSettings(
        tester,
        reducedMotion: false,
        osDisablesAnimations: true,
      );

      expect(tester.widget<Switch>(_switchFor('Calm motion')).value, isFalse);
    });

    testWidgets('writes the child\'s choice to the store when tapped', (
      tester,
    ) async {
      // The half of "persists across a restart"
      // (`specs/08-settings-about.md:73`) that this screen owns: the value
      // reaches the store. That the store then survives a reopen is
      // `store_test.dart`'s question, asked there against a real Hive box —
      // a `MemoryStore` could not answer it honestly.
      late final Store store;
      await _openSettings(tester, onStore: (Store s) => store = s);
      expect(store.reducedMotion, isNull, reason: 'the premise: never chosen');

      await tester.tap(find.text('Calm motion'));
      await tester.pumpAndSettle();

      expect(store.reducedMotion, isTrue);
      expect(tester.widget<Switch>(_switchFor('Calm motion')).value, isTrue);
    });

    testWidgets('turns back off, storing a real false rather than clearing it', (
      tester,
    ) async {
      // Off must be written, not erased. Were the "off" tap to reset the key to
      // null, a child on a phone with the OS flag on could never turn Calm
      // motion off — it would come straight back on the next build.
      late final Store store;
      await _openSettings(
        tester,
        reducedMotion: true,
        osDisablesAnimations: true,
        onStore: (Store s) => store = s,
      );

      await tester.tap(find.text('Calm motion'));
      await tester.pumpAndSettle();

      expect(store.reducedMotion, isFalse);
      expect(tester.widget<Switch>(_switchFor('Calm motion')).value, isFalse);
    });

    testWidgets('takes a tap on the words, not only on the switch', (
      tester,
    ) async {
      // A [Switch] is a small target at the far edge of the screen. A child
      // aiming at the label — which is what reads as the button — would
      // otherwise hit nothing at all.
      late final Store store;
      await _openSettings(tester, onStore: (Store s) => store = s);

      await tester.tap(
        find.text(
          'Slows the radar down and keeps the animals '
          'calmer.',
        ),
      );
      await tester.pumpAndSettle();

      expect(store.reducedMotion, isTrue);
    });

    testWidgets('is at least 48dp tall, and stays so at 1.5× text', (
      tester,
    ) async {
      // `specs/08-settings-about.md:82`, measured off the rendered box the same
      // way the two targets above are.
      await _openSettings(tester);
      expect(
        tester.getSize(_tappableAround(find.text('Calm motion'))).height,
        greaterThanOrEqualTo(48),
      );

      await _openSettings(tester, textScale: 1.5);
      expect(
        tester.getSize(_tappableAround(find.text('Calm motion'))).height,
        greaterThanOrEqualTo(48),
      );
    });

    testWidgets('speaks as one control, not an emoji and a stray switch', (
      tester,
    ) async {
      // A screen reader walking an emoji, two strings and an unlabelled switch
      // never says which setting the switch belongs to.
      await _openSettings(tester);

      expect(
        find.bySemanticsLabel(
          'Calm motion. Slows the radar down and keeps the animals calmer.',
        ),
        findsOneWidget,
      );
    });
  });

  /// The 🔊 Sound toggle (`specs/08-settings-about.md:46`, `:33-35`, and the
  /// acceptance criterion at `:78`: *"The sound toggle here and the one in the
  /// Play hub always agree"*).
  ///
  /// **The interesting claim is agreement, not that a switch exists**, and it is
  /// a claim about there being no second copy of the value. Two surfaces reading
  /// one [soundOnProvider] cannot disagree; two surfaces each caching a `bool`
  /// would, and only under a sequence nobody runs by hand. So the two tests that
  /// matter mount **both** surfaces at once, in one container, and flip each
  /// from the other side.
  ///
  /// What the toggle *does* — the gate on every cue — is pinned in
  /// `sound_controller_test.dart`, and that it survives a restart is pinned
  /// against a real reopened box in `games_hub_test.dart`. Neither is repeated
  /// here; this group owns the new surface.
  group('the 🔊 Sound toggle', () {
    testWidgets('is on the Settings screen, above Calm motion', (tester) async {
      // Order is spec 08's own list (`:45-53`), and it is the order a grown-up
      // scanning for the switch they came for expects to find it in.
      await _openSettings(tester);

      expect(find.text('Sound'), findsOneWidget);
      expect(find.text('🔊'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Sound')).dy,
        lessThan(tester.getTopLeft(find.text('Calm motion')).dy),
      );
    });

    testWidgets('shows on by default, the way a fresh install sounds', (
      tester,
    ) async {
      // [Store.soundOn] defaults to true — a game that starts silent reads as
      // broken — so the row must open showing that rather than its own idea.
      await _openSettings(tester);

      expect(tester.widget<Switch>(_switchFor('Sound')).value, isTrue);
    });

    testWidgets('shows off when the stored value is off', (tester) async {
      await _openSettings(tester, soundOn: false);

      expect(tester.widget<Switch>(_switchFor('Sound')).value, isFalse);
    });

    testWidgets('writes the flip to the store, both ways', (tester) async {
      // The half of "persists across a restart"
      // (`specs/08-settings-about.md:73`) this screen owns: the value reaches
      // the store. Both directions, because a toggle that can only write `false`
      // strands a child in silence.
      late final Store store;
      await _openSettings(tester, onStore: (Store s) => store = s);
      expect(store.soundOn, isTrue, reason: 'the premise: the default');

      await tester.tap(find.text('Sound'));
      await tester.pumpAndSettle();
      expect(store.soundOn, isFalse);
      expect(tester.widget<Switch>(_switchFor('Sound')).value, isFalse);

      await tester.tap(find.text('Sound'));
      await tester.pumpAndSettle();
      expect(store.soundOn, isTrue);
      expect(tester.widget<Switch>(_switchFor('Sound')).value, isTrue);
    });

    testWidgets('turning sound on from here answers with the happy jingle', (
      tester,
    ) async {
      // The confirmation blip (`if(soundOn)playHappy()`, `index.html:1020`) was
      // the Play hub button's alone while that button was the only flip point.
      // A child who turns sound back on from *here* has exactly the same
      // question — "did that do anything?" — and a Switch sliding across answers
      // it no better than an emoji did. The rule now lives in
      // `SoundOnNotifier.toggle`, so this surface inherits it; this test is what
      // says the inheritance is real rather than assumed.
      late final RecordingSoundEngine engine;
      await _openSettings(
        tester,
        soundOn: false,
        onEngine: (RecordingSoundEngine e) => engine = e,
      );

      await tester.tap(find.text('Sound'));
      await tester.pumpAndSettle();

      expect(tester.widget<Switch>(_switchFor('Sound')).value, isTrue);
      expect(engine.played, <SoundCue>[SoundCue.happy]);
    });

    testWidgets('turning sound off from here is silent', (tester) async {
      // The other half, and the one a mutation would slip past: a blip fired on
      // every flip rather than only on the way on would still pass the test
      // above while contradicting itself out loud.
      late final RecordingSoundEngine engine;
      await _openSettings(
        tester,
        onEngine: (RecordingSoundEngine e) => engine = e,
      );

      await tester.tap(find.text('Sound'));
      await tester.pumpAndSettle();

      expect(tester.widget<Switch>(_switchFor('Sound')).value, isFalse);
      expect(engine.played, isEmpty);
    });

    testWidgets('the Play hub follows a flip made in Settings, at once', (
      tester,
    ) async {
      // `specs/08-settings-about.md:78`. Both surfaces mounted together, so
      // "immediately" is literal: one pump, no navigation, no reload.
      await tester.pumpWidget(_bothSurfaces());
      expect(find.text('🔇'), findsNothing);

      await tester.tap(find.text('Sound'));
      await tester.pump();

      // The hub's button is the emoji; the Settings row's 🔊 is its own glyph
      // and does not change with the state, which is why this asserts the
      // *muted* one appearing rather than the loud one going away.
      expect(find.text('🔇'), findsOneWidget);
      expect(tester.widget<Switch>(_switchFor('Sound')).value, isFalse);
    });

    testWidgets('Settings follows a flip made in the Play hub, at once', (
      tester,
    ) async {
      // The other direction, and not a mirror of the test above: the hub writes
      // through its own handler, so a regression that made *it* the owner of a
      // private copy would pass the first test and fail this one.
      await tester.pumpWidget(_bothSurfaces());
      expect(tester.widget<Switch>(_switchFor('Sound')).value, isTrue);

      await tester.tap(find.bySemanticsLabel('Sound').first);
      await tester.pump();

      expect(tester.widget<Switch>(_switchFor('Sound')).value, isFalse);
      expect(find.text('🔇'), findsOneWidget);
    });

    testWidgets('is at least 48dp tall, and stays so at 1.5× text', (
      tester,
    ) async {
      // `specs/08-settings-about.md:82`, measured off the rendered box like
      // every other target in this file.
      await _openSettings(tester);
      expect(
        tester.getSize(_tappableAround(find.text('Sound'))).height,
        greaterThanOrEqualTo(48),
      );

      await _openSettings(tester, textScale: 1.5);
      expect(
        tester.getSize(_tappableAround(find.text('Sound'))).height,
        greaterThanOrEqualTo(48),
      );
    });

    testWidgets('speaks as one control', (tester) async {
      await _openSettings(tester);

      expect(
        find.bySemanticsLabel(
          'Sound. Plays happy little sounds in the games and when you win a '
          'badge.',
        ),
        findsOneWidget,
      );
    });
  });

  /// The 🧸 Little Kids mode toggle (`specs/08-settings-about.md:51-53`).
  ///
  /// **What the setting does is nothing, in v1, and that is pinned next door**
  /// in `little_kids_mode_test.dart` — spec 08 allows the body to be a no-op and
  /// the extension point behind it is where that claim belongs. This group owns
  /// the surface, on the same terms as the two rows above it: the row exists, it
  /// says the right words, it is big enough, it shows the right state, and a tap
  /// reaches the store.
  group('the 🧸 Little Kids mode toggle', () {
    testWidgets('is on the Settings screen, below Calm motion', (tester) async {
      // Order is spec 08's own list (`:45-53`): Sound, Calm motion, Little Kids
      // mode, then About.
      await _openSettings(tester);

      expect(find.text('Little Kids mode'), findsOneWidget);
      expect(find.text('🧸'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Little Kids mode')).dy,
        greaterThan(tester.getTopLeft(find.text('Calm motion')).dy),
      );
    });

    testWidgets('sits above the About block, not below it', (tester) async {
      // The other half of its position, and the one a later edit is likelier to
      // get wrong: About is the change of subject at the foot of the screen, so
      // a toggle that drifted under it would read as part of the small print.
      await _openSettings(tester);

      expect(
        tester.getTopLeft(find.text('Little Kids mode')).dy,
        lessThan(
          tester.getTopLeft(find.textContaining('Asteroid data from NASA')).dy,
        ),
      );
    });

    testWidgets('promises nothing that has not shipped', (tester) async {
      // **The honesty check, and it is a product requirement rather than a copy
      // preference** (`specs/08-settings-about.md:69` forbids dead ends).
      //
      // Its first form was the mirror of this one: while the mode was a no-op
      // the hint *had* to end "coming soon", and the words were asserted present
      // so that shipping the behaviour would fail here and force the copy to be
      // rewritten. It did. Now the switch does something, so the assertion turns
      // over: no promise of a feature a grown-up cannot get.
      //
      // **It turns over once per affordance, and this is the second turn.**
      // Bigger buttons has shipped, so the words that were asserted *absent*
      // here are now asserted present. Read-aloud has not, so it keeps the
      // absent half — this still catches a well-meant re-listing of all three.
      await _openSettings(tester);

      expect(find.textContaining('coming soon'), findsNothing);
      expect(find.textContaining('Read-aloud'), findsNothing);
      // What it says instead: the two things that actually happen.
      expect(find.textContaining('Bigger buttons'), findsOneWidget);
      expect(find.textContaining('two simplest games'), findsOneWidget);
    });

    testWidgets('is off on a fresh install', (tester) async {
      await _openSettings(tester);

      expect(
        tester.widget<Switch>(_switchFor('Little Kids mode')).value,
        isFalse,
      );
    });

    testWidgets('shows on when the stored value is on', (tester) async {
      await _openSettings(tester, littleKidsMode: true);

      expect(
        tester.widget<Switch>(_switchFor('Little Kids mode')).value,
        isTrue,
      );
    });

    testWidgets('writes the flip to the store, both ways', (tester) async {
      // The half of "all three toggles persist across a restart"
      // (`specs/08-settings-about.md:73`) this screen owns: the value reaches
      // the store. That the store survives a reopen is `store_test.dart`'s
      // question, asked there against a real Hive box.
      late final Store store;
      await _openSettings(tester, onStore: (Store s) => store = s);
      expect(store.littleKidsMode, isFalse, reason: 'the premise: the default');

      await tester.tap(find.text('Little Kids mode'));
      await tester.pumpAndSettle();
      expect(store.littleKidsMode, isTrue);
      expect(
        tester.widget<Switch>(_switchFor('Little Kids mode')).value,
        isTrue,
      );

      await tester.tap(find.text('Little Kids mode'));
      await tester.pumpAndSettle();
      expect(store.littleKidsMode, isFalse);
      expect(
        tester.widget<Switch>(_switchFor('Little Kids mode')).value,
        isFalse,
      );
    });

    testWidgets('is at least 48dp tall, and stays so at 1.5× text', (
      tester,
    ) async {
      // `specs/08-settings-about.md:82`, measured off the rendered box like
      // every other target in this file.
      await _openSettings(tester);
      expect(
        tester.getSize(_tappableAround(find.text('Little Kids mode'))).height,
        greaterThanOrEqualTo(48),
      );

      await _openSettings(tester, textScale: 1.5);
      expect(
        tester.getSize(_tappableAround(find.text('Little Kids mode'))).height,
        greaterThanOrEqualTo(48),
      );
    });

    testWidgets('speaks as one control', (tester) async {
      await _openSettings(tester);

      expect(
        find.bySemanticsLabel(
          'Little Kids mode. Bigger buttons, and only the two simplest games: '
          'Power Duel and Closer or Farther.',
        ),
        findsOneWidget,
      );
    });
  });
}

/// Opens the Settings screen from the Profile tab, the way a child does.
///
/// Scrolled to first, as every test in this file must: the row is the last thing
/// on a tab taller than any phone, so a default finder looks straight past it.
///
/// **Both the OS flag and the text scale are set on the platform dispatcher
/// rather than by wrapping the tree in a [MediaQuery], and that is not a style
/// choice.** Settings is a *pushed route*: it hangs off the [Navigator], which
/// is an ancestor of `home`, so a `MediaQuery` placed under `home` — the way
/// [_app] sets the scale for the Profile row — is nowhere in this screen's
/// ancestry and reaches nothing it renders. The only copy it can see is
/// `MaterialApp`'s own `MediaQuery.fromView`, and the way to move that is to
/// move what the view reports. An assertion written the other way passes while
/// measuring the default.
Future<void> _openSettings(
  WidgetTester tester, {
  double textScale = 1,
  bool? reducedMotion,
  bool soundOn = true,
  bool littleKidsMode = false,
  bool osDisablesAnimations = false,
  void Function(Store store)? onStore,
  void Function(RecordingSoundEngine engine)? onEngine,
}) async {
  if (osDisablesAnimations) {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  }
  if (textScale != 1) {
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  await tester.pumpWidget(
    _app(
      reducedMotion: reducedMotion,
      soundOn: soundOn,
      littleKidsMode: littleKidsMode,
      onStore: onStore,
      onEngine: onEngine,
    ),
  );
  await tester.scrollUntilVisible(find.text('Settings'), 200);
  await tester.tap(find.text('Settings'));
  await tester.pumpAndSettle();
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

/// The [Switch] belonging to the settings row labelled [label].
///
/// **Scoped rather than `find.byType(Switch)`**, which is what these assertions
/// said while Calm motion was the only row. That finder was correct exactly once
/// and would have silently started measuring whichever switch the tree happened
/// to lay out first as soon as a second one landed — so it is scoped by the row
/// a child actually reads, not by index.
Finder _switchFor(String label) => find.descendant(
  of: _tappableAround(find.text(label)),
  matching: find.byType(Switch),
);

/// The Profile tab under a real [Navigator], because every assertion here is
/// about pushing off it. The store and the sound engine are faked for the
/// reason `my_space_zoo_screen_test.dart` states: this screen reads the store in
/// its first frame, and a badge earned mid-test would otherwise reach the real
/// engine.
Widget _app({
  double textScale = 1,

  /// The child's stored 🐢 Calm motion choice, or null for "never chose".
  bool? reducedMotion,

  /// The stored 🔊 Sound value. True is [Store.soundOn]'s own default.
  bool soundOn = true,

  /// The stored 🧸 Little Kids mode value. False is the fresh-install state,
  /// and — unlike Calm motion — there is no third "never chose" to express.
  bool littleKidsMode = false,

  /// Handed back so a test can ask what the toggle wrote.
  void Function(Store store)? onStore,

  /// Handed back so a test can ask what the toggle *played*.
  void Function(RecordingSoundEngine engine)? onEngine,
}) {
  final Store store = MemoryStore(
    points: 142,
    bestStreak: 7,
    reducedMotion: reducedMotion,
    soundOn: soundOn,
    littleKidsMode: littleKidsMode,
  );
  onStore?.call(store);

  final RecordingSoundEngine engine = RecordingSoundEngine();
  onEngine?.call(engine);

  return UncontrolledProviderScope(
    container: _container(store, engine),
    child: MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: const Scaffold(body: MySpaceZooScreen()),
      ),
    ),
  );
}

/// The Play hub and the Settings screen mounted side by side over **one**
/// container — the only arrangement in which "the two toggles always agree"
/// (`specs/08-settings-about.md:78`) is a claim a test can make about the same
/// instant rather than about two runs stitched together.
///
/// It is not how a child meets either screen, and that is fine: what is under
/// test is the wiring behind both, and a route push in between would add a
/// `pumpAndSettle` that hides whether the second surface reacted on the frame of
/// the tap or merely rebuilt on arrival.
Widget _bothSurfaces() {
  return UncontrolledProviderScope(
    container: _container(MemoryStore(points: 142, bestStreak: 7)),
    child: const MaterialApp(
      home: Column(
        children: <Widget>[
          Expanded(child: GamesHub()),
          Expanded(child: SettingsScreen()),
        ],
      ),
    ),
  );
}

/// A container over [store] with the sound engine recorded rather than played.
///
/// The engine is faked for the reason `my_space_zoo_screen_test.dart` states:
/// the Profile reads the store in its first frame, and a badge earned mid-test
/// would otherwise reach the real one. `badgesProvider` is read eagerly here so
/// that ledger is warm before anything mounts.
ProviderContainer _container(Store store, [RecordingSoundEngine? engine]) {
  final ProviderContainer container = ProviderContainer(
    overrides: [
      storeProvider.overrideWithValue(store),
      soundEngineProvider.overrideWithValue(engine ?? RecordingSoundEngine()),
    ],
  );
  addTearDown(container.dispose);
  container.read(badgesProvider);
  return container;
}

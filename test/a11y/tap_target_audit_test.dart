import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/core/a11y/control_scale.dart';
import 'package:rockimals/core/audio/sound_engine.dart';
import 'package:rockimals/data/models/asteroid.dart';
import 'package:rockimals/data/models/asteroid_feed.dart';
import 'package:rockimals/features/data/providers.dart';
import 'package:rockimals/features/detail/detail_screen.dart';
import 'package:rockimals/features/games/challenge_game.dart';
import 'package:rockimals/features/games/closer_game.dart';
import 'package:rockimals/features/games/duel_game.dart';
import 'package:rockimals/features/games/games_hub.dart';
import 'package:rockimals/features/games/match_game.dart';
import 'package:rockimals/features/radar/radar_geometry.dart';
import 'package:rockimals/features/radar/radar_painter.dart';
import 'package:rockimals/features/settings/little_kids_mode.dart';
import 'package:rockimals/features/settings/settings_screen.dart';
import 'package:rockimals/features/shell/app_shell.dart';
import 'package:rockimals/features/title/title_screen.dart';

import '../support/memory_store.dart';
import '../support/recording_sound_engine.dart';
import '../support/tap_target_audit.dart';

/// **The app-wide tap-target audit** — `specs/06-title-polish-safety.md:21`
/// ("large, well-spaced tap targets everywhere") and
/// `specs/08-settings-about.md:82` ("Every tap target is ≥48dp").
///
/// This is the automatable half of the accessibility item. It mounts every
/// screen a child can reach and walks the rendered tree, rather than asserting
/// button by button, because the failure worth catching is the button *nobody
/// thought to write a test for* — a pill copied from an older pill, a chip whose
/// padding was tuned by eye. See `test/support/tap_target_audit.dart` for how a
/// hittable region is identified and why the rule is one report per region.
///
/// **Screen coverage is not the whole of the question, and this file used to
/// claim it was.** A screen is not one tree; it is a tree per state it can be
/// in, and a walk that reaches tabs by tapping their labels only ever sees the
/// state each tab opens in. That is not hypothetical — the radar's HUD card is a
/// *state* of the radar tab, and two 31dp buttons lived in it, one of them the
/// primary route into the detail screen, for as long as this doc said "every
/// screen a child can reach" and meant it. The `on the selected-animal card`
/// arm below is that hole, closed next to the walk that missed it;
/// `tap_target_states_test.dart` is the general form — the named list of the
/// other states, from a game's revealed answer to the panel it ends on.
///
/// **Both text scales are audited, and the second one is the point.** A target
/// that clears 48 only because its label happens to be 15px is not a target that
/// clears 48 — a child whose grown-up has turned the system font up is the child
/// most likely to need the big target in the first place. The settings suite
/// established this convention on its two rows; this generalises it to the app.
///
/// What this **cannot** check is on the far side of the HUMAN-GATED Xcode /
/// Android SDK item: real fingers, real DPI, and iOS/Android divergence. dp is
/// dp in `flutter_tester`, so the geometry here is honest, but "comfortable to
/// tap" finally needs a device and a five-year-old.
void main() {
  group('every tap target is at least 48dp', () {
    for (final double scale in <double>[1.0, 1.5]) {
      final String at = scale == 1.0 ? '' : ' at $scale× text';

      testWidgets('on the title screen$at', (tester) async {
        await _pump(tester, const TitleScreen(), scale: scale);
        expectEveryTapTargetIsBigEnough(tester, reason: 'Title$at');
      });

      testWidgets('on all four shell tabs$at', (tester) async {
        await _pump(tester, const AppShell(), scale: scale);
        // The radar is the tab the shell opens on, so it is audited before any
        // tap. The other three are reached the way a child reaches them.
        expectEveryTapTargetIsBigEnough(tester, reason: 'Radar tab$at');

        for (final String tab in <String>['Sky', 'Watchlist', 'Profile']) {
          await tester.tap(find.text(tab));
          await tester.pump(const Duration(milliseconds: 100));
          expectEveryTapTargetIsBigEnough(tester, reason: '$tab tab$at');
        }
      });

      testWidgets('on the selected-animal card$at', (tester) async {
        // **The state the walk above cannot reach by tapping tab labels**, and
        // the hole that hid a real violation: the radar's HUD card only exists
        // once an animal has been selected, so its two buttons — Meet, the
        // primary way into the whole detail screen, and Follow — sat at 31dp
        // for as long as this audit only ever visited the unselected radar.
        // Auditing the tab is not auditing the tab's states.
        await _pump(tester, const AppShell(), scale: scale);
        await _selectAnimal(tester);
        expect(
          find.textContaining('Meet '),
          findsOneWidget,
          reason: 'the card did not open, so this arm audited nothing',
        );
        expectEveryTapTargetIsBigEnough(tester, reason: 'Selected animal$at');
      });

      testWidgets('on the detail screen$at', (tester) async {
        await _pump(tester, const DetailScreen(asteroid: _rock), scale: scale);
        expectEveryTapTargetIsBigEnough(tester, reason: 'Detail$at');
      });

      testWidgets('on the parent gate$at', (tester) async {
        // The one dialog in the app, and the one gate on the one external link
        // — so the one place where a mis-sized button costs a grown-up the
        // ability to use the feature at all.
        await _pump(tester, const DetailScreen(asteroid: _rock), scale: scale);
        // The link is the last thing on a long scrolling screen, and at 1.5×
        // text it is further down still — so it has to be scrolled to rather
        // than tapped where it would be on a taller phone.
        final Finder link = find.text('Look it up on NASA/JPL ↗');
        await tester.scrollUntilVisible(link, 200);
        await tester.tap(link);
        await tester.pumpAndSettle();

        expect(
          find.text('Open ↗'),
          findsOneWidget,
          reason: 'gate did not open',
        );
        expectEveryTapTargetIsBigEnough(tester, reason: 'Parent gate$at');
      });

      testWidgets('on the Play hub$at', (tester) async {
        await _pump(tester, const GamesHub(), scale: scale);
        expectEveryTapTargetIsBigEnough(tester, reason: 'Play hub$at');
      });

      testWidgets('on the settings screen$at', (tester) async {
        await _pump(tester, const SettingsScreen(), scale: scale);
        expectEveryTapTargetIsBigEnough(tester, reason: 'Settings$at');
      });

      testWidgets('in all four games$at', (tester) async {
        // Every game, not a sample: an answer card is the control a child taps
        // most in the whole app, and the four games build theirs separately.
        final Map<String, Widget> games = <String, Widget>{
          'Challenge': const ChallengeGame(),
          'Duel': const DuelGame(),
          'Closer': const CloserGame(),
          'Match': const MatchGame(),
        };

        for (final MapEntry<String, Widget> game in games.entries) {
          await _pump(tester, game.value, scale: scale);
          expectEveryTapTargetIsBigEnough(tester, reason: '${game.key}$at');
        }
      });
    }
  });

  group('🧸 Little Kids mode only ever makes targets bigger', () {
    // **The bigger-controls item's "still passes the audit at 1.5× text"
    // criterion**, and it is asking two questions at once.
    //
    // The first is nearly free: the multiplier raises `kMinTapTarget`'s floor,
    // so no target can shrink and the ≥48dp bar cannot start failing. Running
    // the audit anyway is cheap insurance against a future affordance that
    // scales something *down* to make room.
    //
    // The second is the one worth the wall-clock: **overflow**. Growing padding
    // and avatars inside fixed-height chrome is exactly how a screen starts
    // reporting a RenderFlex overflow, and 1.5× text on top of 1.25× controls is
    // the tightest the app is ever asked to be. An overflow throws a
    // [FlutterError] that fails the test outright, so simply mounting each
    // screen here is the assertion — `expectEveryTapTargetIsBigEnough` is the
    // second one.
    const double worst = 1.5;

    testWidgets('on all four shell tabs at $worst× text', (tester) async {
      await _pump(
        tester,
        const AppShell(),
        scale: worst,
        controlScale: kLittleKidsControlScale,
      );
      // The Sky and Watchlist tabs are the reason this case is not redundant
      // with the ones above: `AnimalCard` is the shared row the affordance
      // grows, and those two tabs are the only places it renders.
      expectEveryTapTargetIsBigEnough(tester, reason: 'Radar tab, little kids');

      for (final String tab in <String>['Sky', 'Watchlist', 'Profile']) {
        await tester.tap(find.text(tab));
        await tester.pump(const Duration(milliseconds: 100));
        expectEveryTapTargetIsBigEnough(
          tester,
          reason: '$tab tab, little kids',
        );
      }
    });

    testWidgets('on the selected-animal card at $worst× text', (tester) async {
      // Two [TapTarget] pills side by side in a flex row, inside a HUD card
      // that floats over a live radar — so this is where a 60dp floor under a
      // 1.5× label has the least room to grow into before it overflows.
      await _pump(
        tester,
        const AppShell(),
        scale: worst,
        controlScale: kLittleKidsControlScale,
      );
      await _selectAnimal(tester);
      expectEveryTapTargetIsBigEnough(
        tester,
        reason: 'Selected animal, little kids',
      );
    });

    testWidgets('on the detail screen at $worst× text', (tester) async {
      // Two `ActionButton`s side by side in a flex row — the one place in the
      // app where a wider button has a neighbour to collide with.
      await _pump(
        tester,
        const DetailScreen(asteroid: _rock),
        scale: worst,
        controlScale: kLittleKidsControlScale,
      );
      expectEveryTapTargetIsBigEnough(tester, reason: 'Detail, little kids');
    });

    testWidgets('on the Play hub and settings at $worst× text', (tester) async {
      await _pump(
        tester,
        const GamesHub(),
        scale: worst,
        controlScale: kLittleKidsControlScale,
      );
      expectEveryTapTargetIsBigEnough(tester, reason: 'Play hub, little kids');

      await _pump(
        tester,
        const SettingsScreen(),
        scale: worst,
        controlScale: kLittleKidsControlScale,
      );
      expectEveryTapTargetIsBigEnough(tester, reason: 'Settings, little kids');
    });

    testWidgets('in all four games at $worst× text', (tester) async {
      // The games stack full-width `ActionButton`s and are where a child taps
      // most, so they get the same coverage here as in the audit above.
      final Map<String, Widget> games = <String, Widget>{
        'Challenge': const ChallengeGame(),
        'Duel': const DuelGame(),
        'Closer': const CloserGame(),
        'Match': const MatchGame(),
      };

      for (final MapEntry<String, Widget> game in games.entries) {
        await _pump(
          tester,
          game.value,
          scale: worst,
          controlScale: kLittleKidsControlScale,
        );
        expectEveryTapTargetIsBigEnough(
          tester,
          reason: '${game.key}, little kids',
        );
      }
    });
  });

  testWidgets('the audit can actually fail', (tester) async {
    // A tree-walking assertion that silently matches nothing is the most
    // expensive kind of green test: it would have passed on every screen above
    // even with the walk broken, and nobody would look at it again. So: a
    // deliberately 20dp button, and the audit must name it and its size.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Semantics(
              button: true,
              label: 'Far too small',
              child: SizedBox(
                width: 20,
                height: 20,
                child: InkWell(onTap: () {}, child: const SizedBox.shrink()),
              ),
            ),
          ),
        ),
      ),
    );

    final List<TapTargetViolation> found = tapTargetViolations(tester);

    expect(found, hasLength(1));
    expect(found.single.size, const Size(20, 20));
    expect(found.single.toString(), contains('Far too small'));
  });
}

/// Taps the first animal on the live radar and lets its card finish sliding up,
/// so the HUD buttons are measured where a finger would actually find them.
///
/// Driven through the real field — the painter's own geometry, the same way
/// `selected_animal_card_test.dart` does it — rather than by reaching for a
/// private selection hook, because the point of this file is to audit what a
/// child's taps actually produce.
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
  await tester.pump(
    const Duration(milliseconds: 250),
  ); // finish the 200ms slide
}

/// Mounts [home] with the feed, streak and store all stood in front of, so no
/// screen in this file touches the network or a Hive box.
///
/// The feed is [AsteroidFeed.fallback] — the 14 bundled sample rocks — rather
/// than a one-rock stub, because a tap target is a layout question and layout is
/// what a realistic list changes. It also resolves immediately, which is what
/// anything under [AppShell] needs: the shell reads `requireValue`, so a pending
/// override would throw on the first build (see the plan's note on this trap).
Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  required double scale,
  double controlScale = 1,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        asteroidFeedProvider.overrideWith((Ref ref) => AsteroidFeed.fallback()),
        dayStreakProvider.overrideWithValue(0),
        storeProvider.overrideWithValue(MemoryStore()),
        // The walk taps its way through all four games, and an answer plays a
        // cue. Nothing here asserts on sound; this keeps the audio plugin off
        // the path, which the audit had been getting away with only because a
        // real `ToneSoundEngine` failed *quietly* on a host VM. It no longer
        // does: the handoff is now bounded by a timer, and a timer still pending
        // when the tree is disposed fails the test outright.
        soundEngineProvider.overrideWithValue(RecordingSoundEngine()),
      ],
      child: MaterialApp(
        // [ControlScale] is injected here rather than left to come from
        // `littleKidsExperienceProvider`, because these screens are mounted
        // directly rather than under `RockimalsApp` — which is where the real
        // wiring lives, and is `app_test.dart`'s question, not this file's.
        builder: (BuildContext context, Widget? child) => ControlScale(
          scale: controlScale,
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
  // Pumped rather than settled: the radar's ticker and the title's bob never
  // stop, so `pumpAndSettle` would time out on the two busiest screens here.
  await tester.pump(const Duration(milliseconds: 100));
}

/// A close flyby, so the surfaces that only render for one — the radar's wave
/// and name label, the amber badge — are on screen while the walk runs.
const Asteroid _rock = Asteroid(
  name: '2004 BL86',
  diaMin: 250,
  diaMax: 560,
  velKps: 15.6,
  missKm: 1200000,
  missLunar: 3.1,
  hazardous: true,
  mag: 19.1,
  jpl: 'https://ssd.jpl.nasa.gov/tools/sbdb_lookup.html',
  date: '2026-07-18',
);

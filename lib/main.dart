import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// `Override` is not exported from the package root — Riverpod 3 parks the types
// you mostly need in a test under `misc.dart`, alongside `ProviderException`.
import 'package:flutter_riverpod/misc.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:rockimals/core/a11y/control_scale.dart';
import 'package:rockimals/core/lifecycle/app_resume_host.dart';
import 'package:rockimals/core/storage/store.dart';
import 'package:rockimals/core/streak/day_streak.dart';
import 'package:rockimals/core/theme/palette.dart';
import 'package:rockimals/features/data/providers.dart';
import 'package:rockimals/features/rewards/badge_popup.dart';
import 'package:rockimals/features/settings/little_kids_mode.dart';
import 'package:rockimals/features/title/title_screen.dart';

Future<void> main() async {
  // Explicit rather than left to `Hive.initFlutter()`, which calls it too:
  // depending on that would make the binding's existence a side effect of a
  // storage call, and the next line added above it would break in a way that
  // reads as a Hive bug.
  WidgetsFlutterBinding.ensureInitialized();
  runApp(await bootstrap());
}

/// The cold-launch sequence: everything that must be finished before the first
/// frame, and nothing that can wait until after it.
///
/// Only the store qualifies today. The sky does not — [asteroidFeedProvider]
/// loads behind "Contacting NASA…" precisely because a request over a phone
/// network is not something to hold a blank screen for. A child's points and
/// followed animals are the opposite: they are already on the disk, they take
/// microseconds, and showing zero of them for one frame before they pop in is
/// how an app tells a child it lost their things.
///
/// Returns the root widget rather than calling `runApp` itself so this is
/// testable — the property worth pinning is that the store is *live at first
/// paint*, and a function that painted as a side effect could not be asked.
/// `runApp(await bootstrap())` is also the shape that makes the ordering
/// unmissable: there is no frame for a lazily-opened box to slip into.
///
/// [overrides] is the seam a test uses to stand something in front of the real
/// thing, and it exists because the app now *paints a screen that loads the
/// sky*. Without it, a test of the boot sequence builds a live [Dio] and starts
/// a real request as a side effect of asking whether the store is open —
/// leaving the repository's ten-second ceiling pending at teardown, and resting
/// on `flutter_test` happening to mock `HttpClient` to keep the request off a
/// real network. The production call passes nothing.
Future<Widget> bootstrap({
  List<Override> overrides = const <Override>[],
}) async {
  await Hive.initFlutter();
  final Store store = await Store.open();

  // The store first, so a test can still override it with its own.
  final List<Override> scoped = <Override>[
    storeProvider.overrideWithValue(store),
    ...overrides,
  ];

  // Opening Rockimals is the day's engagement (plan decisions 3/14), so the
  // consecutive-days-played streak is advanced here, before the first frame —
  // the same reason the store itself is opened here rather than lazily: the home
  // flame must be right at first paint, not a frame later.
  //
  // **The day comes from [dayClockProvider], read through a throwaway container
  // built from the very overrides the app is about to run under.** This line
  // used to call `DateTime.now()` inline, on the reasoning that the scope it
  // would read a clock from does not exist yet — which is true, and is why the
  // launch was the one day-streak trigger no test could drive on a chosen day.
  //
  // A `DateTime Function() now = DateTime.now` parameter would have been the
  // cheaper fix and was rejected: it makes the launch a *second* seam for a fact
  // the app already has one seam for, so a test that overrides the clock and
  // forgets the parameter gets the wall clock back at launch and nothing says
  // so. That is the exact split the sky's two clocks had. One override now
  // dates the streak, the sky, and the games alike.
  //
  // The probe is safe to build and drop: [dayClockProvider] is a plain value
  // provider with no dependencies and nothing to dispose, and an `Override` is a
  // description rather than state, so reusing `scoped` in the real scope below
  // is not sharing anything.
  final ProviderContainer clockProbe = ProviderContainer(overrides: scoped);
  final DateTime Function() now = clockProbe.read(dayClockProvider);
  clockProbe.dispose();

  await DayStreak.record(store, now());

  return ProviderScope(overrides: scoped, child: const RockimalsApp());
}

class RockimalsApp extends ConsumerWidget {
  const RockimalsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // **🧸 Little Kids mode's bigger controls, injected once at the root.** The
    // shared chrome that obeys this — `TapTarget`, `ActionButton`, `AnimalCard`
    // — lives in `core/`, so it reads the number off an inherited widget rather
    // than watching this feature's provider; `control_scale.dart` argues that
    // direction. This line is the other end of it, and the only place in the app
    // where the setting and the widgets that honour it are connected.
    //
    // `watch` rather than `read`: flipping the switch must resize the controls
    // on the spot, the same bar the Calm motion and Sound rows are held to
    // (`specs/08-settings-about.md:75`). Rebuilding the whole [MaterialApp] is
    // the cost, and it is paid only on a settings toggle.
    final double controlScale = ref
        .watch(littleKidsExperienceProvider)
        .controlScale;

    return AppResumeHost(
      // The day the child is having, re-asked each time they come back to the
      // app. `bootstrap()` above answers it once per *process*, which is not the
      // same question: a phone locked with the radar open and unlocked the next
      // morning never cold-launches, so without this the home flame stays on
      // yesterday's count until the child force-quits or starts a game.
      //
      // `read` inside the callback rather than a `watch` up here, for two
      // reasons: this must not rebuild the whole app when the streak moves, and
      // `recordEngagementProvider` reads the store — which a widget test may
      // legitimately not have wired, and which it should only be made to answer
      // for if a resume actually happens.
      //
      // Unawaited because a lifecycle callback is synchronous. The write is a
      // Hive put of two small fields and nothing paints off its completion; the
      // flame repaints through the provider invalidation inside.
      onResume: () {
        unawaited(ref.read(recordEngagementProvider)());
        // The second thing a launch computes that a locked phone never
        // recomputes: the sky itself. `loadData()` runs once per process, so
        // without this the child above — the one whose flame has just rolled
        // over to a new day — is looking at yesterday's animals under a Sky tab
        // captioned today. The provider owns the "only if the day changed"
        // guard and the reason a refresh does not flash the loading screen.
        //
        // Synchronous and not unawaited, unlike the line above: this starts a
        // load and does not wait for one, so there is no future here to drop.
        ref.read(refreshSkyForNewDayProvider)();
      },
      child: MaterialApp(
        title: 'Rockimals',
        // **Every pointer a child (or a parent at a desk) might hold.** The
        // default [MaterialScrollBehavior] only lets touch and stylus *drag* a
        // scrollable, which is right on a phone and wrong everywhere the web
        // build runs: on the demo site a mouse user could see the Play hub's
        // "scroll down to explore" cue and still not reach the Build section,
        // because neither dragging nor (through some embedders) the wheel moved
        // the list. One behaviour at the root rather than per-screen
        // `ScrollConfiguration`s, for the reason the control scale is injected
        // once above: a scrollable added next month must not be able to forget
        // it.
        scrollBehavior: const AppScrollBehavior(),
        theme: ThemeData(
          // `flutter create` seeded this with `#5B7CFA`, a blue that appears
          // nowhere in the prototype. The seed is now `--accent`, and the reason
          // is what `--accent` *is*: the prototype's single interactive colour
          // (19 uses — every selected chip, every primary button, the play
          // control, the spinner's lit quarter). "Where the app says this does
          // something" is exactly what Material derives from a seed, so the two
          // agree about what they are for.
          colorScheme:
              ColorScheme.fromSeed(
                seedColor: Palette.accent,
                brightness: Brightness.dark,
              ).copyWith(
                // **The seed alone would be a lie, which is why these two are
                // pinned.** `fromSeed` does not hand back the colour it is given:
                // it runs the seed through a tonal palette and returns a
                // harmonised neighbour, so seeding with `--accent` and calling the
                // result the brand orange would ship an orange that is *not*
                // `#E8571F`. Pinning `primary` makes the claim true, and
                // `app_test.dart` asserts the inequality so this cannot be tidied
                // away as redundant.
                primary: Palette.accent,
                // And the prototype already answers the question `onPrimary` asks
                // — `.rchip.on` and `.rplay` both put `#1a0d05` on the orange
                // rather than the white or black Material would compute.
                onPrimary: Palette.onAccent,
              ),
          // `body{background:#070f1f}` (`index.html:15`). Not cosmetic
          // housekeeping: three of the four tabs are bare bodies with no surface
          // of their own, so until this line the colour behind them was a tonal
          // value generated from a seed nobody chose.
          scaffoldBackgroundColor: Palette.pageBackground,
        ),
        // **The celebration popup, above the `Navigator` rather than on a
        // screen.** `.badgePop` is `z-index:60` — over the game overlay, the
        // detail screen, and the loading gate (`index.html:233-234,165,247`),
        // i.e. over everything. `MaterialApp.builder` is the one place in a
        // Flutter app with that reach: a badge is nearly always earned mid-game,
        // and a popup mounted inside a tab would celebrate underneath the game
        // the child is looking at. See `badge_popup.dart`.
        // `ControlScale` outside the popup host so it reaches the whole
        // navigator — the detail screen is a pushed route, and its two
        // `ActionButton`s are among the controls this is for.
        builder: (BuildContext context, Widget? child) => ControlScale(
          scale: controlScale,
          child: BadgePopupHost(child: child ?? const SizedBox.shrink()),
        ),
        // **The title, and then the gate behind it** (`title.html`,
        // `specs/06-title-polish-safety.md:16`). This used to be [LoadingGate]
        // directly, for a reason that still holds — the shell is only built once
        // there is a sky to put in it (`index.html:271`) — and the gate is still
        // the only thing that decides that. What changed is that the gate is now
        // reached by a tap rather than by a cold launch.
        //
        // The load itself did *not* move back a step with it: [TitleScreen] starts
        // the feed when it mounts, so the request is in flight while a child is
        // still looking at Rusty. See its own docs — that is the whole reason a
        // splash in front of a network gate is not a delay.
        home: const TitleScreen(),
      ),
    );
  }
}

/// [MaterialScrollBehavior] with every drag-capable pointer enabled, so the
/// same build scrolls by finger on a phone and by mouse or trackpad on the web
/// demo. See the `scrollBehavior:` line in [RockimalsApp] for why this exists;
/// public (rather than `_AppScrollBehavior`) so `app_test.dart` can pin the
/// mouse into [dragDevices] and keep the web demo scrollable from a test.
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => <PointerDeviceKind>{
    PointerDeviceKind.touch,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.unknown,
  };
}

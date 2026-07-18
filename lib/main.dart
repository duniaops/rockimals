import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// `Override` is not exported from the package root — Riverpod 3 parks the types
// you mostly need in a test under `misc.dart`, alongside `ProviderException`.
import 'package:flutter_riverpod/misc.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:rockimals/core/storage/store.dart';
import 'package:rockimals/core/streak/day_streak.dart';
import 'package:rockimals/core/theme/palette.dart';
import 'package:rockimals/features/data/providers.dart';
import 'package:rockimals/features/rewards/badge_popup.dart';
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

  // Opening Rockimals is the day's engagement (plan decisions 3/14), so the
  // consecutive-days-played streak is advanced here, before the first frame —
  // the same reason the store itself is opened here rather than lazily: the home
  // flame must be right at first paint, not a frame later.
  await DayStreak.record(store, DateTime.now());

  return ProviderScope(
    // The store first, so a test can still override it with its own.
    overrides: <Override>[storeProvider.overrideWithValue(store), ...overrides],
    child: const RockimalsApp(),
  );
}

class RockimalsApp extends StatelessWidget {
  const RockimalsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rockimals',
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
      builder: (BuildContext context, Widget? child) =>
          BadgePopupHost(child: child ?? const SizedBox.shrink()),
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
    );
  }
}

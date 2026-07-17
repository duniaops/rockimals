import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// `Override` is not exported from the package root — Riverpod 3 parks the types
// you mostly need in a test under `misc.dart`, alongside `ProviderException`.
import 'package:flutter_riverpod/misc.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:rockimals/core/storage/store.dart';
import 'package:rockimals/features/data/providers.dart';
import 'package:rockimals/features/debug/debug_animal_list_screen.dart';

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
Future<Widget> bootstrap({List<Override> overrides = const <Override>[]}) async {
  await Hive.initFlutter();
  final Store store = await Store.open();

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
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF5B7CFA),
          brightness: Brightness.dark,
        ),
      ),
      // The task-01 throwaway (spec 01 §5), and the app's only screen until the
      // shell and radar land — at which point a plan item deletes it. It
      // replaced the scaffold's placeholder rather than joining it: two
      // stand-ins would be one more than the app has room for, and the
      // placeholder was never a thing to build on.
      home: const DebugAnimalListScreen(),
    );
  }
}

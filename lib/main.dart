import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:rockimals/core/storage/store.dart';
import 'package:rockimals/features/data/providers.dart';

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
Future<Widget> bootstrap() async {
  await Hive.initFlutter();
  final Store store = await Store.open();

  return ProviderScope(
    // Left to inference: Riverpod 3 does not export `Override`, so there is no
    // name to annotate this list with.
    overrides: [storeProvider.overrideWithValue(store)],
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
      home: const PlaceholderHome(),
    );
  }
}

/// Stands in until the title screen (task 06) and radar (task 02) land.
/// Replaced wholesale, not built on.
class PlaceholderHome extends StatelessWidget {
  const PlaceholderHome({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('🦊', style: TextStyle(fontSize: 64)),
            SizedBox(height: 16),
            Text('ROCKIMALS', style: TextStyle(fontSize: 28, letterSpacing: 4)),
          ],
        ),
      ),
    );
  }
}

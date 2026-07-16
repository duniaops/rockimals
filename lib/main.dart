import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  runApp(const ProviderScope(child: RockimalsApp()));
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

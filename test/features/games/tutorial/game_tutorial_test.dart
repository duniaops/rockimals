import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/features/data/providers.dart';
import 'package:rockimals/features/games/tutorial/game_tutorial.dart';

import '../../../support/memory_store.dart';

void main() {
  testWidgets('a first game launch teaches first, then offers practice', (
    WidgetTester tester,
  ) async {
    final MemoryStore store = MemoryStore();
    await tester.pumpWidget(_gate(store));

    expect(find.text('Welcome to Play!'), findsOneWidget);
    await tester.tap(find.text('Skip tutorial'));
    await tester.pump();

    expect(store.gameTutorialProgress, <String>[kGameGuideProgressToken]);
    expect(find.text('Practice round'), findsOneWidget);
  });

  testWidgets('practice completion is persisted and the next round is scored', (
    WidgetTester tester,
  ) async {
    final MemoryStore store = MemoryStore(
      gameTutorialProgress: const <String>[kGameGuideProgressToken],
    );
    await tester.pumpWidget(_gate(store));

    expect(find.text('Practice round'), findsOneWidget);
    await tester.tap(find.text('Finish practice'));
    await tester.pump();

    expect(store.gameTutorialProgress, <String>[
      kGameGuideProgressToken,
      'duel',
    ]);
    expect(find.text('Scored game'), findsOneWidget);
  });

  testWidgets('the guide covers power and the full Mouse to Whale ladder', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: _GuideHarness())),
    );

    await tester.tap(find.text('Next'));
    await tester.pump();
    expect(
      find.textContaining('Power = bigger + closer + faster'),
      findsOneWidget,
    );

    await tester.tap(find.text('Next'));
    await tester.pump();
    expect(find.textContaining('Mouse'), findsOneWidget);
    expect(find.textContaining('Whale'), findsOneWidget);
  });
}

Widget _gate(MemoryStore store) => ProviderScope(
  overrides: [storeProvider.overrideWithValue(store)],
  child: const MaterialApp(home: _GateHarness()),
);

class _GateHarness extends StatelessWidget {
  const _GateHarness();

  @override
  Widget build(BuildContext context) => GameTutorialGate(
    game: GameTutorialId.duel,
    builder:
        ({required bool practice, required VoidCallback onPracticeComplete}) =>
            Scaffold(
              body: Center(
                child: practice
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const Text('Practice round'),
                          TextButton(
                            onPressed: onPracticeComplete,
                            child: const Text('Finish practice'),
                          ),
                        ],
                      )
                    : const Text('Scored game'),
              ),
            ),
  );
}

class _GuideHarness extends StatelessWidget {
  const _GuideHarness();

  @override
  Widget build(BuildContext context) => GameTutorialScreen(onFinished: () {});
}

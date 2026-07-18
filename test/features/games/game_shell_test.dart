import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:rockimals/core/storage/store.dart';
import 'package:rockimals/features/games/game_shell.dart';

/// The game framework (`specs/04`, "Game framework"): the shared surface, the
/// score bar, the one `gameOver` end screen, `markPlayed`, and the two seams a
/// game routes an outcome to (points and a happy/sad reaction).
///
/// **Split the way this codebase splits store-backed UI** (the Play hub suite's
/// rule): the *store writes* are a real Hive round trip, so they are plain
/// `test()`s against a temp-dir box where `await` works; the *widget flow* stands
/// a recording [GameActions] in front of the game so a store write can never
/// deadlock the `testWidgets` fake clock. A tiny [_StubGame] plays the role of
/// the four real games — it is the Done-when's "a stub game routes in, awards a
/// point, and ends through gameOver".
void main() {
  group('GameActions writes to the store (real box)', () {
    late Directory tempDir;
    late Store store;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('rockimals_game_shell');
      Hive.init(tempDir.path);
      store = await Store.open();
    });

    tearDown(() async {
      await Hive.deleteFromDisk();
      await Hive.close();
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    });

    test('markPlayed increments played and survives a reopen', () async {
      final GameActions actions = GameActions(store);
      expect(store.played, 0);

      await actions.markPlayed();
      expect(store.played, 1);
      await actions.markPlayed();
      expect(store.played, 2);

      // Force-quit and relaunch: the count is on disk, not just in memory.
      await store.close();
      final Store reopened = await Store.open();
      expect(reopened.played, 2);
    });

    test('awardPoints accumulates the total and survives a reopen', () async {
      final GameActions actions = GameActions(store);

      await actions.awardPoints(10);
      await actions.awardPoints(5);
      expect(store.points, 15);

      await store.close();
      final Store reopened = await Store.open();
      expect(reopened.points, 15);
    });

    test('a zero award is a no-op and touches nothing', () async {
      final GameActions actions = GameActions(store);
      await actions.awardPoints(0);
      expect(store.points, 0);

      // `points == 0` alone proves only that nothing was *added* — it holds
      // just as well if the write happened and stored a 0. A wrong answer
      // scores 0 and is therefore a real, repeated call site, so the claim
      // worth pinning is that it costs no disk write at all: with the
      // short-circuit gone the key exists (holding 0), and with it in place
      // the key was never written. Asserted on the raw key the way
      // `store_test.dart` does, because absence is not observable through the
      // typed getter (which answers 0 for both).
      expect(
        Hive.box<Object>(Store.boxName).containsKey('aw_points'),
        isFalse,
        reason: 'awardPoints(0) must not write to the box',
      );
    });

    test('points can never be taken away (a negative award asserts)', () {
      final GameActions actions = GameActions(store);
      expect(
        () => actions.awardPoints(-1),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('the reaction seam', () {
    test('react publishes a fresh event every call, so a run of the same '
        'sign still fires each time', () {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      final List<GameReaction?> seen = <GameReaction?>[];
      container.listen<GameReaction?>(
        gameReactionProvider,
        (GameReaction? _, GameReaction? next) => seen.add(next),
      );

      final GameReactionNotifier notifier = container.read(
        gameReactionProvider.notifier,
      );
      notifier.react(correct: true);
      notifier.react(correct: true);
      notifier.react(correct: false);

      // Two identical-sign reactions in a row are two events, not one
      // deduped-away — the point of the no-value-equality event.
      expect(seen.length, 3);
      expect(seen[0]!.correct, isTrue);
      expect(seen[1]!.correct, isTrue);
      expect(seen[2]!.correct, isFalse);
    });

    test('starts empty (no reaction before an answer)', () {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(gameReactionProvider), isNull);
    });
  });

  group('the game surface and end screen', () {
    testWidgets('a stub game routes in, awards a point, and ends through '
        'gameOver', (WidgetTester tester) async {
      final _RecordingActions actions = _RecordingActions();
      final List<GameReaction?> reactions = <GameReaction?>[];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            gameActionsProvider.overrideWithValue(actions),
          ],
          child: MaterialApp(
            home: _Launcher(onReaction: reactions.add),
          ),
        ),
      );

      // Routes in: the hub opens the game.
      await tester.tap(find.text('Open the game'));
      await tester.pumpAndSettle();

      // The shared surface: the title bar and the score bar.
      expect(find.text('🎮 Stub Game'), findsOneWidget);
      expect(find.text('SCORE'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);
      // markPlayed fired once when the game started.
      expect(actions.played, 1);

      // Awards a point, and reacts.
      await tester.tap(find.text('Score a point!'));
      await tester.pumpAndSettle();
      expect(actions.awarded, <int>[1]);
      expect(reactions.single!.correct, isTrue);

      // Ends through gameOver: the shared end screen.
      expect(find.text('GAME OVER'), findsOneWidget);
      expect(find.text('1'), findsOneWidget); // the big score
      expect(find.text('you scored 1'), findsOneWidget);
      expect(find.text('Play again'), findsOneWidget);
      expect(find.text('Back to games'), findsOneWidget);
    });

    testWidgets('Play again re-runs the game (a fresh round, another '
        'markPlayed)', (WidgetTester tester) async {
      final _RecordingActions actions = _RecordingActions();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            gameActionsProvider.overrideWithValue(actions),
          ],
          child: const MaterialApp(home: _StubGame()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Score a point!'));
      await tester.pumpAndSettle();
      expect(find.text('GAME OVER'), findsOneWidget);

      await tester.tap(find.text('Play again'));
      await tester.pumpAndSettle();

      // Back on a round, and a second play was counted.
      expect(find.text('Score a point!'), findsOneWidget);
      expect(find.text('GAME OVER'), findsNothing);
      expect(actions.played, 2);
    });

    testWidgets('Back to games pops the game off the navigator', (
      WidgetTester tester,
    ) async {
      final _RecordingActions actions = _RecordingActions();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            gameActionsProvider.overrideWithValue(actions),
          ],
          child: MaterialApp(home: _Launcher(onReaction: (_) {})),
        ),
      );

      await tester.tap(find.text('Open the game'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Score a point!'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Back to games'));
      await tester.pumpAndSettle();

      // Back at the launcher (the hub), the game gone.
      expect(find.text('Open the game'), findsOneWidget);
      expect(find.text('🎮 Stub Game'), findsNothing);
    });

    testWidgets('the score bar shows every cell it is given', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GameScoreBar(
              scores: <GameScore>[
                GameScore(value: '3', label: 'STREAK'),
                GameScore(value: '7', label: 'BEST'),
              ],
            ),
          ),
        ),
      );

      expect(find.text('3'), findsOneWidget);
      expect(find.text('STREAK'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
      expect(find.text('BEST'), findsOneWidget);
    });
  });
}

/// A screen that opens the stub game — stands in for the Play hub, so the game
/// genuinely *routes in* and `Back to games` has somewhere to pop to.
class _Launcher extends StatelessWidget {
  const _Launcher({required this.onReaction});

  final void Function(GameReaction?) onReaction;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () => Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (BuildContext context) => _StubGame(onReaction: onReaction),
            ),
          ),
          child: const Text('Open the game'),
        ),
      ),
    );
  }
}

/// The four real games in miniature: it counts the play on start, shows a score
/// bar and one "score a point" button, and finishes through [GameOverPanel] —
/// the smallest thing that exercises every part of the framework.
class _StubGame extends ConsumerStatefulWidget {
  const _StubGame({this.onReaction});

  /// Test spy for the reaction the game publishes; the real games leave this to
  /// task 05's listeners.
  final void Function(GameReaction?)? onReaction;

  @override
  ConsumerState<_StubGame> createState() => _StubGameState();
}

class _StubGameState extends ConsumerState<_StubGame> {
  int _score = 0;
  bool _over = false;

  @override
  void initState() {
    super.initState();
    // Publish the reaction to the spy as the real games publish it to task 05.
    if (widget.onReaction != null) {
      ref.listenManual<GameReaction?>(
        gameReactionProvider,
        (GameReaction? _, GameReaction? next) => widget.onReaction!(next),
      );
    }
    // markPlayed on start, exactly as every prototype `start*` does.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(ref.read(gameActionsProvider).markPlayed());
    });
  }

  void _scorePoint() {
    ref.read(gameActionsProvider).awardPoints(1);
    ref.read(gameReactionProvider.notifier).react(correct: true);
    setState(() {
      _score = 1;
      _over = true;
    });
  }

  void _playAgain() {
    ref.read(gameActionsProvider).markPlayed();
    setState(() {
      _score = 0;
      _over = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return GameShell(
      title: '🎮 Stub Game',
      body: _over
          ? GameOverPanel(
              title: 'GAME OVER',
              score: '$_score',
              subtitle: 'you scored $_score',
              onPlayAgain: _playAgain,
            )
          : Column(
              children: <Widget>[
                GameScoreBar(
                  scores: <GameScore>[
                    GameScore(value: '$_score', label: 'SCORE'),
                  ],
                ),
                ElevatedButton(
                  onPressed: _scorePoint,
                  child: const Text('Score a point!'),
                ),
              ],
            ),
    );
  }
}

/// A [GameActions] that records instead of writing — the widget flow's stand-in
/// for the store, so a Hive `await` never deadlocks the test's fake clock (the
/// Play hub suite's rule). Implements only the public surface; the real class's
/// private [Store] is not part of the cross-library interface.
class _RecordingActions implements GameActions {
  int played = 0;
  final List<int> awarded = <int>[];

  @override
  Future<void> markPlayed() async => played++;

  @override
  Future<void> awardPoints(int n) async => awarded.add(n);
}

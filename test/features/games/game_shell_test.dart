import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:rockimals/core/audio/sound_engine.dart';
import 'package:rockimals/core/storage/store.dart';
import 'package:rockimals/core/streak/day_streak.dart';
import 'package:rockimals/features/data/providers.dart';
import 'package:rockimals/features/games/game_shell.dart';
import 'package:rockimals/features/games/games_providers.dart';
import 'package:rockimals/features/settings/calm_motion.dart';
// `Override` lives here in Riverpod 3, not in the main barrel.

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
import '../../support/recording_sound_engine.dart';
import '../../support/stub_settings.dart';

void main() {
  group('GameActions writes to the store (real box)', () {
    late Directory tempDir;
    late Store store;
    late List<int> refreshedAt;
    late List<int> flameRefreshedAt;

    /// The points total at each `checkBadges()` — the badge system's seam. What
    /// it pins is that a badge check follows every write that can earn one, and
    /// *only* those: the three per-game bests must not trigger it.
    late List<int> badgeChecks;
    late DateTime today;

    /// A [GameActions] whose three "your snapshot is stale" callbacks record
    /// what they were told about — the points total for the Play hub, the day
    /// streak for the home flame, and the badge check. The lists are the
    /// assertion surface for *which* writes are live: a write that must repaint
    /// a surface (or ask the badge system a question) appends, one that must not
    /// stays silent.
    ///
    /// The clock is [today], a mutable field rather than `DateTime.now`, so a
    /// test can play a game "tomorrow" without waiting a day.
    GameActions actionsOn(Store s) => GameActions(
      s,
      () => refreshedAt.add(s.points),
      () => flameRefreshedAt.add(s.dayStreak),
      () => badgeChecks.add(s.points),
      now: () => today,
    );

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('rockimals_game_shell');
      Hive.init(tempDir.path);
      store = await Store.open();
      refreshedAt = <int>[];
      flameRefreshedAt = <int>[];
      badgeChecks = <int>[];
      today = DateTime(2026, 7, 18);
    });

    tearDown(() async {
      await Hive.deleteFromDisk();
      await Hive.close();
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    });

    test('markPlayed increments played and survives a reopen', () async {
      final GameActions actions = actionsOn(store);
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
      final GameActions actions = actionsOn(store);

      await actions.awardPoints(10);
      await actions.awardPoints(5);
      expect(store.points, 15);

      await store.close();
      final Store reopened = await Store.open();
      expect(reopened.points, 15);
    });

    test('a zero award is a no-op and touches nothing', () async {
      final GameActions actions = actionsOn(store);
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

    test('setBestDuel persists the streak across a restart', () async {
      final GameActions actions = actionsOn(store);
      expect(actions.bestDuel, 0);

      await actions.setBestDuel(4);
      expect(actions.bestDuel, 4);

      // The promise Power Duel's item names: force-quit and relaunch, and the
      // BEST cell still reads 4.
      await store.close();
      final Store reopened = await Store.open();
      expect(actionsOn(reopened).bestDuel, 4);
    });

    test('noteStreak keeps the longest run and never lowers it', () async {
      final GameActions actions = actionsOn(store);

      await actions.noteStreak(3);
      expect(store.bestStreak, 3);

      // A shorter run later must not overwrite the record
      // (`if(s>prog.bestStreak)`, `index.html:998`) — an all-time best that
      // falls back down is not a best.
      await actions.noteStreak(1);
      expect(store.bestStreak, 3);

      await actions.noteStreak(5);
      expect(store.bestStreak, 5);

      await store.close();
      final Store reopened = await Store.open();
      expect(reopened.bestStreak, 5);
    });

    test('a streak that only ties the record costs no disk write', () async {
      final GameActions actions = actionsOn(store);

      // The tie case (`>` not `>=`, `index.html:998`) is invisible through the
      // value — writing the record back over itself leaves the same number — so
      // the only way to see it is at the one tie where the key is still absent:
      // a fresh box, whose record is 0. That makes this the same
      // absence-of-a-write assertion the zero-award test makes, and for the
      // same reason: a value check here would pass whether or not the
      // short-circuit exists.
      expect(store.bestStreak, 0);
      await actions.noteStreak(0);

      expect(
        Hive.box<Object>(Store.boxName).containsKey('aw_bstreak'),
        isFalse,
        reason: 'a streak that beats nothing must not write to the box',
      );
    });

    test('points can never be taken away (a negative award asserts)', () {
      final GameActions actions = actionsOn(store);
      expect(() => actions.awardPoints(-1), throwsA(isA<AssertionError>()));
    });

    /// `specs/05`, "Wire points": *points accumulate across all four games and
    /// survive a restart*. Each game's own suite already pins what **it** awards
    /// (`+10` on a correct answer in Duel / Closer / Match, `grade.gain` in
    /// Today's Challenge) against a recording fake; what none of them can see is
    /// the total those four separately-mounted screens build up in one box.
    /// That is this test, and it is the Done-when's other half.
    test('points from all four games land in one total that survives a '
        'restart', () async {
      final GameActions actions = actionsOn(store);

      // A plausible session, in the amounts the four games actually award.
      await actions.awardPoints(10); // Power Duel, one correct
      await actions.awardPoints(10); // Closer or Farther, one correct
      await actions.awardPoints(10); // Animal Match, one correct
      await actions.awardPoints(0); // Animal Match, one wrong — nothing
      await actions.awardPoints(75); // Today's Challenge, graded on accuracy

      expect(store.points, 105);

      await store.close();
      final Store reopened = await Store.open();
      expect(
        reopened.points,
        105,
        reason: 'a child force-quitting must not lose the afternoon',
      );
    });

    /// Which writes drop the store-backed stats snapshots. This is the item's
    /// actual bug fix, and the list is exact in both directions:
    /// over-refreshing costs a rebuild of a screen nobody is looking at, but
    /// *under*-refreshing is the silent staleness the child sees — their new
    /// total simply not there.
    ///
    /// **One callback now serves two snapshots, so "the hub does not show it"
    /// stopped being the test.** The Profile item widened this seam rather than
    /// adding a second callback beside it (`profile_providers.dart` argues the
    /// choice), which moved `noteStreak` across: the hub does not show the best
    /// answer streak, but the Profile's 🔥 stat does, and a fifth callback is
    /// the thing a sixth write forgets. The over-refresh that buys costs the hub
    /// nothing — `GamesHubStats` compares by value, so recomputing its four
    /// unchanged numbers notifies no listener. That equality was added by the
    /// previous item *against this exact day*, and this is the day.
    group('telling the stats snapshots their numbers moved', () {
      test('every number a snapshot shows refreshes it', () async {
        final GameActions actions = actionsOn(store);

        await actions.awardPoints(10);
        await actions.setBestDuel(3);
        await actions.setBestCloser(2);
        await actions.setBestSize(8);
        // The Profile's 🔥 stat, which is why this one is here at all — the hub
        // shows no answer streak.
        await actions.noteStreak(4);

        // Five writes, five refreshes — and the first carries the *new* total,
        // which is the read-after-un-awaited-write ordering the class doc
        // argues is safe. Were the refresh firing before Hive's keystore
        // insert, this would read 0.
        expect(refreshedAt, <int>[10, 10, 10, 10, 10]);
      });

      test('a write no snapshot shows leaves them alone', () async {
        final GameActions actions = actionsOn(store);

        await actions.markPlayed();
        await actions.notePerfectRun();
        // A zero award moves no total, so it is not a repaint either.
        await actions.awardPoints(0);
        // Nor is a streak that fails to beat the record: `noteStreak` refreshes
        // only on a write, so a losing round costs nothing.
        await actions.noteStreak(0);

        expect(refreshedAt, isEmpty);
      });
    });

    /// Which writes ask the badge system a question — the port of the trailing
    /// `checkBadges()` on the prototype's `addPoints`, `noteStreak`, and
    /// `markPlayed` (`index.html:997-999`).
    ///
    /// **Exact in both directions, and the two failures are not symmetrical.**
    /// A missing check is a badge that never pops — the child earned something
    /// and the app said nothing, and nothing anywhere reports it. A spurious one
    /// is nine cheap comparisons that find nothing. So the "must" list is the
    /// one that matters, and the "must not" list is here to keep the check on
    /// the four writes that can actually earn something rather than on every
    /// write there is.
    group('asking the badge system whether something was earned', () {
      test('every write that can earn a badge asks', () async {
        final GameActions actions = actionsOn(store);

        await actions.markPlayed(); // Lift Off
        await actions.awardPoints(10); // the five point tiers
        await actions.noteStreak(5); // On Fire
        await actions.notePerfectRun(); // Perfect Match

        expect(badgeChecks, hasLength(4));
      });

      test('the points check sees the new total, not the old one', () async {
        // The ordering the whole badge system rests on: crossing 50 points must
        // pop Mouse Scout on *that* answer. A check that ran before the write
        // landed would read 40 here and defer every tier by one answer.
        await store.setPoints(40);
        final GameActions actions = actionsOn(store);

        await actions.awardPoints(10);

        expect(badgeChecks, <int>[50]);
      });

      test('a write that can earn nothing does not ask', () async {
        final GameActions actions = actionsOn(store);

        // The three per-game bests: no badge reads any of them.
        await actions.setBestDuel(3);
        await actions.setBestCloser(2);
        await actions.setBestSize(8);
        // A zero award moves no total, so there is nothing new to check.
        await actions.awardPoints(0);
        // And a streak that is not a record writes nothing at all.
        await actions.noteStreak(0);

        expect(badgeChecks, isEmpty);
      });
    });

    /// The home flame's half of the same seam. `markPlayed` records the day as
    /// engaged (decision 14, settled in its doc: the launch trigger stays and a
    /// game *begun* is an engagement too), so these pin the three things that
    /// makes true — it advances on a new day, it is silent on a day already
    /// counted, and the advance is on the disk rather than only in memory.
    group('starting a game records the day as engaged', () {
      test('a game on a new day advances the flame and says so', () async {
        final GameActions actions = actionsOn(store);

        // Day one: a fresh install whose first engagement is this game.
        await actions.markPlayed();
        expect(store.dayStreak, 1);
        expect(flameRefreshedAt, <int>[1]);

        // The next calendar day — the case the whole item exists for, since
        // `bootstrap()` only records the day the app *launched* on.
        today = DateTime(2026, 7, 19);
        await actions.markPlayed();
        expect(store.dayStreak, 2);
        // The callback carries the *new* streak, which is the same
        // read-after-un-awaited-write ordering the points half relies on: were
        // the refresh firing before Hive's keystore insert, this would read 1.
        expect(flameRefreshedAt, <int>[1, 2]);
      });

      test('a second game the same day leaves the flame alone', () async {
        final GameActions actions = actionsOn(store);

        await actions.markPlayed();
        expect(flameRefreshedAt, <int>[1]);

        // Two games in one afternoon is one day. Repainting the flame with the
        // number already on it is the over-refresh the points half avoids for
        // the same reason.
        await actions.markPlayed();
        await actions.markPlayed();
        expect(store.dayStreak, 1);
        expect(flameRefreshedAt, <int>[1]);
      });

      test('a streak advanced by a game survives a restart', () async {
        final GameActions actions = actionsOn(store);
        await actions.markPlayed();

        today = DateTime(2026, 7, 19);
        await actions.markPlayed();
        expect(store.dayStreak, 2);

        // Force-quit and relaunch: the flame is on disk, not just in the
        // provider that was invalidated. This is the "still survives a restart"
        // half of the item's Done-when.
        await store.close();
        final Store reopened = await Store.open();
        expect(reopened.dayStreak, 2);
        expect(reopened.lastPlayedDate, '2026-07-19');
      });
    });
  });

  /// The wiring itself: an award made through the app's own
  /// [gameActionsProvider] must reach [gamesHubStatsProvider], because that
  /// snapshot is what the Play hub's points card and three "Best" tags render.
  ///
  /// **A `ProviderContainer` rather than a mounted hub**, following this
  /// codebase's split for store-backed UI: the store half needs `await` on real
  /// Hive I/O, which deadlocks inside `testWidgets`. What the hub does with a
  /// snapshot is pinned in `games_hub_test.dart` against a stood-in value; what
  /// this pins is that the snapshot moves at all.
  group('the Play hub snapshot goes live when a game scores', () {
    late Directory tempDir;
    late Store store;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('rockimals_hub_live');
      Hive.init(tempDir.path);
      store = await Store.open();
    });

    tearDown(() async {
      await Hive.deleteFromDisk();
      await Hive.close();
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    });

    test(
      'an award through the real provider updates the hub snapshot',
      () async {
        final ProviderContainer container = ProviderContainer(
          overrides: <Override>[storeProvider.overrideWithValue(store)],
        );
        addTearDown(container.dispose);

        // Read it first, so it is memoised — the whole failure being fixed is
        // that a *cached* snapshot outlived the game that changed it.
        expect(container.read(gamesHubStatsProvider).points, 0);

        final List<int> seen = <int>[];
        container.listen<GamesHubStats>(
          gamesHubStatsProvider,
          (GamesHubStats? _, GamesHubStats next) => seen.add(next.points),
        );

        await container.read(gameActionsProvider).awardPoints(10);
        expect(container.read(gamesHubStatsProvider).points, 10);
        expect(seen, <int>[
          10,
        ], reason: 'the hub must be told, not just re-read');

        // And a best earned in a game reaches the card's "Best n" tag the same
        // way, without a relaunch.
        await container.read(gameActionsProvider).setBestDuel(3);
        expect(container.read(gamesHubStatsProvider).bestDuel, 3);
      },
    );

    /// The item's headline Done-when: *playing on a new day advances the flame
    /// without a relaunch*. The failure this replaces is not a wrong number but
    /// a frozen one — `dayStreakProvider` memoised its read of the store, so a
    /// streak advanced mid-session sat behind a snapshot until the next cold
    /// launch, and the child saw yesterday's flame over today's play.
    ///
    /// Built through the app's own [gameActionsProvider] rather than a
    /// hand-made [GameActions], because the wiring *is* the fix: the callback
    /// the provider passes is the only thing that drops the snapshot.
    test('playing on a new day moves the flame with no relaunch', () async {
      // The launch half: `bootstrap()` records the day the app opened on.
      await DayStreak.record(store, DateTime(2026, 7, 18));

      // Midnight passes with the app still open — the one case the launch
      // trigger cannot cover, and so the case worth driving.
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          storeProvider.overrideWithValue(store),
          dayClockProvider.overrideWithValue(() => DateTime(2026, 7, 19)),
        ],
      );
      addTearDown(container.dispose);

      // Read it first so it is memoised — a cached flame outliving the game
      // that moved it is the whole bug.
      expect(container.read(dayStreakProvider), 1);

      final List<int> seen = <int>[];
      container.listen<int>(
        dayStreakProvider,
        (int? _, int next) => seen.add(next),
      );

      await container.read(gameActionsProvider).markPlayed();

      expect(container.read(dayStreakProvider), 2);
      expect(seen, <int>[
        2,
      ], reason: 'the flame must be told, not just re-read');
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
            // GameShell listens on `gameReactionProvider` and plays a cue; these
            // keep that off the audio plugin and off the real store.
            soundEngineProvider.overrideWithValue(RecordingSoundEngine()),
            soundOnProvider.overrideWith(() => StubSoundOn(true)),
            reducedMotionProvider.overrideWith(StubCalmMotion.new),
          ],
          child: MaterialApp(home: _Launcher(onReaction: reactions.add)),
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
            // GameShell listens on `gameReactionProvider` and plays a cue; these
            // keep that off the audio plugin and off the real store.
            soundEngineProvider.overrideWithValue(RecordingSoundEngine()),
            soundOnProvider.overrideWith(() => StubSoundOn(true)),
            reducedMotionProvider.overrideWith(StubCalmMotion.new),
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
            // GameShell listens on `gameReactionProvider` and plays a cue; these
            // keep that off the audio plugin and off the real store.
            soundEngineProvider.overrideWithValue(RecordingSoundEngine()),
            soundOnProvider.overrideWith(() => StubSoundOn(true)),
            reducedMotionProvider.overrideWith(StubCalmMotion.new),
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
              builder: (BuildContext context) =>
                  _StubGame(onReaction: onReaction),
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

  // The rest of the surface exists for the two streak games and is unexercised
  // here.
  @override
  int get points => 0;

  @override
  int get bestDuel => 0;

  @override
  Future<void> setBestDuel(int streak) async {}
  @override
  int get bestCloser => 0;

  @override
  Future<void> setBestCloser(int streak) async {}

  @override
  int bestSize = 0;

  @override
  Future<void> setBestSize(int score) async => bestSize = score;

  @override
  Future<void> notePerfectRun() async {}

  @override
  Future<void> noteStreak(int streak) async {}
}

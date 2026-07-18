import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/core/animals/animal_system.dart';
import 'package:rockimals/data/models/asteroid.dart';
import 'package:rockimals/data/models/asteroid_feed.dart';
import 'package:rockimals/features/data/providers.dart';
import 'package:rockimals/features/games/challenge_game.dart';
import 'package:rockimals/features/games/game_shell.dart';
import 'package:rockimals/features/games/games_hub.dart';
import 'package:rockimals/features/games/games_providers.dart';

/// Today's Challenge end to end (`specs/04`, game 1). The scoring itself is
/// pinned in `challenge_grader_test.dart` against the prototype's own output;
/// this suite is the screen — ranking, revealing, and the two store seams.
///
/// **Every test plays by *name*, never by grid position.** The round is dealt by
/// a shuffle, so which card sits where is not knowable from outside; what is
/// knowable is each animal's power, so "perfect play" here means tapping the
/// four names in descending [power] order. That makes the assertions independent
/// of the shuffle rather than dependent on a seed that a later change to the
/// deal could silently invalidate.
///
/// **The store is stood in front of, not written to** — the Play hub suite's
/// rule: real Hive I/O awaited inside `testWidgets` deadlocks the fake clock, so
/// a recording [GameActions] takes the writes and the persistence promises are
/// tested where `await` works (`game_shell_test.dart`).
void main() {
  // Four rocks with widely separated power, so the true ranking is unambiguous
  // and a rounding wobble cannot reorder them.
  final Asteroid strongest = _rock('2020 AAA', diaMax: 3000, missLunar: 0.3, velKps: 30);
  final Asteroid strong = _rock('2020 BBB', diaMax: 500, missLunar: 2, velKps: 20);
  final Asteroid weak = _rock('2020 CCC', diaMax: 60, missLunar: 12, velKps: 12);
  final Asteroid weakest = _rock('2020 DDD', diaMax: 5, missLunar: 40, velKps: 6);
  final List<Asteroid> sky = <Asteroid>[strong, weakest, strongest, weak];

  // Names are hashed from the designation, and 24 names over 4 rocks can
  // collide (the naming item's pigeonhole note). These four do not — if a future
  // edit to the fixture makes them, every find-by-name below would go ambiguous,
  // so it is asserted rather than assumed.
  final List<String> perfectOrder = <String>[
    critter(strongest).name,
    critter(strong).name,
    critter(weak).name,
    critter(weakest).name,
  ];

  setUp(() {
    expect(perfectOrder.toSet().length, 4, reason: 'fixture names must be distinct');
  });

  group('dealing a round', () {
    testWidgets('shows four animals from today, counts the play, and starts '
        'unranked', (WidgetTester tester) async {
      final _RecordingActions actions = _RecordingActions();
      await _mount(tester, sky: sky, actions: actions);

      for (final String name in perfectOrder) {
        expect(find.text(name), findsOneWidget);
      }
      expect(find.text('Daily Challenge'), findsOneWidget);
      expect(find.text('0/4 ranked'), findsOneWidget);
      // `markPlayed()` before the first render (`index.html:884`).
      expect(actions.played, 1);
      // Nothing to do yet but rank: no Reveal, no Start over.
      expect(find.text('Reveal the truth'), findsNothing);
      expect(find.text('Start over'), findsNothing);
    });

    testWidgets('never shows a real designation — only animal names '
        '(CLAUDE.md:71)', (WidgetTester tester) async {
      await _mount(tester, sky: sky);
      for (final Asteroid a in sky) {
        expect(find.text(a.name), findsNothing);
      }
    });

    testWidgets('falls back to the whole window when today has fewer than '
        'four', (WidgetTester tester) async {
      // A quiet day: two rocks approaching today, four in the window. A
      // three-card challenge would be a different game, so the pool widens
      // (`todayList.length >= 4 ? todayList : asteroids`, `index.html:882`).
      await _mount(
        tester,
        sky: sky,
        todayList: <Asteroid>[strongest, weakest],
      );

      expect(find.text('0/4 ranked'), findsOneWidget);
      for (final String name in perfectOrder) {
        expect(find.text(name), findsOneWidget);
      }
    });
  });

  group('ranking', () {
    testWidgets('each tap places the next rank and offers Start over', (
      WidgetTester tester,
    ) async {
      await _mount(tester, sky: sky);

      await _tapCard(tester, perfectOrder[0]);
      expect(find.text('1/4 ranked'), findsOneWidget);
      // The rank badge the child just earned.
      expect(find.text('1'), findsOneWidget);
      // Mid-round the only action is to rethink it.
      expect(find.text('Start over'), findsOneWidget);
      expect(find.text('Reveal the truth'), findsNothing);

      await _tapCard(tester, perfectOrder[1]);
      expect(find.text('2/4 ranked'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('tapping an already-ranked animal does nothing', (
      WidgetTester tester,
    ) async {
      await _mount(tester, sky: sky);

      await _tapCard(tester, perfectOrder[0]);
      await _tapCard(tester, perfectOrder[0]);

      // Still one placement, not two (`chPicks.includes(i)`, `index.html:904`).
      expect(find.text('1/4 ranked'), findsOneWidget);
    });

    testWidgets('a full ranking offers Reveal, and Start over clears it '
        'without re-dealing', (WidgetTester tester) async {
      final _RecordingActions actions = _RecordingActions();
      await _mount(tester, sky: sky, actions: actions);
      await _rank(tester, perfectOrder);

      expect(find.text('4/4 ranked'), findsOneWidget);
      expect(find.text('Reveal the truth'), findsOneWidget);

      await tester.tap(find.text('Start over'));
      await tester.pumpAndSettle();

      expect(find.text('0/4 ranked'), findsOneWidget);
      // The *same* four animals — mid-round Start over is a rethink, not a new
      // puzzle (`chPicks=[]`, `index.html:910`), so it is not another play.
      for (final String name in perfectOrder) {
        expect(find.text(name), findsOneWidget);
      }
      expect(actions.played, 1);
    });
  });

  group('revealing', () {
    testWidgets('a perfect ranking scores 100, cheers, and shows every true '
        'rank', (WidgetTester tester) async {
      final _RecordingActions actions = _RecordingActions();
      final List<bool> reactions = <bool>[];
      await _mount(tester, sky: sky, actions: actions, onReaction: reactions.add);

      await _rank(tester, perfectOrder);
      await tester.tap(find.text('Reveal the truth'));
      await tester.pumpAndSettle();

      expect(find.text('🎯 Amazing! — 100% right · +100 ⭐'), findsOneWidget);
      // 4 exact placements (60) plus the flawless-order bonus (40).
      expect(actions.awarded, <int>[100]);
      expect(reactions, <bool>[true]);
      // Each card now shows the power that decided it and its true position.
      expect(
        find.text('power ⭐ ${powerStars(strongest)} · #1'),
        findsOneWidget,
      );
      expect(find.text('power ⭐ ${powerStars(weakest)} · #4'), findsOneWidget);
      // The round is over: reveal turns into Play again / Done.
      expect(find.text('Play again'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
      expect(find.text('Reveal the truth'), findsNothing);
    });

    testWidgets('a reversed ranking scores nothing and still encourages', (
      WidgetTester tester,
    ) async {
      final _RecordingActions actions = _RecordingActions();
      final List<bool> reactions = <bool>[];
      await _mount(tester, sky: sky, actions: actions, onReaction: reactions.add);

      await _rank(tester, perfectOrder.reversed.toList());
      await tester.tap(find.text('Reveal the truth'));
      await tester.pumpAndSettle();

      // Never harsh, even at 0% (`CLAUDE.md:70`).
      expect(
        find.text('Good try — keep going! — 0% right · +0 ⭐'),
        findsOneWidget,
      );
      expect(reactions, <bool>[false]);
      // A zero award still goes through the one seam; GameActions short-circuits
      // the write (`game_shell_test.dart`), so the game does not have to.
      expect(actions.awarded, <int>[0]);
    });

    testWidgets('a revealed board is inert — no tap can change the answer', (
      WidgetTester tester,
    ) async {
      await _mount(tester, sky: sky);
      await _rank(tester, perfectOrder);
      await tester.tap(find.text('Reveal the truth'));
      await tester.pumpAndSettle();

      await _tapCard(tester, perfectOrder[0]);

      // The banner is still the result, not a ranking count.
      expect(find.text('🎯 Amazing! — 100% right · +100 ⭐'), findsOneWidget);
    });
  });

  group('finishing', () {
    testWidgets('Play again deals a fresh round and counts another play', (
      WidgetTester tester,
    ) async {
      final _RecordingActions actions = _RecordingActions();
      await _mount(tester, sky: sky, actions: actions);
      await _rank(tester, perfectOrder);
      await tester.tap(find.text('Reveal the truth'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Play again'));
      await tester.pumpAndSettle();

      expect(find.text('0/4 ranked'), findsOneWidget);
      expect(find.text('Play again'), findsNothing);
      // "Play again" is `startChallenge` again (`index.html:946`), so it is a
      // second play, unlike the mid-round Start over.
      expect(actions.played, 2);
    });

    testWidgets('Done leaves the games behind and returns to the radar', (
      WidgetTester tester,
    ) async {
      await _mountFromHub(tester, sky: sky);

      await tester.tap(find.text("Today's Challenge"));
      await tester.pumpAndSettle();
      expect(find.text('Daily Challenge'), findsOneWidget);

      await _rank(tester, perfectOrder);
      await tester.tap(find.text('Reveal the truth'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      // Both overlays closed, back where Play was opened from
      // (`index.html:947`) — not merely back at the hub.
      expect(find.text('Daily Challenge'), findsNothing);
      expect(find.text('Play'), findsNothing);
      expect(find.text('the radar'), findsOneWidget);
    });

    testWidgets('the hub launches the real game, not the placeholder', (
      WidgetTester tester,
    ) async {
      await _mountFromHub(tester, sky: sky);

      await tester.tap(find.text("Today's Challenge"));
      await tester.pumpAndSettle();

      expect(find.text('Daily Challenge'), findsOneWidget);
      expect(find.text('This game is on its way — coming soon!'), findsNothing);
    });
  });
}

/// Rank the cards by tapping the given animal names in order.
Future<void> _rank(WidgetTester tester, List<String> names) async {
  for (final String name in names) {
    await _tapCard(tester, name);
  }
}

Future<void> _tapCard(WidgetTester tester, String name) async {
  await tester.tap(find.text(name));
  await tester.pumpAndSettle();
}

/// Mount the game alone, with the sky and the store seam stood in front of it.
Future<void> _mount(
  WidgetTester tester, {
  required List<Asteroid> sky,
  List<Asteroid>? todayList,
  _RecordingActions? actions,
  void Function(bool)? onReaction,
}) async {
  tester.view
    ..physicalSize = const Size(390, 780)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        asteroidFeedProvider.overrideWith(
          (Ref ref) => _feed(sky, todayList ?? sky),
        ),
        gameActionsProvider.overrideWithValue(actions ?? _RecordingActions()),
      ],
      child: MaterialApp(
        home: _ReactionSpy(onReaction: onReaction, child: const ChallengeGame()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Mount the whole route the child takes — a stand-in radar, the Play hub, then
/// the game — so "Done" has two screens to close and somewhere to land.
Future<void> _mountFromHub(
  WidgetTester tester, {
  required List<Asteroid> sky,
}) async {
  tester.view
    ..physicalSize = const Size(390, 900)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        asteroidFeedProvider.overrideWith((Ref ref) => _feed(sky, sky)),
        gameActionsProvider.overrideWithValue(_RecordingActions()),
        gamesHubStatsProvider.overrideWithValue(
          const GamesHubStats(points: 0, bestDuel: 0, bestCloser: 0, bestSize: 0),
        ),
        soundOnProvider.overrideWith(_StubSound.new),
      ],
      child: const MaterialApp(home: _RadarStub()),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.text('🎮 Play'));
  await tester.pumpAndSettle();
}

AsteroidFeed _feed(List<Asteroid> asteroids, List<Asteroid> todayList) {
  return AsteroidFeed(
    asteroids: asteroids,
    todayList: todayList,
    feedRange: 'sample data',
    provenance: FeedProvenance.sample,
  );
}

/// The first route: what the child sees behind Play, so `Done`'s pop-to-root has
/// a destination to be found at.
class _RadarStub extends StatelessWidget {
  const _RadarStub();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text('the radar'),
            TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (BuildContext context) => const GamesHub(),
                ),
              ),
              child: const Text('🎮 Play'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Records the reactions the game publishes on the shared channel — the seam
/// task 05's animations and sounds will listen on.
class _ReactionSpy extends ConsumerStatefulWidget {
  const _ReactionSpy({required this.onReaction, required this.child});

  final void Function(bool)? onReaction;
  final Widget child;

  @override
  ConsumerState<_ReactionSpy> createState() => _ReactionSpyState();
}

class _ReactionSpyState extends ConsumerState<_ReactionSpy> {
  @override
  Widget build(BuildContext context) {
    ref.listen<GameReaction?>(gameReactionProvider, (
      GameReaction? _,
      GameReaction? next,
    ) {
      if (next != null) widget.onReaction?.call(next.correct);
    });
    return widget.child;
  }
}

/// A [GameActions] that records instead of writing, so a Hive `await` can never
/// deadlock the fake clock (the Play hub / game framework suites' rule).
class _RecordingActions implements GameActions {
  int played = 0;
  final List<int> awarded = <int>[];

  @override
  Future<void> markPlayed() async => played++;

  @override
  Future<void> awardPoints(int n) async => awarded.add(n);
}

/// The sound toggle with the store taken out — the hub reads it on build.
class _StubSound extends SoundOnNotifier {
  @override
  bool build() => true;
}

Asteroid _rock(
  String name, {
  required double diaMax,
  required double missLunar,
  required double velKps,
}) {
  return Asteroid(
    name: name,
    diaMax: diaMax,
    diaMin: diaMax / 2,
    hazardous: false,
    missLunar: missLunar,
    missKm: missLunar * 384400,
    velKps: velKps,
    mag: 20,
    jpl: 'https://ssd.jpl.nasa.gov/tools/sbdb_lookup.html',
    date: '2026-07-16',
  );
}

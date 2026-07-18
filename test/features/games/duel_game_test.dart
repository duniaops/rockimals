import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/core/animals/animal_system.dart';
import 'package:rockimals/core/audio/sound_engine.dart';
import 'package:rockimals/data/models/asteroid.dart';
import 'package:rockimals/data/models/asteroid_feed.dart';
import 'package:rockimals/features/data/providers.dart';
import 'package:rockimals/features/games/duel_game.dart';
import 'package:rockimals/features/games/game_shell.dart';
import 'package:rockimals/features/games/games_hub.dart';
import 'package:rockimals/features/games/games_providers.dart';
import 'package:rockimals/features/rewards/reaction.dart';
import 'package:rockimals/features/settings/calm_motion.dart';

import '../../support/recording_sound_engine.dart';
import '../../support/stub_settings.dart';

/// Power Duel end to end (`specs/04`, game 2). The deal and the winner test are
/// pinned in `duel_pairing_test.dart`; this suite is the screen — answering,
/// the streak, the two delays, and the four store seams.
///
/// **The sky is exactly two animals, and that is the whole testing trick.** The
/// deal is random, so on any larger sky which pair appears is unknowable from
/// outside; with two well-separated rocks the deal can only ever produce those
/// two, so every test knows both names and which one is the right answer —
/// without a seed the widget would otherwise have to accept (the challenge
/// suite's rule).
///
/// **The store is stood in front of, not written to** — real Hive I/O awaited
/// inside `testWidgets` deadlocks the fake clock (the Play hub suite's rule), so
/// a recording [GameActions] takes the writes and the persistence promises are
/// tested where `await` works (`game_shell_test.dart`).
void main() {
  // Two animals whose power is far enough apart that the deal's gap rule is
  // satisfied on the first draw and no rounding wobble can swap them.
  final Asteroid strong = _rock(
    '2020 AAA',
    diaMax: 3000,
    missLunar: 0.3,
    velKps: 30,
  );
  final Asteroid weak = _rock('2020 DDD', diaMax: 5, missLunar: 40, velKps: 6);
  final List<Asteroid> sky = <Asteroid>[strong, weak];

  final String strongName = critter(strong).name;
  final String weakName = critter(weak).name;

  setUp(() {
    // Names are hashed from the designation and 24 names over 2 rocks can
    // collide (the naming item's pigeonhole note). These two do not — if a
    // future edit to the fixture made them, every find-by-name below would go
    // ambiguous, so it is asserted rather than assumed.
    expect(strongName, isNot(weakName), reason: 'fixture names must differ');
    expect(power(strong) - power(weak), greaterThan(0.6));
  });

  group('starting a round', () {
    testWidgets('deals two animals, counts the play, and starts at zero', (
      WidgetTester tester,
    ) async {
      final _RecordingActions actions = _RecordingActions();
      await _mount(tester, sky: sky, actions: actions);

      expect(find.text('⚔️ Power Duel'), findsOneWidget);
      expect(find.text(strongName), findsOneWidget);
      expect(find.text(weakName), findsOneWidget);
      expect(_scoreValue(tester, 'STREAK'), '0');
      // `markPlayed()` before the first round (`index.html:1035`).
      expect(actions.played, 1);
      // The power is the answer, so it stays hidden until the child commits.
      expect(find.textContaining('power ⭐'), findsNothing);
    });

    testWidgets('seeds BEST from storage', (WidgetTester tester) async {
      await _mount(tester, sky: sky, actions: _RecordingActions(bestDuel: 4));

      expect(_scoreValue(tester, 'BEST'), '4');
    });

    testWidgets('never shows a real designation — only animal names '
        '(CLAUDE.md:71)', (WidgetTester tester) async {
      await _mount(tester, sky: sky);
      for (final Asteroid a in sky) {
        expect(find.text(a.name), findsNothing);
      }
    });
  });

  group('a correct answer', () {
    testWidgets('cheers, awards 10, extends the streak, and reveals both '
        'powers', (WidgetTester tester) async {
      final _RecordingActions actions = _RecordingActions();
      await _mount(tester, sky: sky, actions: actions);

      await _tap(tester, strongName);

      expect(find.text('✓ Correct!  +10 ⭐'), findsOneWidget);
      expect(_scoreValue(tester, 'STREAK'), '1');
      expect(actions.awarded, <int>[10]);
      // Both cards show what decided it, so a child can see *why*
      // (`index.html:1051`).
      expect(find.text('power ⭐ ${powerStars(strong)}'), findsOneWidget);
      expect(find.text('power ⭐ ${powerStars(weak)}'), findsOneWidget);

      await _drain(tester);
    });

    testWidgets('persists the new best and notes the cross-game streak', (
      WidgetTester tester,
    ) async {
      final _RecordingActions actions = _RecordingActions();
      await _mount(tester, sky: sky, actions: actions);

      await _tap(tester, strongName);

      // `aw_duel` (this game's best) and `aw_bstreak` (the profile's all-time
      // run of right answers) are two different records fed the same number
      // here — `noteStreak`, `index.html:1053`.
      expect(actions.bestDuelWrites, <int>[1]);
      expect(actions.streakNotes, <int>[1]);
      expect(_scoreValue(tester, 'BEST'), '1');

      await _drain(tester);
    });

    testWidgets('does not lower an existing best', (WidgetTester tester) async {
      final _RecordingActions actions = _RecordingActions(bestDuel: 4);
      await _mount(tester, sky: sky, actions: actions);

      await _tap(tester, strongName);

      // A streak of 1 against a best of 4 writes nothing
      // (`if(duelStreak>bestDuel)`, `index.html:1053`).
      expect(actions.bestDuelWrites, isEmpty);
      expect(_scoreValue(tester, 'BEST'), '4');

      await _drain(tester);
    });

    testWidgets('deals the next pair after 950ms, still on the same play', (
      WidgetTester tester,
    ) async {
      final _RecordingActions actions = _RecordingActions();
      await _mount(tester, sky: sky, actions: actions);

      await _tap(tester, strongName);
      // Just short of the delay: still showing the answer.
      await tester.pump(const Duration(milliseconds: 949));
      expect(find.text('✓ Correct!  +10 ⭐'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 1));
      // A fresh round: the banner is clear and the powers are hidden again.
      expect(find.text('✓ Correct!  +10 ⭐'), findsNothing);
      expect(find.textContaining('power ⭐'), findsNothing);
      // The streak survives the round boundary; the run is one play.
      expect(_scoreValue(tester, 'STREAK'), '1');
      expect(actions.played, 1);
    });

    testWidgets('a second tap during the reveal is ignored', (
      WidgetTester tester,
    ) async {
      final _RecordingActions actions = _RecordingActions();
      await _mount(tester, sky: sky, actions: actions);

      await _tap(tester, strongName);
      // The prototype clears both handlers on the first tap
      // (`index.html:1047`), so an excited double-tap cannot bank two answers
      // — nor end the run by hitting the loser next.
      await _tap(tester, weakName);

      expect(actions.awarded, <int>[10]);
      expect(_scoreValue(tester, 'STREAK'), '1');
      expect(find.text('✓ Correct!  +10 ⭐'), findsOneWidget);

      await _drain(tester);
    });

    testWidgets('publishes a happy reaction on the shared channel', (
      WidgetTester tester,
    ) async {
      final List<bool> reactions = <bool>[];
      await _mount(tester, sky: sky, onReaction: reactions.add);

      await _tap(tester, strongName);

      expect(reactions, <bool>[true]);
      await _drain(tester);
    });
  });

  group('a wrong answer', () {
    testWidgets('is encouraging, awards nothing, and ends the run after '
        '1250ms', (WidgetTester tester) async {
      final _RecordingActions actions = _RecordingActions();
      await _mount(tester, sky: sky, actions: actions);

      await _tap(tester, weakName);

      // Never harsh (`CLAUDE.md:70`).
      expect(find.text('✗ So close! Try the next one 💪'), findsOneWidget);
      expect(actions.awarded, isEmpty);
      // The board stays up long enough to see which animal was stronger.
      expect(find.text('power ⭐ ${powerStars(strong)}'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 1249));
      expect(find.text('GAME OVER'), findsNothing);

      await tester.pump(const Duration(milliseconds: 1));
      expect(find.text('GAME OVER'), findsOneWidget);
      expect(find.text('Play again'), findsOneWidget);
      expect(find.text('Back to games'), findsOneWidget);
    });

    testWidgets('the end screen reports the run, the best, and the points', (
      WidgetTester tester,
    ) async {
      final _RecordingActions actions = _RecordingActions();
      await _mount(tester, sky: sky, actions: actions);

      // One right answer, then a wrong one.
      await _tap(tester, strongName);
      await tester.pump(kDuelAdvanceDelay);
      await _tap(tester, weakName);
      await tester.pump(kDuelGameOverDelay);

      expect(find.text('1'), findsOneWidget);
      // `"best streak "+bestDuel+" · ⭐ "+points+" points"`
      // (`index.html:1055`).
      expect(find.text('best streak 1 · ⭐ 10 points'), findsOneWidget);
    });

    testWidgets('publishes a sad reaction on the shared channel', (
      WidgetTester tester,
    ) async {
      final List<bool> reactions = <bool>[];
      await _mount(tester, sky: sky, onReaction: reactions.add);

      await _tap(tester, weakName);

      expect(reactions, <bool>[false]);
      await _drain(tester);
    });

    testWidgets('Play again starts a fresh run and counts another play', (
      WidgetTester tester,
    ) async {
      final _RecordingActions actions = _RecordingActions();
      await _mount(tester, sky: sky, actions: actions);

      await _tap(tester, strongName);
      await tester.pump(kDuelAdvanceDelay);
      await _tap(tester, weakName);
      await tester.pump(kDuelGameOverDelay);

      await _tap(tester, 'Play again');

      // `startDuel` again (`index.html:1030`): the streak is back to zero, the
      // board is back, and the play is counted a second time.
      expect(find.text('GAME OVER'), findsNothing);
      expect(_scoreValue(tester, 'STREAK'), '0');
      // The best it reached survives the reset.
      expect(_scoreValue(tester, 'BEST'), '1');
      expect(actions.played, 2);
    });
  });

  testWidgets('the hub launches the real game, not the placeholder', (
    WidgetTester tester,
  ) async {
    tester.view
      ..physicalSize = const Size(390, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          asteroidFeedProvider.overrideWith((Ref ref) => _feed(sky)),
          gameActionsProvider.overrideWithValue(_RecordingActions()),
          gamesHubStatsProvider.overrideWithValue(
            const GamesHubStats(
              points: 0,
              bestDuel: 0,
              bestCloser: 0,
              bestSize: 0,
            ),
          ),
          soundOnProvider.overrideWith(_StubSound.new),
          reducedMotionProvider.overrideWith(StubCalmMotion.new),
        ],
        child: const MaterialApp(home: GamesHub()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Power Duel'));
    await tester.pumpAndSettle();

    expect(find.text('⚔️ Power Duel'), findsOneWidget);
    expect(find.text('This game is on its way — coming soon!'), findsNothing);
  });

  group('the reaction (specs/05)', () {
    testWidgets('a correct answer hops the tapped animal and leaves the other '
        'one alone', (WidgetTester tester) async {
      await _mount(tester, sky: sky);

      await _tap(tester, strongName);

      // `react(av, win)` where `av` is the avatar inside the card that was
      // clicked (`index.html:1052`) — the losing animal is revealed but does
      // not perform.
      expect(_cardReaction(tester, strongName), Reaction.happy);
      expect(_cardReaction(tester, weakName), isNull);
      await _drain(tester);
    });

    testWidgets('a wrong answer wobbles the tapped animal, still not the '
        'other', (WidgetTester tester) async {
      await _mount(tester, sky: sky);

      await _tap(tester, weakName);

      expect(_cardReaction(tester, weakName), Reaction.sad);
      expect(_cardReaction(tester, strongName), isNull);
      await _drain(tester);
    });

    testWidgets('the next pair opens with both animals still, so the following '
        'answer can react again', (WidgetTester tester) async {
      // The reset [ReactionAvatar] needs to replay a same-sign answer — the
      // port of the prototype's remove-class-and-reflow (`index.html:968`).
      await _mount(tester, sky: sky);

      await _tap(tester, strongName);
      await tester.pump(kDuelAdvanceDelay);

      expect(_cardReaction(tester, strongName), isNull);
      expect(_cardReaction(tester, weakName), isNull);
      await _drain(tester);
    });
  });
}

/// Tap something and rebuild — a single `pump`, never `pumpAndSettle`, because
/// the game leaves a real timer running and settling would advance the clock
/// through it and past the state under test.
Future<void> _tap(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pump();
}

/// Let the round's pending timer fire, so a test that ends mid-reveal does not
/// leave one behind for the framework to complain about.
Future<void> _drain(WidgetTester tester) =>
    tester.pump(kDuelGameOverDelay + kDuelAdvanceDelay);

/// The big number in the score-bar cell captioned [label].
String _scoreValue(WidgetTester tester, String label) {
  final Finder cell = find
      .ancestor(of: find.text(label), matching: find.byType(Column))
      .first;
  final Text value = tester.widget<Text>(
    find.descendant(of: cell, matching: find.byType(Text)).first,
  );
  return value.data!;
}

Future<void> _mount(
  WidgetTester tester, {
  required List<Asteroid> sky,
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
        asteroidFeedProvider.overrideWith((Ref ref) => _feed(sky)),
        gameActionsProvider.overrideWithValue(actions ?? _RecordingActions()),
        // Nothing here asserts on sound; these keep the audio plugin and the
        // real store off the answer path. `game_sound_test.dart` owns the cues.
        soundEngineProvider.overrideWithValue(RecordingSoundEngine()),
        soundOnProvider.overrideWith(() => StubSoundOn(true)),
        reducedMotionProvider.overrideWith(StubCalmMotion.new),
      ],
      child: MaterialApp(
        home: _ReactionSpy(onReaction: onReaction, child: const DuelGame()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

AsteroidFeed _feed(List<Asteroid> asteroids) {
  return AsteroidFeed(
    asteroids: asteroids,
    todayList: asteroids,
    feedRange: 'sample data',
    provenance: FeedProvenance.sample,
  );
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
  _RecordingActions({this.bestDuel = 0});

  int played = 0;
  final List<int> awarded = <int>[];
  final List<int> bestDuelWrites = <int>[];
  final List<int> streakNotes = <int>[];

  @override
  int bestDuel;

  @override
  int get points => awarded.fold(0, (int sum, int n) => sum + n);

  @override
  Future<void> markPlayed() async => played++;

  @override
  Future<void> awardPoints(int n) async {
    if (n > 0) awarded.add(n);
  }

  @override
  Future<void> setBestDuel(int streak) async {
    bestDuelWrites.add(streak);
    bestDuel = streak;
  }

  @override
  Future<void> noteStreak(int streak) async => streakNotes.add(streak);

  // Closer or Farther's half of the surface; Power Duel never touches it.
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

/// The motion the avatar on [animalName]'s card is playing, or null if that
/// card is sitting still.
Reaction? _cardReaction(WidgetTester tester, String animalName) {
  final Finder card = find
      .ancestor(of: find.text(animalName), matching: find.byType(Column))
      .first;
  return tester
      .widget<ReactionAvatar>(
        find.descendant(of: card, matching: find.byType(ReactionAvatar)),
      )
      .reaction;
}

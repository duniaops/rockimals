import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/core/animals/animal_system.dart';
import 'package:rockimals/core/audio/sound_engine.dart';
import 'package:rockimals/data/models/asteroid.dart';
import 'package:rockimals/data/models/asteroid_feed.dart';
import 'package:rockimals/features/data/providers.dart';
import 'package:rockimals/features/games/closer_game.dart';
import 'package:rockimals/features/games/game_shell.dart';
import 'package:rockimals/features/games/games_hub.dart';
import 'package:rockimals/features/games/games_providers.dart';
import 'package:rockimals/features/rewards/reaction.dart';
import 'package:rockimals/features/settings/calm_motion.dart';

import '../../support/recording_sound_engine.dart';
import '../../support/stub_settings.dart';

/// Closer or Farther end to end (`specs/04`, game 3). The deal and the
/// comparison are pinned in `closer_pairing_test.dart`; this suite is the screen
/// — answering, the chain, the two delays, and the store seams.
///
/// **The sky is exactly two animals, as in the duel suite — but this game's two
/// roles are not interchangeable, so every test asks the board which is which.**
/// The duel shows both cards and a test can tap either by name; here one animal
/// is the anchor (on the card, distance shown) and the other is the challenger
/// (in the question, distance hidden), and the deal picks the anchor at random.
/// So [_anchorOf] reads the anchor off the screen and the correct button follows
/// from it. That works because the anchor's name is a plain [Text] while the
/// question and the reveal are `Text.rich` — `find.text` skips rich text unless
/// asked, which makes the card the one unambiguous place a name appears.
///
/// **The store is stood in front of, not written to** — real Hive I/O awaited
/// inside `testWidgets` deadlocks the fake clock (the Play hub suite's rule), so
/// a recording [GameActions] takes the writes and the persistence promises are
/// tested where `await` works (`game_shell_test.dart`).
void main() {
  // Far apart in distance, so the deal's 0.05 gap is satisfied on the first draw
  // whichever rock it opens on.
  final Asteroid near = _rock('2020 AAA', missLunar: 0.4);
  final Asteroid far = _rock('2020 BBB', missLunar: 12);
  final List<Asteroid> sky = <Asteroid>[near, far];

  setUp(() {
    // Names are hashed from the designation and 24 names over 2 rocks can
    // collide (the naming item's pigeonhole note). These two do not — if a
    // future edit to the fixture made them, [_anchorOf] would silently pick the
    // wrong rock and every "correct answer" below would be a coin flip.
    expect(
      critter(near).name,
      isNot(critter(far).name),
      reason: 'fixture names must differ',
    );
  });

  group('starting a round', () {
    testWidgets('asks the question, counts the play, and starts at zero', (
      WidgetTester tester,
    ) async {
      final _RecordingActions actions = _RecordingActions();
      await _mount(tester, sky: sky, actions: actions);

      expect(find.text('📏 Closer or Farther'), findsOneWidget);
      expect(find.text('⬇ Closer'), findsOneWidget);
      expect(find.text('⬆ Farther'), findsOneWidget);
      expect(_scoreValue(tester, 'STREAK'), '0');
      // `markPlayed()` before the first round (`index.html:1061`).
      expect(actions.played, 1);

      final Asteroid anchor = _anchorOf(sky);
      final Asteroid challenger = _otherThan(anchor, sky);
      // The anchor states its distance — it is what the child measures against.
      expect(
        find.text('flies ${distLabel(anchor.missLunar)} from Earth'),
        findsOneWidget,
      );
      // The challenger's distance is the answer, so it stays off the board.
      expect(
        find.textContaining(
          distLabel(challenger.missLunar),
          findRichText: true,
        ),
        findsNothing,
      );
    });

    testWidgets('seeds BEST from storage', (WidgetTester tester) async {
      await _mount(tester, sky: sky, actions: _RecordingActions(bestCloser: 6));

      expect(_scoreValue(tester, 'BEST'), '6');
    });

    testWidgets('never shows a real designation — only animal names '
        '(CLAUDE.md:71)', (WidgetTester tester) async {
      await _mount(tester, sky: sky);
      for (final Asteroid a in sky) {
        expect(find.textContaining(a.name, findRichText: true), findsNothing);
      }
    });
  });

  group('a correct answer', () {
    testWidgets('reveals where the animal really flies, awards 10, and extends '
        'the streak', (WidgetTester tester) async {
      final _RecordingActions actions = _RecordingActions();
      await _mount(tester, sky: sky, actions: actions);

      final Asteroid challenger = _otherThan(_anchorOf(sky), sky);
      await _tap(tester, _correctLabel(sky));

      // The reveal names the distance *before* the verdict — the answer is a
      // real fact about a real rock, not a score (`index.html:1078`).
      expect(
        find.text(_revealText(sky, win: true), findRichText: true),
        findsOneWidget,
      );
      expect(_scoreValue(tester, 'STREAK'), '1');
      expect(actions.awarded, <int>[10]);
      expect(
        find.textContaining(
          distLabel(challenger.missLunar),
          findRichText: true,
        ),
        findsOneWidget,
      );

      await _drain(tester);
    });

    testWidgets('persists the new best and notes the cross-game streak', (
      WidgetTester tester,
    ) async {
      final _RecordingActions actions = _RecordingActions();
      await _mount(tester, sky: sky, actions: actions);

      await _tap(tester, _correctLabel(sky));

      // `aw_closer` (this game's best) and `aw_bstreak` (the profile's all-time
      // run of right answers) are two different records fed the same number
      // here (`index.html:1079`).
      expect(actions.bestCloserWrites, <int>[1]);
      expect(actions.streakNotes, <int>[1]);
      expect(_scoreValue(tester, 'BEST'), '1');

      await _drain(tester);
    });

    testWidgets('does not lower an existing best', (WidgetTester tester) async {
      final _RecordingActions actions = _RecordingActions(bestCloser: 6);
      await _mount(tester, sky: sky, actions: actions);

      await _tap(tester, _correctLabel(sky));

      // A streak of 1 against a best of 6 writes nothing
      // (`if(closerScore>bestCloser)`, `index.html:1079`).
      expect(actions.bestCloserWrites, isEmpty);
      expect(_scoreValue(tester, 'BEST'), '6');

      await _drain(tester);
    });

    testWidgets('does not rewrite a best it merely ties', (
      WidgetTester tester,
    ) async {
      final _RecordingActions actions = _RecordingActions(bestCloser: 1);
      await _mount(tester, sky: sky, actions: actions);

      await _tap(tester, _correctLabel(sky));

      // A streak of 1 against a best of 1 is not a new record
      // (`if(closerScore>bestCloser)`, `index.html:1079`), and the assertion has
      // to be about the *write*: with `>=` the stored number would be identical,
      // so every value on screen and in the box stays 1 and only the wasted disk
      // write distinguishes the two. (The same trap the duel's `noteStreak` tie
      // test fell into first.)
      expect(actions.bestCloserWrites, isEmpty);
      expect(_scoreValue(tester, 'BEST'), '1');

      await _drain(tester);
    });

    testWidgets('promotes the challenger to anchor after 1250ms — the chain '
        'advances', (WidgetTester tester) async {
      final _RecordingActions actions = _RecordingActions();
      await _mount(tester, sky: sky, actions: actions);

      final Asteroid firstAnchor = _anchorOf(sky);
      final Asteroid challenger = _otherThan(firstAnchor, sky);

      await _tap(tester, _correctLabel(sky));
      // Just short of the delay: still reading the reveal.
      await tester.pump(const Duration(milliseconds: 1249));
      expect(
        find.text(_revealText(sky, win: true), findRichText: true),
        findsOneWidget,
      );

      await tester.pump(const Duration(milliseconds: 1));
      // `closerAnchor=ch` (`index.html:1079`) — the animal just guessed about is
      // now the one on the card, so each answer is measured against what the
      // child has just learned.
      expect(_anchorOf(sky), same(challenger));
      expect(
        find.text('flies ${distLabel(challenger.missLunar)} from Earth'),
        findsOneWidget,
      );
      // The banner is clear again, the streak survives, and it is one play.
      expect(find.textContaining('flies', findRichText: true), findsOneWidget);
      expect(_scoreValue(tester, 'STREAK'), '1');
      expect(actions.played, 1);
    });

    testWidgets('a second tap during the reveal is ignored', (
      WidgetTester tester,
    ) async {
      final _RecordingActions actions = _RecordingActions();
      final List<bool> reactions = <bool>[];
      await _mount(
        tester,
        sky: sky,
        actions: actions,
        onReaction: reactions.add,
      );

      await _tap(tester, _correctLabel(sky));
      final String reveal = _revealText(sky, win: true);
      // The prototype disables both buttons on the first tap
      // (`index.html:1074`), so an excited double-tap cannot bank two answers —
      // nor end the run by hitting the wrong one next.
      await _tap(tester, _wrongLabel(sky));

      expect(actions.awarded, <int>[10]);
      expect(_scoreValue(tester, 'STREAK'), '1');
      // **The points and the streak alone cannot catch this** — a wrong answer
      // scores nothing and does not touch the streak, so both are identical
      // whether or not the second tap landed. What changes is everything else:
      // the board would flip to the losing reveal, fire a sad cue, and start a
      // game-over timer. So the assertions are about those.
      expect(find.text(reveal, findRichText: true), findsOneWidget);
      expect(reactions, <bool>[true], reason: 'one cheer, no sad follow-up');

      // Long enough for a game-over timer to have fired; instead the round's own
      // advance carries the run on.
      await tester.pump(kCloserGameOverDelay);
      expect(find.text('GAME OVER'), findsNothing);

      await _drain(tester);
    });

    testWidgets('publishes a happy reaction on the shared channel', (
      WidgetTester tester,
    ) async {
      final List<bool> reactions = <bool>[];
      await _mount(tester, sky: sky, onReaction: reactions.add);

      await _tap(tester, _correctLabel(sky));

      expect(reactions, <bool>[true]);
      await _drain(tester);
    });
  });

  group('a wrong answer', () {
    testWidgets('is encouraging, awards nothing, and ends the run after '
        '1350ms', (WidgetTester tester) async {
      final _RecordingActions actions = _RecordingActions();
      await _mount(tester, sky: sky, actions: actions);

      await _tap(tester, _wrongLabel(sky));

      // Never harsh (`CLAUDE.md:70`), and it still teaches: the true distance
      // and direction are stated whichever way the child guessed.
      expect(
        find.text(_revealText(sky, win: false), findRichText: true),
        findsOneWidget,
      );
      expect(actions.awarded, isEmpty);

      await tester.pump(const Duration(milliseconds: 1349));
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
      await _tap(tester, _correctLabel(sky));
      await tester.pump(kCloserAdvanceDelay);
      await _tap(tester, _wrongLabel(sky));
      await tester.pump(kCloserGameOverDelay);

      expect(find.text('1'), findsOneWidget);
      // `"best streak "+bestCloser+" · ⭐ "+points+" points"`
      // (`index.html:1080`).
      expect(find.text('best streak 1 · ⭐ 10 points'), findsOneWidget);
    });

    testWidgets('publishes a sad reaction on the shared channel', (
      WidgetTester tester,
    ) async {
      final List<bool> reactions = <bool>[];
      await _mount(tester, sky: sky, onReaction: reactions.add);

      await _tap(tester, _wrongLabel(sky));

      expect(reactions, <bool>[false]);
      await _drain(tester);
    });

    testWidgets('Play again starts a fresh run and counts another play', (
      WidgetTester tester,
    ) async {
      final _RecordingActions actions = _RecordingActions();
      await _mount(tester, sky: sky, actions: actions);

      await _tap(tester, _correctLabel(sky));
      await tester.pump(kCloserAdvanceDelay);
      await _tap(tester, _wrongLabel(sky));
      await tester.pump(kCloserGameOverDelay);

      await _tap(tester, 'Play again');

      // `startCloser` again (`index.html:1080`): the score is back to zero, the
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
          // The avatars resolve 🐢 Calm motion to time their hop, and the real
          // notifier reads the store. Held at "never chose", so these tests
          // measure the full-length reaction as they did before the setting.
          reducedMotionProvider.overrideWith(StubCalmMotion.new),
        ],
        child: const MaterialApp(home: GamesHub()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Closer or Farther'));
    await tester.pumpAndSettle();

    expect(find.text('📏 Closer or Farther'), findsOneWidget);
    expect(find.text('This game is on its way — coming soon!'), findsNothing);
  });

  group('the reaction (specs/05)', () {
    testWidgets('a correct answer hops the anchor animal', (
      WidgetTester tester,
    ) async {
      await _mount(tester, sky: sky);

      await _tap(tester, _correctLabel(sky));

      // `react($("gameBody").querySelector('.avatar'), win)`
      // (`index.html:1076`) — and the anchor card holds the only `.avatar` in
      // this game's body, so it is the one that performs.
      expect(_soloReaction(tester), Reaction.happy);
      await _drain(tester);
    });

    testWidgets('a wrong answer wobbles it instead', (
      WidgetTester tester,
    ) async {
      await _mount(tester, sky: sky);

      await _tap(tester, _wrongLabel(sky));

      expect(_soloReaction(tester), Reaction.sad);
      await _drain(tester);
    });

    testWidgets('the next round opens with the new anchor still', (
      WidgetTester tester,
    ) async {
      await _mount(tester, sky: sky);

      await _tap(tester, _correctLabel(sky));
      await tester.pump(kCloserAdvanceDelay);

      expect(_soloReaction(tester), isNull);
      await _drain(tester);
    });
  });
}

/// Which rock the deal put on the anchor card, read off the board.
///
/// The anchor's name is the one place a name renders as a plain [Text]; the
/// question and the reveal are `Text.rich`, which `find.text` skips by default.
Asteroid _anchorOf(List<Asteroid> sky) => sky.firstWhere(
  (Asteroid a) => find.text(critter(a).name).evaluate().isNotEmpty,
  orElse: () => throw StateError('no anchor card on screen'),
);

Asteroid _otherThan(Asteroid a, List<Asteroid> sky) =>
    sky.firstWhere((Asteroid x) => !identical(x, a));

/// The button that wins this round, given whichever anchor the deal chose.
String _correctLabel(List<Asteroid> sky) {
  final Asteroid anchor = _anchorOf(sky);
  final Asteroid challenger = _otherThan(anchor, sky);
  return challenger.missLunar < anchor.missLunar ? '⬇ Closer' : '⬆ Farther';
}

String _wrongLabel(List<Asteroid> sky) =>
    _correctLabel(sky) == '⬇ Closer' ? '⬆ Farther' : '⬇ Closer';

/// The reveal sentence for the round currently on screen (`index.html:1078`).
String _revealText(List<Asteroid> sky, {required bool win}) {
  final Asteroid anchor = _anchorOf(sky);
  final Asteroid challenger = _otherThan(anchor, sky);
  final Critter c = critter(challenger);
  final String direction = challenger.missLunar < anchor.missLunar
      ? 'closer'
      : 'farther';
  final String outcome = win ? '✓ +10 ⭐' : '✗ good try!';
  return '${c.animal.emoji} ${c.name} flies '
      '${distLabel(challenger.missLunar)} — $direction. $outcome';
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
    tester.pump(kCloserGameOverDelay + kCloserAdvanceDelay);

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
        home: _ReactionSpy(onReaction: onReaction, child: const CloserGame()),
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
  _RecordingActions({this.bestCloser = 0});

  int played = 0;
  final List<int> awarded = <int>[];
  final List<int> bestCloserWrites = <int>[];
  final List<int> streakNotes = <int>[];

  @override
  int bestCloser;

  @override
  int bestDuel = 0;

  @override
  int get points => awarded.fold(0, (int sum, int n) => sum + n);

  @override
  Future<void> markPlayed() async => played++;

  @override
  Future<void> awardPoints(int n) async {
    if (n > 0) awarded.add(n);
  }

  @override
  Future<void> setBestCloser(int streak) async {
    bestCloserWrites.add(streak);
    bestCloser = streak;
  }

  @override
  Future<void> setBestDuel(int streak) async => bestDuel = streak;

  @override
  int bestSize = 0;

  @override
  Future<void> setBestSize(int score) async => bestSize = score;

  @override
  Future<void> notePerfectRun() async {}

  @override
  Future<void> noteStreak(int streak) async => streakNotes.add(streak);
}

/// The sound toggle with the store taken out — the hub reads it on build.
class _StubSound extends SoundOnNotifier {
  @override
  bool build() => true;
}

Asteroid _rock(String name, {required double missLunar}) {
  return Asteroid(
    name: name,
    diaMax: 120,
    diaMin: 60,
    hazardous: false,
    missLunar: missLunar,
    missKm: missLunar * 384400,
    velKps: 15,
    mag: 20,
    jpl: 'https://ssd.jpl.nasa.gov/tools/sbdb_lookup.html',
    date: '2026-07-16',
  );
}

/// The motion the one avatar on screen is playing, or null if it is still.
Reaction? _soloReaction(WidgetTester tester) =>
    tester.widget<ReactionAvatar>(find.byType(ReactionAvatar)).reaction;

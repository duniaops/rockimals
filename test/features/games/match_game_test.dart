import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/core/animals/animal_system.dart';
import 'package:rockimals/data/models/asteroid.dart';
import 'package:rockimals/data/models/asteroid_feed.dart';
import 'package:rockimals/features/data/providers.dart';
import 'package:rockimals/features/games/game_shell.dart';
import 'package:rockimals/features/games/games_hub.dart';
import 'package:rockimals/features/games/games_providers.dart';
import 'package:rockimals/features/games/match_game.dart';
import 'package:rockimals/features/games/match_round.dart';
import 'package:rockimals/features/rewards/reaction.dart';

/// Animal Match end to end (`specs/04`, game 4). The deal is pinned in
/// `match_round_test.dart`; this suite is the screen — answering, the 1400ms
/// advance, the eight-round run, and the two records a finished run banks.
///
/// **The sky is a single rock, which makes every round the same question.** The
/// other three games shrink the sky to two so a test knows both animals; here
/// the hidden truth is the species, and the deal draws a fresh rock each round,
/// so a two-rock sky would leave the answer unknown from round to round. One
/// rock fixes the answer for the whole run — the game happily asks about it
/// eight times (the deal has no memory, by design) — and every test can name the
/// button it wants without seeding a `Random` into the widget.
///
/// **The store is stood in front of, not written to** — real Hive I/O awaited
/// inside `testWidgets` deadlocks the fake clock (the Play hub suite's rule), so
/// a recording [GameActions] takes the writes and the persistence promises are
/// tested where `await` works (`game_shell_test.dart`).
void main() {
  // 302 m — two metres over the Bear/Elephant boundary, so it is the real datum
  // the size-ladder item kept as a permanent boundary test rather than a round
  // number that could sit anywhere in its rung.
  final Asteroid rock = _rock('2020 AAA', diaMax: 302);
  final List<Asteroid> sky = <Asteroid>[rock];
  final Animal answer = animalFor(rock);

  setUp(() {
    // If a future edit to the fixture moved it off the Elephant rung, the
    // vowel-article assertions below would silently stop testing that branch.
    expect(answer.species, 'Elephant');
  });

  group('starting a run', () {
    testWidgets('asks the width, hides the animal, and counts the play', (
      WidgetTester tester,
    ) async {
      final _RecordingActions actions = _RecordingActions();
      await _mount(tester, sky: sky, actions: actions);

      expect(find.text('🐾 Animal Match'), findsOneWidget);
      expect(_scoreValue(tester, 'ROUND'), '1/8');
      expect(_scoreValue(tester, 'CORRECT'), '0');
      // `markPlayed()` before the first round (`index.html:1088`).
      expect(actions.played, 1);

      // The rock is a mystery: its width is the only clue on the board.
      expect(find.text('❓'), findsOneWidget);
      expect(find.textContaining('302 m', findRichText: true), findsOneWidget);
      // The answer is not on the board — only in one of the three buttons.
      expect(find.text(answer.emoji), findsNothing);
    });

    testWidgets('offers exactly three species to choose from', (
      WidgetTester tester,
    ) async {
      await _mount(tester, sky: sky);

      final List<Animal> onScreen = _optionsOnScreen();
      expect(onScreen, hasLength(kMatchOptions));
      expect(
        onScreen.where((Animal a) => a.species == answer.species),
        hasLength(1),
      );
    });

    testWidgets('never shows a real designation — only species names '
        '(CLAUDE.md:71)', (WidgetTester tester) async {
      await _mount(tester, sky: sky);

      expect(find.textContaining(rock.name, findRichText: true), findsNothing);
    });
  });

  group('a correct answer', () {
    testWidgets('reveals the animal, awards 10, and counts it', (
      WidgetTester tester,
    ) async {
      final _RecordingActions actions = _RecordingActions();
      await _mount(tester, sky: sky, actions: actions);

      await _tap(tester, _label(answer));

      // The "❓" becomes the real animal — the beat this game exists for
      // (`$("szRock").textContent=an.emoji`, `index.html:1112`).
      expect(find.text('❓'), findsNothing);
      expect(find.text(answer.emoji), findsOneWidget);
      // `Yes! 🐘 It’s a <b>Elephant</b>! +10 ⭐` (`index.html:1115`) — with the
      // article agreeing with the species (see the port note in the banner).
      expect(
        find.text(
          'Yes! ${answer.emoji} It’s an Elephant! +10 ⭐',
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(actions.awarded, <int>[10]);
      expect(_scoreValue(tester, 'CORRECT'), '1');

      await _drain(tester);
    });

    testWidgets('publishes a happy reaction on the shared channel', (
      WidgetTester tester,
    ) async {
      final List<bool> reactions = <bool>[];
      await _mount(tester, sky: sky, onReaction: reactions.add);

      await _tap(tester, _label(answer));

      expect(reactions, <bool>[true]);
      await _drain(tester);
    });

    testWidgets('advances to the next round after 1400ms', (
      WidgetTester tester,
    ) async {
      await _mount(tester, sky: sky);

      await _tap(tester, _label(answer));
      await tester.pump(const Duration(milliseconds: 1399));
      // Still reading the reveal.
      expect(_scoreValue(tester, 'ROUND'), '1/8');
      expect(find.text('❓'), findsNothing);

      await tester.pump(const Duration(milliseconds: 1));

      // `setTimeout(sizeRound,1400)` (`index.html:1116`): a fresh mystery, the
      // banner cleared, the score carried over.
      expect(_scoreValue(tester, 'ROUND'), '2/8');
      expect(_scoreValue(tester, 'CORRECT'), '1');
      expect(find.text('❓'), findsOneWidget);
      expect(find.textContaining('It’s', findRichText: true), findsNothing);
    });
  });

  group('a wrong answer', () {
    testWidgets('names the animal encouragingly, scores nothing, and plays on', (
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

      await _tap(tester, _label(_wrongOption()));

      // Never harsh (`CLAUDE.md:70`), and it still teaches: the true animal is
      // named whichever way the child guessed (`index.html:1115`).
      expect(
        find.text(
          'It’s ${answer.emoji} an Elephant — you’ll get the next one!',
          findRichText: true,
        ),
        findsOneWidget,
      );
      // The rock turns into the animal on a wrong answer too — the child is
      // shown what it was, not just told they missed. (One match, not two: the
      // banner's copy of the emoji is inside a `Text.rich`, which `find.text`
      // skips by default.)
      expect(find.text(answer.emoji), findsOneWidget);
      expect(actions.awarded, isEmpty);
      expect(_scoreValue(tester, 'CORRECT'), '0');
      expect(reactions, <bool>[false]);

      // Unlike the two streak games, a wrong answer does not end the run.
      await tester.pump(kMatchAdvanceDelay);
      expect(find.text('ALL DONE!'), findsNothing);
      expect(_scoreValue(tester, 'ROUND'), '2/8');
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

      final String wrongLabel = _label(_wrongOption());
      await _tap(tester, wrongLabel);
      // The prototype disables every option on the first tap
      // (`index.html:1110`), so an excited double-tap cannot turn a wrong
      // answer into a right one.
      await _tap(tester, _label(answer));

      // **The score alone cannot catch this** — a second tap that scored would
      // read 1, but so would a first tap on the right answer, so the assertion
      // has to be that nothing *else* moved either: no points, one sad cue, and
      // the losing banner still on screen.
      //
      // **Two independent layers stop the tap, and this test cannot tell them
      // apart** (found by mutation): the revealed board passes `onTap: null`,
      // *and* `_pick` returns early on an answered round. Removing either alone
      // leaves this green; only removing both fails it. That is defence in
      // depth rather than dead code — the guard is what would still hold if a
      // later item (task 05's reactions) rebuilt the button — but a future
      // agent should know the mutation that proves this suite bites is the pair,
      // not either one.
      expect(_scoreValue(tester, 'CORRECT'), '0');
      expect(actions.awarded, isEmpty);
      expect(reactions, <bool>[false], reason: 'one cue, no cheer after it');
      expect(
        find.textContaining('you’ll get the next one!', findRichText: true),
        findsOneWidget,
      );

      await _drain(tester);
    });
  });

  group('finishing a run', () {
    testWidgets('eight rounds end on ALL DONE! with the score out of 8', (
      WidgetTester tester,
    ) async {
      final _RecordingActions actions = _RecordingActions();
      await _mount(tester, sky: sky, actions: actions);

      // Seven right, one wrong — a good run that is not a perfect one.
      for (int i = 0; i < kMatchRounds; i++) {
        expect(_scoreValue(tester, 'ROUND'), '${i + 1}/8');
        await _answer(tester, correct: i != 3);
      }

      // Not "GAME OVER": nobody loses this one (`index.html:1093`).
      expect(find.text('ALL DONE!'), findsOneWidget);
      expect(find.text('7/8'), findsOneWidget);
      // `"best "+bestSize+"/8 · ⭐ "+points+" points"`.
      expect(find.text('best 7/8 · ⭐ 70 points'), findsOneWidget);
      expect(find.text('Play again'), findsOneWidget);
      expect(find.text('Back to games'), findsOneWidget);

      // A 7 is a new best but not a perfect run.
      expect(actions.bestSizeWrites, <int>[7]);
      expect(actions.perfectRuns, 0);
    });

    testWidgets('8/8 records a perfect run', (WidgetTester tester) async {
      final _RecordingActions actions = _RecordingActions();
      await _mount(tester, sky: sky, actions: actions);

      for (int i = 0; i < kMatchRounds; i++) {
        await _answer(tester, correct: true);
      }

      expect(find.text('8/8'), findsOneWidget);
      // `prog.perfect++` (`index.html:1092`) — the Perfect Match badge's
      // condition, banked exactly once for the run.
      expect(actions.perfectRuns, 1);
      expect(actions.bestSizeWrites, <int>[8]);
      expect(find.text('best 8/8 · ⭐ 80 points'), findsOneWidget);
    });

    testWidgets('does not lower an existing best', (WidgetTester tester) async {
      final _RecordingActions actions = _RecordingActions(bestSize: 6);
      await _mount(tester, sky: sky, actions: actions);

      // Two right, six wrong.
      for (int i = 0; i < kMatchRounds; i++) {
        await _answer(tester, correct: i < 2);
      }

      // `if(sizeScore>bestSize)` (`index.html:1091`) — a 2 against a 6 writes
      // nothing, and the end screen still reports the 6.
      expect(actions.bestSizeWrites, isEmpty);
      expect(find.text('2/8'), findsOneWidget);
      expect(find.text('best 6/8 · ⭐ 20 points'), findsOneWidget);
    });

    testWidgets('does not rewrite a best it merely ties', (
      WidgetTester tester,
    ) async {
      final _RecordingActions actions = _RecordingActions(bestSize: 3);
      await _mount(tester, sky: sky, actions: actions);

      for (int i = 0; i < kMatchRounds; i++) {
        await _answer(tester, correct: i < 3);
      }

      // A 3 against a best of 3 is not a record. The assertion has to be about
      // the *write*: with `>=` the stored number would be identical, so nothing
      // on screen or in the box would differ — only the wasted disk write does
      // (the same trap the duel and closer suites hit first).
      expect(actions.bestSizeWrites, isEmpty);
      expect(find.text('best 3/8 · ⭐ 30 points'), findsOneWidget);
    });

    testWidgets('banks nothing until the eighth reveal has passed', (
      WidgetTester tester,
    ) async {
      final _RecordingActions actions = _RecordingActions();
      await _mount(tester, sky: sky, actions: actions);

      for (int i = 0; i < kMatchRounds - 1; i++) {
        await _answer(tester, correct: true);
      }
      await _tap(tester, _label(answer));

      // The eighth answer is in and the reveal is on screen, but `sizeRound`
      // does the banking on its *next* call (`index.html:1090-1093`) — so a
      // child who backs out here banks nothing, as in the prototype.
      expect(actions.bestSizeWrites, isEmpty);
      expect(actions.perfectRuns, 0);
      expect(find.text('ALL DONE!'), findsNothing);

      await tester.pump(kMatchAdvanceDelay);
      expect(actions.bestSizeWrites, <int>[8]);
      expect(actions.perfectRuns, 1);
    });

    testWidgets('Play again starts a fresh run and counts another play', (
      WidgetTester tester,
    ) async {
      final _RecordingActions actions = _RecordingActions();
      await _mount(tester, sky: sky, actions: actions);

      for (int i = 0; i < kMatchRounds; i++) {
        await _answer(tester, correct: true);
      }
      await _tap(tester, 'Play again');

      // `startSize` again (`index.html:1093`): round and score back to the top,
      // the board back, and the play counted a second time.
      expect(find.text('ALL DONE!'), findsNothing);
      expect(_scoreValue(tester, 'ROUND'), '1/8');
      expect(_scoreValue(tester, 'CORRECT'), '0');
      expect(find.text('❓'), findsOneWidget);
      expect(actions.played, 2);
    });
  });

  testWidgets('the hub launches the real game, and Back returns to the hub', (
    WidgetTester tester,
  ) async {
    // Animal Match was the last card still routed to the hub's "coming soon"
    // placeholder, so this test carries what the hub suite's own placeholder
    // tests used to cover: the card reaches its game, and the game's back
    // button reaches the hub again.
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
        ],
        child: const MaterialApp(home: GamesHub()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Animal Match'));
    await tester.pumpAndSettle();
    expect(find.text('🐾 Animal Match'), findsOneWidget);
    expect(find.text('This game is on its way — coming soon!'), findsNothing);

    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pumpAndSettle();

    expect(find.text('🐾 Animal Match'), findsNothing);
    expect(find.text("Today's Challenge"), findsOneWidget);
  });

  group('the reaction (specs/05)', () {
    testWidgets('a correct answer hops the rock as it turns into an animal', (
      WidgetTester tester,
    ) async {
      await _mount(tester, sky: sky);

      await _tap(tester, _label(_optionsOnScreen().firstWhere(_isAnswer)));

      // `$("szRock").textContent=an.emoji; react($("szRock"), ok)`
      // (`index.html:1112`) — the reveal and the celebration are one beat.
      expect(_soloReaction(tester), Reaction.happy);
      await _drain(tester);
    });

    testWidgets('a wrong answer wobbles it — the animal still appears', (
      WidgetTester tester,
    ) async {
      await _mount(tester, sky: sky);

      await _tap(tester, _label(_wrongOption()));

      expect(_soloReaction(tester), Reaction.sad);
      await _drain(tester);
    });

    testWidgets('the next question opens with the rock still, so eight rounds '
        'each get their own reaction', (WidgetTester tester) async {
      await _mount(tester, sky: sky);

      await _answer(tester, correct: true);

      expect(_soloReaction(tester), isNull);
      await _drain(tester);
    });
  });
}

/// The label an option button renders (`${o.emoji}&nbsp;&nbsp;${o.species}`,
/// `index.html:1108`).
///
/// **The two spaces are non-breaking, and this cost a debugging round.** Typed
/// as literal spaces here the finder matched nothing while the widget was
/// plainly on screen, because U+00A0 and U+0020 are different characters that
/// look identical in an editor. Both sides now spell it `\u00A0` for that
/// reason — if this ever drifts again, compare `codeUnits`, not the rendering.
String _label(Animal a) => '${a.emoji}\u00A0\u00A0${a.species}';

/// Which three species the deal put on the board this round.
List<Animal> _optionsOnScreen() => kAnimals
    .where((Animal a) => find.text(_label(a)).evaluate().isNotEmpty)
    .toList();

/// Any option that is not the answer — the wrong button to tap.
Animal _wrongOption() =>
    _optionsOnScreen().firstWhere((Animal a) => !_isAnswer(a));

/// The one-rock sky fixes the answer for the whole suite (see the file doc), so
/// "which button is right" is a constant rather than something read off the
/// board.
bool _isAnswer(Animal a) => a.species == 'Elephant';

/// Answer the round on screen and let its 1400ms timer carry the game on.
Future<void> _answer(WidgetTester tester, {required bool correct}) async {
  final Animal option = correct
      ? _optionsOnScreen().firstWhere(_isAnswer)
      : _wrongOption();
  await _tap(tester, _label(option));
  await tester.pump(kMatchAdvanceDelay);
}

/// Tap something and rebuild — a single `pump`, never `pumpAndSettle`, because
/// the game leaves a real timer running and settling would advance the clock
/// through it and past the state under test.
Future<void> _tap(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pump();
}

/// Let a pending reveal timer fire, so a test that ends mid-round does not leave
/// one behind for the framework to complain about.
Future<void> _drain(WidgetTester tester) => tester.pump(kMatchAdvanceDelay);

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
    ..physicalSize = const Size(390, 900)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        asteroidFeedProvider.overrideWith((Ref ref) => _feed(sky)),
        gameActionsProvider.overrideWithValue(actions ?? _RecordingActions()),
      ],
      child: MaterialApp(
        home: _ReactionSpy(onReaction: onReaction, child: const MatchGame()),
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
  _RecordingActions({this.bestSize = 0});

  int played = 0;
  int perfectRuns = 0;
  final List<int> awarded = <int>[];
  final List<int> bestSizeWrites = <int>[];

  @override
  int bestSize;

  @override
  int bestCloser = 0;

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
  Future<void> setBestSize(int score) async {
    bestSizeWrites.add(score);
    bestSize = score;
  }

  @override
  Future<void> notePerfectRun() async => perfectRuns++;

  @override
  Future<void> setBestCloser(int streak) async => bestCloser = streak;

  @override
  Future<void> setBestDuel(int streak) async => bestDuel = streak;

  @override
  Future<void> noteStreak(int streak) async {}
}

/// The sound toggle with the store taken out — the hub reads it on build.
class _StubSound extends SoundOnNotifier {
  @override
  bool build() => true;
}

Asteroid _rock(String name, {required double diaMax}) {
  return Asteroid(
    name: name,
    diaMax: diaMax,
    diaMin: diaMax / 2,
    hazardous: false,
    missLunar: 4,
    missKm: 4 * 384400,
    velKps: 15,
    mag: 20,
    jpl: 'https://ssd.jpl.nasa.gov/tools/sbdb_lookup.html',
    date: '2026-07-16',
  );
}

/// The motion the one avatar on screen is playing, or null if it is still.
Reaction? _soloReaction(WidgetTester tester) =>
    tester.widget<ReactionAvatar>(find.byType(ReactionAvatar)).reaction;

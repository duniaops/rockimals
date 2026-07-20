/// **The tap-target audit's second half: the states a screen can be in.**
///
/// `tap_target_audit_test.dart` mounts every screen a child can reach and walks
/// the tree. That is necessary and it is not sufficient, and the gap had already
/// cost something real: the radar's selected-animal HUD card is not a screen, it
/// is a *state* of the radar tab, and its two buttons — one of them the primary
/// route into the whole detail screen — shipped at 31dp for as long as the walk
/// only ever tapped tab labels. Auditing a tab is not auditing the tab's states.
///
/// That one state is now covered in the audit file itself, next to the walk that
/// missed it. This file is the general form of the question: the named list of
/// (screen, state) pairs that a screen-shaped walk cannot reach, each with a
/// helper that drives it the way a child would.
///
/// **A separate file rather than more groups in the audit**, for two reasons.
/// The audit was already the slowest file in the suite, and `flutter test` runs
/// files concurrently but cases within a file serially — so splitting buys back
/// most of what these arms cost. And the two files are asking different
/// questions: one is exhaustive over screens and cheap per screen, this one is a
/// curated list that pays real setup per entry.
///
/// **Why every entry is a test and not a comment.** Three of the five states
/// below turn out, on inspection, to be unable to add an undersized target —
/// Sky's chips do not change size when selected, radar focus sets the very same
/// field a tap does, an empty Watchlist has no controls at all. The tempting
/// resolution is a paragraph saying so. But a paragraph is what the audit's own
/// class doc already was when it claimed to cover "every screen a child can
/// reach", and comments do not fail. Each claim below is instead written as the
/// assertion that would break if it stopped being true.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/core/a11y/control_scale.dart';
import 'package:rockimals/core/animals/animal_system.dart';
import 'package:rockimals/core/audio/sound_engine.dart';
import 'package:rockimals/data/fallback_asteroids.dart';
import 'package:rockimals/data/models/asteroid.dart';
import 'package:rockimals/data/models/asteroid_feed.dart';
import 'package:rockimals/features/data/providers.dart';
import 'package:rockimals/features/games/challenge_game.dart';
import 'package:rockimals/features/games/closer_game.dart';
import 'package:rockimals/features/games/duel_game.dart';
import 'package:rockimals/features/games/game_shell.dart';
import 'package:rockimals/features/games/match_game.dart';
import 'package:rockimals/features/radar/radar_focus.dart';
import 'package:rockimals/features/rewards/badge_controller.dart';
import 'package:rockimals/features/rewards/badge_popup.dart';
import 'package:rockimals/features/shell/app_shell.dart';

import '../support/memory_store.dart';
import '../support/recording_sound_engine.dart';
import '../support/tap_target_audit.dart';

void main() {
  // Both scales, for the reason the audit file gives: a target that clears 48
  // only because its label happens to be 15px is not a target that clears 48.
  // The small scale is where undersize shows up and the large one is where
  // overflow does, so neither alone is the worst case.
  for (final double scale in <double>[1.0, 1.5]) {
    final String at = scale == 1.0 ? '' : ' at $scale× text';

    group('states, not just screens$at', () {
      testWidgets('Sky\'s sort and filter chips, selected$at', (tester) async {
        // A selected chip is a `_Toggle` with a different fill, border and text
        // colour and **the same geometry** — `EdgeInsets.symmetric(horizontal:
        // 12, vertical: 7)` is a const shared by both states, and the weight is
        // w700 either way. So this arm is expected to pass, and what it is
        // really guarding is the change that would make it stop: a checkmark, a
        // leading icon, or a bolder selected label, any of which reflows the
        // pill inside its `TapTarget` and none of which the unselected walk in
        // the audit file would see.
        await _mount(tester, const AppShell(), scale: scale);
        await _openTab(tester, 'Sky');

        // Every chip in its selected state, not one representative: the three
        // sort chips are one widget with one label each, but the filter chip is
        // a different call site with a much longer label, and length is the
        // thing that moves a pill's width at 1.5× text.
        for (final String chip in <String>[
          'Biggest',
          'Fastest',
          'Closest',
          '👋 Close flybys only',
        ]) {
          await tester.tap(find.text(chip));
          await tester.pump(const Duration(milliseconds: 100));
          expectEveryTapTargetIsBigEnough(tester, reason: 'Sky · $chip$at');
        }
      });

      testWidgets('a populated Watchlist$at', (tester) async {
        // **The audit file visits this tab with an empty store**, so what it has
        // been auditing all along is the empty state — `Rusty` and a line of
        // text, which contains no interactive widget at all. The rows are the
        // half nobody was looking at.
        //
        // Not redundant with the Sky tab's rows, which are the same
        // `AnimalCard`: the Watchlist passes a `footer` that Sky does not, so
        // the card is taller here and its tap target is a different box.
        await _mount(
          tester,
          const AppShell(),
          scale: scale,
          store: MemoryStore(
            follows: const <String>['2004 BL86', '2012 DA14', '99942 Apophis'],
          ),
        );
        await _openTab(tester, 'My Animals');

        expect(
          find.textContaining('not following'),
          findsNothing,
          reason:
              'the follows did not take, so this arm audited the empty '
              'state the audit file already covers',
        );
        expectEveryTapTargetIsBigEnough(tester, reason: 'Watchlist rows$at');
      });

      testWidgets('the radar, focused from Show on radar$at', (tester) async {
        // Focus is the one state here that reaches an *already audited* widget:
        // `_focusOnRadar` sets `_selected`, the same field a tap on the field
        // sets, so the HUD card it raises is the card the audit file's
        // `_selectAnimal` arm already measures. The interesting difference is
        // that focus also resets zoom and rotation and can arrive from another
        // tab — so the card is built during a tab switch rather than in place.
        await _mount(tester, const AppShell(), scale: scale);
        // Away from the radar first, because arriving from elsewhere is the
        // whole path: `Show on radar` is a detail-screen button.
        await _openTab(tester, 'Sky');

        _container(tester).read(radarFocusProvider.notifier).focus(_rock);
        await tester.pump();
        await tester.pump(
          const Duration(milliseconds: 250),
        ); // the card's slide

        expect(
          find.textContaining('Meet '),
          findsOneWidget,
          reason:
              'focus did not raise the HUD card, so this arm audited the '
              'unselected radar',
        );
        expectEveryTapTargetIsBigEnough(tester, reason: 'Radar, focused$at');
      });

      testWidgets('the badge popup$at', (tester) async {
        // The popup is a `Stack` layer over the whole app, not a route, so it
        // does not replace what is under it — the shell's chrome is still
        // onstage and still audited while the scrim is up. That is the point:
        // the popup is the one place in the app where an undersized button can
        // hide *behind* a big interactive region, and `tap_target_audit.dart`'s
        // dedupe rule is bounded to `kMinTapTarget` of growth specifically so
        // this scrim cannot excuse it.
        //
        // Its own control is the full-screen dismiss `GestureDetector`, which
        // clears 48dp by a mile. Auditing it is therefore cheap insurance, and
        // the load-bearing half of this arm is that mounting it at 1.5× text
        // does not overflow the card.
        await _mount(
          tester,
          const AppShell(),
          scale: scale,
          store: _fiftyPoints(),
          badgeHost: true,
        );

        _container(tester).read(badgesProvider.notifier).check();
        await tester.pump();
        await tester.pump(kBadgePopupDuration);

        expect(
          find.textContaining('New badge!'),
          findsOneWidget,
          reason: 'no badge was celebrated, so this arm audited a plain shell',
        );
        expectEveryTapTargetIsBigEnough(tester, reason: 'Badge popup$at');

        // The hop never ends, so nothing here may settle; and `dismiss` arms a
        // real timer, so the popup has to be taken down rather than left up.
        await tester.tapAt(const Offset(20, 20));
        await tester.pump();
        await tester.pump(kBadgePopupDuration);
        await tester.pump(kBadgeDrainGap);
        await tester.pump(kBadgePopupDuration);
      });

      testWidgets('every game, once an answer is revealed$at', (tester) async {
        // **The state a child is in for a second after every single tap they
        // make in this app**, and the audit file has only ever seen the four
        // boards before the first tap. Revealing swaps a banner in, plays a
        // reaction on the avatar, and — in the games that keep the board — turns
        // the answer controls inert.
        //
        // Inert is why this arm asserts on the banner first. `onTap: null` reads
        // as non-interactive to the audit, so a game whose reveal did not
        // actually fire would present *fewer* targets and pass loudly.
        for (final _Game game in _games) {
          await _mount(
            tester,
            game.build(),
            scale: scale,
            feed: _gameSky,
            // Real `GameActions` over a `MemoryStore`: the games' own suites
            // stub this out because a Hive box awaited under the fake clock
            // deadlocks, but the store here is plain fields, so the writes an
            // answer triggers are honest and synchronous.
            store: MemoryStore(),
          );
          await game.answer(tester);

          expect(
            game.revealMarker,
            findsWidgets,
            reason: '${game.name} did not reach its revealed state',
          );
          expectEveryTapTargetIsBigEnough(
            tester,
            reason: '${game.name}, revealed$at',
          );

          // Every game but the challenge leaves a real timer running, and a
          // timer still pending when the tree goes away fails the test on
          // something other than what it asked.
          await tester.pump(game.drain);
        }
      });

      testWidgets('the panel a game ends on$at', (tester) async {
        // `GameOverPanel`'s two buttons — `Play again` and `Back to games` —
        // are controls that exist nowhere else in the app, and no screen-shaped
        // walk can reach them, because reaching them means losing.
        //
        // Duel and Closer, and not all four. Match's end panel is the same
        // `GameOverPanel` in the same `GameShell` chrome, reached only by
        // playing eight rounds; the challenge does not use the panel at all and
        // is covered by the reveal arm above, which is where its own
        // `Play again` / `Done` pair appears. Two instances of the shared panel
        // in two different games is the coverage; a third is wall-clock.
        await _mount(
          tester,
          const DuelGame(),
          scale: scale,
          feed: _gameSky,
          store: MemoryStore(),
        );
        // Losing on purpose, which means knowing which animal is weaker, which
        // means knowing which two the deal produced — and it is drawn from an
        // unseeded `Random`. So the pair is read back off the board rather than
        // predicted, and `power()` decides from there.
        for (int life = 3; life > 0; life--) {
          final List<Asteroid> pair = _dealt(tester);
          expect(
            pair,
            hasLength(2),
            reason: 'the duel board did not show two distinct animals',
          );
          pair.sort((Asteroid a, Asteroid b) => power(a).compareTo(power(b)));
          await _tap(tester, critter(pair.first).name);
          await _tap(tester, 'Next');
        }

        expect(
          find.text('Play again'),
          findsOneWidget,
          reason: 'the duel did not end, so this arm audited a live board',
        );
        expectEveryTapTargetIsBigEnough(tester, reason: 'Duel, game over$at');

        await _mount(
          tester,
          const CloserGame(),
          scale: scale,
          feed: _gameSky,
          store: MemoryStore(),
        );
        // Same idea as the duel, read off a different part of the board. The
        // question names the challenger ("Does 🐘 Suki fly closer or farther
        // than…") and the card underneath is the anchor, so the pair and their
        // roles are both recoverable — and once they are, the true answer is
        // just which of the two flies nearer.
        for (int life = 3; life > 0; life--) {
          await _tap(tester, _closerWrongAnswer(tester));
          await _tap(tester, 'Next');
        }

        expect(
          find.text('Play again'),
          findsOneWidget,
          reason:
              'the closer game did not end, so this arm audited a live '
              'board',
        );
        expectEveryTapTargetIsBigEnough(tester, reason: 'Closer, game over$at');
      });
    });
  }
}

/// One (screen, state) pair for the reveal arm: how to build the game, how a
/// child answers it, and the text that proves the answer landed.
///
/// **Every game plays the full bundled sky**, and an earlier draft of this file
/// did not — it handed the duel two rocks and the closer game two, on the theory
/// that a pool with one pair in it makes an unseeded deal predictable. It does
/// not. `dealDuelPair` draws its two animals *independently* and gives up after
/// 50 tries (`duel_pairing.dart:77`), so a two-rock pool deals the same rock
/// twice often enough to fail one run in three, and `dealCloserRound`'s
/// distance-gap rule has the same escape hatch. Both docstrings say outright
/// that the pool is meant to be the whole sky. So the deal is read back off the
/// board instead of predicted — see [_dealt].
class _Game {
  const _Game({
    required this.name,
    required this.build,
    required this.answer,
    required this.revealMarker,
    required this.drain,
  });

  final String name;
  final Widget Function() build;
  final Future<void> Function(WidgetTester) answer;

  /// Proof the answer actually landed, as a [Finder] rather than a string
  /// because the four games do not render their reveal the same way: three use
  /// a plain `Text`, and Match builds a `Text.rich` so it can bold the species —
  /// which a default `find.textContaining` walks straight past.
  final Finder revealMarker;

  /// Long enough to run out whatever timer the reveal armed.
  final Duration drain;
}

final List<_Game> _games = <_Game>[
  _Game(
    name: 'Challenge',
    build: ChallengeGame.new,
    // Rank all four, in whatever order the shuffle put them on the board: the
    // reveal only unlocks once every card has a place.
    answer: (WidgetTester tester) async {
      final List<Asteroid> cards = _dealt(tester);
      expect(
        cards,
        hasLength(4),
        reason: 'the challenge board did not deal four distinct animals',
      );
      for (final Asteroid a in cards) {
        await _tap(tester, critter(a).name);
      }
      await _tap(tester, 'Reveal the truth');
    },
    // The challenge grades a ranking rather than marking one answer, so its
    // revealed state is named by the button pair that replaces the ranking
    // controls.
    revealMarker: _text('Play again'),
    drain: Duration.zero,
  ),
  _Game(
    name: 'Duel',
    build: DuelGame.new,
    // Either card would reveal the round; the stronger one is tapped so this
    // arm lands on the winning banner and the end-panel arm below is the only
    // place a run is lost on purpose.
    answer: (WidgetTester tester) async {
      final List<Asteroid> pair = _dealt(tester);
      expect(
        pair,
        hasLength(2),
        reason: 'the duel board did not show two distinct animals',
      );
      pair.sort((Asteroid a, Asteroid b) => power(a).compareTo(power(b)));
      await _tap(tester, critter(pair.last).name);
    },
    // Either outcome, not just the winning one. Tapping the stronger animal is
    // correct by construction here, but a marker that only matches a win turns
    // a re-deal or a changed power formula into "the reveal is broken" instead
    // of a plain wrong answer — and the state under audit is the same either
    // way.
    revealMarker: _text(RegExp('Correct!|So close')),
    drain: kGameFeedbackAutoAdvanceDelay,
  ),
  _Game(
    name: 'Closer',
    build: CloserGame.new,
    // Either button reaches the same revealed state, so this arm does not need
    // to work out which one is true — the end-panel arm below is the one that
    // has to care.
    answer: (WidgetTester tester) => _tap(tester, '⬇ Closer'),
    // The common panel always gives the child a player-paced continuation.
    revealMarker: _text('Next'),
    drain: kGameFeedbackAutoAdvanceDelay,
  ),
  _Game(
    name: 'Match',
    build: MatchGame.new,
    // The three options are drawn from the species ladder, so their labels are
    // not predictable from the sky the way a duel's two names are. They are,
    // though, the only text in the app rendered as `emoji + two non-breaking
    // spaces + species` — which is a finder that does not care which three the
    // deal produced.
    //
    // The gap is written as an escape and not typed as two spaces on purpose:
    // it is two *non-breaking* spaces (`match_game.dart:418`, so a species that
    // wraps cannot strand the emoji alone on a line), and a literal-space finder
    // here matches nothing and fails as though the game were broken.
    answer: (WidgetTester tester) =>
        _tapFinder(tester, find.textContaining('\u00A0\u00A0').first),
    revealMarker: _text('Next'),
    drain: kGameFeedbackAutoAdvanceDelay,
  ),
];

/// A store already holding the 50 points that earn 🐭 Mouse Scout, so the badge
/// arm's `check()` has something to celebrate.
///
/// **A function and not a shared `final`**, which cost a confusing failure to
/// learn: a badge is earned once and then written to `store.badges`, so a second
/// arm running against the same instance finds nothing new, celebrates nothing,
/// and fails as though the popup were broken. Every arm gets its own store.
MemoryStore _fiftyPoints() => MemoryStore(points: 50);

/// The close flyby the radar-focus arm asks for, taken from the bundled sky so
/// the radar can match it by designation.
final Asteroid _rock = kFallbackAsteroids.firstWhere(
  (Asteroid a) => a.name == '2004 BL86',
);

/// The sky the four games play: the bundled set minus one rock.
///
/// **`2019 OK` is dropped because it is a homonym.** `critter()` names a rock by
/// hashing its designation and pairing that with its species, and across the 14
/// bundled rocks exactly one pair collides: `2010 WC9` and `2019 OK` are both
/// 130m — so both are Bears — and both hash to "Bruno". Homonyms are a
/// **decided, accepted** property of the naming rather than an open question:
/// see the argument on `kNamePool` and the assertions in
/// `test/core/animals/name_collisions_test.dart`. What they are not is
/// unambiguous, and [_dealt] needs unambiguity — one "Bruno the Bear" on the
/// board matches two asteroids, and the power comparison the duel needs then
/// has two different answers.
///
/// This drop stays even once the games reject a name-colliding deal (the open
/// plan item): that guard would keep two Brunos off the board *together*, which
/// is not the same as telling this file which single Bruno it is looking at.
///
/// Dropping one is honest in a way that special-casing the pair would not be —
/// 13 rocks is still well inside what `dealDuelPair` and `dealCloserRound` need
/// for their gap rules, and every arm here is about layout rather than about
/// which rocks are in the sky.
final List<Asteroid> _gameSkyRocks = kFallbackAsteroids
    .where((Asteroid a) => a.name != '2019 OK')
    .toList(growable: false);

final AsteroidFeed _gameSky = AsteroidFeed(
  asteroids: _gameSkyRocks,
  todayList: _gameSkyRocks,
  feedRange: 'sample data',
  provenance: FeedProvenance.sample,
);

/// Every string on screen, `Text.rich` spans flattened in with the plain ones.
///
/// `Text.data` is null for a rich span, so reading only `data` misses the closer
/// game's question and three of the four reveal banners — the exact places this
/// file needs to read.
List<String> _screenText(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((Text t) => t.data ?? t.textSpan?.toPlainText() ?? '')
    .where((String s) => s.isNotEmpty)
    .toList(growable: false);

/// Which animals a game actually dealt, recovered by matching the bundled sky
/// against the names written on the board.
///
/// **This is the answer to unseeded randomness**, and it is a better one than
/// seeding would be: the deal stays the game's own business, and what this file
/// asserts about is what a child can actually see. Every caller checks the
/// length it expects, so a deal that collapses — the same rock dealt twice, a
/// card that failed to render — fails as itself rather than as a missing tap.
List<Asteroid> _dealt(WidgetTester tester) {
  final List<String> screen = _screenText(tester);
  return _gameSkyRocks
      .where(
        (Asteroid a) => screen.any((String s) => s.contains(critter(a).name)),
      )
      .toList();
}

/// The button that loses the current closer round.
///
/// The question names the challenger and the card below it is the anchor, so
/// both ends of the comparison are on screen: whichever flies nearer settles
/// what `⬇ Closer` means this round, and the wrong button is the other one.
String _closerWrongAnswer(WidgetTester tester) {
  final List<Asteroid> dealt = _dealt(tester);
  expect(
    dealt,
    hasLength(2),
    reason: 'the closer board did not show an anchor and a challenger',
  );
  final String question = _screenText(
    tester,
  ).firstWhere((String s) => s.startsWith('Does '));
  final Asteroid challenger = dealt.firstWhere(
    (Asteroid a) => question.contains(critter(a).name),
  );
  final Asteroid anchor = dealt.firstWhere(
    (Asteroid a) => a.name != challenger.name,
  );
  return challenger.missLunar < anchor.missLunar ? '⬆ Farther' : '⬇ Closer';
}

/// Tap by label and rebuild once — never `pumpAndSettle`, which the games'
/// suites avoid for a reason this file inherits: a reveal arms a real timer, and
/// settling would run the clock through it and straight past the state under
/// test.
Future<void> _tap(WidgetTester tester, String label) =>
    _tapFinder(tester, find.text(label));

Finder _text(Pattern fragment) => find.textContaining(fragment);

Future<void> _tapFinder(WidgetTester tester, Finder finder) async {
  // Scrolled to first when there is something to scroll, because a game's board
  // is taller than a phone at 1.5× text and `tap` on an off-screen widget does
  // not fail — it warns, misses, and leaves the test asserting against a state
  // it never reached. The guard is what keeps this usable for the shell's nav
  // labels too, which have no [Scrollable] over them to ask.
  if (find
      .ancestor(of: finder, matching: find.byType(Scrollable))
      .evaluate()
      .isNotEmpty) {
    await tester.ensureVisible(finder);
    await tester.pump();
  }
  await tester.tap(finder);
  await tester.pump();
}

Future<void> _openTab(WidgetTester tester, String tab) async {
  await tester.tap(find.text(tab));
  await tester.pump(const Duration(milliseconds: 100));
}

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));

/// Mounts [home] with the feed, streak, store and audio all stood in front of,
/// so nothing here touches the network, a Hive box or the audio plugin.
///
/// The shape mirrors `tap_target_audit_test.dart`'s helper, with the two knobs
/// the states above need that the screens did not: a [store] a test can seed
/// (follows for the Watchlist, points for the badge), and a [feed] a game can
/// narrow to a sky whose deal is predictable.
///
/// [badgeHost] is opt-in rather than always on, and that is not tidiness: the
/// games award points, awarding points runs `badgesProvider.check()`, and a
/// popup raised mid-game would cover the very panel the game arms are there to
/// measure.
Future<void> _mount(
  WidgetTester tester,
  Widget home, {
  required double scale,
  AsteroidFeed? feed,
  MemoryStore? store,
  bool badgeHost = false,
}) async {
  tester.view
    ..physicalSize = const Size(390, 800)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final AsteroidFeed sky = feed ?? AsteroidFeed.fallback();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // Resolved, not pending: `AppShell` reads `requireValue`, so a feed
        // still loading would throw on the first build.
        asteroidFeedProvider.overrideWith((Ref ref) => sky),
        dayStreakProvider.overrideWithValue(0),
        storeProvider.overrideWithValue(store ?? MemoryStore()),
        soundEngineProvider.overrideWithValue(RecordingSoundEngine()),
      ],
      child: MaterialApp(
        builder: (BuildContext context, Widget? child) {
          final Widget scaled = ControlScale(
            scale: 1,
            child: MediaQuery.withClampedTextScaling(
              minScaleFactor: scale,
              maxScaleFactor: scale,
              child: child!,
            ),
          );
          return badgeHost ? BadgePopupHost(child: scaled) : scaled;
        },
        home: home,
      ),
    ),
  );
  // Pumped rather than settled: the radar's ticker and the badge's hop never
  // stop, so a settle would time out on the two states that most need one.
  await tester.pump(const Duration(milliseconds: 100));
}

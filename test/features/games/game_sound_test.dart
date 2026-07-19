/// Sound wiring (`specs/05`, "Build the sound engine": *"Each cue plays; toggling
/// sound off silences all audio while reactions still animate"*).
///
/// **What this suite owns, and what it deliberately leaves to others.** The four
/// games each publish a right/wrong outcome to `gameReactionProvider`, and their
/// own suites already pin that they do — including the two awkward cases, Power
/// Duel firing per tapped card and Today's Challenge folding four cards into one
/// `acc >= 60` verdict. What was missing until this item is the other half: that
/// something *listens* and turns those outcomes into cues. That listener lives in
/// [GameShell], which all four games render into, so testing it here covers all
/// four by construction rather than by four copies of the same test.
///
/// The cue *contents* are pinned in `test/core/audio/sound_cues_test.dart`; the
/// toggle gate itself in `test/features/rewards/sound_controller_test.dart`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/core/audio/sound_cues.dart';
import 'package:rockimals/core/audio/sound_engine.dart';
import 'package:rockimals/features/data/providers.dart';
import 'package:rockimals/features/games/game_shell.dart';
import 'package:rockimals/features/games/games_hub.dart';
import 'package:rockimals/features/games/games_providers.dart';
import 'package:rockimals/features/settings/calm_motion.dart';
import 'package:rockimals/features/settings/sound.dart';

import '../../support/memory_store.dart';
import '../../support/recording_sound_engine.dart';
import '../../support/stub_settings.dart';

void main() {
  group('a game answer makes the matching sound', () {
    testWidgets('a correct answer plays the happy jingle', (
      WidgetTester tester,
    ) async {
      final RecordingSoundEngine engine = RecordingSoundEngine();
      final ProviderContainer container = await _pumpShell(tester, engine);

      container.read(gameReactionProvider.notifier).react(correct: true);
      await tester.pump();

      expect(engine.played, <SoundCue>[SoundCue.happy]);
    });

    testWidgets('a wrong answer plays the gentle sad cue', (
      WidgetTester tester,
    ) async {
      final RecordingSoundEngine engine = RecordingSoundEngine();
      final ProviderContainer container = await _pumpShell(tester, engine);

      container.read(gameReactionProvider.notifier).react(correct: false);
      await tester.pump();

      expect(engine.played, <SoundCue>[SoundCue.sad]);
    });

    testWidgets('two right answers in a row are two separate cheers', (
      WidgetTester tester,
    ) async {
      // The regression this guards is subtle and was designed against in
      // `GameReaction`: if the channel held a bare `bool`, the second
      // `react(true)` would compare equal to the first and `ref.listen` would
      // never fire — a child on a streak would hear the first answer and then
      // silence. A fresh event object per answer is what prevents it, and only a
      // *repeat* of the same verdict can catch a regression.
      final RecordingSoundEngine engine = RecordingSoundEngine();
      final ProviderContainer container = await _pumpShell(tester, engine);

      final GameReactionNotifier reactions = container.read(
        gameReactionProvider.notifier,
      );
      reactions.react(correct: true);
      await tester.pump();
      reactions.react(correct: true);
      await tester.pump();
      reactions.react(correct: false);
      await tester.pump();
      reactions.react(correct: false);
      await tester.pump();

      expect(engine.played, <SoundCue>[
        SoundCue.happy,
        SoundCue.happy,
        SoundCue.sad,
        SoundCue.sad,
      ]);
    });

    testWidgets('with sound off the answer is silent', (
      WidgetTester tester,
    ) async {
      final RecordingSoundEngine engine = RecordingSoundEngine();
      final ProviderContainer container = await _pumpShell(
        tester,
        engine,
        soundOn: false,
      );

      container.read(gameReactionProvider.notifier).react(correct: true);
      await tester.pump();

      expect(engine.played, isEmpty);
    });

    testWidgets('a reaction published after leaving the game is not heard', (
      WidgetTester tester,
    ) async {
      // The listener is scoped to the shell, which scopes it in time as well as
      // in place: a late reaction — one arriving after the child has navigated
      // away — must not play a tone over whatever screen they are now on.
      final RecordingSoundEngine engine = RecordingSoundEngine();
      final ProviderContainer container = await _pumpShell(tester, engine);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: Text('elsewhere'))),
        ),
      );
      await tester.pump();

      container.read(gameReactionProvider.notifier).react(correct: true);
      await tester.pump();

      expect(engine.played, isEmpty);
    });

    testWidgets('mounting a game is silent until an answer is given', (
      WidgetTester tester,
    ) async {
      // `ref.listen` fires on *change*, not on the value already sitting there,
      // so re-entering a game after a previous one does not replay its last
      // outcome. Worth pinning: the channel deliberately outlives any one game.
      final RecordingSoundEngine engine = RecordingSoundEngine();
      final ProviderContainer container = await _pumpShell(tester, engine);
      container.read(gameReactionProvider.notifier).react(correct: true);
      await tester.pump();
      engine.played.clear();

      // Re-enter a game with the channel already holding a "correct".
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: GameShell(title: '⚔️ Power Duel', body: Text('round 2')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(engine.played, isEmpty);
    });
  });

  group('the Play hub sound toggle', () {
    testWidgets('turning sound on answers with the happy jingle', (
      WidgetTester tester,
    ) async {
      // `if(soundOn)playHappy()` (`index.html:1020`) — the confirmation a child
      // needs, because an emoji swapping from 🔇 to 🔊 does not prove the speaker
      // works.
      final RecordingSoundEngine engine = RecordingSoundEngine();
      await _pumpHub(tester, engine, startOn: false);

      await tester.tap(find.text('🔇'));
      await tester.pumpAndSettle();

      expect(find.text('🔊'), findsOneWidget);
      expect(engine.played, <SoundCue>[SoundCue.happy]);
    });

    testWidgets('turning sound off is silent — it does not sign off', (
      WidgetTester tester,
    ) async {
      // The prototype only plays on the way on, and that is the coherent
      // behaviour: a cue confirming that sound is off would contradict itself.
      final RecordingSoundEngine engine = RecordingSoundEngine();
      await _pumpHub(tester, engine, startOn: true);

      await tester.tap(find.text('🔊'));
      await tester.pumpAndSettle();

      expect(find.text('🔇'), findsOneWidget);
      expect(engine.played, isEmpty);
    });
  });
}

/// Mount a bare [GameShell] over a recording engine, and hand back the container
/// so a test can publish reactions the way a game does.
///
/// A bare shell rather than a real game: the four games' own suites pin that they
/// publish to [gameReactionProvider], so driving the channel directly tests this
/// file's actual subject — the listener — without four sets of asteroid fixtures.
Future<ProviderContainer> _pumpShell(
  WidgetTester tester,
  RecordingSoundEngine engine, {
  bool soundOn = true,
}) async {
  final ProviderContainer container = ProviderContainer(
    overrides: [
      soundEngineProvider.overrideWithValue(engine),
      soundOnProvider.overrideWith(() => StubSoundOn(soundOn)),
      reducedMotionProvider.overrideWith(StubCalmMotion.new),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: GameShell(title: '⚔️ Power Duel', body: Text('round 1')),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// Mount the Play hub over the **real** [SoundOnNotifier], seeded from a
/// [MemoryStore] — no stub toggle, because the toggle is now the subject.
///
/// **This used to override `soundOnProvider` with a fake that reimplemented
/// `toggle()`, and that would now test nothing.** The confirmation blip moved
/// into the real `toggle()` (`SoundOnNotifier.toggle`), so a fake that replaces
/// that method replaces the very rule these two tests exist to check — they
/// would pass against a hub wired to nothing at all. A memory store keeps the
/// flip honest while staying off Hive, whose `await` inside a pumped frame is
/// the deadlock `memory_store.dart` warns about; persistence across a real
/// restart stays in `games_hub_test.dart`, against a reopened box.
///
/// The gate is not stood in front of either, and no longer needs to be: the blip
/// reaches [soundEngineProvider] directly, so [engine] records what was asked
/// for rather than what survived a second check. A mutation making the blip
/// unconditional still fails the second test.
Future<void> _pumpHub(
  WidgetTester tester,
  RecordingSoundEngine engine, {
  required bool startOn,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        soundEngineProvider.overrideWithValue(engine),
        storeProvider.overrideWithValue(MemoryStore(soundOn: startOn)),
        reducedMotionProvider.overrideWith(StubCalmMotion.new),
        gamesHubStatsProvider.overrideWithValue(
          const GamesHubStats(
            points: 0,
            bestDuel: 0,
            bestCloser: 0,
            bestSize: 0,
          ),
        ),
      ],
      child: const MaterialApp(home: GamesHub()),
    ),
  );
  await tester.pumpAndSettle();
}

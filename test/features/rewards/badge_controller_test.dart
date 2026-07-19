/// The badge system's behaviour (`specs/05`, "Build the badge system"):
/// *"Crossing 50 points pops Mouse Scout; earning two at once queues both;
/// earned badges persist."*
///
/// **Against a real Hive box, not a fake store.** The acceptance criterion is
/// "earned badges persist across launches", and the only honest way to ask that
/// is to close the box and reopen it — which is also the shape that would have
/// caught `Store.badges`' `List<String>` round-trip hazard had it not already
/// been handled. The sound engine *is* faked, for the reason
/// `recording_sound_engine.dart` gives: a host VM is silent whether or not the
/// cheer fired, so recording what was asked for is the only way to see it.
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:rockimals/core/audio/sound_cues.dart';
import 'package:rockimals/core/audio/sound_engine.dart';
import 'package:rockimals/core/storage/store.dart';
import 'package:rockimals/features/data/providers.dart';
import 'package:rockimals/features/games/games_providers.dart';
import 'package:rockimals/features/rewards/badge_controller.dart';
import 'package:rockimals/features/rewards/badges.dart';

import '../../support/recording_sound_engine.dart';

void main() {
  late Directory tempDir;
  late Store store;
  late RecordingSoundEngine engine;
  late ProviderContainer container;

  /// A container wired the way the app is, over a real box.
  ProviderContainer containerOn(Store s) {
    final ProviderContainer c = ProviderContainer(
      overrides: [
        storeProvider.overrideWithValue(s),
        soundEngineProvider.overrideWithValue(engine),
        soundOnProvider.overrideWith(() => StubSoundOn(true)),
      ],
    );
    addTearDown(c.dispose);
    // **Read once up front, because the app does.** A Riverpod provider is
    // created on its first read, and `BadgeController.build` is where the follow
    // listener is registered — so a container that has never read this has a
    // badge system that is not watching anything yet. In the app `BadgePopupHost`
    // does this read in the first frame and holds it for the session; here it is
    // this line. Leaving it out is not a smaller test, it is a different one:
    // two follow tests below passed only because they happened to read the state
    // between toggles, and the two that did not, failed.
    c.read(badgesProvider);
    return c;
  }

  BadgeState read() => container.read(badgesProvider);
  BadgeController controller() => container.read(badgesProvider.notifier);

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('rockimals_badges');
    Hive.init(tempDir.path);
    store = await Store.open();
    engine = RecordingSoundEngine();
    container = containerOn(store);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await Hive.close();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  group('a fresh install', () {
    test('starts with nothing earned and nothing celebrating', () {
      expect(read().earned, isEmpty);
      expect(read().queue, isEmpty);
      expect(read().celebrating, isNull);
    });

    test('a check that earns nothing is completely silent', () async {
      controller().check();

      expect(read().celebrating, isNull);
      expect(engine.played, isEmpty);
      // Not merely "no popup": no disk write either. This is the path every
      // wrong answer in the app takes, and it must cost nothing.
      expect(store.badges, isEmpty);
    });
  });

  group('earning one badge', () {
    test('crossing 50 points pops Mouse Scout with the cheer', () async {
      await store.setPoints(50);
      controller().check();

      expect(read().celebrating!.id, 'mouse');
      expect(read().celebrating!.title, 'Mouse Scout');
      expect(read().queue, isEmpty);
      expect(engine.played, <SoundCue>[SoundCue.cheer]);
    });

    test('49 points pops nothing', () async {
      await store.setPoints(49);
      controller().check();

      expect(read().celebrating, isNull);
      expect(engine.played, isEmpty);
    });

    test('is not re-awarded by a second check', () async {
      await store.setPoints(50);
      controller().check();
      controller().dismiss();
      await Future<void>.delayed(kBadgeDrainGap * 2);

      await store.setPoints(60);
      controller().check();

      expect(
        read().celebrating,
        isNull,
        reason: 'the earned set is checked before the condition is asked',
      );
      expect(engine.played, <SoundCue>[SoundCue.cheer], reason: 'one cheer');
    });
  });

  group('earning two at once', () {
    /// The acceptance criterion's second clause. It is a real situation, not a
    /// contrived one: the answer that carries a child past 50 points can also be
    /// the fifth in a row, and both badges are found by the same check.
    Future<void> earnTwo() async {
      await store.setPoints(50);
      await store.setBestStreak(5);
      controller().check();
    }

    test('shows the first and queues the second', () async {
      await earnTwo();

      expect(read().celebrating!.id, 'mouse');
      expect(read().queue.map((AnimalBadge b) => b.id), <String>['fire']);
      expect(engine.played, <SoundCue>[SoundCue.cheer]);
    });

    test(
      'marks both earned immediately, before either is celebrated',
      () async {
        // Persistence happens on the check, not on the dismissal
        // (`index.html:988-989`), so an app killed with the popup up still has
        // both badges next launch.
        await earnTwo();

        expect(read().earned, <String>{'mouse', 'fire'});
        expect(store.badges, containsAll(<String>['mouse', 'fire']));
      },
    );

    test('the second arrives after the gap, with its own cheer', () async {
      await earnTwo();
      controller().dismiss();

      // The beat between the two (`setTimeout(drainBadges,300)`): nothing on
      // screen, but the queue still holds the badge that is coming.
      expect(read().celebrating, isNull);
      expect(read().queue, hasLength(1));

      await Future<void>.delayed(kBadgeDrainGap * 2);

      expect(read().celebrating!.id, 'fire');
      expect(read().queue, isEmpty);
      expect(engine.played, <SoundCue>[SoundCue.cheer, SoundCue.cheer]);
    });

    test('dismissing the last one leaves the popup closed for good', () async {
      await earnTwo();
      controller().dismiss();
      await Future<void>.delayed(kBadgeDrainGap * 2);
      controller().dismiss();
      await Future<void>.delayed(kBadgeDrainGap * 2);

      expect(read().celebrating, isNull);
      expect(read().queue, isEmpty);
      expect(
        engine.played,
        hasLength(2),
        reason: 'no cheer for an empty queue',
      );
    });

    test('a badge earned while one is on screen joins the queue', () async {
      await store.setPoints(50);
      controller().check();
      expect(read().celebrating!.id, 'mouse');

      // A second game finishing while the child has not tapped the popup yet.
      await store.setPlayed(1);
      controller().check();

      expect(
        read().celebrating!.id,
        'mouse',
        reason: 'a celebration in progress is never interrupted',
      );
      expect(read().queue.map((AnimalBadge b) => b.id), <String>['play']);
      expect(engine.played, hasLength(1));
    });
  });

  group('the earned ledger', () {
    test('survives a force-quit and relaunch', () async {
      await store.setPoints(150);
      controller().check();
      expect(read().earned, <String>{'mouse', 'fox'});

      await store.close();
      final Store reopened = await Store.open();
      addTearDown(reopened.close);
      container = containerOn(reopened);

      expect(read().earned, <String>{'mouse', 'fox'});
      expect(
        read().celebrating,
        isNull,
        reason: 'a relaunch must not re-celebrate what was already seen',
      );
      expect(engine.played, hasLength(1), reason: 'and must not re-cheer');
    });

    test('answers the shelf\'s lit test and the Profile\'s count', () async {
      await store.setPoints(150);
      controller().check();

      expect(read().isEarned('mouse'), isTrue);
      expect(read().isEarned('whale'), isFalse);
      expect(read().earnedCount, 2);
    });

    test('never gives a badge back', () async {
      // Zoo Keeper reads a set a child can shrink. Earning it and then
      // unfollowing everything must not take it away — a badge records that
      // something happened, and un-earning one would punish changing your mind.
      final FollowsNotifier follows = container.read(followsProvider.notifier);
      await follows.toggle('2011 EW');
      await follows.toggle('2004 BL86');
      await follows.toggle('2010 XC15');
      expect(read().isEarned('keep'), isTrue);

      await follows.toggle('2011 EW');
      await follows.toggle('2004 BL86');
      controller().check();

      expect(read().isEarned('keep'), isTrue);
      expect(store.badges, contains('keep'));
    });
  });

  group('following animals', () {
    test('the third follow earns Zoo Keeper with no explicit check', () async {
      // Nothing in the radar HUD or the detail screen knows badges exist; the
      // controller watches the follow set itself. This is the wiring, and it is
      // the half the prototype is missing entirely.
      final FollowsNotifier follows = container.read(followsProvider.notifier);

      await follows.toggle('2011 EW');
      expect(read().celebrating, isNull);
      await follows.toggle('2004 BL86');
      expect(read().celebrating, isNull);
      await follows.toggle('2010 XC15');

      expect(read().celebrating!.id, 'keep');
      expect(engine.played, <SoundCue>[SoundCue.cheer]);
    });

    test('the count comes from the live set, not a stale store read', () async {
      // `followsProvider` writes to Hive and to its own state; reading the store
      // instead would be a frame behind on exactly the tap that earns this.
      await container.read(followsProvider.notifier).toggle('2011 EW');
      await container.read(followsProvider.notifier).toggle('2004 BL86');
      await container.read(followsProvider.notifier).toggle('2010 XC15');

      expect(read().isEarned('keep'), isTrue);
    });
  });

  group('the sound toggle', () {
    test('mutes the cheer without changing what is celebrated', () async {
      // The acceptance criterion "the sound toggle mutes all audio" reaches the
      // fourth call site the gate was built for. The popup must still appear —
      // silence is not the same as no celebration.
      final ProviderContainer silent = ProviderContainer(
        overrides: [
          storeProvider.overrideWithValue(store),
          soundEngineProvider.overrideWithValue(engine),
          soundOnProvider.overrideWith(() => StubSoundOn(false)),
        ],
      );
      addTearDown(silent.dispose);

      await store.setPoints(50);
      silent.read(badgesProvider.notifier).check();

      expect(silent.read(badgesProvider).celebrating!.id, 'mouse');
      expect(engine.played, isEmpty);
    });
  });

  group('dismiss', () {
    test('does nothing when there is nothing on screen', () async {
      controller().dismiss();

      expect(read().celebrating, isNull);
      expect(engine.played, isEmpty);
    });
  });
}

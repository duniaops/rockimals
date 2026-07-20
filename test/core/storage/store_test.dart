import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:rockimals/core/storage/store.dart';

/// The store's whole job is to still be there tomorrow, so almost every test
/// here writes, **closes the box, and opens a new one** rather than reading
/// back through the same instance. Reading from a live box only proves Hive's
/// in-memory map works; the thing this app actually promises a child is that
/// their points and their animals survive the app being force-quit — and the
/// two paths are not the same code. Hive's binary round trip is where a
/// `List<String>` quietly becomes a `List<dynamic>`.
void main() {
  late Directory tempDir;
  late Store store;

  setUp(() async {
    // A fresh directory per test: Hive is a process-wide singleton, so a shared
    // one would let a test read the previous test's box and pass for it.
    tempDir = await Directory.systemTemp.createTemp('rockimals_store_test');
    Hive.init(tempDir.path);
    store = await Store.open();
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await Hive.close();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  /// Force-quit and relaunch, as far as this layer can tell the difference.
  Future<Store> restart() async {
    await store.close();
    store = await Store.open();
    return store;
  }

  group('a fresh install reads the documented defaults', () {
    test('every counter starts at zero', () {
      expect(store.points, 0);
      expect(store.played, 0);
      expect(store.bestStreak, 0);
      expect(store.perfect, 0);
      expect(store.bestDuel, 0);
      expect(store.bestCloser, 0);
      expect(store.bestSize, 0);
      expect(store.dayStreak, 0);
    });

    test('the collections start empty', () {
      expect(store.badges, isEmpty);
      expect(store.follows, isEmpty);
      expect(store.gameTutorialProgress, isEmpty);
      expect(store.dailyQuestPatches, isEmpty);
    });

    test('sound starts on — a game that boots silent reads as broken', () {
      expect(store.soundOn, isTrue);
    });

    test('little kids mode starts off', () {
      expect(store.littleKidsMode, isFalse);
    });

    test('calm motion starts null, meaning "no choice yet — ask the OS"', () {
      // Not `false`. Spec 08 defaults this to MediaQuery.disableAnimations on
      // first run and to the child's choice thereafter, which is three states
      // in a bool's clothing. If this ever returns false on a fresh install,
      // the OS accessibility flag becomes unreadable from here and a child who
      // needs calm motion never gets it by default.
      expect(store.reducedMotion, isNull);
    });

    test('the child has never played, and the store says so', () {
      expect(store.lastPlayedDate, isNull);
    });
  });

  group('every field survives a restart', () {
    test('the rewards fields read back', () async {
      await store.setPoints(1240);
      await store.setPlayed(37);
      await store.setBestStreak(9);
      await store.setPerfect(2);
      await store.setBadges(<String>['play', 'mouse', 'fox']);

      final Store reopened = await restart();

      expect(reopened.points, 1240);
      expect(reopened.played, 37);
      expect(reopened.bestStreak, 9);
      expect(reopened.perfect, 2);
      expect(reopened.badges, <String>['play', 'mouse', 'fox']);
    });

    test('the game bests read back', () async {
      await store.setBestDuel(14);
      await store.setBestCloser(6);
      await store.setBestSize(8);

      final Store reopened = await restart();

      expect(reopened.bestDuel, 14);
      expect(reopened.bestCloser, 6);
      expect(reopened.bestSize, 8);
    });

    test('follows read back, keyed by designation and in order', () async {
      await store.setFollows(<String>['2011 EW', '433 Eros', '99942 Apophis']);

      final Store reopened = await restart();

      // Ordered, not just present: insertion order is what this list stores,
      // and a set-like round trip that scrambled it would be a silent change to
      // what the store means.
      expect(reopened.follows, <String>[
        '2011 EW',
        '433 Eros',
        '99942 Apophis',
      ]);
    });

    test('the day streak and its date read back', () async {
      await store.setDayStreak(4);
      await store.setLastPlayedDate('2026-07-17');

      final Store reopened = await restart();

      expect(reopened.dayStreak, 4);
      expect(reopened.lastPlayedDate, '2026-07-17');
    });

    test('the settings read back', () async {
      await store.setSoundOn(false);
      await store.setReducedMotion(true);
      await store.setLittleKidsMode(true);

      final Store reopened = await restart();

      expect(reopened.soundOn, isFalse);
      expect(reopened.reducedMotion, isTrue);
      expect(reopened.littleKidsMode, isTrue);
    });

    test('the game guide and practice completions read back', () async {
      await store.setGameTutorialProgress(<String>['guide', 'daily', 'duel']);

      expect((await restart()).gameTutorialProgress, <String>[
        'guide',
        'daily',
        'duel',
      ]);
    });

    test('daily mission patches read back', () async {
      await store.setDailyQuestPatches(<String>['2026-07-19', '2026-07-20']);

      expect((await restart()).dailyQuestPatches, <String>[
        '2026-07-19',
        '2026-07-20',
      ]);
    });
  });

  group('a stored zero is not a missing key', () {
    // This is the prototype's one persistence bug, pinned so the port cannot
    // reacquire it. `gGet` ends in `||d` (`index.html:954`), which coalesces on
    // falsy rather than on absent, so `gGet("aw_sound", 1)` answers `1` for a
    // stored `0`: sound-off survives until the page reloads and no further. Any
    // "simplification" here that reintroduces `?? default` on a *value* instead
    // of on absence fails these.

    test('sound turned off stays off across a restart', () async {
      await store.setSoundOn(false);

      expect((await restart()).soundOn, isFalse);
    });

    test(
      'calm motion turned explicitly off stays off, and stays a choice',
      () async {
        await store.setReducedMotion(false);

        // False, not null: the child said no. If this reads null, the next launch
        // asks the OS instead and can silently overrule them.
        expect((await restart()).reducedMotion, isFalse);
      },
    );

    test('a zero score is stored, not treated as unset', () async {
      await store.setPoints(0);
      await store.setBestDuel(0);

      final Store reopened = await restart();

      expect(reopened.points, 0);
      expect(reopened.bestDuel, 0);
    });

    test('an emptied follow list stays empty', () async {
      await store.setFollows(<String>['2011 EW']);
      await restart();
      await store.setFollows(const <String>[]);

      // Unfollowing the last animal must not restore the default — which, for a
      // list, happens to be the same empty list. It is asserted anyway because
      // the *reason* it is empty differs, and a future default of "some starter
      // set" would make this the test that catches it.
      expect((await restart()).follows, isEmpty);
    });
  });

  group('the lists it hands out cannot be written through', () {
    test('badges, follows, and quest patches are unmodifiable', () async {
      await store.setBadges(<String>['play']);
      await store.setFollows(<String>['2011 EW']);
      await store.setDailyQuestPatches(<String>['2026-07-20']);

      expect(() => store.badges.add('whale'), throwsUnsupportedError);
      expect(() => store.follows.add('433 Eros'), throwsUnsupportedError);
      expect(
        () => store.dailyQuestPatches.add('2026-07-21'),
        throwsUnsupportedError,
      );
      expect(store.badges, <String>['play']);
      expect(store.follows, <String>['2011 EW']);
      expect(store.dailyQuestPatches, <String>['2026-07-20']);
    });

    test('the caller cannot mutate the store by keeping its own list', () async {
      final List<String> mine = <String>['play', 'mouse'];
      await store.setFollows(mine);

      mine.add('fox');

      // **Assert the in-session read, not the restarted one — the restarted one
      // cannot fail.** Hive serialises on `put`, so the disk is right either
      // way; a setter that stored the caller's list by reference would keep
      // that live list only in the box's *in-memory* map. The store would then
      // answer `[play, mouse, fox]` for the rest of the session while the disk
      // held `[play, mouse]`, and the third badge would vanish at the next
      // launch with nothing having failed. That is the whole bug, and it is
      // invisible from the far side of a restart.
      expect(store.follows, <String>['play', 'mouse']);

      // And the two views agree, which is the property that actually matters:
      // what the store says it remembers is what it will still say tomorrow.
      expect((await restart()).follows, store.follows);
    });

    test('badges are copied on the way in too', () async {
      // The same property, asserted separately rather than trusted to
      // symmetry: `setBadges` and `setFollows` are two `toList` calls, and
      // dropping either one is its own edit. Left implicit, a badges-setter
      // mutation passes the whole suite.
      final List<String> mine = <String>['play'];
      await store.setBadges(mine);

      mine.add('whale');

      expect(store.badges, <String>['play']);
      expect((await restart()).badges, store.badges);
    });
  });

  group('a corrupt box degrades to defaults rather than throwing', () {
    // The defence is against a child losing the whole app to a store they
    // cannot see and did not break — a half-written box, or a field whose type
    // changed between two versions of Rockimals. Points back to zero is a bad
    // day; a launch that throws is an app that is gone. The prototype wraps
    // every one of its storage calls in a bare try/catch for this same reason
    // (`index.html:954-955, 973, 988`).

    test('a wrongly-typed counter reads as its default', () async {
      await Hive.box<Object>(Store.boxName).put('aw_points', 'not a number');

      expect(store.points, 0);
    });

    test('a wrongly-typed toggle reads as its default', () async {
      await Hive.box<Object>(Store.boxName).put('aw_sound', 1);

      // Note this is exactly what the *prototype's* own box holds — it stores
      // sound as 1/0 (`index.html:1020`). An int is not a bool here, so it is
      // ignored in favour of the default rather than coerced. Safe: no data
      // migrates from the prototype (see the key comment in store.dart), so the
      // only way an int lands here is corruption.
      expect(store.soundOn, isTrue);
    });

    test('a wrongly-typed list reads as empty', () async {
      await Hive.box<Object>(Store.boxName).put('aw_badges', 42);

      expect(store.badges, isEmpty);
    });

    test('a list with unexpected elements keeps only the strings', () async {
      await Hive.box<Object>(
        Store.boxName,
      ).put('aw_follows', <Object>['2011 EW', 7, '433 Eros']);

      expect(store.follows, <String>['2011 EW', '433 Eros']);
    });
  });

  group('the feed cache entry', () {
    // The store holds this as one opaque string and knows nothing else about it
    // — `feed_cache_test.dart` owns the format and every rule. What belongs here
    // is only that the box keeps a string and gives it back after a restart,
    // which is the disk half the whole cache exists for.

    test('starts absent, which is how a fresh install misses', () {
      expect(store.cachedFeed, isNull);
    });

    test('survives a restart', () async {
      await store.setCachedFeed('{"window":"2026-07-15 → 2026-07-17"}');

      expect(
        (await restart()).cachedFeed,
        '{"window":"2026-07-15 → 2026-07-17"}',
      );
    });

    test('is overwritten whole, never merged', () async {
      // One `put` of one string is what makes the entry atomic: the key, the
      // timestamp, and the payload cannot be interrupted halfway and leave a new
      // window label over old asteroids. Nothing here appends.
      await store.setCachedFeed('first');
      await store.setCachedFeed('second');

      expect((await restart()).cachedFeed, 'second');
    });

    test(
      'a wrongly-typed entry reads as absent rather than throwing',
      () async {
        await Hive.box<Object>(Store.boxName).put('aw_feedcache', 42);

        expect(store.cachedFeed, isNull);
      },
    );
  });
}

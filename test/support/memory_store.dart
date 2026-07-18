/// A [Store] that lives in memory — every field, no box, no disk.
///
/// **Why this exists now and did not before.** Until the badge system, nothing
/// above the loading gate read the store, so a widget test could mount
/// `RockimalsApp` with only a feed override and never touch persistence. The
/// celebration popup changed that: it hangs off `MaterialApp.builder` above the
/// `Navigator` (it has to — a badge is nearly always earned inside a pushed game
/// route), so it is built in the first frame of every launch and reads the
/// earned ledger there. The store is now a hard requirement for the app to build
/// at all, and two suites needed one at once.
///
/// **Not a Hive box, deliberately.** `testWidgets` drives a fake clock, and a
/// real box's `await` inside a pumped frame is a deadlock waiting to be written.
/// The suites that must prove something *persists* — `store_test.dart`,
/// `badge_controller_test.dart` — open a real box on a temp directory and close
/// and reopen it, because that is the only honest way to ask. This is for the
/// tests where the store is scenery.
library;

import 'package:rockimals/core/storage/store.dart';

class MemoryStore implements Store {
  MemoryStore({
    this.points = 0,
    this.played = 0,
    this.bestStreak = 0,
    this.perfect = 0,
    this.dayStreak = 0,
    this.soundOn = true,
    // Null by default because that is the fresh-install state and the one the
    // Calm motion resolver treats specially — "never chosen, ask the OS". A
    // test that wants a *chosen* value has to say so.
    this.reducedMotion,
    this.badges = const <String>[],
    this.follows = const <String>[],
  });

  @override
  int points;

  @override
  int played;

  @override
  int bestStreak;

  @override
  int perfect;

  @override
  int dayStreak;

  @override
  bool soundOn;

  @override
  int bestDuel = 0;

  @override
  int bestCloser = 0;

  @override
  int bestSize = 0;

  @override
  String? lastPlayedDate;

  @override
  bool? reducedMotion;

  @override
  bool littleKidsMode = false;

  @override
  String? cachedFeed;

  // Plain mutable fields: `Store` declares these as getters, and a field
  // satisfies a getter — so the interface is met and a test can seed one in the
  // constructor without a second name for it.
  @override
  List<String> badges;

  @override
  List<String> follows;

  // The setters mirror the real store's signatures — `Future<void>`, taking an
  // `Iterable` and snapshotting it — so a caller that awaits them, or hands one
  // a lazy iterable, behaves the same here as against a box.
  @override
  Future<void> setPoints(int value) async => points = value;

  @override
  Future<void> setPlayed(int value) async => played = value;

  @override
  Future<void> setBestStreak(int value) async => bestStreak = value;

  @override
  Future<void> setPerfect(int value) async => perfect = value;

  @override
  Future<void> setBadges(Iterable<String> value) async =>
      badges = value.toList(growable: false);

  @override
  Future<void> setFollows(Iterable<String> value) async =>
      follows = value.toList(growable: false);

  @override
  Future<void> setBestDuel(int value) async => bestDuel = value;

  @override
  Future<void> setBestCloser(int value) async => bestCloser = value;

  @override
  Future<void> setBestSize(int value) async => bestSize = value;

  @override
  Future<void> setDayStreak(int value) async => dayStreak = value;

  @override
  Future<void> setLastPlayedDate(String value) async => lastPlayedDate = value;

  @override
  Future<void> setSoundOn(bool value) async => soundOn = value;

  @override
  Future<void> setReducedMotion(bool value) async => reducedMotion = value;

  @override
  Future<void> setLittleKidsMode(bool value) async => littleKidsMode = value;

  @override
  Future<void> setCachedFeed(String value) async => cachedFeed = value;

  @override
  Future<void> close() async {}
}

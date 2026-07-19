import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:rockimals/core/storage/store.dart';
import 'package:rockimals/core/streak/day_streak.dart';

/// The consecutive-days-played rule (plan decisions 3/14). Two things are worth
/// pinning: the arithmetic of the streak itself — advance on the next day, hold
/// on the same day, reset on a gap — and that a recorded streak is still there
/// after the box is closed and reopened, which is the whole promise of the
/// flame ("survives a restart", the home-overlay item's Done-when).
void main() {
  group('afterVisit', () {
    test('a fresh install, never played, starts the run at 1', () {
      // Store default is 0; the first visit ever is day 1, not day 0 — the flame
      // should read `🔥 1` on the first launch, not `🔥 0`.
      expect(
        DayStreak.afterVisit(
          lastPlayed: null,
          today: DateTime(2026, 7, 17),
          current: 0,
        ),
        1,
      );
    });

    test('a second visit the same day holds the streak', () {
      // Idempotent per day: opening the app twice on Friday is one Friday.
      expect(
        DayStreak.afterVisit(
          lastPlayed: '2026-07-17',
          today: DateTime(2026, 7, 17, 22),
          current: 4,
        ),
        4,
      );
    });

    test('a same-day visit whose stored streak is still 0 reads 1', () {
      // The one state the writer cannot otherwise produce: last-played is today
      // but the count never advanced past the default. Must read 1, not 0.
      expect(
        DayStreak.afterVisit(
          lastPlayed: '2026-07-17',
          today: DateTime(2026, 7, 17),
          current: 0,
        ),
        1,
      );
    });

    test('a visit the day after the last one advances by one', () {
      expect(
        DayStreak.afterVisit(
          lastPlayed: '2026-07-16',
          today: DateTime(2026, 7, 17),
          current: 4,
        ),
        5,
      );
    });

    test('a gap of more than a day resets the run to 1', () {
      // Two days missed is a broken streak, and today is the first day of the
      // new one — 1, not 0.
      expect(
        DayStreak.afterVisit(
          lastPlayed: '2026-07-14',
          today: DateTime(2026, 7, 17),
          current: 9,
        ),
        1,
      );
    });

    test('"the day before" is calendar arithmetic across a month end', () {
      // The advance must fire when yesterday was the last day of the previous
      // month — `DateTime(y, m, d - 1)` normalises `March 0` to `February 28`,
      // which a `Duration(days: 1)` subtraction across a DST change could miss.
      expect(
        DayStreak.afterVisit(
          lastPlayed: '2026-02-28',
          today: DateTime(2026, 3), // March 1, 2026 — day defaults to 1.
          current: 2,
        ),
        3,
      );
    });

    test('and across a year end', () {
      expect(
        DayStreak.afterVisit(
          lastPlayed: '2025-12-31',
          today: DateTime(2026), // January 1, 2026 — month and day default to 1.
          current: 6,
        ),
        7,
      );
    });
  });

  group('keyOf', () {
    test('is a zero-padded local yyyy-mm-dd', () {
      expect(DayStreak.keyOf(DateTime(2026, 1, 3)), '2026-01-03');
      expect(DayStreak.keyOf(DateTime(2026, 12, 31, 23, 59)), '2026-12-31');
    });
  });

  group('record', () {
    late Directory tempDir;
    late Store store;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('rockimals_streak_test');
      Hive.init(tempDir.path);
      store = await Store.open();
    });

    tearDown(() async {
      await Hive.deleteFromDisk();
      await Hive.close();
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    });

    Future<Store> restart() async {
      await store.close();
      store = await Store.open();
      return store;
    }

    test('a first launch persists a streak of 1 that survives a restart', () async {
      final int returned = await DayStreak.record(store, DateTime(2026, 7, 17));
      expect(returned, 1);

      final Store reopened = await restart();
      expect(reopened.dayStreak, 1);
      expect(reopened.lastPlayedDate, '2026-07-17');
    });

    test('a launch the next day advances the persisted streak', () async {
      await DayStreak.record(store, DateTime(2026, 7, 17));
      final Store reopened = await restart();

      final int returned = await DayStreak.record(
        reopened,
        DateTime(2026, 7, 18),
      );
      expect(returned, 2);

      final Store again = await restart();
      expect(again.dayStreak, 2);
      expect(again.lastPlayedDate, '2026-07-18');
    });

    test('a second launch the same day leaves the box untouched', () async {
      await DayStreak.record(store, DateTime(2026, 7, 17));
      final int returned = await DayStreak.record(
        store,
        DateTime(2026, 7, 17, 21),
      );
      expect(returned, 1);
      expect(store.dayStreak, 1);
      expect(store.lastPlayedDate, '2026-07-17');
    });

    test('a launch after a gap resets the persisted streak to 1', () async {
      await DayStreak.record(store, DateTime(2026, 7, 14));
      // Build the streak up so the reset is visible rather than a no-op.
      await store.setDayStreak(9);

      final int returned = await DayStreak.record(store, DateTime(2026, 7, 17));
      expect(returned, 1);
      expect((await restart()).dayStreak, 1);
    });
  });

  /// The "only if it moved" guard, which used to be written out at each call
  /// site. It is one rule and it has three callers — a cold launch, a game
  /// begun, and a return from the background — so it lives in one place, and
  /// this is where that place is pinned.
  group('recordAndNotify', () {
    late Directory tempDir;
    late Store store;
    late List<int> announced;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('rockimals_notify_test');
      Hive.init(tempDir.path);
      store = await Store.open();
      announced = <int>[];
    });

    tearDown(() async {
      await Hive.deleteFromDisk();
      await Hive.close();
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    });

    Future<int> recordOn(DateTime day) => DayStreak.recordAndNotify(
      store,
      day,
      () => announced.add(store.dayStreak),
    );

    test('announces a first engagement', () async {
      expect(await recordOn(DateTime(2026, 7, 17)), 1);
      expect(announced, <int>[1]);
    });

    test('announces a new day', () async {
      await recordOn(DateTime(2026, 7, 17));
      expect(await recordOn(DateTime(2026, 7, 18)), 2);
      expect(announced, <int>[1, 2]);
    });

    test('and says nothing at all on a second engagement the same day',
        () async {
      // The case that carries the guard's whole weight, and the common one:
      // most engagements land on a day already counted. Announcing them would
      // repaint the home flame for a number that did not change.
      await recordOn(DateTime(2026, 7, 17));
      announced.clear();

      expect(await recordOn(DateTime(2026, 7, 17, 22)), 1);
      expect(announced, isEmpty);
    });

    test('announces a reset after a gap, which is a move downwards', () async {
      // A move is a *change*, not an increase. A child returning after a week
      // drops from 9 to 1, and the flame has to be told — a guard written as
      // `after > before` would leave the old number on screen.
      await recordOn(DateTime(2026, 7, 10));
      await store.setDayStreak(9);
      announced.clear();

      expect(await recordOn(DateTime(2026, 7, 17)), 1);
      expect(announced, <int>[1]);
    });
  });
}

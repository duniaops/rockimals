import 'package:rockimals/core/storage/store.dart';

/// The consecutive-days-played streak behind the home flame (plan decision 3),
/// and the single home for the one rule that drives it.
///
/// **This is the concept the prototype never had.** Its `streak`
/// (`index.html:345`) seeded at a hardcoded `3`, incremented on every Challenge
/// reveal whether the child was right or wrong (`index.html:941`), and never
/// persisted — a challenges-completed counter wearing a flame. Decision 3
/// replaces it with a *persisted consecutive-days-played* count, starting at 0
/// on a fresh install. This file owns that rule so no feature has to re-derive
/// it; the [Store] only holds the two fields it reads and writes.
///
/// **"Played" is read as "engaged", and that is decision 14.** The Done-when of
/// the home-overlay item needs the streak to advance "on a new day played", but
/// the games that would be the obvious trigger do not exist yet. Opening
/// Rockimals is the day's engagement, so [record] is called once per cold launch
/// from `bootstrap()`. It is idempotent per day, so when the games land they can
/// call the same rule on a completed game without changing the count — the
/// streak stays "days the child came back", and a later item may tighten
/// "engaged" to "finished a game" by moving the sole caller.
abstract final class DayStreak {
  /// The streak after the child engages on [today], given the [lastPlayed] day
  /// (a `yyyy-mm-dd` key, or null on a fresh install) and the [current] stored
  /// streak.
  ///
  /// A visit on a day already counted returns the streak unchanged (idempotent
  /// per day); a visit the day after the last one advances it by one; any longer
  /// gap — or the very first visit ever — starts a fresh run at 1. The
  /// `current > 0` guard on the same-day branch is for the one state the writer
  /// cannot otherwise reach: a fresh install whose first-ever visit is "today"
  /// must read 1, not the stored 0.
  static int afterVisit({
    required String? lastPlayed,
    required DateTime today,
    required int current,
  }) {
    final String todayKey = keyOf(today);
    if (lastPlayed == todayKey) return current > 0 ? current : 1;
    if (lastPlayed == keyOf(_dayBefore(today))) return current + 1;
    return 1;
  }

  /// Record [today] as a day played — persisting the new streak and the day it
  /// was earned — and return the streak. Writes only what changed, so a second
  /// launch on the same day touches the box not at all.
  static Future<int> record(Store store, DateTime today) async {
    final String todayKey = keyOf(today);
    final int updated = afterVisit(
      lastPlayed: store.lastPlayedDate,
      today: today,
      current: store.dayStreak,
    );
    if (store.dayStreak != updated) await store.setDayStreak(updated);
    if (store.lastPlayedDate != todayKey) {
      await store.setLastPlayedDate(todayKey);
    }
    return updated;
  }

  /// [record], plus the one thing every caller of it has to do next: run
  /// [onMoved] **only if the streak actually changed**, and return the streak.
  ///
  /// The guard is here rather than at each call site because it is a rule, not
  /// a detail — [record] is idempotent per day, so on an ordinary day the great
  /// majority of calls write nothing, and a caller that announced every call
  /// would repaint the flame on each of them. There are three callers now (cold
  /// launch, a game begun, and a resume from the background), all reaching for
  /// the same before/after comparison; the second one to write it by hand is
  /// the point at which the third gets it subtly wrong.
  ///
  /// [onMoved] is deliberately a plain callback rather than anything Riverpod:
  /// this file is `core/` and knows about a [Store] and a calendar, not about
  /// which provider happens to memoise the count today.
  static Future<int> recordAndNotify(
    Store store,
    DateTime today,
    void Function() onMoved,
  ) async {
    final int before = store.dayStreak;
    final int after = await record(store, today);
    if (after != before) onMoved();
    return after;
  }

  /// The `yyyy-mm-dd` key for a **local** calendar day — the same shape and the
  /// same timezone the store keeps `lastPlayedDate` in
  /// ([Store.lastPlayedDate]). Local, not UTC: this must agree with the child's
  /// idea of "yesterday", not with the feed's UTC window keys, or the flame
  /// would roll over mid-afternoon on a UTC+13 phone.
  static String keyOf(DateTime day) =>
      '${_pad(day.year, 4)}-${_pad(day.month, 2)}-${_pad(day.day, 2)}';

  /// The calendar day before [day], built by field arithmetic rather than by
  /// subtracting a [Duration]: `DateTime(y, m, d - 1)` normalises across month
  /// and year ends and is immune to the daylight-saving jump a `Duration` of 24
  /// hours would land on twice a year.
  static DateTime _dayBefore(DateTime day) =>
      DateTime(day.year, day.month, day.day - 1);

  static String _pad(int value, int width) =>
      value.toString().padLeft(width, '0');
}

import 'dart:convert';

import 'package:rockimals/core/storage/store.dart';
import 'package:rockimals/data/models/asteroid.dart';
import 'package:rockimals/data/models/feed_window.dart';
import 'package:rockimals/data/neows_client.dart';

/// Keeps the windows NASA answered on the disk, so that a launch which cannot
/// reach NASA can still show a real sky.
///
/// A decorator over any [AsteroidFeedSource], and an addition to the prototype
/// rather than a port of it (`specs/01-foundation.md:30-32`) — `index.html` has
/// no cache at all.
///
/// **It caches the source's output, never an [AsteroidFeed]** (plan decision
/// 13). A resolved feed is a function of the clock as well as the data:
/// `todayList` and `feedRange` are derived at load time, so a stored feed would
/// caption the wrong range and name the wrong animals as today's the moment UTC
/// rolls over. Sitting below the repository, this class stores the one thing
/// that genuinely does not vary — the asteroids NASA listed for a window — and
/// every policy above it (the too-few rule, dedupe, who is visiting today) runs
/// again on each load.
///
/// **Nesting is `Repository → CachingFeedSource → NeoWsClient → Dio[retry]`,
/// and the order carries two properties.** Outside the client, a hit costs zero
/// retries and zero requests against a 30-per-hour key a household shares.
/// Inside the repository, this only ever sees what NASA actually said — the
/// sample set is the repository's answer to a source that could not help, so it
/// can never be written back here and come out next launch wearing
/// `usingFallback: false`.
class CachingFeedSource implements AsteroidFeedSource {
  CachingFeedSource(
    this._source,
    this._store, {
    DateTime Function()? now,
    Duration? ttl,
  }) : _now = now ?? DateTime.now,
       _ttl = ttl ?? _defaultTtl;

  final AsteroidFeedSource _source;
  final Store _store;

  /// Injectable so the suite can age an entry past the TTL instead of sitting
  /// out six hours. It must be the **same clock the repository was given**: the
  /// repository builds the window this keys on, so two clocks that disagree
  /// would let a test cache one window and ask for another.
  final DateTime Function() _now;

  final Duration _ttl;

  /// How many windows the disk holds at once (`specs/06-title-polish-safety.md:38`,
  /// "cache feeds by date").
  ///
  /// **It is more than one because the app now asks for two windows a day.** The
  /// repository fetches today's window on launch and then quietly prefetches the
  /// one tomorrow's launch will ask for
  /// ([AsteroidRepository.prefetchTomorrow]). With a single slot the second of
  /// those would evict the first, and a child who relaunched an hour later with
  /// no signal would be handed the sample set while today's real sky sat on the
  /// disk — the prefetch would have paid for tomorrow by breaking today.
  ///
  /// Four, because that is two days of asking: a device that has been offline
  /// since yesterday still holds both of yesterday's windows while today's two
  /// arrive. The spec's "past days forever" is deliberately not taken literally
  /// — only the newest window that is not in the future is ever servable
  /// ([_bestServable]), so an entry older than that is disk spent on a sky
  /// nothing would ever choose to show.
  static const int _maxEntries = 4;

  /// Six hours, and the number is doing less than it looks.
  ///
  /// The window key already self-invalidates every UTC day — a new day asks for
  /// a window nothing is stored under — so this only governs *re-asking within
  /// one day*, which is a much smaller question. Six hours means a child who
  /// plays after breakfast and again after school gets a genuinely re-fetched
  /// sky, while a child who opens the app five times in an hour spends one
  /// request rather than five. That matters more than it sounds: `DEMO_KEY`
  /// allows 30 requests an hour *per IP*, which is a whole household's budget,
  /// and the app is at its most fragile exactly when it is most used.
  static const Duration _defaultTtl = Duration(hours: 6);

  static const String _startDateField = 'startDate';
  static const String _endDateField = 'endDate';
  static const String _savedAtField = 'savedAt';
  static const String _asteroidsField = 'asteroids';

  /// Three outcomes, and which one happens turns on the window first and the
  /// TTL second:
  ///
  ///  * **Fresh hit** — an entry for *exactly this* window, saved within the
  ///    TTL. Answer from the disk and touch no network.
  ///  * **Miss or stale** — go to NASA, and store whatever comes back.
  ///  * **NASA cannot be reached** — answer with the best window on the disk
  ///    ([_bestServable]) and say which window that is. Real rocks beat invented
  ///    ones, and it is the reason this class is on the disk rather than in
  ///    memory.
  ///
  /// **A hit still demands an exact window match; only the failure path is
  /// generous.** The two are different questions. A hit is "may I skip asking?",
  /// and a different window is a different question, so the answer is no — the
  /// key self-invalidates every UTC day and a new day must re-ask (plan decision
  /// 13). The failure path is "is there anything better than the sample set?",
  /// and yesterday's real sky plainly is.
  ///
  /// **This serves an old window without deciding whether it is too old, and
  /// that restraint is the design.** It says only what it has and which days it
  /// is about; whether a three-day-old sky is still worth showing a child is a
  /// question about the app's promises, and `AsteroidRepository` owns those. So
  /// there is no age ceiling here, and no way for one to drift out of step with
  /// the caption, which the repository derives from the same [FeedWindow].
  @override
  Future<FeedWindow> fetchFeed({
    required String startDate,
    required String endDate,
  }) async {
    final List<_CacheEntry> cached = _read();
    final _CacheEntry? exact = _entryFor(cached, startDate, endDate);

    if (exact != null && _isFresh(exact)) return exact.feed;

    try {
      final FeedWindow fetched = await _source.fetchFeed(
        startDate: startDate,
        endDate: endDate,
      );
      await _save(fetched, cached);
      return fetched;
    } catch (_) {
      // Bare, and it rethrows rather than deciding anything: what a dead network
      // means is the repository's call (the sample set), and it has already been
      // made one layer up. All this adds is the one better answer available
      // here — that NASA said something recently, and it is still on the disk.
      final _CacheEntry? servable = _bestServable(cached, endDate);
      if (servable != null) return servable.feed;
      rethrow;
    }
  }

  /// The entry for exactly this window, or null.
  static _CacheEntry? _entryFor(
    List<_CacheEntry> entries,
    String startDate,
    String endDate,
  ) {
    for (final _CacheEntry entry in entries) {
      if (entry.feed.startDate == startDate && entry.feed.endDate == endDate) {
        return entry;
      }
    }
    return null;
  }

  /// The best answer on the disk when NASA cannot be reached: the **newest
  /// window that does not end after the one being asked for**.
  ///
  /// **The "does not end after" half is what makes the prefetch safe**, and it
  /// is the one rule this method exists for. Once tomorrow's window is on the
  /// disk, "newest wins" would hand it to a load that asked for today's — and
  /// the repository refuses a window dated in the future
  /// (`AsteroidRepository._isTooOld` admits only today and the three days
  /// before it), so a child relaunching offline this afternoon would get the
  /// sample set *because* the app had prefetched for them. Comparing against the
  /// requested end date keeps the prefetched entry invisible until the day it is
  /// for, when it becomes the exact match instead.
  ///
  /// Newest by [FeedWindow.endDate] rather than by [_CacheEntry.savedAt],
  /// because the question is which sky is most recent, not which request was.
  /// The dates are `YYYY-MM-DD`, so comparing them as strings is comparing them
  /// as days — no parsing, and none of the timezone surface parsing would add.
  static _CacheEntry? _bestServable(
    List<_CacheEntry> entries,
    String requestedEndDate,
  ) {
    _CacheEntry? best;
    for (final _CacheEntry entry in entries) {
      if (entry.feed.endDate.compareTo(requestedEndDate) > 0) continue;
      if (best == null || entry.feed.endDate.compareTo(best.feed.endDate) > 0) {
        best = entry;
      }
    }
    return best;
  }

  /// An entry saved in the *future* is not fresh, it is unexplained.
  ///
  /// Ages are computed against a device clock, and device clocks move — a manual
  /// change, a timezone setup screen, an NTP correction. A clock knocked
  /// backwards makes every stored entry appear to be from the future, and a
  /// negative age passes any `age < ttl` test forever, so the app would serve
  /// one frozen sky until the clock caught up. Distrusting the entry costs one
  /// request; trusting it costs a sky that never changes again.
  ///
  /// Such an entry is never *fresh*, but it is not thrown away either: it is
  /// still real rocks for a real window, so it stays servable on the failure
  /// path, where the repository judges it on the days it describes rather than
  /// on a `savedAt` the clock has made meaningless. The first successful fetch
  /// overwrites it.
  bool _isFresh(_CacheEntry entry) {
    final Duration age = _now().toUtc().difference(entry.savedAt);
    return !age.isNegative && age < _ttl;
  }

  /// **Swallows its own failures, and that is the point of the method.**
  ///
  /// By the time this runs, NASA has answered and the child's sky is in hand. A
  /// full disk, a locked box, or anything else going wrong here must cost them
  /// nothing more than the next launch being a request slower. Letting it throw
  /// would drop into the catch above and answer with a *stale* sky — or with the
  /// sample set — while the real one sat in a local variable, which would be an
  /// absurd way to lose it.
  /// Writes [feed] into [existing] and puts the whole shelf back as one string.
  ///
  /// One entry per window: a re-fetch of a window already held **replaces** it
  /// rather than joining it, so a child who opens the app all day does not fill
  /// the shelf with copies of one sky. The newest [_maxEntries] survive, judged
  /// by `savedAt` — the shelf is bounded by how recently each entry was
  /// *fetched*, while what is servable off it is judged by which days it
  /// describes ([_bestServable]); the two questions stay separate here as they
  /// do everywhere else in this class.
  Future<void> _save(FeedWindow feed, List<_CacheEntry> existing) async {
    try {
      final DateTime savedAt = _now().toUtc();
      final List<_CacheEntry> next = <_CacheEntry>[
        _CacheEntry(savedAt: savedAt, feed: feed),
        for (final _CacheEntry entry in existing)
          if (entry.feed.startDate != feed.startDate ||
              entry.feed.endDate != feed.endDate)
            entry,
      ]..sort((_CacheEntry a, _CacheEntry b) => b.savedAt.compareTo(a.savedAt));

      await _store.setCachedFeed(
        jsonEncode(<Object?>[
          for (final _CacheEntry entry in next.take(_maxEntries))
            <String, Object?>{
              _startDateField: entry.feed.startDate,
              _endDateField: entry.feed.endDate,
              _savedAtField: entry.savedAt.toIso8601String(),
              _asteroidsField: entry.feed.asteroids
                  .map((Asteroid a) => a.toJson())
                  .toList(growable: false),
            },
        ]),
      );
    } catch (_) {
      // Deliberately nothing. See above: the sky is already in the caller's
      // hand, and the only thing failing to cache costs is one request later.
    }
  }

  /// Reads the shelf, skipping *anything* that is not a whole entry.
  ///
  /// Every failure is a miss rather than a throw: a truncated string, a field
  /// that changed type between two builds of Rockimals, a `savedAt` that is not
  /// a date, a box that will not answer at all. All of them mean the same thing
  /// — ask NASA — and none is worth a crash, because this is a cache and the
  /// network is right there. It mirrors [Store]'s own read-side defensiveness
  /// for the same reason.
  ///
  /// **A corrupt entry costs only itself.** The guard is per entry rather than
  /// around the whole list, so one record that will not parse cannot throw away
  /// the other window sitting beside it — which is the window a child with no
  /// signal would otherwise have been shown. An unreadable *shelf* is still an
  /// empty one.
  ///
  /// **The store read is inside the guard, not above it**, which is not
  /// housekeeping: a box that throws on read would otherwise throw straight out
  /// of [fetchFeed], and the repository — which cannot see what failed — would
  /// answer with the sample set. A broken cache would take the network down with
  /// it and hand a child invented rocks on a perfectly good connection.
  ///
  /// **The one-entry format this replaced is not read, and needs no migration**:
  /// no build of Rockimals has shipped (the bundle ID is still `com.example`),
  /// so the only blobs in the old shape are on developers' own devices, where
  /// the cost of not reading one is a single request on one launch.
  List<_CacheEntry> _read() {
    final List<_CacheEntry> entries = <_CacheEntry>[];
    try {
      final String? raw = _store.cachedFeed;
      if (raw == null) return entries;

      final Object? decoded = jsonDecode(raw);
      if (decoded is! List<Object?>) return entries;

      for (final Object? item in decoded) {
        final _CacheEntry? entry = _entryFrom(item);
        if (entry != null) entries.add(entry);
      }
    } catch (_) {
      // See above — an unreadable shelf is an empty one.
    }
    return entries;
  }

  /// One stored entry, or null if it is not a whole one.
  static _CacheEntry? _entryFrom(Object? item) {
    try {
      if (item is! Map<String, Object?>) return null;

      final Object? startDate = item[_startDateField];
      final Object? endDate = item[_endDateField];
      final Object? savedAt = item[_savedAtField];
      final Object? asteroids = item[_asteroidsField];
      if (savedAt is! String || asteroids is! List<Object?>) return null;
      if (startDate is! String || endDate is! String) return null;
      if (!_isDateKey(startDate) || !_isDateKey(endDate)) return null;

      final DateTime? parsedAt = DateTime.tryParse(savedAt);
      if (parsedAt == null) return null;

      return _CacheEntry(
        savedAt: parsedAt.toUtc(),
        feed: FeedWindow(
          startDate: startDate,
          endDate: endDate,
          asteroids: asteroids
              .map((Object? json) {
                if (json is! Map<String, Object?>) {
                  throw FormatException(
                    'cache: expected an asteroid, got: $json',
                  );
                }
                return Asteroid.fromJson(json);
              })
              .toList(growable: false),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  /// A stored window date has to be a `YYYY-MM-DD` key or the entry is not whole.
  ///
  /// **Checked here even though the repository would reject a nonsense window
  /// anyway**, because "the repository happens to catch it" is not the same as
  /// this class being correct: [fetchFeed] promises a [FeedWindow] that says
  /// which days its rocks are about, and `endDate: "banana"` does not. Leaving it
  /// would make this file's contract depend on a rule living in another one.
  ///
  /// A miss rather than a throw, like every other unreadable entry: it costs one
  /// request and the next successful fetch overwrites the corruption.
  static bool _isDateKey(String value) => _dateKeyPattern.hasMatch(value);

  static final RegExp _dateKeyPattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');
}

/// One stored window — a [FeedWindow] exactly as it will be served — plus the
/// one fact that is nobody's business but this class's: when it was saved.
///
/// The split is the layering in miniature. [FeedWindow] is what a child can
/// eventually see (real rocks, and the days they are about); [savedAt] is a
/// receipt for a request, and it is used for one thing — deciding whether to
/// spend another. It stops at this file.
///
/// [FeedWindow.asteroids] being empty is a perfectly good entry and **not** a
/// miss (plan decision 13). NASA does list quiet windows, and an empty answer
/// must hold its slot for the TTL like any other — otherwise every launch on a
/// quiet window re-asks, which is the one case where the cache would be both
/// useless and expensive. The repository turns an empty window into the sample
/// set through its too-few rule, which is a decision about what to *show*, not a
/// claim that nothing was ever fetched.
class _CacheEntry {
  const _CacheEntry({required this.savedAt, required this.feed});

  /// Always UTC. Stored as an ISO-8601 instant so that a phone crossing
  /// timezones compares the same two moments it would have at home.
  final DateTime savedAt;

  final FeedWindow feed;
}

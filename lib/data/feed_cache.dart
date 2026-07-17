import 'dart:convert';

import 'package:rockimals/core/storage/store.dart';
import 'package:rockimals/data/models/asteroid.dart';
import 'package:rockimals/data/neows_client.dart';

/// Keeps the last window NASA answered on the disk, so that a launch which
/// cannot reach NASA can still show a real sky.
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

  static const String _windowField = 'window';
  static const String _savedAtField = 'savedAt';
  static const String _asteroidsField = 'asteroids';

  /// Three outcomes, and which one happens turns on the window key first and the
  /// TTL second:
  ///
  ///  * **Fresh hit** — an entry for *this* window, saved within the TTL. Answer
  ///    from the disk and touch no network.
  ///  * **Miss or stale** — go to NASA, and store whatever comes back.
  ///  * **Miss or stale, and NASA cannot be reached** — answer with the stale
  ///    entry if it is for this window. Yesterday's real rocks beat the sample
  ///    set, and it is the reason this class is on the disk rather than in
  ///    memory.
  ///
  /// **The stale-on-failure answer is deliberately limited to *this* window,
  /// and that costs something worth naming.** A device offline across a UTC
  /// midnight holds an entry only for yesterday's window, so it misses, and the
  /// repository shows the sample set — even though real rocks were right there.
  /// The alternative is worse: this class's contract is "the asteroids between
  /// [startDate] and [endDate]", and the repository captions whatever it gets
  /// with the range it *asked* for. Handing back a different window's rocks
  /// would print `2026-07-15 → 2026-07-17` over data from two days earlier, and
  /// with no upper bound — a phone left offline for a season would show a
  /// season-old sky labelled as today's, reported by nothing, with
  /// `usingFallback` calmly false. The sample set is at least honest about being
  /// the sample set. Serving old rocks *with their own caption* is a real
  /// improvement over both, but it needs this interface to say which window it
  /// answered; see the plan's follow-up item.
  @override
  Future<List<Asteroid>> fetchFeed({
    required String startDate,
    required String endDate,
  }) async {
    final String window = _windowKey(startDate, endDate);
    final _CacheEntry? cached = _read();
    final _CacheEntry? forThisWindow = cached?.window == window ? cached : null;

    if (forThisWindow != null && _isFresh(forThisWindow)) {
      return forThisWindow.asteroids;
    }

    try {
      final List<Asteroid> fetched = await _source.fetchFeed(
        startDate: startDate,
        endDate: endDate,
      );
      await _save(window, fetched);
      return fetched;
    } catch (_) {
      // Bare, and it rethrows rather than deciding anything: what a dead network
      // means is the repository's call (the sample set), and it has already been
      // made one layer up. All this adds is the one better answer available
      // here — that NASA said something recently, and it is still on the disk.
      if (forThisWindow != null) return forThisWindow.asteroids;
      rethrow;
    }
  }

  /// The two dates, exactly as the repository asked for them.
  ///
  /// Keyed by the **window**, not by the day, and not assembled from per-day
  /// entries (plan decision 13). NeoWs bills per request and this app makes one
  /// range request, so a day-partitioned cache would cost the same single
  /// request and save nothing — while forcing a cross-day ordering that the
  /// repository's first-seen-wins dedupe would then resolve against the home
  /// strip, silently dropping today's rocks out of it.
  ///
  /// It reads like [AsteroidFeed.feedRange] and is not it: that is a caption for
  /// a child, this is a key. They are free to diverge.
  static String _windowKey(String startDate, String endDate) =>
      '$startDate → $endDate';

  /// An entry saved in the *future* is not fresh, it is unexplained.
  ///
  /// Ages are computed against a device clock, and device clocks move — a manual
  /// change, a timezone setup screen, an NTP correction. A clock knocked
  /// backwards makes every stored entry appear to be from the future, and a
  /// negative age passes any `age < ttl` test forever, so the app would serve
  /// one frozen sky until the clock caught up. Distrusting the entry costs one
  /// request; trusting it costs a sky that never changes again.
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
  Future<void> _save(String window, List<Asteroid> asteroids) async {
    try {
      await _store.setCachedFeed(
        jsonEncode(<String, Object?>{
          _windowField: window,
          _savedAtField: _now().toUtc().toIso8601String(),
          _asteroidsField: asteroids
              .map((Asteroid a) => a.toJson())
              .toList(growable: false),
        }),
      );
    } catch (_) {
      // Deliberately nothing. See above: the sky is already in the caller's
      // hand, and the only thing failing to cache costs is one request later.
    }
  }

  /// Reads the entry, or null for *anything* that is not a whole one.
  ///
  /// Every failure is a miss rather than a throw: a truncated string, a field
  /// that changed type between two builds of Rockimals, a `savedAt` that is not
  /// a date, a box that will not answer at all. All of them mean the same thing
  /// — ask NASA — and none is worth a crash, because this is a cache and the
  /// network is right there. It mirrors [Store]'s own read-side defensiveness
  /// for the same reason.
  ///
  /// **The store read is inside the guard, not above it**, which is not
  /// housekeeping: a box that throws on read would otherwise throw straight out
  /// of [fetchFeed], and the repository — which cannot see what failed — would
  /// answer with the sample set. A broken cache would take the network down with
  /// it and hand a child invented rocks on a perfectly good connection.
  _CacheEntry? _read() {
    try {
      final String? raw = _store.cachedFeed;
      if (raw == null) return null;

      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) return null;

      final Object? window = decoded[_windowField];
      final Object? savedAt = decoded[_savedAtField];
      final Object? asteroids = decoded[_asteroidsField];
      if (window is! String || savedAt is! String) return null;
      if (asteroids is! List<Object?>) return null;

      final DateTime? parsedAt = DateTime.tryParse(savedAt);
      if (parsedAt == null) return null;

      return _CacheEntry(
        window: window,
        savedAt: parsedAt.toUtc(),
        // Unmodifiable, because this list is handed straight out and the entry
        // is re-read from one string that a caller could otherwise sort out from
        // under the next reader (plan decision 13).
        asteroids: List<Asteroid>.unmodifiable(
          asteroids.map((Object? json) {
            if (json is! Map<String, Object?>) {
              throw FormatException('cache: expected an asteroid, got: $json');
            }
            return Asteroid.fromJson(json);
          }),
        ),
      );
    } catch (_) {
      return null;
    }
  }
}

/// One stored window: what NASA said, which window it said it about, and when.
///
/// [asteroids] being empty is a perfectly good entry and **not** a miss (plan
/// decision 13). NASA does list quiet windows, and an empty answer must hold its
/// slot for the TTL like any other — otherwise every launch on a quiet window
/// re-asks, which is the one case where the cache would be both useless and
/// expensive. The repository turns an empty window into the sample set through
/// its too-few rule, which is a decision about what to *show*, not a claim that
/// nothing was ever fetched.
class _CacheEntry {
  const _CacheEntry({
    required this.window,
    required this.savedAt,
    required this.asteroids,
  });

  final String window;

  /// Always UTC. Stored as an ISO-8601 instant so that a phone crossing
  /// timezones compares the same two moments it would have at home.
  final DateTime savedAt;

  final List<Asteroid> asteroids;
}

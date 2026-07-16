import 'package:rockimals/data/models/asteroid.dart';
import 'package:rockimals/data/models/asteroid_feed.dart';
import 'package:rockimals/data/neows_client.dart';

/// Resolves the sky the app shows, from NASA if it can and from the bundled
/// sample set if it cannot.
///
/// A port of the decision half of the prototype's `loadData()`
/// (`index.html:364-383`). The rule the whole class exists to keep is spec 01
/// §3's: **the app is always playable.** There is no error state to reach — a
/// dead network, a rate-limited key, a feed NASA served empty, and a record
/// with a corrupt number all resolve to the same friendly sky.
class AsteroidRepository {
  AsteroidRepository(this._source, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final AsteroidFeedSource _source;

  /// Injectable so tests can pin a date against a fixed fixture. The clock is
  /// read once per load and used for both ends of the window *and* for today's
  /// key, so a load that straddles midnight cannot ask for one window and then
  /// filter against the next day.
  final DateTime Function() _now;

  /// The prototype's `start.setDate(start.getDate()-2)` (`index.html:365`): a
  /// three-day window, today included. Today alone is often only a handful of
  /// rocks — too few for a sky, and too few for the games to pick four from.
  static const Duration _windowLength = Duration(days: 2);

  /// Below this the live feed is not worth showing, so the sample set wins
  /// (`index.html:376`). A near-empty sky is a broken-looking app even when the
  /// request technically succeeded.
  static const int _minimumPoolSize = 6;

  /// Today's own animals, padded from the rest of the window when there are not
  /// enough (`index.html:378`). Four is what the Challenge game needs to deal a
  /// 2x2 grid.
  static const int _minimumTodayCount = 4;

  /// Never throws. [AsteroidFeed.usingFallback] is how a caller learns the
  /// network path did not work out; there is deliberately nothing more specific
  /// to report, because no surface in this app would do anything different with
  /// the distinction.
  Future<AsteroidFeed> loadData() async {
    final DateTime end = _now().toUtc();
    final DateTime start = end.subtract(_windowLength);
    final String startKey = _formatFeedDate(start);
    final String endKey = _formatFeedDate(end);

    try {
      final List<Asteroid> pool = await _source.fetchFeed(
        startDate: startKey,
        endDate: endKey,
      );

      // Checked on the raw pool, *before* dedupe, exactly as the prototype does
      // (`index.html:376-377`). Six records that collapse to two therefore
      // pass, and the app shows two animals. Faithful on purpose: moving the
      // check after dedupe would send more days to the sample set than the
      // prototype does, and it is the prototype that has been watched working.
      if (pool.length < _minimumPoolSize) return AsteroidFeed.fallback();

      final List<Asteroid> asteroids = _dedupe(pool);

      return AsteroidFeed(
        asteroids: asteroids,
        todayList: _todayList(asteroids, endKey),
        feedRange: '$startKey → $endKey',
        usingFallback: false,
      );
    } catch (_) {
      // Bare on purpose, and specified that way (spec 01 §3): "if the network
      // fails or returns too few objects, use [the sample set] so the app is
      // always playable". Narrowing this to DioException would let a
      // FormatException from one corrupt record crash the app instead.
      return AsteroidFeed.fallback();
    }
  }

  /// First-seen-wins (`index.html:396`). The same asteroid appears once per day
  /// it approaches, so a three-day window routinely lists one twice; keeping
  /// the earliest is what makes an animal's index — and so its orbit phase on
  /// the radar — stable across the window.
  static List<Asteroid> _dedupe(List<Asteroid> pool) {
    final Set<String> seen = <String>{};
    final List<Asteroid> unique = <Asteroid>[];
    for (final Asteroid asteroid in pool) {
      if (seen.add(asteroid.name)) unique.add(asteroid);
    }
    return unique;
  }

  /// Today's animals, or the first few of the window if today is quiet
  /// (`index.html:378`).
  ///
  /// The padding replaces the date-filtered list rather than topping it up, so
  /// on a quiet day the strip shows the window's first four — which may not
  /// include today's one rock at all. That is the prototype's behaviour and the
  /// strip is honest about it either way, since it is captioned by [feedRange].
  static List<Asteroid> _todayList(List<Asteroid> asteroids, String todayKey) {
    final List<Asteroid> today = asteroids
        .where((Asteroid a) => a.date == todayKey)
        .toList(growable: false);
    if (today.length >= _minimumTodayCount) return today;

    // `take` rather than a sublist: dedupe can leave fewer than four asteroids
    // even though the pool passed the six-record check, and asking for a fixed
    // window of a shorter list would throw on the one path that must not fail.
    return asteroids.take(_minimumTodayCount).toList(growable: false);
  }

  /// The feed's date-key format, and the prototype's
  /// `d.toISOString().slice(0,10)` (`index.html:363`) — which is **UTC**, so
  /// this is too. The keys NASA returns have to be compared against a key this
  /// app builds, and agreeing with the feed matters more than agreeing with the
  /// phone's timezone: a local-midnight key would ask for a window whose date
  /// strings no record is filed under.
  static String _formatFeedDate(DateTime date) {
    final DateTime utc = date.toUtc();
    final String month = utc.month.toString().padLeft(2, '0');
    final String day = utc.day.toString().padLeft(2, '0');
    return '${utc.year.toString().padLeft(4, '0')}-$month-$day';
  }
}

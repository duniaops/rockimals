import 'dart:async';

import 'package:rockimals/data/models/asteroid.dart';
import 'package:rockimals/data/models/asteroid_feed.dart';
import 'package:rockimals/data/models/feed_window.dart';
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
  AsteroidRepository(this._source, {DateTime Function()? now, Duration? loadCeiling})
    : _now = now ?? DateTime.now,
      _loadCeiling = loadCeiling ?? _defaultLoadCeiling;

  final AsteroidFeedSource _source;

  /// Injectable so tests can pin a date against a fixed fixture. The clock is
  /// read once per load and used for both ends of the window *and* for today's
  /// key, so a load that straddles midnight cannot ask for one window and then
  /// filter against the next day.
  final DateTime Function() _now;

  /// How long a child may be asked to watch "Contacting NASA…" before the app
  /// stops waiting and shows them a sky. Injectable so tests can prove the
  /// mechanism in milliseconds instead of sitting out the real budget.
  final Duration _loadCeiling;

  /// Ten seconds, and the number is a judgment call: long enough that a slow
  /// connection still gets to deliver today's real sky, short enough that a
  /// broken one does not hold the app hostage.
  ///
  /// This lives here rather than in the client because it is the one promise
  /// the app actually makes — *a sky within ten seconds, whatever is going on
  /// underneath* — and it is the repository that owns what the app promises.
  /// The client's per-attempt timeouts and the retry schedule are tuning knobs
  /// beneath it, and this ceiling is what stops any future combination of them
  /// from silently multiplying into a minute-long spinner.
  static const Duration _defaultLoadCeiling = Duration(seconds: 10);

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

  /// How far into the past a window may reach and still be a sky worth showing.
  /// Older than this and the bundled sample set wins instead.
  ///
  /// Only the feed cache can produce an old window at all — it holds the last
  /// thing NASA said, and offers it when the network is gone. That is a real
  /// kindness for a real child (a plane, a tunnel, a weekend at a caravan park),
  /// and the caption never lies about it: [AsteroidFeed.feedRange] prints the
  /// days the rocks are actually from. So this is not a rule about honesty. It
  /// is a rule about **when a true statement stops being interesting**.
  ///
  /// Three days, and the reasoning is the app's own live behaviour rather than
  /// taste: the live window is already three days wide ([_windowLength]), so a
  /// rock two days old is *routinely* part of "the sky" and nobody minds. A
  /// window that ended three days ago puts the oldest rock in it at five days —
  /// roughly double the staleness the app ships on its best day, which is about
  /// as far as "look what's flying past" can stretch and still mean anything.
  /// Beyond it, a fixed real sky is worth no more to a child than the sample one
  /// and carries a stranger caption, so the sample set wins.
  ///
  /// Deliberately **not** derived from [_windowLength]: that they are both three
  /// is an argument, not a law, and binding them would let a future change to the
  /// fetch window silently redefine what counts as too old.
  static const int _maxWindowAgeDays = 3;

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
      // The ceiling wraps the whole source, not just the socket: a hung disk
      // read from the feed cache that lands later must be as survivable as a
      // hung request. It abandons the attempt rather than cancelling it — the
      // request runs on until the client's own timeouts end it, which is
      // harmless, because nothing below here mutates anything.
      final FeedWindow answered = await _source
          .fetchFeed(startDate: startKey, endDate: endKey)
          .timeout(_loadCeiling);

      // **Everything below reads the window that came back, never the one asked
      // for**, and that is the whole shape of this item. The source may answer an
      // earlier window than it was given — the cache does exactly that when the
      // network is gone (see [FeedWindow]) — and a caption, a day filter, or an
      // age check written against `startKey`/`endKey` would then describe a sky
      // that is not the one on the screen.
      if (_isTooOld(answered.endDate, end)) return AsteroidFeed.fallback();

      // Checked on the raw pool, *before* dedupe, exactly as the prototype does
      // (`index.html:376-377`). Six records that collapse to two therefore
      // pass, and the app shows two animals. Faithful on purpose: moving the
      // check after dedupe would send more days to the sample set than the
      // prototype does, and it is the prototype that has been watched working.
      if (answered.asteroids.length < _minimumPoolSize) {
        return AsteroidFeed.fallback();
      }

      final List<Asteroid> asteroids = _dedupe(answered.asteroids);

      return AsteroidFeed(
        asteroids: asteroids,
        todayList: _todayList(asteroids, answered.endDate),
        feedRange: '${answered.startDate} → ${answered.endDate}',
        provenance: answered.endDate == endKey
            ? FeedProvenance.today
            : FeedProvenance.earlier,
      );
    } catch (_) {
      // Bare on purpose, and specified that way (spec 01 §3): "if the network
      // fails or returns too few objects, use [the sample set] so the app is
      // always playable". Narrowing this to DioException would let a
      // FormatException from one corrupt record — or the TimeoutException the
      // ceiling above throws — crash the app instead.
      return AsteroidFeed.fallback();
    }
  }

  /// Whether a window that ended on [endDate] is too far in the past to show,
  /// judged against the same [now] the window was built from.
  ///
  /// **This compares date *keys*, and never parses one, which is the point.**
  /// The obvious implementation — `DateTime.parse(endDate)` and subtract — has a
  /// bug that no test in a UTC timezone would ever show: a bare `2026-07-14`
  /// parses as **local** midnight, so differencing it against a UTC clock is off
  /// by the device's offset, up to ±14 hours. That is more than enough to move
  /// the answer across a day boundary, and it would do so only for children east
  /// of UTC — every one of them, and none of us. Building the acceptable keys
  /// with [_formatFeedDate], the very function that built the window, keeps the
  /// whole question in the one representation the feed itself uses and leaves no
  /// timezone surface to get wrong.
  ///
  /// It also disposes of the clock-knocked-backwards case for free, rather than
  /// with a second rule: a window dated in the *future* is not in the set either,
  /// so it is refused without anyone having to think of it as a separate branch.
  bool _isTooOld(String endDate, DateTime now) {
    final Set<String> servable = <String>{
      for (int daysAgo = 0; daysAgo <= _maxWindowAgeDays; daysAgo++)
        _formatFeedDate(now.subtract(Duration(days: daysAgo))),
    };
    return !servable.contains(endDate);
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

  /// The animals of the window's last day, or the first few of the window if
  /// that day is quiet (`index.html:378`).
  ///
  /// **[dayKey] is the last day of the window that was actually answered, which
  /// is today whenever the sky is a live one and is *not* today when the cache
  /// served an earlier window.** Passing the real today instead would be a quiet
  /// bug rather than a rounding error: no record in an earlier window carries
  /// today's date, so the filter would match nothing, every cached load would
  /// take the pad branch below, and `todayList` would be exactly the window's
  /// first four rocks — every time. The Challenge deals from
  /// `todayList.length >= 4 ? todayList : asteroids` (`index.html:881`), so it
  /// would then deal those same four rocks to the same child on every offline
  /// launch, forever. Filtering on the answered day reproduces the live shape
  /// exactly, and [AsteroidFeed.provenance] is what tells a surface not to call
  /// the result "today".
  ///
  /// The padding replaces the date-filtered list rather than topping it up, so
  /// on a quiet day the strip shows the window's first four — which may not
  /// include that day's one rock at all. That is the prototype's behaviour and
  /// the strip is honest about it either way, since it is captioned by
  /// [AsteroidFeed.feedRange].
  static List<Asteroid> _todayList(List<Asteroid> asteroids, String dayKey) {
    final List<Asteroid> today = asteroids
        .where((Asteroid a) => a.date == dayKey)
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

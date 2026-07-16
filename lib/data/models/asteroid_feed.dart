import 'package:rockimals/data/fallback_asteroids.dart';
import 'package:rockimals/data/models/asteroid.dart';

/// One resolved load of the sky — everything the app knows about what is out
/// there right now, and where it came from.
///
/// This is the four globals the prototype's `loadData()` assigns
/// (`index.html:377-382`) gathered into one value, so that "the live feed" and
/// "the sample set" are two instances of the same thing rather than two states
/// the rest of the app has to reconcile.
class AsteroidFeed {
  const AsteroidFeed({
    required this.asteroids,
    required this.todayList,
    required this.feedRange,
    required this.usingFallback,
  });

  /// The offline answer: the bundled sample set, whole and in source order.
  ///
  /// [todayList] is the **first seven** records rather than a date filter, and
  /// that is not an approximation of the live rule — it is a different rule
  /// (`index.html:381`). Every sample record's date is the deliberate non-date
  /// `sample`, so a date filter would match nothing and leave the sky empty on
  /// exactly the path that has to work: a plane, a tunnel, a dead network.
  factory AsteroidFeed.fallback() => AsteroidFeed(
    asteroids: kFallbackAsteroids,
    todayList: kFallbackAsteroids.take(_fallbackTodayCount).toList(
      growable: false,
    ),
    feedRange: sampleFeedRange,
    usingFallback: true,
  );

  static const int _fallbackTodayCount = 7;

  /// Every asteroid in the window, deduplicated by designation. The radar draws
  /// from this full list, and the Sky tab lists all of it.
  final List<Asteroid> asteroids;

  /// The handful visiting today, for the home overlay strip and the Challenge
  /// game's pool. A subset of [asteroids], never a separate fetch.
  final List<Asteroid> todayList;

  /// Kid-facing provenance for the Sky tab's footer: `2026-07-14 → 2026-07-16`,
  /// or [sampleFeedRange] offline.
  final String feedRange;

  /// True when this is the bundled sample set rather than anything NASA served.
  /// The app stays fully playable either way; this only decides whether a
  /// surface says "(sample)" — which it must, rather than passing invented
  /// rocks off as today's sky.
  final bool usingFallback;
}

/// What [AsteroidFeed.feedRange] reads when the app is running on the bundled
/// sample set (`index.html:381`).
const String sampleFeedRange = 'sample data';

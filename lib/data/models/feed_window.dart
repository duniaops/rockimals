import 'package:rockimals/data/models/asteroid.dart';

/// What a feed source answered: some asteroids, and **which window they are
/// for**.
///
/// The window is here because a source cannot always answer the one it was
/// asked. [AsteroidFeedSource.fetchFeed] takes a start and an end date, and for
/// `NeoWsClient` the answer is always that exact window — it asked NASA for it.
/// But `CachingFeedSource` holds the last window NASA answered, and when the
/// network is gone that entry is the only real sky available; on a device that
/// has been offline since yesterday it is for a *different* window than the one
/// the repository just asked for.
///
/// Returning a bare `List<Asteroid>` made that sky unservable. The repository
/// captions a feed with the window it asked for, so serving yesterday's rocks
/// would have printed today's dates over them — and with no upper bound, a phone
/// left offline for a season would have shown a season-old sky labelled as
/// today's. The cache therefore refused, and a child on a plane got fourteen
/// invented rocks while real ones sat on the disk.
///
/// Saying which window was answered is what unties that knot: nothing has to
/// pretend, so the repository can caption the truth ([AsteroidFeed.feedRange])
/// and decide for itself whether a window is too old to be worth showing.
///
/// This carries no timestamp, and that is deliberate: *when the app asked* is
/// the cache's own business (its TTL), while *which days the sky describes* is
/// the only part a child can see. Only the second one crosses this boundary.
class FeedWindow {
  /// [asteroids] is copied into an unmodifiable list.
  ///
  /// This value crosses the source boundary carrying an order that is
  /// load-bearing — the radar seeds every animal's orbit phase from its index in
  /// the list (plan decision 9), so an in-place `sort()` anywhere upstream would
  /// move the sky with nothing throwing. The cache hands out an entry it retains
  /// and re-reads, which is exactly the caller that would suffer for it. Guarding
  /// here makes the guarantee a property of the type rather than a rule each of
  /// the two producers has to remember, for the cost of one shallow copy of a few
  /// dozen references. [AsteroidFeed] is built the same way and for the same
  /// reason.
  FeedWindow({
    required List<Asteroid> asteroids,
    required this.startDate,
    required this.endDate,
  }) : asteroids = List<Asteroid>.unmodifiable(asteroids);

  /// Every asteroid the source listed for this window, in the order it gave
  /// them. Empty is a perfectly good answer — NASA does list quiet windows — and
  /// means "nothing was out there", not "nothing was fetched".
  final List<Asteroid> asteroids;

  /// The first and last day this sky describes, inclusive, as the feed's own
  /// `YYYY-MM-DD` UTC date keys.
  ///
  /// These are the days the *data* is about, which is not the same as when it
  /// was fetched, and the difference is the whole reason this type exists.
  final String startDate;
  final String endDate;
}

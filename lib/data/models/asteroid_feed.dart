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
  /// [asteroids] and [todayList] are copied into unmodifiable lists, so there
  /// is no way to build a feed whose sky a consumer can reorder.
  ///
  /// **The guarantee lives here rather than at each call site because the
  /// blast radius is the whole app.** One load is handed to every consumer
  /// through the providers, so an in-place `sort()` — a Sky tab ordering by
  /// size, say — would not sort a copy, it would reorder the radar's own
  /// source list, and the radar seeds each animal's orbit phase from that
  /// list's index (plan decision 9). Nothing would throw; the animals would
  /// just quietly jump. A fixed-length list (`toList(growable: false)`, what
  /// the repository used to rely on) does not stop that — it blocks `add`,
  /// while `sort` and `[]=` still write.
  ///
  /// **Copied rather than wrapped in an `UnmodifiableListView`**, which would
  /// also block the writes but only for as long as nobody retains the backing
  /// list — a condition every future caller would have to keep. The disk feed
  /// cache is about to be exactly such a caller: it retains its entry and hands
  /// it out (plan decision 13). Copying makes the guarantee unconditional
  /// instead of a rule to remember, and it costs one shallow copy of at most a
  /// few dozen references, once per load.
  AsteroidFeed({
    required List<Asteroid> asteroids,
    required List<Asteroid> todayList,
    required this.feedRange,
    required this.provenance,
  }) : asteroids = List<Asteroid>.unmodifiable(asteroids),
       todayList = List<Asteroid>.unmodifiable(todayList);

  /// The offline answer: the bundled sample set, whole and in source order.
  ///
  /// [todayList] is the **first seven** records rather than a date filter, and
  /// that is not an approximation of the live rule — it is a different rule
  /// (`index.html:381`). Every sample record's date is the deliberate non-date
  /// `sample`, so a date filter would match nothing and leave the sky empty on
  /// exactly the path that has to work: a plane, a tunnel, a dead network.
  factory AsteroidFeed.fallback() => AsteroidFeed(
    asteroids: kFallbackAsteroids,
    todayList: kFallbackAsteroids
        .take(_fallbackTodayCount)
        .toList(growable: false),
    feedRange: sampleFeedRange,
    provenance: FeedProvenance.sample,
  );

  static const int _fallbackTodayCount = 7;

  /// Every asteroid in the window, deduplicated by designation. The radar draws
  /// from this full list, and the Sky tab lists all of it.
  ///
  /// Unmodifiable: sort a copy, never this. Its **order is load-bearing** —
  /// the radar seeds every animal's orbit phase from the index (plan decision
  /// 9), so reordering it in place moves the sky.
  final List<Asteroid> asteroids;

  /// The handful visiting today, for the home overlay strip and the Challenge
  /// game's pool. A subset of [asteroids], never a separate fetch.
  ///
  /// Unmodifiable, for the same reason as [asteroids].
  final List<Asteroid> todayList;

  /// Kid-facing provenance for the Sky tab's footer: `2026-07-14 → 2026-07-16`,
  /// or [sampleFeedRange] offline.
  ///
  /// Always the window this sky is **actually** about, which is not necessarily
  /// the one the app asked for — see [FeedProvenance.earlier].
  final String feedRange;

  /// Which of the three skies this is. See [FeedProvenance]; the app is equally
  /// playable on any of them.
  final FeedProvenance provenance;

  /// True when this is the bundled sample set rather than anything NASA served.
  /// The app stays fully playable either way; this only decides whether a
  /// surface says "(sample)" — which it must, rather than passing invented
  /// rocks off as today's sky.
  ///
  /// Derived rather than stored, so it cannot contradict [provenance].
  bool get usingFallback => provenance == FeedProvenance.sample;
}

/// Which sky a child is looking at, and therefore what a surface may honestly
/// call it.
///
/// **This exists because "not the sample set" stopped meaning "today".** It used
/// to: every live feed was a window ending today, so one bool told a surface
/// everything. Then the disk cache learned to serve the last window NASA
/// answered when the network is gone — real rocks, but from an earlier window —
/// and a single bool would have had to call that either "sample" (it isn't, and
/// the footer would deny it came from NASA) or "today" (it isn't, and the
/// prototype's home strip renders exactly that word:
/// `${todayList.length} visiting ${usingFallback?'(sample)':'today'}`,
/// `index.html:454`). Neither is true, so there are three values and not two.
///
/// A bool pair would have permitted a fourth, meaningless state; one enum cannot
/// be internally contradictory, which is the same reason [AsteroidFeed] exists
/// at all rather than a scatter of globals.
enum FeedProvenance {
  /// A real window ending today. The ordinary case, online.
  ///
  /// It deliberately does **not** claim the network was touched: a fresh cache
  /// hit for today's window comes off the disk and is still `today`, because
  /// nothing above `CachingFeedSource` can tell — nor should it, since the rocks
  /// and the days are identical either way. What this value promises is about
  /// *when the sky is from*, not *where the bytes came from*.
  today,

  /// A real window from NASA that ended **before** today, kept on the disk and
  /// served because the network could not be reached — a plane, a tunnel, a
  /// weekend away.
  ///
  /// These are real asteroids and [AsteroidFeed.feedRange] says which days they
  /// are from, so nothing here is a lie. But they are not visiting *now*, and a
  /// surface must not say they are. `AsteroidRepository` refuses windows older
  /// than a few days outright, so this is stale by days, never by seasons.
  earlier,

  /// The bundled sample set: fourteen invented rocks, no network needed, and the
  /// app fully playable (spec 01 §3).
  ///
  /// A surface must say so — `(sample)` — rather than passing them off as
  /// anything NASA published.
  sample,
}

/// What [AsteroidFeed.feedRange] reads when the app is running on the bundled
/// sample set (`index.html:381`).
const String sampleFeedRange = 'sample data';

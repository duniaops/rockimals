import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rockimals/core/storage/store.dart';
import 'package:rockimals/core/streak/day_streak.dart';
import 'package:rockimals/data/asteroid_repository.dart';
import 'package:rockimals/data/feed_cache.dart';
import 'package:rockimals/data/models/asteroid.dart';
import 'package:rockimals/data/models/asteroid_feed.dart';
import 'package:rockimals/data/neows_client.dart';

/// Everything Rockimals remembers about a child, as one live [Store] — points,
/// badges, follows, the day streak, and the settings toggles.
///
/// **This has no default and throws until it is overridden, on purpose.**
/// Opening the box is asynchronous ([Store.open]), so a provider that opened it
/// itself could only do so lazily, behind an [AsyncValue] — and then every
/// consumer would carry a "not loaded yet" branch whose only honest rendering is
/// zero points and an empty shelf. Shown for even one frame, that is
/// indistinguishable from lost progress to the one person who cannot be told it
/// is temporary. So the open finishes *before the first frame* instead:
/// `bootstrap()` (`lib/main.dart`) awaits it and overrides this with the result,
/// which is also why that await is written into `runApp`'s argument rather than
/// left as a line above it.
///
/// Reading it without an override is a wiring bug, and it throws so as to stay
/// one. The alternative — handing back a store on some unopened box — would
/// answer every read with a default, which is the exact shape of a child's
/// progress having been wiped, reported by nothing.
///
/// Tests override it with a store on a temp directory; see
/// `test/features/data/providers_test.dart`.
final Provider<Store> storeProvider = Provider<Store>(
  (Ref ref) => throw UnimplementedError(
    'storeProvider was read before it was overridden with an opened Store. '
    'The app wires it in bootstrap() (lib/main.dart); a test must override it '
    'with a Store on a temp-directory box.',
  ),
  name: 'store',
);

/// The data layer's composition root, and the seam every test reaches for.
///
/// This is the only place the app names a concrete [NeoWsClient] or assembles
/// the stack around it: `AsteroidRepository → CachingFeedSource → NeoWsClient →
/// Dio[retry]`. That order is load-bearing at both joints — the cache sits
/// outside the client so a hit costs no retries and no request, and inside the
/// repository so it only ever stores what NASA really said rather than the
/// sample set the repository substitutes (plan decision 13).
///
/// **It reads [storeProvider], so this now throws until the store is wired.**
/// That is the intended direction of the dependency: the cache's whole value is
/// on the disk, and a repository built without one would be the no-cache app
/// silently, on a path nobody would think to test.
///
/// Deliberately not `autoDispose`: one load per process is the design
/// ([asteroidFeedProvider]), so a repository that could be thrown away and
/// rebuilt between listeners would only reopen a connection nothing asked for.
final Provider<AsteroidRepository> asteroidRepositoryProvider =
    Provider<AsteroidRepository>(
      (Ref ref) =>
          AsteroidRepository(CachingFeedSource(NeoWsClient(), ref.watch(storeProvider))),
      name: 'asteroidRepository',
    );

/// The sky, and the app's load state — the two are the same object, because
/// there is exactly one load and everything else is a view of it.
///
/// This provider *is* the memoization the prototype gets from calling
/// `loadData()` once per process (`index.html:1143`): the first listener
/// triggers the fetch and every later one joins the same [Future]. A refresh —
/// pull-to-refresh, a resume hook, neither of which exists yet — is
/// `ref.invalidate(asteroidFeedProvider)`, which is the one gesture that must
/// re-hit the network, and is why no TTL cache belongs *underneath* this
/// (plan decision 13).
///
/// **The error branch is unreachable, and that is a promise made one layer
/// down.** [AsteroidRepository.loadData] catches everything and answers a dead
/// network, a rate-limited key, an empty feed, and a corrupt record with the
/// same bundled sample sky (spec 01 §3: the app is always playable). So this
/// resolves to loading → data, never loading → error. An [AsyncError] here
/// would mean that promise broke — a bug to fix in the repository, not a state
/// for the UI to render. Nothing is caught here to paper over it: swallowing it
/// would hide the bug and leave a child on a spinner forever.
final FutureProvider<AsteroidFeed> asteroidFeedProvider =
    FutureProvider<AsteroidFeed>((Ref ref) async {
      final AsteroidRepository repository = ref.watch(
        asteroidRepositoryProvider,
      );
      final AsteroidFeed feed = await repository.loadData();

      // Tomorrow's sky, warmed onto the disk for tomorrow's launch
      // (`specs/06-title-polish-safety.md:38`). **Unawaited on purpose** — the
      // child's sky is in hand and returning it must not wait on a second
      // request; `prefetchTomorrow` never throws, so nothing here can turn a
      // resolved feed into an error.
      //
      // **Skipped on the sample set**, which is the one signal available up here
      // that the network just failed. Prefetching over a dead connection would
      // spend the ceiling again for an answer that cannot come, and on a live
      // connection it costs one request a day against a key a household shares.
      if (!feed.usingFallback) unawaited(repository.prefetchTomorrow());

      return feed;
    }, name: 'asteroidFeed', retry: _neverRetry);

/// Riverpod 3 retries a failed provider **by default** — ten attempts on a
/// 200ms→6400ms backoff (`ProviderContainer.defaultRetry`), roughly 25 seconds
/// of it — and it applies unless a provider opts out, which is why this exists
/// rather than being left implicit.
///
/// Every one of those seconds would be spent behind "Contacting NASA…", and it
/// would quietly undo three decisions already made and tested a layer down:
/// the repository's 10-second ceiling on how long a child may be asked to wait,
/// the client's two-retry schedule, and the deliberate rule that a 429 is
/// *never* retried because NASA's limit is hourly and no backoff clears it.
/// Retry policy belongs to the layer that knows what failed; up here nothing
/// does, because the repository has already turned every failure into a sky.
Duration? _neverRetry(int retryCount, Object error) => null;

/// Every asteroid in the window, deduplicated — the radar's source list
/// (plan decision 9) and the Sky tab's.
final Provider<AsyncValue<List<Asteroid>>> asteroidsProvider = _fieldOf(
  (AsteroidFeed feed) => feed.asteroids,
  name: 'asteroids',
);

/// The handful visiting today: the home overlay strip and the Challenge game's
/// pool. Offline this is the first seven sample records rather than a date
/// filter, and that difference is the repository's to keep (plan decision 10).
final Provider<AsyncValue<List<Asteroid>>> todayListProvider = _fieldOf(
  (AsteroidFeed feed) => feed.todayList,
  name: 'todayList',
);

/// Kid-facing provenance for the Sky tab's footer: `2026-07-14 → 2026-07-16`,
/// or `sample data` offline.
final Provider<AsyncValue<String>> feedRangeProvider = _fieldOf(
  (AsteroidFeed feed) => feed.feedRange,
  name: 'feedRange',
);

/// Whether this sky is the bundled sample set. Only ever decides whether a
/// surface says "(sample)" — the app is equally playable either way, and it
/// must never pass invented rocks off as today's real sky.
///
/// **`false` does not mean "today".** It used to, and no longer does: the feed
/// cache serves the last window NASA answered when the network is gone, so a
/// sky can be real, not the sample set, and still be from an earlier day. A
/// surface that needs to say *when* — the home strip's
/// `${todayList.length} visiting today` (`index.html:454`) is the one that does
/// — must read [AsteroidFeed.provenance] and its three cases, not this. Watch
/// [asteroidFeedProvider] for it; a `provenanceProvider` is one `_fieldOf` call
/// away and is left for the first surface that actually needs one.
final Provider<AsyncValue<bool>> usingFallbackProvider = _fieldOf(
  (AsteroidFeed feed) => feed.usingFallback,
  name: 'usingFallback',
);

/// Which of the three skies this is — the home strip reads it to say whether the
/// animals are visiting `today`, are from an `earlier` cached window, or are the
/// `sample` set ([FeedProvenance]).
///
/// This is the first surface [usingFallbackProvider]'s note anticipated: a bool
/// cannot tell `earlier` (real NASA rocks from a day or two ago) from `today`,
/// and the strip must not print "visiting today" over a two-day-old sky
/// (`CLAUDE.md:60`). So it reads the enum, not the bool.
final Provider<AsyncValue<FeedProvenance>> provenanceProvider = _fieldOf(
  (AsteroidFeed feed) => feed.provenance,
  name: 'provenance',
);

/// The consecutive-days-played streak for the home flame (plan decision 3).
///
/// A read of the store, seeded by the `DayStreak.record` that `bootstrap()` runs
/// before the first frame — so the flame is right at first paint, not a frame
/// later. Its own provider rather than an inline `store.dayStreak` for one
/// reason: a widget test can stand a number in front of the flame without
/// opening a Hive box, exactly as the radar suites override the feed rather than
/// build a repository.
///
/// **Live, by invalidation rather than by holding state** — the shape
/// [gamesHubStatsProvider] uses, and chosen here for the same two reasons.
/// Starting a game is an engagement too (`GameActions.markPlayed`, which owns
/// the trigger decision), so a child who plays across midnight moves the streak
/// mid-session; `GameActions` drops this snapshot when — and only when — that
/// write actually changed the number. Keeping it a [Provider] leaves the store
/// the single source of truth, with no second in-memory copy of the count to
/// drift from the box, and keeps `overrideWithValue` working, which six test
/// files use to stand a fixed flame in front of the radar. `NotifierProvider`
/// has no such override, so lifting it would have churned all six for no
/// behaviour.
final Provider<int> dayStreakProvider = Provider<int>(
  (Ref ref) => ref.watch(storeProvider).dayStreak,
  name: 'dayStreak',
);

/// What "today" is, for every day-streak write.
///
/// Its own provider for one reason: without it, the only way to test that
/// engaging on a *new day* moves the flame is to hand-build the writer with a
/// fake clock — which tests everything except the wiring, and the wiring is
/// where the staleness bug lived. Overriding this instead lets a test drive the
/// real `gameActionsProvider` or [recordEngagementProvider], callbacks and all,
/// on any day it likes.
///
/// It lives here, next to [dayStreakProvider], rather than in the games feature
/// where it started life as `gameClockProvider`. Starting a game was the only
/// caller then, so the name was accurate; a resume from the background is a
/// second one, and a clock named after one of its two consumers is how the
/// other ends up with a clock of its own that drifts.
final Provider<DateTime Function()> dayClockProvider =
    Provider<DateTime Function()>((Ref ref) => DateTime.now, name: 'dayClock');

/// Record today as a day the child engaged with Rockimals, and repaint the home
/// flame if — and only if — that moved it.
///
/// **The third caller of [DayStreak.record], and the one that covers an
/// ordinary phone habit the other two cannot.** `bootstrap()` records the day at
/// cold launch and `GameActions.markPlayed` records it when a game begins.
/// Neither fires for a child who leaves the radar open, locks the phone, and
/// comes back the next morning: the process never died, so there is no launch,
/// and they have not started a game. Until this, that child saw yesterday's
/// flame until they force-quit the app.
///
/// A function behind a [Provider] rather than a method on some notifier,
/// matching `gameActionsProvider`: the store stays the single source of truth
/// and the flame stays a memoised read of it, invalidated on a write. See
/// [DayStreak.recordAndNotify] for why the "only on a move" guard is not
/// written out here.
final Provider<Future<void> Function()> recordEngagementProvider =
    Provider<Future<void> Function()>((Ref ref) {
      final Store store = ref.watch(storeProvider);
      final DateTime Function() now = ref.watch(dayClockProvider);
      return () async => DayStreak.recordAndNotify(
        store,
        now(),
        () => ref.invalidate(dayStreakProvider),
      );
    }, name: 'recordEngagement');

/// The animals a child follows, live — the persisted set of designations
/// (plan decision 4), read as `state` and changed through [toggle].
///
/// **A `Notifier`, where [dayStreakProvider] next to it is an invalidated read,
/// and the difference is how often the writer fires.** The streak moves at most
/// once a day, from a launch or a game start, and nothing on screen is waiting
/// on the same tap — so re-reading the store on invalidation is enough. A follow
/// is the opposite: the radar's Follow button and the detail screen both write it
/// *during* a session and the button must flip the same frame the thumb lifts. So
/// this holds the set in [state], seeds it from the store, and writes every
/// change straight back.
///
/// Seeded and keyed by **real designation** (`2011 EW`), the asteroid's identity
/// everywhere in this app (plan decision 12) — never the derived "Milo the Fox",
/// which would point at a different animal in a build where the pool changed.
class FollowsNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => ref.watch(storeProvider).follows.toSet();

  /// Whether [designation] is currently followed.
  bool isFollowing(String designation) => state.contains(designation);

  /// Add or remove [designation] and persist the new set (`watch.add`/`delete`,
  /// `index.html:725`).
  ///
  /// A fresh set rather than a mutation of [state]: a `Notifier` only notifies
  /// when `state` is reassigned to a value that is not `identical` to the old
  /// one, so mutating the existing set in place would write to Hive and change
  /// nothing on screen. Insertion order is preserved through the `{...}` copy,
  /// which is what the store persists (`Store.follows`).
  Future<void> toggle(String designation) {
    final Set<String> next = <String>{...state};
    if (next.contains(designation)) {
      next.remove(designation);
    } else {
      next.add(designation);
    }
    state = next;
    return ref.read(storeProvider).setFollows(next);
  }
}

/// The live follow set (plan decision 4). See [FollowsNotifier].
final NotifierProvider<FollowsNotifier, Set<String>> followsProvider =
    NotifierProvider<FollowsNotifier, Set<String>>(
      FollowsNotifier.new,
      name: 'follows',
    );

/// One field of the loaded feed, and nothing else — the shape every derived
/// provider above shares.
///
/// [AsyncValue] rather than a bare value on purpose. These fields have no
/// honest answer before the feed resolves: an empty `asteroids` would read as
/// "space is empty" and a `usingFallback` of `false` would read as "this is
/// NASA's real sky", and both are lies told at exactly the moment the app does
/// not know yet. Callers behind the loading screen that legitimately know the
/// data is there can say so with `.requireValue`.
///
/// **No `.select` here, and that was measured rather than assumed.** The
/// obvious reason to split one feed into four providers is so that a widget
/// watching [feedRangeProvider] does not repaint when a refresh changes the
/// asteroids under an unchanged caption — but Riverpod already delivers that,
/// one layer lower: a derived provider notifies its listeners only when its own
/// output differs by `==`, and `AsyncData('2026-07-14 → 2026-07-16')` equals
/// itself. Adding `.select` on top suppressed nothing that was not already
/// suppressed; dropping it kept every test green, including the one that
/// watches for exactly that rebuild.
Provider<AsyncValue<T>> _fieldOf<T>(
  T Function(AsteroidFeed feed) field, {
  required String name,
}) {
  return Provider<AsyncValue<T>>(
    (Ref ref) => ref.watch(asteroidFeedProvider).whenData(field),
    name: name,
  );
}

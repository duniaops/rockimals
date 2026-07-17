import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rockimals/data/asteroid_repository.dart';
import 'package:rockimals/data/models/asteroid.dart';
import 'package:rockimals/data/models/asteroid_feed.dart';
import 'package:rockimals/data/neows_client.dart';

/// The data layer's composition root, and the seam every test and every future
/// decorator reaches for.
///
/// This is the only place the app names a concrete [NeoWsClient]. The feed
/// cache lands as a decorator here (`Repository → CachingFeedSource →
/// NeoWsClient`) without a single consumer changing, and tests swap the whole
/// repository for a fake rather than standing up a socket.
///
/// Deliberately not `autoDispose`: one load per process is the design
/// ([asteroidFeedProvider]), so a repository that could be thrown away and
/// rebuilt between listeners would only reopen a connection nothing asked for.
final Provider<AsteroidRepository> asteroidRepositoryProvider =
    Provider<AsteroidRepository>(
      (Ref ref) => AsteroidRepository(NeoWsClient()),
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
    FutureProvider<AsteroidFeed>(
      (Ref ref) => ref.watch(asteroidRepositoryProvider).loadData(),
      name: 'asteroidFeed',
      retry: _neverRetry,
    );

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
final Provider<AsyncValue<bool>> usingFallbackProvider = _fieldOf(
  (AsteroidFeed feed) => feed.usingFallback,
  name: 'usingFallback',
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

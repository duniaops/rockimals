import 'package:dio/dio.dart';
import 'package:rockimals/core/config/app_config.dart';
import 'package:rockimals/data/models/asteroid.dart';
import 'package:rockimals/data/models/feed_window.dart';
import 'package:rockimals/data/retry_interceptor.dart';

/// Where the app's live asteroids come from.
///
/// An interface rather than just the concrete [NeoWsClient] because two things
/// have to stand in for it: the feed cache wraps it, and the repository's tests
/// need to exercise a thin feed, a duplicate designation, and a dead network
/// without calling NASA 30 times an hour on a shared demo key.
abstract interface class AsteroidFeedSource {
  /// The asteroids for a window, **and which window that turned out to be**.
  ///
  /// [startDate] and [endDate] (`YYYY-MM-DD`, inclusive) are what the caller
  /// wants. The returned [FeedWindow] says what it got, and the two need not
  /// match: a source with no network may still hold a real sky for an earlier
  /// window, and answering it honestly is strictly better than refusing (see
  /// [FeedWindow]). An implementation that goes and asks NASA, of course, always
  /// answers the window it was given.
  ///
  /// A caller must therefore caption and age-check what it *received*, never
  /// what it requested.
  ///
  /// Throws on anything the app cannot use — a dead network, a non-2xx status,
  /// a body that is not the shape NeoWs documents, or a record whose numbers do
  /// not parse. Every one of those means the same thing to the caller ("use the
  /// sample data"), so none of them is distinguished here.
  Future<FeedWindow> fetchFeed({
    required String startDate,
    required String endDate,
  });
}

/// Reads NASA's Near Earth Object Web Service feed.
///
/// A port of the fetch half of the prototype's `loadData()`
/// (`index.html:364-383`). This class knows the feed's URL and its JSON shape
/// and nothing else: the decisions about a feed that is *usable but thin*, and
/// about which animals are visiting today, are the repository's, because they
/// are policy rather than protocol.
class NeoWsClient implements AsteroidFeedSource {
  /// Configures whatever [Dio] it is handed, rather than only the one it makes
  /// itself: the injected instance exists so tests can stub the socket, and a
  /// test whose client had no timeouts and no retry would be testing a client
  /// this app never runs.
  NeoWsClient({Dio? dio, Future<void> Function(Duration)? sleep})
    : _dio = dio ?? Dio() {
    _dio.options = _dio.options.copyWith(
      connectTimeout: _connectTimeout,
      receiveTimeout: _receiveTimeout,
    );
    _dio.interceptors.add(RetryInterceptor(_dio, sleep: sleep));
  }

  /// Dio ships with **no** timeouts — both default to null, meaning wait
  /// forever — and forever is a real duration on a phone. Airplane mode fails
  /// fast and is fine; the case these bound is the hotel or café captive
  /// portal, which accepts the connection and then answers nothing. Without a
  /// timeout `loadData()` never returns, its catch never fires, the sample set
  /// never loads, and "Contacting NASA…" *is* the app, permanently — the exact
  /// opposite of spec 01 §3's promise that it is always playable.
  ///
  /// Per-attempt, not total: `AsteroidRepository` owns the overall budget. The
  /// job here is only to stop one dead socket from eating all of it, so that a
  /// retry still fits inside.
  static const Duration _connectTimeout = Duration(seconds: 4);
  static const Duration _receiveTimeout = Duration(seconds: 6);

  final Dio _dio;

  /// Dio's default `validateStatus` rejects any non-2xx, which is the port of
  /// the prototype's `if(!r.ok) throw 0` — a rate-limited 429 on `DEMO_KEY` and
  /// a 500 from NASA both land in the caller's fallback path. What differs is
  /// the route: the 500 gets retried on the way there ([RetryInterceptor]), the
  /// 429 does not, because an hourly limit outlasts any backoff worth waiting.
  /// Always answers the window it was asked for, because it just asked NASA for
  /// exactly that — the honesty [FeedWindow] exists to allow costs this class
  /// nothing. It is `CachingFeedSource` that has a real choice to make.
  @override
  Future<FeedWindow> fetchFeed({
    required String startDate,
    required String endDate,
  }) async {
    final Response<Object?> response = await _dio.get<Object?>(
      '${AppConfig.neowsBaseUrl}/feed',
      queryParameters: <String, String>{
        'start_date': startDate,
        'end_date': endDate,
        'api_key': AppConfig.nasaApiKey,
      },
    );
    return FeedWindow(
      asteroids: _parseFeed(response.data),
      startDate: startDate,
      endDate: endDate,
    );
  }

  /// The feed nests its objects under `near_earth_objects` keyed by date, and
  /// that date key — not anything on the object — is what tells the app which
  /// day an approach belongs to, so it is threaded into every [Asteroid].
  ///
  /// Iteration follows the JSON's own key order. `jsonDecode` preserves it, as
  /// does the prototype's `Object.keys`, and it is load-bearing downstream: it
  /// decides which record wins a dedupe collision and it fixes each animal's
  /// index, which the radar seeds its orbit phase from.
  static List<Asteroid> _parseFeed(Object? body) {
    if (body is! Map<String, Object?>) {
      throw FormatException('NeoWs: expected a JSON object, got: $body');
    }

    final Object? byDate = body['near_earth_objects'];
    // The prototype's `||{}`: a feed with no objects at all is not malformed,
    // it is empty. It fails the caller's "too few to play with" check instead.
    if (byDate == null) return const <Asteroid>[];
    if (byDate is! Map<String, Object?>) {
      throw FormatException('NeoWs: expected near_earth_objects, got: $byDate');
    }

    final List<Asteroid> pool = <Asteroid>[];
    for (final MapEntry<String, Object?> day in byDate.entries) {
      final Object? neos = day.value;
      if (neos is! List<Object?>) {
        throw FormatException('NeoWs: expected a list at "${day.key}"');
      }
      for (final Object? neo in neos) {
        if (neo is! Map<String, Object?>) {
          throw FormatException('NeoWs: expected an object in "${day.key}"');
        }
        // A NEO with no close-approach entry has no distance and no speed, so
        // there is no animal to make of it. The prototype skips it rather than
        // failing the feed (`index.html:372`); one incomplete rock is not a
        // reason to send a child to the sample data.
        final Map<String, Object?>? closeApproach = Asteroid.firstCloseApproach(
          neo,
        );
        if (closeApproach == null) continue;

        pool.add(Asteroid.fromNeoWs(neo, closeApproach, day.key));
      }
    }
    return pool;
  }
}

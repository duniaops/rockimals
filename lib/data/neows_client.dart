import 'package:dio/dio.dart';
import 'package:rockimals/core/config/app_config.dart';
import 'package:rockimals/data/models/asteroid.dart';

/// Where the app's live asteroids come from.
///
/// An interface rather than just the concrete [NeoWsClient] because two things
/// have to stand in for it: the feed cache wraps it, and the repository's tests
/// need to exercise a thin feed, a duplicate designation, and a dead network
/// without calling NASA 30 times an hour on a shared demo key.
abstract interface class AsteroidFeedSource {
  /// Every asteroid the feed lists between [startDate] and [endDate] inclusive
  /// (`YYYY-MM-DD`), in the order the feed returned them.
  ///
  /// Throws on anything the app cannot use — a dead network, a non-2xx status,
  /// a body that is not the shape NeoWs documents, or a record whose numbers do
  /// not parse. Every one of those means the same thing to the caller ("use the
  /// sample data"), so none of them is distinguished here.
  Future<List<Asteroid>> fetchFeed({
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
  NeoWsClient({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  /// Dio's default `validateStatus` rejects any non-2xx, which is the port of
  /// the prototype's `if(!r.ok) throw 0` — a rate-limited 429 on `DEMO_KEY` and
  /// a 500 from NASA both land in the caller's fallback path.
  @override
  Future<List<Asteroid>> fetchFeed({
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
    return _parseFeed(response.data);
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

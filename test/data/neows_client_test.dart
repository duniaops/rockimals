import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/data/models/asteroid.dart';
import 'package:rockimals/data/neows_client.dart';

import '../support/stub_http_adapter.dart';

/// These tests run against `test/fixtures/neows_feed.json` — the same real,
/// unedited capture the model's tests use (`GET /feed?start_date=2026-07-14&
/// end_date=2026-07-16&api_key=DEMO_KEY`, 13 objects over three days).
///
/// It earns its keep again here for a reason no hand-written fixture would have
/// reproduced: NASA returns the date keys **out of order** — `2026-07-16` comes
/// first, then `07-14`, then `07-15`. The client iterates the JSON's own key
/// order, so that ordering is what the app sees, and it is what decides every
/// asteroid's index. The radar seeds each animal's orbit phase from that index.
///
/// The network is stubbed at Dio's adapter, one layer below the client, so the
/// URL, the query string, and the status handling are all real code under test
/// while NASA's 30-requests-an-hour demo key is left alone.
void main() {
  final String feedJson = File('test/fixtures/neows_feed.json').readAsStringSync();

  group('NeoWsClient.fetchFeed', () {
    test('parses every object in a real capture, in the feed\'s own order', () async {
      final NeoWsClient client = _clientReturning(feedJson);

      final List<Asteroid> pool = await client.fetchFeed(
        startDate: '2026-07-14',
        endDate: '2026-07-16',
      );

      expect(pool.length, 13);
      // Document order, not chronological: the five of 07-16 first.
      expect(pool.first.name, '2009 DB1');
      expect(pool[5].name, '2011 UT');
      expect(pool.last.name, '2015 AF45');
    });

    test('threads the date key each object was filed under onto the asteroid', () async {
      // The date lives on the feed's key, not on the object, and the app needs
      // it to know who is visiting today. Losing it here would leave the home
      // strip padding from the window every single day, silently.
      final NeoWsClient client = _clientReturning(feedJson);

      final List<Asteroid> pool = await client.fetchFeed(
        startDate: '2026-07-14',
        endDate: '2026-07-16',
      );

      expect(pool.where((Asteroid a) => a.date == '2026-07-16').length, 5);
      expect(pool.where((Asteroid a) => a.date == '2026-07-14').length, 4);
      expect(pool.where((Asteroid a) => a.date == '2026-07-15').length, 4);
    });

    test('asks NASA for the window it was given, with the configured key', () async {
      final StubHttpAdapter adapter = StubHttpAdapter.json(feedJson);
      final NeoWsClient client = NeoWsClient(dio: Dio()..httpClientAdapter = adapter);

      await client.fetchFeed(startDate: '2026-07-14', endDate: '2026-07-16');

      final Uri uri = adapter.lastRequest!.uri;
      expect(uri.host, 'api.nasa.gov');
      expect(uri.path, '/neo/rest/v1/feed');
      expect(uri.queryParameters['start_date'], '2026-07-14');
      expect(uri.queryParameters['end_date'], '2026-07-16');
      // Default build; `flutter test --dart-define=NASA_API_KEY=…` overrides it,
      // which is why this asserts a non-empty key rather than DEMO_KEY exactly.
      expect(uri.queryParameters['api_key'], isNotEmpty);
    });

    test('throws on a non-2xx status', () async {
      // The prototype's `if(!r.ok) throw 0`. The realistic case is a 429: the
      // shared DEMO_KEY allows 30 requests an hour per IP, so this is the path
      // a kid on a busy network actually takes to the sample set.
      final NeoWsClient client = _clientReturning('{"error":"rate limited"}', status: 429);

      expect(
        () => client.fetchFeed(startDate: '2026-07-14', endDate: '2026-07-16'),
        throwsA(isA<DioException>()),
      );
    });

    test('skips an object with no close-approach data rather than failing', () async {
      // No approach entry means no distance and no speed, so there is no animal
      // to make. One such rock must not cost the other twelve their sky.
      final NeoWsClient client = _clientReturning(
        jsonEncode(<String, Object?>{
          'near_earth_objects': <String, Object?>{
            '2026-07-16': <Object?>[
              _neo(name: '(2020 SW)'),
              _neo(name: '(1999 XX)', closeApproaches: <Object?>[]),
              _neo(name: '(2001 YY)', closeApproaches: null),
            ],
          },
        }),
      );

      final List<Asteroid> pool = await client.fetchFeed(
        startDate: '2026-07-16',
        endDate: '2026-07-16',
      );

      expect(pool.map((Asteroid a) => a.name), <String>['2020 SW']);
    });

    test('reads a feed with no objects as empty, not as broken', () async {
      // The prototype's `d.near_earth_objects||{}`. An empty sky is a real
      // answer NASA can give; the caller turns it into the sample set via the
      // too-few-objects rule, not via the error path.
      final NeoWsClient client = _clientReturning('{"element_count":0}');

      expect(
        await client.fetchFeed(startDate: '2026-07-16', endDate: '2026-07-16'),
        isEmpty,
      );
    });

    test('throws on a body that is not the shape NeoWs documents', () async {
      final NeoWsClient client = _clientReturning('{"near_earth_objects":[]}');

      expect(
        () => client.fetchFeed(startDate: '2026-07-16', endDate: '2026-07-16'),
        throwsA(isA<FormatException>()),
      );
    });

    test('bounds every attempt, so a socket that never answers cannot hang the app', () async {
      // Dio's timeouts both default to null — wait forever — and forever is a
      // duration a phone really reaches: a captive portal accepts the
      // connection and then says nothing. Without these, loadData() never
      // returns, its catch never fires, the sample set never loads, and
      // "Contacting NASA…" is the app until it is force-quit.
      //
      // The exact durations are a judgment call and not worth pinning; that
      // they exist, and sit inside the repository's ten-second ceiling so a
      // retry still fits, is the part that must not regress.
      final Dio dio = Dio()..httpClientAdapter = StubHttpAdapter.json('{}');

      NeoWsClient(dio: dio);

      expect(dio.options.connectTimeout, isNotNull);
      expect(dio.options.receiveTimeout, isNotNull);
      expect(dio.options.connectTimeout, lessThan(const Duration(seconds: 10)));
      expect(dio.options.receiveTimeout, lessThan(const Duration(seconds: 10)));
    });

    test('retries past a 500 and still returns the feed', () async {
      // End to end through the real client: the retry is installed on the Dio
      // the app actually uses, not just unit-tested in isolation.
      int calls = 0;
      final NeoWsClient client = NeoWsClient(
        dio: Dio()
          ..httpClientAdapter = StubHttpAdapter((RequestOptions options) {
            return calls++ == 0
                ? StubHttpAdapter.jsonResponse('{"error":"boom"}', 500)
                : StubHttpAdapter.jsonResponse(feedJson);
          }),
        sleep: (Duration _) async {},
      );

      final List<Asteroid> pool = await client.fetchFeed(
        startDate: '2026-07-14',
        endDate: '2026-07-16',
      );

      expect(pool.length, 13);
      expect(calls, 2);
    });

    test('asks once and once only when the demo key is rate-limited', () async {
      // A 429 must reach the fallback on the first answer. Retrying it cannot
      // work (the limit is hourly) and would spend more of the very budget
      // that ran out — see retry_interceptor_test.dart.
      int calls = 0;
      final NeoWsClient client = NeoWsClient(
        dio: Dio()
          ..httpClientAdapter = StubHttpAdapter((RequestOptions options) {
            calls++;
            return StubHttpAdapter.jsonResponse('{"error":"rate"}', 429);
          }),
      );

      await expectLater(
        client.fetchFeed(startDate: '2026-07-14', endDate: '2026-07-16'),
        throwsA(isA<DioException>()),
      );
      expect(calls, 1);
    });

    test('throws on a record whose numbers do not parse', () async {
      // Deliberate: the model throws where the prototype's parseFloat yields
      // NaN. A NaN would flow into power() and the radar geometry and reach a
      // child as "power ⭐ NaN"; a throw reaches the sample set instead.
      final NeoWsClient client = _clientReturning(
        jsonEncode(<String, Object?>{
          'near_earth_objects': <String, Object?>{
            '2026-07-16': <Object?>[
              _neo(name: '(2020 SW)', lunar: 'not-a-number'),
            ],
          },
        }),
      );

      expect(
        () => client.fetchFeed(startDate: '2026-07-16', endDate: '2026-07-16'),
        throwsA(isA<FormatException>()),
      );
    });
  });
}

NeoWsClient _clientReturning(String body, {int status = 200}) {
  return NeoWsClient(
    dio: Dio()..httpClientAdapter = StubHttpAdapter.json(body, status: status),
  );
}

/// Mirrors the capture's shape, trimmed to the keys the parser reads.
Map<String, Object?> _neo({
  required String name,
  Object? closeApproaches = _unset,
  String lunar = '0.07',
}) {
  return <String, Object?>{
    'name': name,
    'nasa_jpl_url': 'https://ssd.jpl.nasa.gov/tools/sbdb_lookup.html',
    'absolute_magnitude_h': 28.2,
    'estimated_diameter': <String, Object?>{
      'meters': <String, Object?>{
        'estimated_diameter_min': 4.1,
        'estimated_diameter_max': 9.3,
      },
    },
    'is_potentially_hazardous_asteroid': false,
    if (closeApproaches != _unset)
      'close_approach_data': closeApproaches
    else
      'close_approach_data': <Object?>[
        <String, Object?>{
          'relative_velocity': <String, Object?>{'kilometers_per_second': '8.1'},
          'miss_distance': <String, Object?>{'lunar': lunar, 'kilometers': '26908'},
        },
      ],
  };
}

/// Distinguishes "caller passed null" (the key is present and null) from
/// "caller said nothing" (build the default entry).
const Object _unset = Object();

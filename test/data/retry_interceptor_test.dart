import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/data/retry_interceptor.dart';

import '../support/stub_http_adapter.dart';

/// The retry policy is mostly a set of decisions about what *not* to repeat, so
/// most of what follows asserts that a request was made exactly once.
///
/// Every test injects its own `sleep`, which is what makes them assert the
/// schedule (`[400ms, 800ms]`) rather than live through it. A suite that waited
/// out its own backoff would take longer than the app does and would still not
/// prove the delays grow.
void main() {
  group('RetryInterceptor — what it retries', () {
    test('retries a 500 with growing delays, then gives up', () async {
      final _Socket socket = _Socket.always(_error(500));

      await expectLater(socket.get(), throwsA(isA<DioException>()));

      // Three attempts: the original plus two retries. The delays grow — a
      // fixed pause would be a hammer, not a backoff.
      expect(socket.calls, 3);
      expect(socket.slept, <Duration>[
        const Duration(milliseconds: 400),
        const Duration(milliseconds: 800),
      ]);
    });

    test(
      'a retried request that succeeds returns NASA\'s answer, not the error',
      () async {
        // The whole point: one blip on a flaky connection must not cost a child
        // today's real sky.
        final _Socket socket = _Socket.script(<ResponseBody Function()>[
          _error(503),
          () => StubHttpAdapter.jsonResponse('{"element_count":1}'),
        ]);

        final Response<Object?> response = await socket.get();

        expect(response.statusCode, 200);
        expect(socket.calls, 2);
        expect(socket.slept, <Duration>[const Duration(milliseconds: 400)]);
      },
    );

    test('retries a dropped connection and a stalled socket', () async {
      for (final DioExceptionType type in <DioExceptionType>[
        DioExceptionType.connectionError,
        DioExceptionType.connectionTimeout,
        DioExceptionType.receiveTimeout,
        DioExceptionType.sendTimeout,
      ]) {
        final _Socket socket = _Socket.throwing(type);

        await expectLater(socket.get(), throwsA(isA<DioException>()));

        expect(socket.calls, 3, reason: '$type should be retried');
      }
    });
  });

  group('RetryInterceptor — what it must not retry', () {
    test(
      'never retries a 429, because an hourly limit outlasts any backoff',
      () async {
        // The load-bearing exclusion, and the one that looks wrong. 429 is the
        // textbook back-off-and-try-again status, but NASA rate-limits on a
        // rolling hour: no delay a child would sit through can clear it. Retrying
        // is guaranteed to fail, and it spends two more requests from a
        // 30-per-hour allowance a whole household shares — so the one path a
        // busy family reliably takes to the sample set would also be the path
        // that makes the limit worse.
        final _Socket socket = _Socket.always(_error(429));

        await expectLater(socket.get(), throwsA(isA<DioException>()));

        expect(socket.calls, 1);
        expect(socket.slept, isEmpty);
      },
    );

    test('never retries our own mistakes — a 400 or a 403', () async {
      // Deterministic and ours: a 400 means the app built a date NeoWs cannot
      // read, a 403 means the key is wrong. The same request fails identically
      // forever, so a retry only delays the fallback.
      for (final int status in <int>[400, 403, 404]) {
        final _Socket socket = _Socket.always(_error(status));

        await expectLater(socket.get(), throwsA(isA<DioException>()));

        expect(socket.calls, 1, reason: '$status should not be retried');
        expect(socket.slept, isEmpty);
      }
    });

    test(
      'stops after the schedule runs out rather than looping forever',
      () async {
        // Re-issuing a request re-enters this same interceptor, so "retry" is an
        // infinite loop unless the attempt count travels with the request. This
        // asserts the counter survives the re-dispatch.
        final _Socket socket = _Socket.always(_error(500));

        await expectLater(socket.get(), throwsA(isA<DioException>()));

        expect(socket.calls, 3);
      },
    );
  });
}

/// A Dio wired to a scripted socket, carrying the interceptor under test.
class _Socket {
  _Socket._(List<ResponseBody Function(RequestOptions)> script) {
    final StubHttpAdapter adapter = StubHttpAdapter((RequestOptions options) {
      final int index = calls++;
      final ResponseBody Function(RequestOptions) reply = index < script.length
          ? script[index]
          : script.last;
      return reply(options);
    });
    _dio = Dio()..httpClientAdapter = adapter;
    _dio.interceptors.add(
      RetryInterceptor(_dio, sleep: (Duration delay) async => slept.add(delay)),
    );
  }

  /// Answers every attempt the same way.
  factory _Socket.always(ResponseBody Function() reply) =>
      _Socket._(<ResponseBody Function(RequestOptions)>[(_) => reply()]);

  /// Answers each attempt from the list in turn; the last reply repeats.
  factory _Socket.script(List<ResponseBody Function()> replies) => _Socket._(
    replies
        .map(
          (ResponseBody Function() reply) =>
              (RequestOptions _) => reply(),
        )
        .toList(growable: false),
  );

  /// A socket that fails below the HTTP layer — no status, just a broken pipe.
  factory _Socket.throwing(DioExceptionType type) =>
      _Socket._(<ResponseBody Function(RequestOptions)>[
        (RequestOptions options) =>
            throw DioException(requestOptions: options, type: type),
      ]);

  late final Dio _dio;

  int calls = 0;
  final List<Duration> slept = <Duration>[];

  Future<Response<Object?>> get() =>
      _dio.get<Object?>('https://api.nasa.gov/x');
}

/// Dio turns a non-2xx into a `badResponse` DioException itself, so the socket
/// only has to hand back the status.
///
/// A **builder**, not a response, and the distinction is the whole reason these
/// tests can see a retry at all: a [ResponseBody] wraps a single-subscription
/// stream, so handing the same instance to a second attempt fails on the
/// already-consumed stream rather than on the status it is meant to be
/// testing — and a retry test that never reaches its second reply quietly
/// asserts nothing. Every attempt gets a freshly built body, exactly as a real
/// socket would deliver one.
ResponseBody Function() _error(int status) =>
    () => StubHttpAdapter.jsonResponse('{"error":"$status"}', status);

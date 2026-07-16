import 'package:dio/dio.dart';

/// Retries the handful of request failures that a second attempt can actually
/// fix — a dropped connection, a stalled socket, a 5xx from NASA.
///
/// This sits on the [Dio] instance rather than wrapping `AsteroidFeedSource`,
/// and the placement is the design. That interface deliberately collapses every
/// failure into one meaning ("use the sample data"), so a retrying *decorator*
/// above it would have to re-open the box the contract closes: it would need to
/// tell a 500 from a [FormatException] to know what is worth repeating. Down
/// here the inputs to that decision exist natively (a status, a
/// [DioExceptionType]), and the app's own parse is *structurally* out of
/// reach: `NeoWsClient` turns the body into asteroids only once the whole
/// interceptor chain has returned, so the [FormatException] it throws for a
/// record NASA sent malformed can never arrive here. "Never retry a body that
/// will not parse" is a property of where this code lives rather than a check
/// someone has to remember to write.
class RetryInterceptor extends Interceptor {
  RetryInterceptor(
    this._dio, {
    List<Duration>? delays,
    Future<void> Function(Duration)? sleep,
  }) : _delays = delays ?? defaultDelays,
       _sleep = sleep ?? Future<void>.delayed;

  /// Two retries, backing off 400ms then 800ms.
  ///
  /// Small on purpose. Every attempt is another request against `DEMO_KEY`'s
  /// 30-per-hour-per-IP budget — a budget a household shares — so a generous
  /// retry schedule spends the very allowance it is meant to protect, while a
  /// child watches a spinner. The total (~1.2s of waiting) is what a flaky
  /// connection needs and no more.
  ///
  /// No jitter: it exists to break up correlated retries stampeding a shared
  /// server, and this app's clients are uncorrelated cold launches on a
  /// per-IP limit, where a "stampede" is one household.
  static const List<Duration> defaultDelays = <Duration>[
    Duration(milliseconds: 400),
    Duration(milliseconds: 800),
  ];

  final Dio _dio;
  final List<Duration> _delays;

  /// Injected by tests so the suite asserts on the delays rather than living
  /// through them. Production sleeps for real.
  final Future<void> Function(Duration) _sleep;

  /// Rides along on the request so the count survives re-dispatch. Re-issuing
  /// through [Dio.fetch] re-enters this interceptor, so without a counter that
  /// travels with the request, "retry" is an infinite loop.
  static const String _attemptKey = 'rockimals.retry.attempt';

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final int attempt = (err.requestOptions.extra[_attemptKey] as int?) ?? 0;
    if (attempt >= _delays.length || !_isWorthRetrying(err)) {
      handler.next(err);
      return;
    }

    await _sleep(_delays[attempt]);

    final RequestOptions options = err.requestOptions;
    options.extra[_attemptKey] = attempt + 1;
    try {
      handler.resolve(await _dio.fetch<Object?>(options));
    } on DioException catch (retryError) {
      // The retry failed too. Hand the *new* failure onward rather than the
      // original, so the app falls back for the reason it actually hit last.
      handler.next(retryError);
    }
  }

  /// True only where waiting and asking again is plausibly different.
  ///
  /// The interesting exclusion is **429**, which reads like the obvious thing
  /// to back off from and is the one case where backing off cannot work: NASA
  /// rate-limits on a rolling *hourly* window, so no delay a child would sit
  /// through clears it. Retrying a 429 is guaranteed to fail, costs another
  /// second of the loading screen, and spends two more requests from an
  /// allowance that is already exhausted. It falls straight through to the
  /// sample set instead — which is the faster path to a playable sky anyway.
  ///
  /// 400 and 403 are excluded for the opposite reason: they are deterministic
  /// and ours. A 400 means we built a date NeoWs does not understand and a 403
  /// means the key is wrong; the same request will fail identically forever.
  static bool _isWorthRetrying(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return true;
      case DioExceptionType.badResponse:
        final int? status = error.response?.statusCode;
        return status != null && status >= 500;
      case DioExceptionType.badCertificate:
      case DioExceptionType.cancel:
      // Dio's own decode step ran long. That is this app's CPU chewing on a
      // body it already has, not a network fault, so the same bytes would
      // simply be slow again.
      case DioExceptionType.transformTimeout:
      // Anything Dio could not classify. Retrying an unknown failure is a
      // guess, and the fallback is a good answer — take the good answer.
      case DioExceptionType.unknown:
        return false;
    }
  }
}

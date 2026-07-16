import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Stubs the network at Dio's own seam — the lowest layer this app owns.
///
/// Everything above it is the real code under test: the URL, the query string,
/// the status check, the JSON decode. The alternative, faking the client
/// itself, would test the fake.
///
/// Not a live call to NASA, for two reasons beyond the usual: the shared
/// `DEMO_KEY` allows 30 requests an hour per IP, so a test suite would exhaust
/// the developer's whole budget; and today's sky is different tomorrow, which
/// is the definition of a test that will fail for no reason.
class StubHttpAdapter implements HttpClientAdapter {
  StubHttpAdapter(this._respond);

  /// Answers every request with the same JSON body and status.
  StubHttpAdapter.json(String body, {int status = 200})
    : _respond = ((_) => jsonResponse(body, status));

  final ResponseBody Function(RequestOptions options) _respond;

  /// The last request the client actually made, for asserting on the URL and
  /// query parameters it built.
  RequestOptions? lastRequest;

  static ResponseBody jsonResponse(String body, [int status = 200]) {
    return ResponseBody.fromString(
      body,
      status,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
    return _respond(options);
  }

  @override
  void close({bool force = false}) {}
}

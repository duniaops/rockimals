/// Compile-time configuration for the NASA NeoWs feed.
///
/// The key is a `--dart-define` rather than a runtime setting on purpose: the
/// app has no accounts and no settings surface a key could live behind, and
/// baking it in at build time keeps it out of the UI and out of local storage.
abstract final class AppConfig {
  /// NeoWs API root. Ported from `index.html:366`; the client appends
  /// `/feed?start_date=…&end_date=…&api_key=…`.
  static const String neowsBaseUrl = 'https://api.nasa.gov/neo/rest/v1';

  /// NASA's shared demo key (`index.html:342`). Rate-limited to 30 requests an
  /// hour per IP, so it is fine for development but must be replaced for
  /// release — tracked as the registered-key line of the kids-safety paperwork.
  static const String demoApiKey = 'DEMO_KEY';

  /// The key the client authenticates with.
  ///
  /// Override per build: `flutter run --dart-define=NASA_API_KEY=<key>`.
  static const String nasaApiKey = _key.length == 0 ? demoApiKey : _key;

  /// Falls back on an *empty* define as well as a missing one — `--dart-define=
  /// NASA_API_KEY=` (a shell variable that failed to expand) would otherwise
  /// ship an unauthenticated build that fails with an opaque 403.
  static const String _key = String.fromEnvironment(
    'NASA_API_KEY',
    defaultValue: demoApiKey,
  );
}

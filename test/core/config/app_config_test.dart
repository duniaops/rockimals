import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/core/config/app_config.dart';

void main() {
  // `String.fromEnvironment` resolves at compile time, so a single test binary
  // can only ever observe one value. Rather than pretend otherwise, this file
  // asserts whichever half of the contract the current compilation exercises
  // and registers the matching test. Both halves are covered by running:
  //
  //   flutter test
  //   flutter test --dart-define=NASA_API_KEY=test-key-123
  //
  // Both must pass; the second is the only proof the override actually reaches
  // the client's key, which is the failure a release build would hit silently.
  const defineName = 'NASA_API_KEY';

  test('the NeoWs base URL matches the prototype', () {
    expect(AppConfig.neowsBaseUrl, 'https://api.nasa.gov/neo/rest/v1');
  });

  if (const bool.hasEnvironment(defineName)) {
    const injected = String.fromEnvironment(defineName);

    if (injected.isEmpty) {
      test('an empty --dart-define falls back to the demo key', () {
        expect(AppConfig.nasaApiKey, AppConfig.demoApiKey);
      });
    } else {
      test('--dart-define overrides the demo key', () {
        expect(AppConfig.nasaApiKey, injected);
      });
    }
  } else {
    test('defaults to DEMO_KEY when no key is defined', () {
      expect(AppConfig.nasaApiKey, 'DEMO_KEY');
      expect(AppConfig.nasaApiKey, AppConfig.demoApiKey);
    });
  }
}

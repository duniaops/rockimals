/// The automatable half of the kids-safety release checklist
/// (`specs/06-title-polish-safety.md:56-61`, `CLAUDE.md:43-45`).
///
/// **This file verifies; it does not build.** Every surface it asks about was
/// shipped by an earlier item — the About block by task 08, the parent gate by
/// task 06, the store by task 01. What did not exist until now is a single
/// place that asks, in one run, whether the four claims a grown-up has to sign
/// are still true. They are checked here rather than left to the release
/// paperwork because each one is the kind of promise a single careless import
/// breaks silently: a dependency added for a "quick crash report", a second
/// text field, a key that starts holding a name. None of those look like a
/// safety change in a diff, and all four of these tests fail the moment one
/// lands.
///
/// **The four claims, and where each is proved:**
///
/// 1. *No analytics, ads, or login SDKs.* Two tests below — an allowlist over
///    the direct dependencies and a denylist over the whole resolved graph.
/// 2. *No login, no personal-data collection.* Three tests below — the text
///    input census, what the one field will accept, and the persisted keys.
/// 3. *The parent-gated NASA/JPL link is the app's only way out.* **Already
///    proved, and deliberately not re-proved here** — see the group below.
/// 4. *The attribution and the "unofficial" disclaimer render.* One test
///    below, from a cold launch rather than over the widget in isolation.
///
/// The remaining checklist lines — the store questionnaire, a published privacy
/// policy, a reviewer's sign-off, a registered NASA key — need a person and an
/// artefact, and no test can honestly tick them.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// `Override` lives under `misc.dart` in Riverpod 3, not the package root.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:rockimals/core/audio/sound_engine.dart';
import 'package:rockimals/core/safety/parent_gate.dart';
import 'package:rockimals/core/storage/store.dart';
import 'package:rockimals/data/models/asteroid_feed.dart';
import 'package:rockimals/features/data/providers.dart';
import 'package:rockimals/features/settings/about_block.dart';
import 'package:rockimals/features/title/title_screen.dart';
import 'package:rockimals/main.dart';

import '../../support/memory_store.dart';
import '../../support/recording_sound_engine.dart';

void main() {
  group('checklist 1 — no analytics, ads, or login SDKs', () {
    test('the direct dependencies are exactly the reviewed set', () {
      // **An allowlist, not a denylist, and that is the whole point of this
      // test.** A denylist can only name the SDKs that existed when it was
      // written, and the dependency that breaks this promise will be the one
      // nobody thought to list. The question worth failing on is not "is this a
      // tracker" but "did anything at all arrive that a person has not looked
      // at" — so adding a dependency costs a line here, and the thought that
      // goes with writing it.
      expect(_declaredIn('dependencies'), <String>{
        'flutter',
        'cupertino_icons',
        'flutter_riverpod',
        'dio',
        'hive',
        'hive_flutter',
        // The one package in this app that can reach outside it. Confined to a
        // single importer — see checklist 3.
        'url_launcher',
        'audioplayers',
      });

      expect(_declaredIn('dev_dependencies'), <String>{
        'flutter_test',
        'flutter_lints',
        'path_provider_platform_interface',
      });
    });

    test('and nothing in the resolved graph is a tracker', () {
      // The manifest is where the plan item pointed, but it is not where the
      // risk actually is: a tracking SDK does not have to be *our* dependency
      // to end up in the bundle and start a request. It only has to be
      // somebody else's. So this reads `pubspec.lock` — every package that
      // actually resolves, transitives included — and the allowlist above
      // cannot see any of them.
      //
      // Here a denylist is the right shape and above it was the wrong one: an
      // allowlist over transitives would fail on every routine `pub upgrade`
      // that shifts a sub-dependency, which trains a reader to re-bless the
      // list without looking. This one only ever fires on a name that has no
      // business in a children's app.
      final Set<String> resolved = _lockedPackages();

      // Non-vacuity first. An `isEmpty` assertion over an empty set passes for
      // the worst possible reason — a lockfile that moved or a parser that
      // stopped matching — and it would pass silently forever.
      expect(resolved, contains('dio'));
      expect(resolved.length, greaterThan(_declaredIn('dependencies').length));

      expect(resolved.intersection(_trackingSdks), isEmpty);
    });
  });

  group('checklist 2 — no login, no personal data', () {
    test('the parent gate holds the only text input in the app', () {
      // A child's name, an email, a birthday: all of them need somewhere to be
      // typed, and this app has exactly one such place. Pinning that at the
      // source level rather than screen by screen is what makes the claim
      // cover screens that do not exist yet.
      final List<String> withInputs = _dartFilesUnder('lib')
          .where(
            (File f) =>
                f.readAsStringSync().contains('TextField(') ||
                f.readAsStringSync().contains('TextFormField('),
          )
          .map((File f) => f.path)
          .toList();

      expect(withInputs, <String>['lib/core/safety/parent_gate.dart']);
    });

    testWidgets('and that one field will not take a name', (tester) async {
      // The census above would still pass if the gate's field quietly grew a
      // "who are you?" — so this asks the field itself, by typing a name into
      // it. It is refused by `FilteringTextInputFormatter.digitsOnly`, which
      // exists for the arithmetic and happens to be the strongest possible
      // statement that nothing personal can be entered here: the field cannot
      // represent a name at all, rather than merely not being labelled as one.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (BuildContext context) => TextButton(
                onPressed: () => showParentGate(
                  context,
                  challenge: const ParentGateChallenge(3, 9),
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Ada Lovelace');
      await tester.pump();

      expect(find.text('Ada Lovelace'), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        isEmpty,
        reason: 'the gate must be arithmetic, not a form',
      );
    });

    test(
      'every persisted key is a score, a toggle, or a public designation',
      () async {
        // **Asked of the box, not of `Store`'s field list.** The interesting
        // failure is a key that gets written without a named accessor — a
        // "last seen" timestamp, a device id stashed for a crash report — and
        // reading the box back is the only way to see one. Writing through every
        // setter first means the assertion is over the full key set the app can
        // produce, not just the subset a fresh install happens to have touched.
        final Directory tempDir = await Directory.systemTemp.createTemp(
          'rockimals_safety_keys',
        );
        addTearDown(() async {
          await Hive.deleteFromDisk();
          await Hive.close();
          if (tempDir.existsSync()) await tempDir.delete(recursive: true);
        });

        Hive.init(tempDir.path);
        final Store store = await Store.open();
        await store.setPoints(10);
        await store.setPlayed(3);
        await store.setBestStreak(4);
        await store.setPerfect(1);
        await store.setBadges(<String>['first']);
        await store.setFollows(<String>['2011 EW']);
        await store.setBestDuel(5);
        await store.setBestCloser(6);
        await store.setBestSize(8);
        await store.setDayStreak(2);
        await store.setLastPlayedDate('2026-07-18');
        await store.setSoundOn(false);
        await store.setReducedMotion(true);
        await store.setLittleKidsMode(true);
        await store.setCachedFeed('{}');

        expect(Hive.box<Object>(Store.boxName).keys.toSet(), <String>{
          // Scores and counters — a number the child earned, about nobody.
          'aw_points',
          'aw_played',
          'aw_bstreak',
          'aw_perfect',
          'aw_duel',
          'aw_closer',
          'aw_size',
          'aw_daystreak',
          // Toggles the child or their grown-up set.
          'aw_sound',
          'aw_motion',
          'aw_littlekids',
          // Earned badge ids — the app's own vocabulary.
          'aw_badges',
          // Asteroid designations the child chose to follow, and a copy of a feed
          // NASA published to the whole world. Public facts, not private ones.
          'aw_follows',
          'aw_feedcache',
          // The coarsest date the app can hold: a calendar day, so a streak can
          // be counted. Nothing finer, and nothing that says where or on what.
          'aw_lastplayed',
        });
      },
    );
  });

  group('checklist 3 — the parent-gated link is the only way out', () {
    test('is proved by the parent gate suite, which still says so', () {
      // **Deliberately a citation and not a third copy.**
      // `parent_gate_test.dart`'s two cases already prove both halves — that
      // `parent_gate.dart` is the sole importer of `url_launcher` anywhere in
      // `lib/`, and that `openExternalLink` is the sole caller of
      // `launchExternal` inside it — and `about_block_test.dart` adds that
      // Settings imports it nowhere. Re-asserting any of that here would make
      // one broken promise fail in three places and give a reader three
      // near-identical greps to reconcile.
      //
      // What a citation cannot survive on its own is the cited test being
      // renamed or deleted, which would leave this checklist quietly resting on
      // nothing. That is all this line guards: the citation still points at
      // something.
      final String suite = File(
        'test/core/safety/parent_gate_test.dart',
      ).readAsStringSync();

      expect(suite, contains('the app has exactly one way out'));
      expect(
        suite,
        contains("import 'package:url_launcher/url_launcher.dart'"),
      );
    });
  });

  group('checklist 4 — the attribution and the disclaimer render', () {
    testWidgets('a child can be walked to both from a cold launch', (
      tester,
    ) async {
      // **From `main.dart`, not over `AboutBlock`.** `about_block_test.dart`
      // already pins that the widget renders both strings verbatim; what no
      // test asked until now is whether that widget is on a screen anyone can
      // reach. Both failures the checklist actually fears live in that gap —
      // the block dropped from `SettingsScreen`, or Settings itself unreachable
      // — and both would leave every existing assertion green while shipping an
      // app with no attribution in it.
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            storeProvider.overrideWithValue(MemoryStore()),
            soundEngineProvider.overrideWithValue(RecordingSoundEngine()),
            // A resolved sky, so the loading gate opens: behind that gate the
            // shell does not exist, and a pending override would make this test
            // ask about a screen no route can reach.
            asteroidFeedProvider.overrideWith(
              (Ref ref) => Future<AsteroidFeed>.value(AsteroidFeed.fallback()),
            ),
          ],
          child: const RockimalsApp(),
        ),
      );

      // Play, as a child taps it. Pumped by hand rather than settled: the radar
      // schedules a frame forever by design, so `pumpAndSettle` on the shell
      // waits for a quiet frame that never arrives.
      await tester.tap(find.byType(TitleScreen));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      // Profile, then the row at the very bottom of it — scrolled to, because
      // being out of a child's way is the design of that row.
      await tester.tap(find.text('Profile'));
      await tester.pump();
      await tester.scrollUntilVisible(find.text('Settings'), 200);
      await tester.tap(find.text('Settings'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      await tester.scrollUntilVisible(find.text(AboutBlock.disclaimer), 200);

      expect(find.text(AboutBlock.attribution), findsOneWidget);
      expect(find.text(AboutBlock.disclaimer), findsOneWidget);
    });
  });
}

/// The package names declared under [section] of `pubspec.yaml`.
///
/// Hand-scanned rather than parsed with a YAML package, for the reason the rest
/// of this suite reads source with `dart:io`: adding a dependency to answer a
/// question about the dependency list is a knot, and the manifest's shape here
/// is two-space keys under a top-level section.
Set<String> _declaredIn(String section) {
  final RegExp topLevel = RegExp(r'^([a-z_]+):');
  final RegExp entry = RegExp(r'^  ([a-z_0-9]+):');
  String? current;
  final Set<String> names = <String>{};

  for (final String line in File('pubspec.yaml').readAsLinesSync()) {
    final RegExpMatch? top = topLevel.firstMatch(line);
    if (top != null) {
      current = top.group(1);
      continue;
    }
    if (current != section) continue;
    final RegExpMatch? match = entry.firstMatch(line);
    if (match != null) names.add(match.group(1)!);
  }

  return names;
}

/// Every package in `pubspec.lock` — ours and everything ours dragged in.
Set<String> _lockedPackages() {
  final RegExp entry = RegExp(r'^  ([a-z_0-9]+):');
  return File('pubspec.lock')
      .readAsLinesSync()
      .map(entry.firstMatch)
      .whereType<RegExpMatch>()
      .map((RegExpMatch m) => m.group(1)!)
      .toSet();
}

/// Every `.dart` file under [dir], relative to the package root.
///
/// `flutter test` runs from there, which is what makes the bare paths in this
/// file's expectations readable rather than machine-specific.
List<File> _dartFilesUnder(String dir) => Directory(dir)
    .listSync(recursive: true)
    .whereType<File>()
    .where((File f) => f.path.endsWith('.dart'))
    .toList();

/// Packages whose entire purpose is to watch a user, sell to them, or identify
/// them — none of which a children's app may do (`CLAUDE.md:43-44`).
///
/// Exact pub names, never substrings: `lib/data/models/asteroid.dart` parses a
/// NeoWs field called `sentry`, and a substring match would read NASA's
/// impact-monitoring table as a crash reporter.
const Set<String> _trackingSdks = <String>{
  // Analytics and crash reporting.
  'firebase_core',
  'firebase_analytics',
  'firebase_crashlytics',
  'firebase_performance',
  'sentry',
  'sentry_flutter',
  'mixpanel_flutter',
  'amplitude_flutter',
  'posthog_flutter',
  'segment_analytics',
  'matomo_tracker',
  'datadog_flutter_plugin',
  // Ads and install attribution.
  'google_mobile_ads',
  'admob_flutter',
  'applovin_max',
  'unity_ads_plugin',
  'appsflyer_sdk',
  'adjust_sdk',
  'facebook_app_events',
  'app_tracking_transparency',
  'advertising_id',
  // Sign-in — an account is a name, and there are no accounts here.
  'firebase_auth',
  'google_sign_in',
  'sign_in_with_apple',
  'flutter_facebook_auth',
  'flutter_appauth',
  'amplify_auth_cognito',
  // Stable device identifiers, which are how "anonymous" analytics stops being
  // anonymous.
  'device_info_plus',
  'platform_device_id',
  'unique_identifier',
};

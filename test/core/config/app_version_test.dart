/// [AppVersion] against `pubspec.yaml`.
///
/// **This file exists to close exactly one hole**, and it is the hole that
/// hardcoding the version opens: someone bumps `pubspec.yaml` for a release, the
/// About block keeps rendering the old number, and nothing anywhere fails. A
/// version string that lies is worse than no version string — it sends a parent
/// reporting a bug to the wrong build.
///
/// It reads the real `pubspec.yaml` off disk rather than restating `1.0.0+1`,
/// because a test that hardcodes the same constant twice fails only when someone
/// edits *both* copies, which is the one case that was already correct.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/core/config/app_version.dart';

void main() {
  // `flutter test` runs from the package root, so this resolves without a
  // `--test-randomize`-proof dance. Read once: it is the same file for every
  // test below and re-reading would only add ways to fail.
  final String pubspec = File('pubspec.yaml').readAsStringSync();

  /// `version: 1.0.0+1` — the whole line, not a loose search for the digits,
  /// so the `sdk:` constraint and the dependency versions elsewhere in the file
  /// cannot match instead.
  final RegExpMatch? declared = RegExp(
    r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)\s*$',
    multiLine: true,
  ).firstMatch(pubspec);

  test('pubspec.yaml declares a parseable version — the premise of this file', () {
    expect(
      declared,
      isNotNull,
      reason: 'no `version: X.Y.Z+B` line in pubspec.yaml; the tests below '
          'would silently have nothing to compare against',
    );
  });

  test('AppVersion.name matches pubspec.yaml', () {
    expect(AppVersion.name, declared!.group(1));
  });

  test('AppVersion.build matches pubspec.yaml', () {
    expect(AppVersion.build, declared!.group(2));
  });

  test('display carries both halves, and names the app', () {
    // The format is pinned here rather than at the widget, so a change to how
    // the About block reads fails in one place. "Rockimals" is in the string
    // because this line is often screenshotted on its own.
    expect(AppVersion.display, 'Rockimals ${AppVersion.name} '
        '(build ${AppVersion.build})');
    expect(AppVersion.display, contains(AppVersion.name));
    expect(AppVersion.display, contains(AppVersion.build));
  });
}

/// The About block (`specs/08-settings-about.md:55-65`).
///
/// **What is under test here is mostly compliance, not behaviour**, and that
/// changes what the assertions should look like. Three of the four lines are
/// obligations — NASA's attribution is a condition of using NeoWs' data, the
/// disclaimer is what stops the app reading as NASA's own, and the privacy line
/// is `CLAUDE.md:23` said where a parent can find it. So each is asserted
/// **verbatim against the spec's own words**, character for character, rather
/// than by a `contains('NASA')` that a paraphrase would sail through. A
/// well-meaning edit to "Data from NASA!" is precisely the regression worth
/// catching, and it is the one a loose matcher misses.
///
/// **The zero-links criterion (`:64-65`, `:88`) is held two ways**, because
/// neither alone is sufficient. The spec asks for a grep of the widget tree; a
/// tree walk catches a link added as a tappable widget but not one smuggled into
/// a [TextSpan] recognizer, and neither catches a `url_launcher` call added to a
/// code path a test does not render. So this file greps the feature's **source**
/// for the import as well. The source grep is the cheaper and stricter of the
/// two — it fails on the import, long before anything has to be reachable — and
/// the tree walk is what covers a link built out of Flutter's own gesture
/// widgets, which need no import at all.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/core/audio/sound_engine.dart';
import 'package:rockimals/core/config/app_version.dart';
import 'package:rockimals/core/storage/store.dart';
import 'package:rockimals/core/theme/palette.dart';
import 'package:rockimals/features/data/providers.dart';
import 'package:rockimals/features/settings/about_block.dart';
import 'package:rockimals/features/settings/settings_screen.dart';

import '../../support/memory_store.dart';
import '../../support/recording_sound_engine.dart';

void main() {
  group('the four lines', () {
    testWidgets('renders NASA\'s attribution verbatim', (tester) async {
      // `specs/08-settings-about.md:56-57`. Attribution is a condition of using
      // the data, so the wording is not ours to tune.
      await tester.pumpWidget(_block());

      expect(
        find.text(
          "Asteroid data from NASA's NeoWs (Near Earth Object Web Service).",
        ),
        findsOneWidget,
      );
      // And that the constant the widget reads is that same string, so the two
      // cannot drift apart while both still pass.
      expect(
        AboutBlock.attribution,
        "Asteroid data from NASA's NeoWs (Near Earth Object Web Service).",
      );
    });

    testWidgets('renders the unofficial disclaimer verbatim', (tester) async {
      // `:58-59`. The line that keeps Rockimals from reading as NASA's own app.
      await tester.pumpWidget(_block());

      expect(
        find.text(
          'Rockimals is an unofficial app. It is not affiliated with, '
          'endorsed by, or sponsored by NASA.',
        ),
        findsOneWidget,
      );
      expect(
        AboutBlock.disclaimer,
        'Rockimals is an unofficial app. It is not affiliated with, '
        'endorsed by, or sponsored by NASA.',
      );
    });

    testWidgets('renders the privacy line verbatim', (tester) async {
      // `:61-62`, and `CLAUDE.md:23` — the guardrail stated in the app rather
      // than only on a release checklist.
      await tester.pumpWidget(_block());

      expect(
        find.text(
          'Rockimals collects nothing about you. No accounts, no ads, '
          'no tracking.',
        ),
        findsOneWidget,
      );
      expect(
        AboutBlock.privacy,
        'Rockimals collects nothing about you. No accounts, no ads, '
        'no tracking.',
      );
    });

    testWidgets('renders the version and build number', (tester) async {
      // `:63`. Both halves, because the build number is the half that
      // distinguishes two shipped builds of the same version — which is exactly
      // the question someone reads this line to answer.
      await tester.pumpWidget(_block());

      expect(find.text(AppVersion.display), findsOneWidget);
      expect(AppVersion.display, contains(AppVersion.name));
      expect(AppVersion.display, contains(AppVersion.build));
    });
  });

  group('the disclaimer is legible, not fine print', () {
    // `specs/08-settings-about.md:59` states this as a requirement rather than
    // a style note, and it is the requirement most likely to erode: a disclaimer
    // is the natural thing to shrink and grey out when the panel gets crowded.
    // Both assertions read the *rendered* style, so a change made anywhere up
    // the tree fails here.

    testWidgets('is no smaller than the attribution beside it', (tester) async {
      await tester.pumpWidget(_block());

      expect(
        _styleOf(tester, AboutBlock.disclaimer).fontSize,
        greaterThanOrEqualTo(
          _styleOf(tester, AboutBlock.attribution).fontSize!,
        ),
      );
    });

    testWidgets('is larger than the version footnote', (tester) async {
      // The one line on this panel that *is* a footnote, and the yardstick for
      // what fine print looks like here. A disclaimer that had shrunk to match
      // it would fail.
      await tester.pumpWidget(_block());

      expect(
        _styleOf(tester, AboutBlock.disclaimer).fontSize,
        greaterThan(_styleOf(tester, AppVersion.display).fontSize!),
      );
    });

    testWidgets('is full-contrast ink, not the muted grey', (tester) async {
      // Size is only half of legible. `Palette.muted` is the app's
      // de-emphasised colour — the version uses it correctly, the disclaimer
      // must not.
      await tester.pumpWidget(_block());

      expect(_styleOf(tester, AboutBlock.disclaimer).color, Palette.ink);
      expect(_styleOf(tester, AppVersion.display).color, Palette.muted);
    });

    testWidgets('still renders in full at 2× text, unclipped', (tester) async {
      // A parent who has turned system text up is a likely reader of this
      // block, and it is the longest paragraph in the app. Asserted as "no
      // overflow was reported", which is how Flutter surfaces text that has
      // been cut off.
      await tester.pumpWidget(_block(textScale: 2));

      expect(find.text(AboutBlock.disclaimer), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('zero outbound links', () {
    // `specs/08-settings-about.md:64-65` and the acceptance criterion at `:79`.
    // A child can reach Settings unaided — there is no parent gate in front of
    // it — so unlike `grown_up_facts.dart`, nothing here may leave the app.

    test('no file in the settings feature imports url_launcher', () {
      // The spec's "grep the screen's widget tree" (`:88`), read at the level
      // where it actually bites: an import is present or it is not, and no test
      // has to render the right state to notice. This is the whole feature
      // directory rather than the two files it has today, so the next screen
      // added under `features/settings/` inherits the rule for free.
      final Directory feature = Directory('lib/features/settings');
      expect(feature.existsSync(), isTrue, reason: 'the premise of this test');

      final List<File> sources = feature
          .listSync(recursive: true)
          .whereType<File>()
          .where((File f) => f.path.endsWith('.dart'))
          .toList();
      expect(
        sources,
        isNotEmpty,
        reason: 'the grep must have something to grep',
      );

      for (final File source in sources) {
        expect(
          source.readAsStringSync(),
          // The **import directive**, not any mention of the package. A bare
          // `contains('url_launcher')` is what this test said first, and it
          // failed immediately — on `about_block.dart`'s own doc comment
          // explaining this very rule. Prose about the rule is not a breach of
          // it, and a matcher that cannot tell the difference teaches the next
          // agent to stop writing the comment. The narrower form loses nothing:
          // `launchUrl` is unreachable without this line.
          isNot(contains("import 'package:url_launcher")),
          reason:
              '${source.path} reaches outside the app; Settings is not '
              'parent-gated, so the JPL link behind core/safety/parent_gate.dart '
              'is the only outbound link this app is allowed',
        );
      }
    });

    testWidgets('nothing in the block takes a tap', (tester) async {
      // The other half: a link built from Flutter\'s own gesture widgets needs
      // no import and would pass the grep above. Every widget in this app that
      // can be pressed is one of these.
      await tester.pumpWidget(_block());

      for (final Type tappable in <Type>[
        InkWell,
        GestureDetector,
        TextButton,
        ElevatedButton,
        OutlinedButton,
        IconButton,
      ]) {
        expect(
          find.descendant(
            of: find.byType(AboutBlock),
            matching: find.byType(tappable),
          ),
          findsNothing,
          reason:
              'a $tappable in the About block is a link or a button; '
              'the block is text only',
        );
      }
    });

    testWidgets('no span of its text carries a tap recognizer', (tester) async {
      // The sneakiest shape a link can take here, and the one the tree walk
      // above cannot see: an inline `TextSpan` with a `TapGestureRecognizer`,
      // which is how a "NASA" word inside the attribution would most naturally
      // be made tappable.
      await tester.pumpWidget(_block());

      final Iterable<RichText> paragraphs = tester.widgetList<RichText>(
        find.descendant(
          of: find.byType(AboutBlock),
          matching: find.byType(RichText),
        ),
      );
      expect(
        paragraphs,
        isNotEmpty,
        reason:
            'the walk must have something to '
            'walk',
      );

      for (final RichText paragraph in paragraphs) {
        paragraph.text.visitChildren((InlineSpan span) {
          expect(
            span is TextSpan ? span.recognizer : null,
            isNull,
            reason:
                'a tappable span in the About block is an outbound link '
                'in disguise',
          );
          return true;
        });
      }
    });

    // The complement of the grep above — *which* file is allowed to import
    // `url_launcher`, since the package is confined rather than banned — lives
    // with the module it is a claim about, in
    // `test/core/safety/parent_gate_test.dart`. It moved there when the gate
    // was promoted out of `features/detail/`; it is not duplicated here,
    // because two copies of an invariant is one copy that goes stale.
  });

  group('on the Settings screen', () {
    testWidgets('the block is mounted below both toggles', (tester) async {
      // Wiring, not content: everything above proves the block is right, and
      // this proves the screen actually has one. Order is spec 08\'s own —
      // toggles first, About last (`:45-65`).
      await tester.pumpWidget(_screen());
      await tester.scrollUntilVisible(find.byType(AboutBlock), 200);

      expect(find.byType(AboutBlock), findsOneWidget);
      expect(
        tester.getTopLeft(find.byType(AboutBlock)).dy,
        greaterThan(tester.getBottomLeft(find.text('Calm motion')).dy),
      );
    });

    testWidgets('announces About as a heading', (tester) async {
      // A grown-up looking for the attribution wants to skip the switches, and
      // a heading is what lets a screen reader jump. Matches how `sky_screen`
      // announces "The Sky".
      await tester.pumpWidget(_screen());
      await tester.scrollUntilVisible(find.byType(AboutBlock), 200);

      expect(
        tester.getSemantics(find.text('About')),
        isSemantics(label: 'About', isHeader: true),
      );
    });

    testWidgets('the attribution reads without the decorative emoji', (
      tester,
    ) async {
      // Read as authored a screen reader says "satellite, asteroid data
      // from…". The glyph is excluded, the trade every emoji-led row in this
      // app makes.
      await tester.pumpWidget(_screen());
      await tester.scrollUntilVisible(find.byType(AboutBlock), 200);

      expect(find.bySemanticsLabel(AboutBlock.attribution), findsOneWidget);
      expect(find.bySemanticsLabel('🛰️'), findsNothing);
    });
  });
}

/// The block on its own, over the app's page colour. It reads no providers —
/// nothing about it depends on what a child has done — so there is no container
/// here, which is itself worth noticing: an About block that needed one would
/// have grown state it has no business having.
Widget _block({double textScale = 1}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: const Scaffold(
        backgroundColor: Palette.pageBackground,
        // Scrolled so 2× text has somewhere to go: this asks whether the text
        // renders in full, and an unscrollable 600px test viewport would answer
        // with a layout overflow that says nothing about the block.
        body: SingleChildScrollView(child: AboutBlock()),
      ),
    ),
  );
}

/// The whole Settings screen, for the three tests that are about it having an
/// About block rather than about the block. Mounted directly rather than pushed
/// from the Profile — `settings_screen_test.dart` owns the route, and repeating
/// the push here would fail in two places for one cause.
Widget _screen() {
  final Store store = MemoryStore();
  final ProviderContainer container = ProviderContainer(
    overrides: [
      storeProvider.overrideWithValue(store),
      soundEngineProvider.overrideWithValue(RecordingSoundEngine()),
    ],
  );
  addTearDown(container.dispose);

  return UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(home: SettingsScreen()),
  );
}

/// The resolved [TextStyle] the widget rendering [text] actually paints with —
/// read off the tree rather than from the constant that sets it, so a style
/// overridden anywhere up the tree is what gets asserted.
TextStyle _styleOf(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style!;

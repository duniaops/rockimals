/// The parent gate (`core/safety/parent_gate.dart`) — `CLAUDE.md:23-25`,
/// `specs/06-title-polish-safety.md:31-33` and `:46`.
///
/// **What this file is actually protecting.** Every other suite in the repo
/// tests a behaviour a user wants. This one tests a behaviour a user must not
/// be able to get: a child reaching the open internet unaided. That inverts how
/// the assertions have to be written — the interesting cases are the *refusals*,
/// and each of them is asserted as "nothing was launched", because a gate that
/// fails open fails silently and looks exactly like a gate that works.
///
/// So the launcher here is always a spy that records into a list, never a stub
/// returning `true`, and every path out of the dialog that is not a correct
/// answer has its own case: Cancel, the barrier, and running out of tries.
///
/// The last test in the file is the one that keeps the rest honest. Everything
/// above proves *this* module's gate holds; the import grep proves there is no
/// second way out of the app for a gate to be missing from.
library;

import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/core/safety/parent_gate.dart';

void main() {
  // A gate whose answer we know: 3 + 9 = 12.
  const ParentGateChallenge fixed = ParentGateChallenge(3, 9);

  group('ParentGateChallenge', () {
    test('accepts only the exact sum, trimming whitespace', () {
      expect(fixed.answer, 12);
      expect(fixed.accepts('12'), isTrue);
      expect(fixed.accepts('  12 '), isTrue);
      expect(fixed.accepts('13'), isFalse);
      expect(fixed.accepts(''), isFalse);
      expect(fixed.accepts('twelve'), isFalse); // never throws on garbage
    });

    test('spells both numbers out as words', () {
      // The prompt is deliberately not `3 + 9`. Numerals and `+` are the first
      // notation a small child learns to recognise; the words are the reading
      // step that makes this a gate rather than a sum on a flashcard.
      expect(fixed.prompt, 'What is three plus nine?');
      expect(const ParentGateChallenge(7, 4).prompt, 'What is seven plus four?');
    });

    test('random draws addends in 3..9 and always crosses ten', () {
      // Both halves of the difficulty floor. The sum bound is the one that
      // matters most: counting on fingers gets a four-year-old to ten, so a
      // gate that can draw `2 + 3` (as the pre-hardening version could) is not
      // a gate. Every draw is checked, not a sample, because the addend
      // ranges interact — `b`'s floor is computed from `a`.
      final Random seeded = Random(42);
      for (int i = 0; i < 500; i++) {
        final ParentGateChallenge c = ParentGateChallenge.random(seeded);
        expect(c.a, inInclusiveRange(3, 9));
        expect(c.b, inInclusiveRange(3, 9));
        expect(c.answer, greaterThanOrEqualTo(11));
        expect(c.answer, lessThanOrEqualTo(18));
      }
    });

    test('random does not always draw the same sum', () {
      // The reason production passes no challenge: a memorable constant is a
      // gate a child beats once and then forever. Guards against a bad refactor
      // of the `b`-floor arithmetic collapsing the range to a single pair.
      final Random seeded = Random(7);
      final Set<int> sums = <int>{
        for (int i = 0; i < 200; i++) ParentGateChallenge.random(seeded).answer,
      };
      expect(sums.length, greaterThan(1));
    });
  });

  group('isSafeExternalLink', () {
    test('allows https at NASA hosts', () {
      // The live shape (NeoWs' `nasa_jpl_url`) and the bundled fallback's.
      expect(
        isSafeExternalLink(
          Uri.parse('https://ssd.jpl.nasa.gov/tools/sbdb_lookup.html#/?sstr=1'),
        ),
        isTrue,
      );
      expect(isSafeExternalLink(Uri.parse('https://nasa.gov/')), isTrue);
      expect(isSafeExternalLink(Uri.parse('https://www.nasa.gov/x')), isTrue);
    });

    test('refuses any scheme but https', () {
      // A scheme tells the OS *which app* to open, so an unchecked one is the
      // whole hole: these three would hand a child off to a browser over the
      // clear, to the local filesystem, and to the Play Store respectively.
      for (final String url in <String>[
        'http://nasa.gov/',
        'file:///etc/passwd',
        'market://details?id=com.example',
        'javascript:alert(1)',
      ]) {
        expect(isSafeExternalLink(Uri.parse(url)), isFalse, reason: url);
      }
    });

    test('refuses hosts that only look like NASA', () {
      // The two ways a suffix check goes wrong if the leading dot is dropped
      // or the match is done on `contains`.
      for (final String url in <String>[
        'https://evilnasa.gov/',
        'https://nasa.gov.example.com/',
        'https://example.com/nasa.gov',
        'https://example.com/',
      ]) {
        expect(isSafeExternalLink(Uri.parse(url)), isFalse, reason: url);
      }
    });

    test('refuses a URL with no host at all', () {
      expect(isSafeExternalLink(Uri.parse('https://')), isFalse);
      expect(isSafeExternalLink(Uri.parse('not a url')), isFalse);
    });
  });

  group('openExternalLink', () {
    // Pumps a single button wired to `openExternalLink`, and hands back the
    // list the spy launcher writes to. Nothing here touches a platform channel.
    Future<List<Uri>> pumpLink(
      WidgetTester tester,
      Uri url, {
      ParentGateChallenge? challenge = fixed,
    }) async {
      final List<Uri> launched = <Uri>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (BuildContext context) => TextButton(
                onPressed: () => openExternalLink(
                  context,
                  url,
                  challenge: challenge,
                  launcher: (Uri u) async {
                    launched.add(u);
                    return true;
                  },
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );
      return launched;
    }

    final Uri safe = Uri.parse('https://ssd.jpl.nasa.gov/tools/sbdb_lookup.html');

    testWidgets('a tap raises the gate and launches nothing yet', (
      tester,
    ) async {
      final List<Uri> launched = await pumpLink(tester, safe);

      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      expect(find.text('Ask a grown-up 🔭'), findsOneWidget);
      expect(find.text('What is three plus nine?'), findsOneWidget);
      expect(launched, isEmpty);
    });

    testWidgets('a correct answer opens the link and closes the gate', (
      tester,
    ) async {
      final List<Uri> launched = await pumpLink(tester, safe);

      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '12');
      await tester.tap(find.text('Open ↗'));
      await tester.pumpAndSettle();

      expect(launched, <Uri>[safe]);
      expect(find.text('Ask a grown-up 🔭'), findsNothing);
    });

    testWidgets('a wrong answer stays open, is gentle, and clears the field', (
      tester,
    ) async {
      final List<Uri> launched = await pumpLink(tester, safe);

      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '13');
      await tester.tap(find.text('Open ↗'));
      await tester.pumpAndSettle();

      expect(launched, isEmpty);
      expect(find.text('What is three plus nine?'), findsOneWidget);
      // Encouraging, never a scold (`CLAUDE.md:63`).
      expect(find.text('Not quite — ask a grown-up to help!'), findsOneWidget);
      // Cleared, so the next try starts empty rather than from the last guess.
      expect(tester.widget<TextField>(find.byType(TextField)).controller?.text,
          isEmpty);
    });

    testWidgets('the gate closes after kParentGateTries wrong answers', (
      tester,
    ) async {
      // The hardening this item exists for. Sums land in 11..18 — eight
      // possibilities — so an unlimited retry loop is a puzzle a determined
      // child solves by counting upwards. Written as a loop over the constant
      // so raising the cap cannot leave a stale `3` here passing.
      final List<Uri> launched = await pumpLink(tester, safe);

      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      for (int i = 0; i < kParentGateTries; i++) {
        expect(
          find.text('Ask a grown-up 🔭'),
          findsOneWidget,
          reason: 'the gate must still be up before try ${i + 1}',
        );
        await tester.enterText(find.byType(TextField), '13');
        await tester.tap(find.text('Open ↗'));
        await tester.pumpAndSettle();
      }

      expect(find.text('Ask a grown-up 🔭'), findsNothing);
      expect(launched, isEmpty);
    });

    testWidgets('a re-opened gate draws a fresh challenge', (tester) async {
      // What makes the try cap bite: if re-opening restored the same sum, three
      // tries at a time would still walk the whole answer space. Passing a null
      // challenge is production's own configuration.
      final List<Uri> launched = await pumpLink(tester, safe, challenge: null);
      final Set<String> prompts = <String>{};

      for (int i = 0; i < 30; i++) {
        await tester.tap(find.text('go'));
        await tester.pumpAndSettle();
        prompts.add(
          tester
              .widgetList<Text>(find.textContaining('What is '))
              .first
              .data!,
        );
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
      }

      expect(prompts.length, greaterThan(1));
      expect(launched, isEmpty);
    });

    testWidgets('Cancel refuses', (tester) async {
      final List<Uri> launched = await pumpLink(tester, safe);

      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Ask a grown-up 🔭'), findsNothing);
      expect(launched, isEmpty);
    });

    testWidgets('a barrier dismiss refuses', (tester) async {
      // `showDialog` resolves null here, and the gate maps null to false. The
      // case worth pinning: the easiest way out of the dialog must not be the
      // way out of the app.
      final List<Uri> launched = await pumpLink(tester, safe);

      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10)); // the scrim
      await tester.pumpAndSettle();

      expect(find.text('Ask a grown-up 🔭'), findsNothing);
      expect(launched, isEmpty);
    });

    testWidgets('an unsafe URL never even raises the gate', (tester) async {
      // Order matters, not just the outcome: checking the URL *after* the gate
      // would ask a grown-up to do arithmetic for a link that was never going
      // to open, and would teach them the gate is broken.
      final List<Uri> launched =
          await pumpLink(tester, Uri.parse('https://example.com/'));

      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      expect(find.text('Ask a grown-up 🔭'), findsNothing);
      expect(launched, isEmpty);
    });

    testWidgets('a passed gate cannot rescue an unsafe URL', (tester) async {
      // The belt-and-braces case: even a grown-up cannot send this app to a
      // non-NASA host, because the refusal is not a permission the gate grants.
      final List<Uri> launched =
          await pumpLink(tester, Uri.parse('market://details?id=x'));

      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNothing);
      expect(launched, isEmpty);
    });
  });

  group('the app has exactly one way out', () {
    test('parent_gate.dart is the only file in lib/ importing url_launcher', () {
      // Moved here from `about_block_test.dart` when the gate was promoted to
      // `core/safety/`: the assertion belongs with the module it is a claim
      // about, and there must be exactly one copy of it.
      //
      // This is the load-bearing test of the whole hardening item. Every other
      // case above proves the gate holds *when a link goes through it*; only
      // this one proves there is no second exit that skips it. If it fails
      // because another file imports `url_launcher`, the fix is never to add
      // that file to the expected list — it is to route that file through
      // `openExternalLink`.
      final List<String> importers = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((File f) => f.path.endsWith('.dart'))
          .where(
            (File f) => f.readAsStringSync().contains(
                  "import 'package:url_launcher/url_launcher.dart'",
                ),
          )
          .map((File f) => f.path)
          .toList();

      expect(importers, <String>['lib/core/safety/parent_gate.dart']);
    });

    test('openExternalLink is the only caller of launchExternal', () {
      // The complement, and the reason the grep above is sufficient. Confining
      // the *import* to this file would achieve nothing if this file also
      // exported a launch that skipped the gate, so `launchExternal` must
      // appear outside its own declaration only as `openExternalLink`'s
      // default argument.
      final String source =
          File('lib/core/safety/parent_gate.dart').readAsStringSync();
      final List<String> callSites = source
          .split('\n')
          .where((String line) => !line.trimLeft().startsWith('///'))
          .where((String line) => line.contains('launchExternal'))
          .map((String line) => line.trim())
          .toList();

      expect(callSites, <String>[
        'Future<bool> launchExternal(Uri url) =>', // the declaration
        'ExternalLauncher launcher = launchExternal,', // the default
      ]);
    });
  });
}
